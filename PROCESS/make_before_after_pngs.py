#!/usr/bin/env python3

import argparse
import os
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib-jumprope")

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
from astropy.io import fits


def parse_args():
    parser = argparse.ArgumentParser(
        description="Render side-by-side before/after PNGs for processed JUMPROPE products."
    )
    parser.add_argument(
        "--png-dir",
        required=True,
        help="Directory containing processed PNGs whose basenames define the target set.",
    )
    parser.add_argument(
        "--raw-dir",
        required=True,
        help="Directory containing raw *_cal.fits inputs.",
    )
    parser.add_argument(
        "--processed-dir",
        required=True,
        help="Directory containing processed *_cal_Pro1oF_sky_rem.fits outputs.",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory to write side-by-side comparison PNGs.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
    )
    parser.add_argument(
        "--before-label",
        default="Before: raw cal",
    )
    parser.add_argument(
        "--after-label",
        default="After: processed cal_sky_renorm",
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


def stretch_with_limits(data: np.ndarray, low: float, high: float, sigma: float) -> np.ndarray:
    clipped = np.clip(data, low, high)
    shifted = clipped - low
    dynamic = max(high - low, sigma)
    soft = max(3.0 * sigma, dynamic / 18.0, 1e-6)
    stretched = np.arcsinh(shifted / soft) / np.arcsinh(dynamic / soft)
    stretched = np.where(np.isfinite(stretched), stretched, 0.0)
    return np.clip(stretched, 0.0, 1.0)


def mixed_reference_stretch(before: np.ndarray, after: np.ndarray):
    before_median, _, _, _ = robust_stats(before)
    after_median, after_sigma, _, high = robust_stats(after)
    before_low = before_median
    after_low = after_median
    return (
        stretch_with_limits(before, before_low, high, after_sigma),
        stretch_with_limits(after, after_low, high, after_sigma),
    )


def raw_name_from_processed_stem(stem: str) -> str:
    if not stem.endswith("_cal_Pro1oF_sky_rem"):
        raise ValueError(f"Unexpected processed stem: {stem}")
    return stem.replace("_cal_Pro1oF_sky_rem", "_cal") + ".fits"


def render_compare(raw_fits: Path, processed_fits: Path, output_png: Path, before_label: str, after_label: str):
    before = load_image(raw_fits)
    after = load_image(processed_fits)
    # Use each image's own median as vmin, but share the processed image's vmax.
    before_stretch, after_stretch = mixed_reference_stretch(before, after)

    fig = plt.figure(figsize=(12, 6), dpi=150)
    axes = fig.subplots(1, 2)

    for ax, image, title in zip(
        axes,
        [before_stretch, after_stretch],
        [before_label, after_label],
    ):
        ax.imshow(image, origin="lower", cmap="gray", interpolation="nearest")
        ax.set_axis_off()
        ax.set_title(title, fontsize=10)

    fig.suptitle(processed_fits.stem, fontsize=10)
    fig.savefig(output_png, bbox_inches="tight", pad_inches=0.05)
    plt.close(fig)


def main():
    args = parse_args()
    png_dir = Path(args.png_dir)
    raw_dir = Path(args.raw_dir)
    processed_dir = Path(args.processed_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    written = 0
    skipped = 0
    errors = 0

    for png_path in sorted(png_dir.glob("*.png")):
        processed_stem = png_path.stem
        processed_fits = processed_dir / f"{processed_stem}.fits"
        raw_fits = raw_dir / raw_name_from_processed_stem(processed_stem)
        output_png = output_dir / f"{processed_stem}__before_after.png"

        if output_png.exists() and not args.overwrite:
            skipped += 1
            continue

        try:
            if not processed_fits.is_file():
                raise FileNotFoundError(processed_fits)
            if not raw_fits.is_file():
                raise FileNotFoundError(raw_fits)
            render_compare(
                raw_fits,
                processed_fits,
                output_png,
                args.before_label,
                args.after_label,
            )
            written += 1
        except Exception as exc:
            errors += 1
            print(f"ERROR {processed_stem}: {exc}", flush=True)

    print(
        f"written={written} skipped={skipped} errors={errors} output_dir={output_dir}",
        flush=True,
    )


if __name__ == "__main__":
    main()
