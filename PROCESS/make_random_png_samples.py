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


DETECTORS = {"nrca1", "nrca2", "nrcb1", "nrcb2"}
FILENAME_RE = re.compile(
    r"^(jw(?P<visit11>\d{11})_.*?_(?P<det>nrca1|nrca2|nrcb1|nrcb2)_cal_Pro1oF_sky_rem)\.fits$"
)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Make 24 random asinh-stretched PNG samples per visit ID."
    )
    parser.add_argument(
        "--input-dir",
        default="/data7/rzi/PEARLSplus/jumprope/Pro1oF/cal_sky_renorm",
    )
    parser.add_argument(
        "--output-dir",
        default="/data7/rzi/PEARLSplus/jumprope/Pro1oF/png",
    )
    parser.add_argument(
        "--per-visit",
        type=int,
        default=24,
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
    )
    return parser.parse_args()


def load_image(path: Path) -> np.ndarray:
    with fits.open(path, memmap=False) as hdul:
        for hdu in hdul:
            if getattr(hdu, "name", "").upper() == "SCI" and getattr(hdu, "data", None) is not None:
                return np.asarray(hdu.data, dtype=np.float32)
        for hdu in hdul:
            if getattr(hdu, "data", None) is not None and np.ndim(hdu.data) >= 2:
                return np.asarray(hdu.data, dtype=np.float32)
    raise RuntimeError(f"No image HDU found in {path}")


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


def collect_visit_files(input_dir: Path):
    visit_files = defaultdict(list)
    for path in sorted(input_dir.iterdir()):
        if not path.is_file() or path.suffix.lower() != ".fits":
            continue
        match = FILENAME_RE.match(path.name)
        if not match:
            continue
        det = match.group("det")
        if det not in DETECTORS:
            continue
        visit_id = match.group("visit11")[-10:]
        visit_files[visit_id].append(path)
    return visit_files


def choose_files(visit_id: str, paths, per_visit: int):
    if len(paths) <= per_visit:
        return list(paths)
    rng = random.Random(int(visit_id))
    return sorted(rng.sample(list(paths), per_visit))


def main():
    args = parse_args()
    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    visit_files = collect_visit_files(input_dir)
    if not visit_files:
        raise SystemExit("No matching FITS files found.")

    written = 0
    skipped = 0
    errors = 0

    for visit_id in sorted(visit_files):
        selected = choose_files(visit_id, visit_files[visit_id], args.per_visit)

        for fits_path in selected:
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
        f"visit_ids={len(visit_files)} written={written} skipped={skipped} errors={errors} output_dir={output_dir}",
        flush=True,
    )


if __name__ == "__main__":
    main()
