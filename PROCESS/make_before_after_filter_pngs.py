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
        description="Render side-by-side before/after PNGs for processed JUMPROPE products selected by FILTER header."
    )
    parser.add_argument(
        "--raw-dir",
        required=True,
    )
    parser.add_argument(
        "--processed-dir",
        required=True,
    )
    parser.add_argument(
        "--output-dir",
        required=True,
    )
    parser.add_argument(
        "--filters",
        required=True,
        help="Pipe-separated filter list, e.g. F115W|F150W|F200W",
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


def load_filter_and_image(path: Path):
    with fits.open(path, memmap=False) as hdul:
        filt = None
        for hdu in hdul:
            header = getattr(hdu, "header", None)
            if header is not None and "FILTER" in header:
                filt = str(header["FILTER"]).strip().upper()
                break
        image = None
        for hdu in hdul:
            if getattr(hdu, "name", "").upper() == "SCI" and getattr(hdu, "data", None) is not None:
                image = np.asarray(hdu.data, dtype=np.float32)
                break
        if image is None:
            for hdu in hdul:
                if getattr(hdu, "data", None) is not None and np.ndim(hdu.data) >= 2:
                    image = np.asarray(hdu.data, dtype=np.float32)
                    break
    if filt is None:
        raise RuntimeError(f"FILTER header not found in {path}")
    if image is None:
        raise RuntimeError(f"No image HDU found in {path}")
    return filt, image


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
    return (
        stretch_with_limits(before, before_median, high, after_sigma),
        stretch_with_limits(after, after_median, high, after_sigma),
    )


def raw_name_from_processed_name(name: str) -> str:
    if not name.endswith("_cal_Pro1oF_sky_rem.fits"):
        raise ValueError(f"Unexpected processed filename: {name}")
    return name.replace("_cal_Pro1oF_sky_rem.fits", "_cal.fits")


def render_compare(raw_image: np.ndarray, processed_image: np.ndarray, title_stub: str, output_png: Path, before_label: str, after_label: str):
    before_stretch, after_stretch = mixed_reference_stretch(raw_image, processed_image)

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

    fig.suptitle(title_stub, fontsize=10)
    fig.savefig(output_png, bbox_inches="tight", pad_inches=0.05)
    plt.close(fig)


def main():
    args = parse_args()
    filters = {item.strip().upper() for item in args.filters.split("|") if item.strip()}
    raw_dir = Path(args.raw_dir)
    processed_dir = Path(args.processed_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    written = 0
    skipped = 0
    missing_raw = 0
    errors = 0
    matched = 0

    for processed_fits in sorted(processed_dir.glob("*.fits")):
      try:
        filt, processed_image = load_filter_and_image(processed_fits)
        if filt not in filters:
            continue
        matched += 1
        raw_fits = raw_dir / raw_name_from_processed_name(processed_fits.name)
        if not raw_fits.is_file():
            missing_raw += 1
            continue
        _, raw_image = load_filter_and_image(raw_fits)
        output_png = output_dir / f"{processed_fits.stem}__before_after.png"
        if output_png.exists() and not args.overwrite:
            skipped += 1
            continue
        render_compare(
            raw_image,
            processed_image,
            processed_fits.stem,
            output_png,
            args.before_label,
            args.after_label,
        )
        written += 1
      except Exception as exc:
        errors += 1
        print(f"ERROR {processed_fits.name}: {exc}", flush=True)

    print(
        f"filters={sorted(filters)} matched={matched} written={written} skipped={skipped} missing_raw={missing_raw} errors={errors} output_dir={output_dir}",
        flush=True,
    )


if __name__ == "__main__":
    main()
