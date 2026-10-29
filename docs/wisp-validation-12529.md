# Program 12529 continuous wisp validation

The continuous correction was reviewed on **28 F200W exposures**, seven each on NRCA3, NRCA4, NRCB3 and NRCB4, observations 013–014. All trials reused saved original SCI, LW warps, masks and independent priors. Calibration and mosaics were not rerun.

## Changes selected by the tests

- Deep SW/LW source masks, multi-scale LW detection and bright-wing guards exclude astronomical light from fitting; stellar diffraction spikes remain source structure.
- Independent JADES NMF predictions anchor broad wisp structure.
- Signed residual components use the **six other exposures**, excluding the target. Gaussian widths are 2 pixels and clipping quantile is .99999. This permits corrections to both under- and overestimated template structure.
- A common protected sky/1f baseline, continuous model interpolation and physical wisp support replace positive-only residual floors and circular source-mask replacement.
- Source masks also protect the subsequent sky/1f estimators. Science data are not inpainted, and source masks are not added to DQ.

The older masked replacement recovered source perturbations but introduced circular background offsets: the modeled subtraction outside source guards had median ~0.23–0.25 input-noise sigma in the checked off-template regions, versus zero inside. The continuous version has zero modeled pedestal on both sides in those checked off-wisp regions. This is a model-background diagnostic, not a proof of perfect final sky subtraction.

## Completed checks

- All 28 original-file signatures are unchanged; finite models and subtraction identities pass.
- Every target is absent from its residual-template reference set.
- The two reported A3/A4 artificial blank-mask checks show no local model imprint outside physical wisp support.
- Synthetic checks preserve a signed constant residual across a model hole and preserve a masked source while fitting an exposed narrow feature.
- Legacy R default/option and source-mask regressions pass.
- The actual R wisp entrypoint was checked on a disposable calibrated copy, with independent verification of SCI/template identity and unchanged ERR/DQ.
- Exact R/Python clipping precision is checked, including .99999.

Native before/template/after PNGs were generated for every exposure, with additional full-frame/source/wisp-region views. The parent reduction retains those science-specific artifacts; large reference assets and science images are not bundled in this repository.

## Limits

Some narrow A3 residuals remain. Reference masking and varying morphology can leave areas poorly constrained. Undetected celestial emission coherent across reference exposures may contaminate a learned residual template. Full coherent multi-exposure source injection and final-mosaic photometric validation have not been established. The complete residual-template uncertainty is not propagated into ERR. Installing this release does not modify existing calibrated science or mosaics.
