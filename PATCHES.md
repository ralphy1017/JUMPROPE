# JumProPe `nep-miri` change ledger

Base `main`: `9e7af86`. Validated branch HEAD `7f3d2b3`, pushed to `ralphy1017/JUMPROPE` `nep-miri`. Changes are marked `[nep-miri]` in code. The parent project's [reduction reference](../../JUMPROPE.md) gives usage and QA; [vendor provenance](../../vendor/VENDOR.md) covers the separately installed ProPane patch.

## Inherited NEP fixes present at the base commit

| Commit(s) | Change |
|---|---|
| `a485e83`, `55fd1a1`, `700b5e2` | `caljwst.py` parallel files/`--match`; imaging-only MAST query, NumPy 2 compatibility, placeholder-token login skip. |
| `9261ae1`, `aaad6fc`, `c605dbd`, `42e590f` | NEP environment setup and `RAW_DIR` cal-link layout. |
| `e54f672`, `715f1c0` | Convert jwst 3 uint32 DQ read as R `integer64` into numeric matrices at 1/f, sky, pedestal and stacking reads. |
| `d857f23` | Use `cal_sky_info$CRDS_CTX` instead of an undefined context variable. |
| `6fafbe0`, `a24ca5f` | Match pipe-separated visit prefixes correctly, and process combined visits without `ifelse` truncation. |
| `d733707`, `1c88b49`, `a3de00c` | Add fixed-grid `tile_stack_nep.R` aligned to the reference catalog. |
| `2954de7` | Stack unmatched frames using pipeline WCS instead of silently dropping them. |
| `3534151`, `192c755` | Expose `JUMPROPE_dq_dilate` to control DO_NOT_USE warp dilation. |
| `2067593`, `9b0e5e1`, `c4b51d1` | Add `profound_nep.R` multiband detection and forced per-filter measurement. |
| `0d2a528` | Detector1/Image2 use `.call()` so CRDS `pars-*` references apply. |

## Omega branch commits

| Commit | Change |
|---|---|
| `236b6a4` | Set unset DQ warp dilation to **1** at all three call sites; remove Mac absolute paths and require `JP_ROOT`. An unset value no longer defaults to 3. |
| `3250833` | Make `initialise_variables.R` accept config environment knobs: tweak catalog, modules, NAXIS, completion skipping, PSOCK parallel type. |
| `b43ed80` | `JUMPROPE_GRID_FILE` selects a task-specific master/program grid. |
| `43d3c5d` | `JUMPROPE_USE_ALIGNED_WCS` preserves a validated joint fit in ProPane stacking. |
| `dd00717` | Expose interpolation choice and join frame MAGZERO by filename. |
| `530d971` | Return cleanly when no NIRCam SW detector is selected. |
| `54b2373` | Export `wispFixer` into fresh PSOCK workers and surface worker errors. |
| `7f3d2b3` | Require `SCI_ORIG`, `REF_WISP_WARP` and `WISP_TEMPLATE` before skipping wisp work; restore original SCI before retry, retain indexing and clean up worker pools. |

The first inherited DQ option still defaulted to 3; commit `236b6a4` changed the actual defaults to 1. The PSOCK bug previously left wisps in F200W while `SCI_ORIG` alone looked like success. Normal production wisp parameters remain unchanged. Use working copies to protect original calibrated FITS, and verify source flux and residual structure.

Main entry points: `CALIBRATION/caljwst.py` (calibration), `PROCESS/run_all_process.R` (1/f, sky and wisp stages), `PROCESS/tile_stack_nep.R <instrument> <filter> <visit-regex> <label>` (ProPane on an explicit grid), `PROFOUND/profound_nep.R <instrument> <label>` (independent catalog). The parent project sets the environment and invokes them; use its CLI for a full campaign.

## [nep-miri] tile_stack_nep.R: opt-in stacking of FILTER=CLEAR frames (NIRISS), 2026-10-23
NIRISS F090W–F200W imaging has FILTER=CLEAR and the band in PUPIL. `deep_stacker` dropped every filter containing
"CLEAR", so 2738's NIRISS F200W direct images could never be stacked. With `JUMPROPE_ALLOW_CLEAR=T`, CLEAR is kept. The
notebook sets it only when all of a run's CLEAR frames share one pupil, so bands cannot mix. Default behaviour is unchanged.

## [nep-miri] tile_stack_nep.R: median-stack chunk size, 2026-10-24
`propaneStackWarpMed` stops when a grid dimension modulo its chunk (default 1000) is 1. The nircam-nep-v2 2738 grid is
30112 × 30001, so 11 of 12 NIRCam ProPane mosaics failed after their 20-minute inverse-variance stack. The chunk is now the
largest size ≤ 1000 that leaves no 1-pixel remainder in either dimension, taken from the grid JSON.
