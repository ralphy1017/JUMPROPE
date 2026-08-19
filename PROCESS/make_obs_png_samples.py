#!/usr/bin/env python3

import argparse
import os
import random
import re
from collections import defaultdict
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib-jumprope")

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
from astropy.io import fits


FILENAME_RE = re.compile(
    r"^(jw(?P<visit11>\d{11})_.*?_(?P<det>nrc[a-b][1-4])_cal_Pro1oF_sky_rem)\.fits$"
)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Make deterministic random PNG QA samples for selected observation IDs."
    )
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--obs-ids", required=True, help="Pipe-separated 7-digit observation IDs.")
    parser.add_argument("--detectors", default="nrcb3|nrcb4")
    parser.add_argument("--per-obs", type=int, default=20)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def robust_stats(data: np.ndarray):
    finite = data[np.isfinite(data)]
    if finite.size == 0:
        raise RuntimeError("No finite pixels")

    median = float(np.median(finite))
    mad = float(np.median(np.abs(finite - median)))
    sigma = 1.4826 * mad
    if not np.isfinite(sigma) or sigma <= 0:
        p25, p75 = np.percentile(finite, [25, 75])
        sigma = float((p75 - p25) / 1.349) if p75 > p25 else 1.0
    if not np.isfinite(sigma) or sigma <= 0:
        sigma = 1.0

    high = float(np.percentile(finite, 99.8))
    low = median - 2.0 * sigma
    if high <= low:
        high = median + 10.0 * sigma
    return median, sigma, low, high


def asinh_stretch(data: np.ndarray) -> np.ndarray:
    median, sigma, low, high = robust_stats(data)
    clipped = np.clip(data, low, high)
    shifted = clipped - low
    dynamic = max(high - low, sigma)
    soft = max(3.0 * sigma, dynamic / 18.0, 1e-6)
    stretched = np.arcsinh(shifted / soft) / np.arcsinh(dynamic / soft)
    stretched = np.where(np.isfinite(stretched), stretched, 0.0)
    return np.clip(stretched, 0.0, 1.0)


def load_image(path: Path) -> np.ndarray:
    with fits.open(path, memmap=False) as hdul:
        for hdu in hdul:
            if getattr(hdu, "name", "").upper() == "SCI" and getattr(hdu, "data", None) is not None:
                return np.asarray(hdu.data, dtype=np.float32)
        for hdu in hdul:
            if getattr(hdu, "data", None) is not None and np.ndim(hdu.data) >= 2:
                return np.asarray(hdu.data, dtype=np.float32)
    raise RuntimeError(f"No image HDU found in {path}")


def render_png(fits_path: Path, png_path: Path):
    image = load_image(fits_path)
    stretched = asinh_stretch(image)

    fig = plt.figure(figsize=(6, 6), dpi=150)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.imshow(stretched, origin="lower", cmap="gray", interpolation="nearest")
    ax.set_axis_off()
    ax.text(
        0.015,
        0.015,
        fits_path.stem,
        transform=ax.transAxes,
        color="white",
        fontsize=6,
        ha="left",
        va="bottom",
        bbox=dict(boxstyle="round,pad=0.2", facecolor="black", alpha=0.55, edgecolor="none"),
    )
    fig.savefig(png_path, bbox_inches="tight", pad_inches=0)
    plt.close(fig)


def main():
    args = parse_args()
    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    obs_ids = {tok for tok in args.obs_ids.split("|") if tok}
    detectors = {tok.lower() for tok in args.detectors.split("|") if tok}
    obs_files = defaultdict(list)

    for path in sorted(input_dir.iterdir()):
        if not path.is_file() or path.suffix.lower() != ".fits":
            continue
        match = FILENAME_RE.match(path.name)
        if not match:
            continue
        det = match.group("det").lower()
        if det not in detectors:
            continue
        obs = match.group("visit11")[-10:-3]
        if obs not in obs_ids:
            continue
        obs_files[obs].append(path)

    written = 0
    skipped = 0
    errors = 0

    for obs in sorted(obs_files):
        paths = obs_files[obs]
        if len(paths) > args.per_obs:
          rng = random.Random(int(obs))
          paths = sorted(rng.sample(paths, args.per_obs))
        for fits_path in paths:
            png_path = output_dir / f"{fits_path.stem}.png"
            if png_path.exists() and not args.overwrite:
                skipped += 1
                continue
            try:
                render_png(fits_path, png_path)
                written += 1
            except Exception as exc:
                errors += 1
                print(f"ERROR {fits_path}: {exc}", flush=True)

    print(
        f"obs_ids={len(obs_files)} written={written} skipped={skipped} errors={errors} output_dir={output_dir}",
        flush=True,
    )


if __name__ == "__main__":
    main()
