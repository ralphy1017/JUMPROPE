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
        description="Render asinh-stretched PNGs for processed FITS files selected by FILTER header."
    )
    parser.add_argument(
        "--input-dir",
        default="/data7/rzi/PEARLSplus/jumprope/Pro1oF/cal_sky_renorm",
    )
    parser.add_argument(
        "--output-dir",
        default="/data7/rzi/PEARLSplus/png",
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
    return low, high, sigma


def asinh_stretch(data: np.ndarray) -> np.ndarray:
    low, high, sigma = robust_stats(data)
    clipped = np.clip(data, low, high)
    shifted = clipped - low
    dynamic = max(high - low, sigma)
    soft = max(3.0 * sigma, dynamic / 18.0, 1e-6)
    stretched = np.arcsinh(shifted / soft) / np.arcsinh(dynamic / soft)
    stretched = np.where(np.isfinite(stretched), stretched, 0.0)
    return np.clip(stretched, 0.0, 1.0)


def read_filter_and_image(path: Path):
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


def render_png(fits_path: Path, png_path: Path):
    _, image = read_filter_and_image(fits_path)
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
    filters = {item.strip().upper() for item in args.filters.split("|") if item.strip()}
    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    written = 0
    skipped = 0
    errors = 0
    matched = 0

    for fits_path in sorted(input_dir.glob("*.fits")):
        try:
            filt, _ = read_filter_and_image(fits_path)
            if filt not in filters:
                continue
            matched += 1
            png_path = output_dir / f"{fits_path.stem}.png"
            if png_path.exists() and not args.overwrite:
                skipped += 1
                continue
            render_png(fits_path, png_path)
            written += 1
        except Exception as exc:
            errors += 1
            print(f"ERROR {fits_path.name}: {exc}", flush=True)

    print(
        f"filters={sorted(filters)} matched={matched} written={written} skipped={skipped} errors={errors} output_dir={output_dir}",
        flush=True,
    )


if __name__ == "__main__":
    main()
