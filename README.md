# JumProPe for the NEP TDF reduction

This version adds **source-protected, continuous wisp subtraction** to the existing JumProPe wisp stage. It was checked on all 28 program 12529 F200W exposures on NRCA3, NRCA4, NRCB3 and NRCB4. The underlying suite and workflow are described in the [upstream manual](https://www.overleaf.com/read/ksqfmgvhtnhh#3a3d4d).

The selected 12529 recipe is `method="continuous_dynamic"`, `sigma_hi=2`, `sigma_lo=2`, `clip_threshold=0.99999`. It combines a source-masked independent wisp prediction with signed residual templates learned from the **other exposures on the same detector**. A common protected sky/1f baseline and continuous model interpolation replace the circular mask-fill switch and positive-only residual floor. Science source pixels are not inpainted or added to DQ masks.

**Setup, reference preparation and parameters:** [PROCESS/WISP_NMF.md](PROCESS/WISP_NMF.md). The repository includes a pinned JADES template downloader, portable preparation/verification CLI, R/Python integration, source-mask propagation into later sky/1f estimation, and regression tests. The NMF solver is vendored with its MIT license and upstream revision.

**Validation and limits:** [docs/wisp-validation-12529.md](docs/wisp-validation-12529.md). The measured circular background pedestal is removed in the checked regions. Some narrow A3 residuals remain; full-mosaic photometry and arbitrary diffuse-light preservation are not established, and residual-template uncertainty is not fully propagated into ERR. The repository does not include the NEP science data or its large prepared reference assets.

The continuous method is **explicitly selected** through `JUMPROPE_WISP_PARAMS` or `additional_params$wisp_params`; it requires prepared references and does not silently become the default for unprepared datasets. Legacy `wispFixer` defaults remain compatible with the earlier `stable-2026-10-29` tag. That historical no-clipping profile was superseded for this dataset after full-frame/source inspection; it should not be interpreted as the current recommended 12529 configuration. The old tag is retained unchanged.

Run from the repository root:

```sh
Rscript tests/test_wisp_defaults.R
Rscript tests/test_wisp_source_mask.R
python tests/test_wisp_continuous.py
```

Use the established JWST/R environment, with NumPy, SciPy and Astropy for the new helpers. Set `JUMPROPE_PYTHON` to that interpreter. The parent reduction supplies orchestration, calibration references and grids; this clone does not install the patched ProPane 1.12.1.2 needed for the parent project's large-grid stacking. [PATCHES.md](PATCHES.md) records implementation changes. Existing calibrated science and mosaics are not reprocessed by installing this code.
