#!/usr/bin/env python3

import argparse
import os
import random
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor

os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib-jumprope")

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
from astropy.io import fits


SHORT_DETECTORS = {"NRCA1", "NRCA2", "NRCA3", "NRCA4", "NRCB1", "NRCB2", "NRCB3", "NRCB4"}


def parse_args():
    parser = argparse.ArgumentParser(
        description="Render before/after/template triptychs for wisp-removal inspection."
    )
    parser.add_argument("--processed-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--prefix", default="")
    parser.add_argument("--obs-ids", default="")
    parser.add_argument("--detectors", default="nrca3|nrca4|nrcb3|nrcb4")
    parser.add_argument("--filters", default="")
    parser.add_argument("--per-obs", type=int, default=0, help="Deterministically sample up to N files per observation ID. 0 means all.")
    parser.add_argument("--seed", type=int, default=8675309)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def filename_detector(path: Path):
    lower = path.name.lower()
    for detector in sorted(SHORT_DETECTORS, key=len, reverse=True):
        token = detector.lower()
        if f"_{token}_" in lower:
            return detector
    return None


def filename_obs_id(path: Path):
    parts = path.name.split("_", 1)
    if parts and len(parts[0]) >= 10:
        return parts[0][-10:-3]
    return ""


def read_triptych_inputs(path: Path):
    with fits.open(path, memmap=False) as hdul:
        filt = None
        detector = None
        sci = None
        sci_orig = None
        template = None
        for hdu in hdul:
            header = getattr(hdu, "header", None)
            if header is not None:
                if filt is None and "FILTER" in header:
                    filt = str(header["FILTER"]).strip().upper()
                if detector is None and "DETECTOR" in header:
                    detector = str(header["DETECTOR"]).strip().upper()
            name = getattr(hdu, "name", "").upper()
            if name == "SCI" and getattr(hdu, "data", None) is not None:
                sci = np.asarray(hdu.data, dtype=np.float32)
            elif name == "SCI_ORIG" and getattr(hdu, "data", None) is not None:
                sci_orig = np.asarray(hdu.data, dtype=np.float32)
            elif name == "WISP_TEMPLATE" and getattr(hdu, "data", None) is not None:
                template = np.asarray(hdu.data, dtype=np.float32)
    if filt is None or detector is None or sci is None or sci_orig is None or template is None:
        raise RuntimeError(f"Missing required wisp HDU/header in {path}")
    return filt, detector, sci_orig, sci, template


def robust_sigma(data: np.ndarray) -> float:
    finite = data[np.isfinite(data)]
    if finite.size == 0:
        return 1.0
    median = float(np.median(finite))
    mad = float(np.median(np.abs(finite - median)))
    sigma = 1.4826 * mad
    if not np.isfinite(sigma) or sigma <= 0:
        p25, p75 = np.percentile(finite, [25, 75])
        sigma = float((p75 - p25) / 1.349) if p75 > p25 else 1.0
    if not np.isfinite(sigma) or sigma <= 0:
        sigma = 1.0
    return sigma


def image_high(data: np.ndarray) -> float:
    finite = data[np.isfinite(data)]
    if finite.size == 0:
        return 1.0
    return float(np.percentile(finite, 99.8))


def stretch_image(data: np.ndarray, low: float, high: float, sigma: float) -> np.ndarray:
    clipped = np.clip(data, low, high)
    shifted = clipped - low
    dynamic = max(high - low, sigma)
    soft = max(3.0 * sigma, dynamic / 18.0, 1e-6)
    stretched = np.arcsinh(shifted / soft) / np.arcsinh(dynamic / soft)
    stretched = np.where(np.isfinite(stretched), stretched, 0.0)
    return np.clip(stretched, 0.0, 1.0)


def stretch_template(data: np.ndarray) -> np.ndarray:
    finite = data[np.isfinite(data)]
    if finite.size == 0:
        return np.zeros_like(data, dtype=np.float32)
    scale = float(np.percentile(np.abs(finite), 99.8))
    if not np.isfinite(scale) or scale <= 0:
        scale = 1.0
    soft = max(scale / 10.0, 1e-6)
    stretched = np.arcsinh(data / soft) / np.arcsinh(scale / soft)
    return np.clip(np.where(np.isfinite(stretched), stretched, 0.0), -1.0, 1.0)


def render_triptych(path: Path, output_png: Path):
    filt, detector, before, after, template = read_triptych_inputs(path)
    after_sigma = robust_sigma(after)
    after_high = image_high(after)
    before_low = float(np.median(before[np.isfinite(before)]))
    after_low = float(np.median(after[np.isfinite(after)]))
    before_stretch = stretch_image(before, before_low, after_high, after_sigma)
    after_stretch = stretch_image(after, after_low, after_high, after_sigma)
    template_stretch = stretch_template(template)

    fig = plt.figure(figsize=(15, 5), dpi=160)
    axes = fig.subplots(1, 3)
    panels = [
        (before_stretch, "SCI_ORIG", "gray", 0.0, 1.0),
        (after_stretch, "SCI", "gray", 0.0, 1.0),
        (template_stretch, "WISP_TEMPLATE", "coolwarm", -1.0, 1.0),
    ]
    for ax, (image, title, cmap, vmin, vmax) in zip(axes, panels):
        ax.imshow(image, origin="lower", cmap=cmap, interpolation="nearest", vmin=vmin, vmax=vmax)
        ax.set_axis_off()
        ax.set_title(title, fontsize=10)
    fig.suptitle(f"{path.stem} | {detector} | {filt}", fontsize=10)
    fig.savefig(output_png, bbox_inches="tight", pad_inches=0.05)
    plt.close(fig)


def process_triptych(path_str: str, output_png_str: str, filters: tuple[str, ...]):
    path = Path(path_str)
    output_png = Path(output_png_str)
    try:
        filt, detector, _, _, _ = read_triptych_inputs(path)
        if filters and filt not in filters:
            return ("skipped", path.name, "filter")
        if detector not in SHORT_DETECTORS:
            return ("skipped", path.name, "detector")
        render_triptych(path, output_png)
        return ("written", path.name, "")
    except RuntimeError as exc:
        if "Missing required wisp HDU/header" in str(exc):
            return ("skipped", path.name, "missing_hdu")
        return ("error", path.name, str(exc))
    except Exception as exc:
        return ("error", path.name, str(exc))


def main():
    args = parse_args()
    processed_dir = Path(args.processed_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    filters = {item.strip().upper() for item in args.filters.split("|") if item.strip()}
    detectors = {item.strip().upper() for item in args.detectors.split("|") if item.strip()}
    obs_ids = {item.strip() for item in args.obs_ids.split("|") if item.strip()}
    prefix = args.prefix.strip()

    written = 0
    skipped = 0
    errors = 0

    jobs = max(1, int(args.jobs))
    work_items = []

    candidates = []
    for path in sorted(processed_dir.glob("*.fits")):
        obs_id = filename_obs_id(path)
        if obs_ids and obs_id not in obs_ids:
            continue
        file_detector = filename_detector(path)
        if file_detector is None:
            skipped += 1
            continue
        if detectors and file_detector not in detectors:
            skipped += 1
            continue
        candidates.append((obs_id, path))

    if args.per_obs > 0:
        grouped = {}
        for obs_id, path in candidates:
            grouped.setdefault(obs_id, []).append(path)
        sampled = []
        for obs_id in sorted(grouped):
            rng = random.Random(f"{args.seed}:{obs_id}")
            obs_paths = grouped[obs_id]
            if len(obs_paths) > args.per_obs:
                obs_paths = sorted(rng.sample(obs_paths, args.per_obs))
            sampled.extend(obs_paths)
        candidates = [("", path) for path in sorted(sampled)]

    for _, path in candidates:
        png_name = f"{path.stem}__wisp_triptych.png"
        if prefix:
            png_name = f"{prefix}__{png_name}"
        output_png = output_dir / png_name
        if output_png.exists() and not args.overwrite:
            skipped += 1
            continue
        work_items.append((str(path), str(output_png)))

    if jobs == 1:
        for path_str, output_png_str in work_items:
            status, path_name, detail = process_triptych(path_str, output_png_str, tuple(filters))
            if status == "written":
                written += 1
            elif status == "skipped":
                skipped += 1
            else:
                errors += 1
                print(f"ERROR {path_name}: {detail}", flush=True)
    else:
        with ProcessPoolExecutor(max_workers=jobs) as executor:
            futures = [
                executor.submit(process_triptych, path_str, output_png_str, tuple(filters))
                for path_str, output_png_str in work_items
            ]
            for future in futures:
                status, path_name, detail = future.result()
                if status == "written":
                    written += 1
                elif status == "skipped":
                    skipped += 1
                else:
                    errors += 1
                    print(f"ERROR {path_name}: {detail}", flush=True)

    print(f"written={written} skipped={skipped} errors={errors} output_dir={output_dir}", flush=True)


if __name__ == "__main__":
    main()
