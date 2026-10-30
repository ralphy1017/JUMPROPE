# Changes from Jordan's JumProPe

This repository is [JordanDSilva/JUMPROPE](https://github.com/JordanDSilva/JUMPROPE) at commit `0c73324`, plus the bug fixes and settings below. It runs exactly like the original:

```sh
source initialise_env.sh            # paths and cores
# edit PROCESS/initialise_variables.R  (1/f mode, wisp/claw removal, stacks)
cd PROCESS
Rscript run_all_process.R 1345001001                        # one visit (or a PID, e.g. 1345)
Rscript run_all_process.R '1345001001|1345002001|2736001001' # several visits, one after another
```

Nothing from the NEP TDF project is included: no NMF/continuous wisp methods, Python helpers, NEP mosaic or catalog scripts, or patched ProPane. Code changes are marked `[fix]` or `[change]` in comments. Tests: `Rscript tests/test_fixes.R` and `Rscript tests/test_run_all.R` (from the repository root).

## Wisp removal settings

Wisp removal is Jordan's `wispFixer` routine, with these settings in `PROCESS/initialise_variables.R` (`wisp_params`):

| Parameter | Jordan's run | Now |
|---|---|---|
| `source_threshold` | 0.95 | 0.95 |
| `scale_threshold` | 0.95 | 0.95 |
| `sky_threshold` | 0.5 | 0.5 |
| `clip_threshold` | 0.997 | **0.9999** |
| `sigma_hi` | 2 | 2 |
| `sigma_lo` | NULL (`run_all_process.R` passed NULL; the function default was 20) | **2** |

Visits listed in `ID_large` / `ID_vlarge` still use `sigma_lo = NULL`, which now actually takes effect (see the bug-fix table).

## Bug fixes

| Bug | Effect before | Where |
|---|---|---|
| jwst ≥ 3 writes DQ as uint32. Rfits reads it as `integer64`, and `DQ %% 2` failed. | "Not a matrix." in 1/f, sky, pedestal and stacking | `all_codes_process.R`, `tile_stack.R` |
| `ifelse()` on the VID list returns only its first element. | `'A\|B\|C'` processed only A | `run_all_process.R` |
| VID matched as a fixed string. | `'A\|B'` matched no frames | `load_files`, `do_gen_stack`, `do_RGB` (`vid_match`) |
| `glob2rx()` on a VID containing `\|`. | Wrong file pre-selection | `load_files`, `do_regen_sky_info` |
| `do_gen_stack` used `grep("^A\|B")`. | Only the first VID was anchored, so others could match the middle of an unrelated ID | `do_gen_stack` |
| `do_cal_sky_info` used an undefined variable `s`. | The stage crashed | `do_cal_sky_info` |
| The most recent CRDS pmap was chosen with a string `max()`. | `"999"` beat `"1584"` | `do_cal_sky_info` |
| `do_gen_stack` read `ref_cat`, but `initialise_variables.R` sets `tweak_catalogue`. | The astrometric tweak never ran | `do_gen_stack` |
| PSOCK workers did not have `wispFixer`, and `.errorhandling="pass"` hid the error. | With `parallel_type='PSOCK'`, no frame was wisp-corrected, silently | `do_wisp_rem` |
| A rerun read the already-corrected SCI. | The template was subtracted twice | `do_wisp_rem`: restart from `SCI_ORIG` |
| A frame counted as "done" when only `SCI_ORIG` existed, which is written *before* the fit. | Failed fits were skipped with `skip_completed_files` | `do_wisp_rem` |
| The LW reference list was built with `c()`, which drops missing references. | References misaligned with exposures (wrong LW image used) | `do_wisp_rem` |
| `ID_large` / `ID_vlarge` compared `"NRCA"` against `'A'`. | `sigma_lo = NULL` for crowded visits never applied | `do_wisp_rem` |
| `sigma_lo` fill left NA where the low-pass was also NA. | Those science pixels were blanked | `wispFixer` |
| `make_directory_structure()` read stdin. | Batch runs stopped at a prompt | `run_all_process.R`, `zork_process.R` |
| NIRISS F090W–F200W have `FILTER=CLEAR` (band in `PUPIL`), and `FILT` was forced to `"CLEAR\|NIS"`. | All NIRISS bands shared one super sky and one stack; NIRISS F277W–F480M were skipped | Bands from `PUPIL` everywhere (`band_of`) |
| NIRCam F162M/F164N/F323N/F405N/F466N/F470N have the band in `PUPIL`. | Treated as F150W2/F322W2/F444W in super skies and stacks | Same |
| The NIRCam long-wavelength filter list was applied to NIRISS and MIRI runs too. | Most NIRISS filters and every MIRI filter were skipped | `run_all_process.R` |
| F322W2 was missing from the long-wavelength list. | Never processed | `run_all_process.R`, `zork_process.R` |
| Non-imaging `_cal.fits` (WFSS, SOSS, AMI, NIRSpec…) in `RAW_DIR` were processed. | Wrong frames in sky and stacks | `load_files` keeps `*_IMAGE` exposures |
| `tile_stack.R` dropped frames with no reference-catalogue match. | Missing frames in mosaics | `tile_stack.R` |
| `tile_stack.R` matched `MAGZERO_FIX` with `%in%`. | Zeropoints could go to the wrong frames | `tile_stack.R` |
| `caljwst.py` used `Pipeline().run()`, which ignores CRDS parameter reference files (`pars-*`). | Instrument/filter-specific step settings (e.g. snowball and shower flagging) were not applied. **Changes the `_cal.fits`.** | `caljwst.py` uses `.call()` |
| `caljwst.py` crashed when no `*info.csv` existed (`--VISITID` downloads). | Crash | `caljwst.py` |
| `np.core.defchararray` was removed in NumPy 2. | Crash | `query.py` |
| MAST login with the placeholder token `9999`. | Failed login | `query.py` |

## Running many visits

Several things in Jordan's code assumed one small run at a time. They are fixed so a long list of VIDs, or several `Rscript` runs at once, works on a large database.

- **Per-visit processing.** Each VID in `'A|B|C'` is processed on its own, in turn: 1/f, sky, super sky, pedestal and wisp. This is what Jordan's loop intended. Super skies are built from that visit's frames. A PID such as `1345` is still one run over all of its visits.
- **One failing visit no longer stops the rest.** Failed VIDs are listed at the end and written to `JUMPROPE_REF_DIR/failed_VIDs_<time>.txt`, and the exit status is 1. Wisp fits that fail are reported by file name.
- **Per-VID bookkeeping files.** These let separate runs share one `JUMPROPE_REF_DIR`:
  - `sky_pro/sky_info_<VID>.csv`
  - `sky_pro/sky_super/<VID>/super_<DET>_<BAND>.fits`
  - `Pro1oF/cal_sky_info_<VID>.csv`
  - `InVar_Stacks/temp_list_<VID>_<i>.fits` (`do_gen_stack` used to delete every `temp_list_*`)

  A run with no VID (`Rscript run_all_process.R`) keeps Jordan's original names. `tile_stack.R` reads `Pro1oF/cal_sky_info.csv` if it exists, and otherwise combines the per-VID files.
- **No database-wide scans.** Each run reads only its own visit's headers. Previously, every run read every raw file header, re-listed `RAW_DIR`, and rescanned all of `Pro1oF/cal_sky_renorm/`.
- **MAGZERO_FIX scope.** `MAGZERO_FIX` (stacks only) is now referenced to the newest CRDS context among that visit's files. Before, the reference was the newest context in the whole `cal_sky_renorm` directory. For data calibrated with one context, the two are the same.

## New options in `initialise_variables.R`

- `wisp_params`: the `wispFixer` settings above. Use `sigma_lo = NULL` to turn the low-pass fill off. Unknown names are rejected.
- `make_stacks` (default `TRUE`, Jordan's behaviour): when `FALSE`, a run produces only `Pro1oF/cal` and `Pro1oF/cal_sky_renorm`. NIRCam long-wavelength stacks are still made, because wisp removal uses them as the reference.

## Unchanged behaviour to be aware of

- **Wisp removal edits the raw `_cal.fits` in `JUMPROPE_RAW_DIR` in place.** It adds `SCI_ORIG`, `REF_WISP_WARP` and `WISP_TEMPLATE` extensions. `PROCESS/reverse_wisp_fix.R` restores the original. Keep a copy of the raw data if you need it untouched.
- **`parallel_type`** defaults to `NULL` (forked workers), as in Jordan's code. If runs hang on Linux, set `parallel_type = 'PSOCK'`; this is a known fork + multithreaded-BLAS issue.
- **NIRCam, NIRISS and MIRI are separate runs**, selected with `JUMPROPE_do_NIRISS` / `JUMPROPE_do_MIRI`.
