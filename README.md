# JWST UWA MULTIWAVELENGTH PROTOOLS PROCESSING ENDEAVOUR (J U M PRO P E)

Characterised by its ease of use, its speed and its health benefits: JUMPROPE is an all purpose JWST processing suite of codes!

The manual is a living document and can be found on overleaf here: https://www.overleaf.com/read/ksqfmgvhtnhh#3a3d4d

<img src="https://github.com/JordanDSilva/JUMPROPE/blob/main/logo.png" width="500" height="500"/>


## This version

This is Jordan's JumProPe with bug fixes, so it runs on current jwst pipeline outputs, on NIRCam, NIRISS and MIRI, and on long lists of visits. Wisp removal uses Jordan's `wispFixer` with `clip_threshold = 0.9999`, `sigma_hi = 2` and `sigma_lo = 2`. Every change is listed in [CHANGES.md](CHANGES.md).

It runs the same way as the original:

```sh
source initialise_env.sh            # set paths and cores first
cd PROCESS                          # edit initialise_variables.R: 1/f mode, wisp/claw removal, stacks
Rscript run_all_process.R '1345001001|1345002001'
```

Outputs go to `$JUMPROPE_REF_DIR/Pro1oF/cal` and `$JUMPROPE_REF_DIR/Pro1oF/cal_sky_renorm`. ProPane stacks, patches and RGBs are also made unless `make_stacks = FALSE`.

Dependencies are the same as upstream: R with Rfits, Rwcs, ProFound, ProPane, magicaxis, celestial, imager, Highlander, foreach, doParallel, data.table, dplyr, stringr, checkmate, matrixStats, RANN and Cairo. Calibration needs the jwst Python pipeline.
