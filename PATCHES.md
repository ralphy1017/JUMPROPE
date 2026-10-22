# nep-miri: fixes and additions to JumProPe v2.2.0

Branch `nep-miri`, made to reduce the public MIRI (6616, 8303, 12529) and NIRCam (12529) imaging of the JWST NEP Time-Domain Field
with jwst 3.0.0 and CRDS `jwst_1584.pmap`. Every change is marked `## [nep-miri]` (R) or `# [nep-miri]` (Python) in the code.
Nothing upstream is removed. The NEP environment file is `initialise_env_nep.sh`; its paths are this machine's (`~/JP`), so edit them.

New entry points:

| Script | Usage |
|---|---|
| `CALIBRATION/caljwst.py` | `--VISITID <pid> --match _mirimage_\|_nrc --max_cores 1 --nproc 4` |
| `PROCESS/tile_stack_nep.R` | `Rscript tile_stack_nep.R <miri\|nircam> <FILT> <VISIT_ID-prefix regex> <label>`. Mosaic on a fixed global grid (`$JP_ROOT/grids/grid_<inst>.json`), aligned to `$JP_ROOT/refcat.csv`. |
| `PROFOUND/profound_nep.R` | `Rscript profound_nep.R <miri\|nircam> <label>`. ProFound catalogs (JumProPe settings) of the `tile_stack_nep.R` mosaics. |

Known open issue (2026-10-22): on MIRI, ProPane's warp in `tile_stack_nep.R` loses 12–82% of the frame coverage,
because many output pixels fail the s2p mapping. jwst Stage 3 on the same `cal_sky_renorm` frames covers them fully.

## Patches to JumProPe (branch `nep-miri`; marked `## [nep-miri]` in the code)

| Commit | File | Change |
|---|---|---|
| a485e83 | CALIBRATION/caljwst.py | `--nproc N`: N uncal files in parallel (spawned processes, each with `--max_cores`). The `*info.csv` concat is guarded, because VISITID mode writes `<pid>_UNCAL.csv` and `pd.concat([])` raised. |
| a485e83 | CALIBRATION/query.py | `vid_query` keeps NIRCam, MIRI-imager and NIRISS imaging only, with no coronagraphic filters. Parallel download (`JUMPROPE_dl_threads`). `np.core.defchararray` → `np.char` for numpy 2. |
| 55fd1a1 | CALIBRATION/query.py | Skip the MAST login for the placeholder token 9999. |
| 9261ae1, aaad6fc, c605dbd, 42e590f | PATCHES.md, initialise_env_nep.sh | NEP environment file. `RAW_DIR` holds only cal-file links. |
| e54f672 | PROCESS/all_codes_process.R | `dq_numeric()`: jwst 3 DQ is uint32, which Rfits reads as `integer64`, so `DQ %% 2` is not a matrix and `profoundDilate` fails with "Not a matrix.". Applied at the five DQ reads: 1/f, cal_process, pedestal and stacking. |
| d857f23 | PROCESS/all_codes_process.R | `do_cal_sky_info`: the CRDS context came from an undefined `s`; it now uses `cal_sky_info$CRDS_CTX`. |
| 6fafbe0 | PROCESS/all_codes_process.R | `vid_match()`: `VID="A\|B"` was matched as a literal string; it now selects every VISIT_ID that starts with any of the parts (6 places). |
| a24ca5f | PROCESS/run_all_process.R | `VID_list = ifelse(...)` kept only the first of `"A\|B\|C"`. The combined VID now runs in one pass, so the super-skies use all programs. |
| d733707, 1c88b49, a3de00c | PROCESS/tile_stack_nep.R | New. Calstack mosaics of one filter and one group on the global grid (`grid_<inst>.json` → `ref_frame`), aligned to `refcat.csv`. Usage: `tile_stack_nep.R <inst> <FILT> <group regex> <label>`; root from `$JP_ROOT`. |
| 715f1c0 | PROCESS/tile_stack*.R | integer64 DQ (as e54f672). |
| 2954de7 | PROCESS/tile_stack*.R | Frames without reference-catalog matches were left out of the stack (`twIDX = NA`); 8303 F1000W lost 4 of 12. They are now stacked with their pipeline WCS. |
| 3534151, 192c755 | PROCESS/tile_stack*.R, all_codes_process.R (`do_gen_stack`) | `JUMPROPE_dq_dilate`: the DO_NOT_USE mask was dilated 3×3 before warping, so MIRI's 5.9% masked pixels became 19% NaN holes. Set to 1 for NEP; the sky masks keep 3×3. **The default when the variable is unset is still 3** (see `CONTEXT.md`). |
| 2067593, 9b0e5e1, c4b51d1 | PROFOUND/profound_nep.R | New. ProFound catalogs with JumProPe's `profound_detect_master` / `profound_measure_master`. Detection on the inverse-variance-weighted stack of all filters of a label; forced measurement per filter. Usage: `profound_nep.R <inst> <label>`. Output `PRO/ProFound/<inst>_<label>/{detect_segim.fits, cat_detect.csv, cat_<FILT>.csv, cat_multiband.csv}`. For `all`, filters that only one group has use that group's mosaic. |
| 0d2a528 | CALIBRATION/caljwst.py | Detector1/Image2 via `.call()`, so the CRDS `pars-*` apply (see Calibration parameters). |
| 700b5e2 | CALIBRATION/caljwst.py | `--match STR`: only uncal files whose name contains STR (e.g. `_mirimage_`, `_nrc`). |

