# Source-protected continuous wisps

The selected program 12529 correction is `method="continuous_dynamic"`, with `sigma_hi=2`, `sigma_lo=2`, `clip_threshold=0.99999`. It is implemented within `do_wisp_rem`, using the existing `wisp_params` / `JUMPROPE_WISP_PARAMS` interface.

The two widths define signed low/fine residual components. `sigma_lo` is no longer a positive-only floor in this mode. The old single SW/LW colour-ratio subtraction and sky quantile are not used. The target exposure is excluded from construction of its residual templates; only a few global coefficients use its source-free pixels.

## Prepare independent priors

The independent templates/NNLS solver are from Wu et al. 2026, [JADES NMF wisps](https://arxiv.org/abs/2601.15958), pinned to `bd6609fa9a003d1737e3da6f7e266cf10d984bf9`. The vendored solver is unchanged; see `vendor/NMFWISP_LICENSE`. Download the F200W assets once:

```sh
python PROCESS/fetch_wisp_templates.py /path/to/wisp_templates
```

The current downloader covers F200W. B4 is native 2048-pixel resolution; A3/A4/B3 templates are interpolated from the published 512-pixel grids. NumPy, SciPy and Astropy are required. Set `JUMPROPE_PYTHON` to this Python interpreter and `JUMPROPE_DIR` to this clone.

On **preparation working copies**, use the existing wisp stage with:

```json
{
  "method": "nmf",
  "template_dir": "/path/to/wisp_templates",
  "source_mask_files": ["/path/to/deep_LW_segmentation.fits", "/path/to/deep_SW_segmentation.fits"],
  "mask_dilate": 8,
  "correct_1f": true
}
```

The LW warp is used for source detection. Deep segmentation maps require celestial FITS WCS. Multi-scale LW detection, eight-pixel source dilation and 160-pixel guards around eight separated bright interior source groups protect cores, wings, spikes and groups. Their minimum separation is 340 pixels and their interior margin is 170 pixels. Existing bad pixels are excluded separately, without source-style dilation.

NMF outputs retain `SCI_ORIG` and add `WISP_TEMPLATE`, `WISP_SOURCE_MASK`, `WISP_ERR`; the SCI header records `WISPMETH=NMF`. These are the inputs to reference preparation. Do not use a dynamic wisp template as an NMF prior.

## Build the continuous residual references

Create a manifest listing all preparation working copies for each detector/filter:

```json
{
  "frames": [
    {"input": "/path/to/preparation/jw..._nrca3_cal.fits"},
    {"input": "/path/to/preparation/jw..._nrca3_cal.fits"}
  ]
}
```

Include the actual full group: **seven per detector were validated**, and at least three are required mathematically. If the independent prior is a separate FITS file, the record may instead supply `prior` and `prior_method="nmf"`; that FITS must contain `WISP_TEMPLATE`, `WISP_SOURCE_MASK` and `WISP_ERR`.

```sh
python PROCESS/prepare_wisp_continuous.py --manifest frames.json \
  --template-dir /path/to/wisp_templates --output /path/to/continuous_cache \
  --sigma-hi 2 --sigma-lo 2 --clip-threshold 0.99999 --workers 2
```

Run under the caller's normal CPU budget; BLAS/OpenMP should remain at one thread per worker. Preparation never modifies the science inputs. It writes:

- `priors/<frame>/independent.fits`: frozen independent prediction and source mask;
- `basis/<frame>.fits` and JSON: signed broad/fine components, support/count maps, exact input/prior hashes and reference membership;
- `parameters.json`: the configuration to apply in the final working run.

Each residual template is built from the other exposures in its detector/filter group. Source/wisp-protected sky and row/column nuisance estimates give a common background baseline. Residual gaps are harmonically extended in the **model**, then smoothed. Corrections taper to zero outside physical wisp support. Science pixels are never filled. Clipping and signed interpolation do not create a positive-only background floor.

## Apply in the existing workflow

Use the generated `parameters.json` as `wisp_params` / `JUMPROPE_WISP_PARAMS`. It selects `continuous_dynamic`, sets the three numeric parameters above, and supplies `template_dir`, `prepared_prior_dir` and `residual_basis_dir`.

Use a **fresh final working run** with the same calibrated inputs. Do not reuse sky/1f products from the preparation run after changing the wisp method: the established workflow skips files that already exist. Within the wisp stage, `SCI_ORIG` is used for retries so corrections cannot accumulate.

Input hashes and target exclusion are checked before applying a prepared basis. Rebuild assets after changing calibration, references or the Gaussian/clipping settings. R/Python JSON preserves full precision so .99999 is not rounded to 1. Source masks carry forward into the existing sky/1f/pedestal estimation without modifying science DQ or PIXELMASK. Fit sky/stripes are nuisance estimates, not extra subtraction in the wisp step.

Check prepared assets without recomputing them:

```sh
python PROCESS/prepare_wisp_continuous.py --manifest frames.json --verify-only \
  --basis-dir /path/to/continuous_cache/basis --prior-dir /path/to/continuous_cache/priors
```

Outputs retain `SCI_ORIG`, `REF_WISP_WARP`, `WISP_TEMPLATE`, with `WISP_SOURCE_MASK`, `WISP_FIT_MASK`, `WISP_ERR`, `WISP_FIT_1F` and a `.wisp.json` sidecar. `WISP_ERR` describes the independent prior only; full residual-template uncertainty is not propagated into ERR.

## Validation and compatibility

See [the 12529 validation summary](../docs/wisp-validation-12529.md). Some narrow A3 residuals and poor-reference-coverage limitations remain. Final-mosaic photometry and undetected diffuse-light preservation are not certified.

Legacy `dynamic` and independent-only `nmf` remain available. Historical `masked_dynamic` applies direct independent-template replacement inside source guards; it produced circular background offsets and is retained for comparison, not recommended for the final 12529 correction. Continuous mode removes that spatial switch.
