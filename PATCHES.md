# JumProPe `nep-miri` changes, organized

This branch is Jordan's upstream `main` (JordanDSilva/JUMPROPE `0c73324`) plus the `[nep-miri]` commits below. Every change sits in exactly one of five groups:

1. **Bug fixes.** Jordan's code crashed or produced wrong results. Keep all of them.
2. **Default changes.** Results differ from Jordan's even if you set nothing. Each one is a choice to confirm.
3. **Opt-in features.** These are off unless you set something, so they don't change default results.
4. **NEP-only tools.** These were written for the NEP TDF reduction. A generic run doesn't need them.
5. **Known open bugs.** Not fixed yet.

The column **"cal / renorm?"** says whether a change can alter the products you always need: `Pro1oF/cal` and `Pro1oF/cal_sky_renorm`.

---

## 1. Bug fixes to Jordan's code

| What was broken | Fix | Commit(s) | cal / renorm? |
|---|---|---|---|
| jwst ≥ 3 writes DQ as uint32. Rfits reads it as `integer64`, so `DQ %% 2` failed with "Not a matrix." in 1/f, sky, pedestal and stacking. | `dq_numeric()` converts DQ to a numeric matrix at each read. | `e54f672`, `715f1c0` (`tile_stack.R`) | yes: the stages crashed before |
| `do_cal_sky_info` used an undefined variable `s` for the CRDS context. | Use `cal_sky_info$CRDS_CTX`. | `d857f23` | no (stacking zeropoints) |
| `VID='A\|B'` was matched as the literal string "A\|B", so nothing matched. | `vid_match()`: keep visit IDs that start with any of the parts. | `6fafbe0` | yes: file selection |
| `run_all_process.R` used `ifelse()` on the VID list, which returns only its first element. Only the first visit or program was ever processed. | Replaced. *See group 2: the replacement also changed the loop into one combined pass.* | `a24ca5f` | yes |
| Wisp removal on PSOCK workers: fresh workers don't see `wispFixer`, and `.errorhandling="pass"` hid the error. Files kept their wisps but looked done. | Export `wispFixer` to workers; `.errorhandling="stop"`. | `54b2373` | yes: SW wisps were left in |
| Wisp retry could subtract a template twice. Skipped rows shifted the LW-reference list out of line with the exposures. A worker error left the cluster running. | Restart from `SCI_ORIG`; "done" needs all wisp extensions present; index the reference list by exposure; clean up the cluster with `on.exit`. | `7f3d2b3` | yes |
| A selection with no SW wisp detectors (LW-only) crashed in `do_wisp_rem`. | Return early. | `530d971` | no (crash only) |
| With `sigma_lo` set, a template pixel still NA after the low-pass fill blanked the science pixel. | NA → 0 after the fill. | `bb316e1` | yes, only if `sigma_lo` is set |
| `clip_threshold` took a quantile of an empty positive or negative tail. | Skip clipping when `clip_threshold = 1` or the tail is empty. | `aa5e701` | edge case |
| `tile_stack.R` dropped any frame with no reference-catalog match from the stack. | Keep it, using its pipeline WCS. | `2954de7` | no (stacks) |
| `caljwst.py` called `Pipeline().run()`, which ignores CRDS parameter reference files (`pars-*`), e.g. NIRCam snowball expansion and MIRI shower flagging. | Use `Pipeline.call()`. **Changes the calibrated `_cal.fits` themselves.** | `0d2a528` | yes, upstream of everything |
| `caljwst.py` crashed for `--VISITID` downloads, which write `<pid>_UNCAL.csv` and no `*info.csv`. | Only compare against the table when one exists. | `a485e83` | no |
| `query.py` used `np.core.defchararray`, which NumPy 2 removed. | `np.char.find`. | `a485e83` | no |
| `query.py` tried a MAST login with the placeholder token `9999`. | Skip the login for an empty token or `9999`. | `55fd1a1` | no |

## 2. Default changes (results differ from Jordan's without opting in)

| Change | Jordan | Now | Commit(s) | cal / renorm? |
|---|---|---|---|---|
| **wispFixer parameters** | sky 0.5, clip 0.997, σ_hi 2, σ_lo NULL (`run_all_process.R` passes NULL) | sky **0.4**, clip **1** (no clipping), σ_hi **0.5**, σ_lo NULL | `aa5e701` | **yes**, SW wisp frames |
| Several visits in one call | meant to loop over each VID (broken, see group 1) | **one combined pass**, so super-skies use every listed visit together | `a24ca5f` | **yes**, super-sky |
| Parallel backend | fork (`parallel_type = NULL`) | **PSOCK**. Avoids a fork + multithreaded-BLAS deadlock on Linux. | `3250833` | no (stability only) |
| DQ dilation before warping (stacks) | 3×3 | **1** (none). Set it with `JUMPROPE_dq_dilate`. | `3534151`, `192c755`, `236b6a4` | no (stacks only) |
| MAST query | all products of the visit | imaging only (NIRCam, MIRI imager, NIRISS imaging); no coronagraphy or TA | `a485e83` | no (what gets downloaded) |

Why the wisp defaults changed: on 28 frames from program 12529 F200W (A3/A4/B3/B4), this profile left less wisp. It was tuned on that one program and filter. An injection test there recovered only about 19% of compact SW-only source flux. Details are in `docs/wisp-validation-12529.md`. To get Jordan's behaviour back, set:

```
JUMPROPE_WISP_PARAMS='{"sky_threshold":0.5,"clip_threshold":0.997,"sigma_hi":2,"sigma_lo":null}'
```

## 3. Opt-in features (no effect unless you set them)

**Calibration and download**

| Setting | What it does | Commit |
|---|---|---|
| `caljwst.py --nproc N` | Calibrate N uncal files at once. | `a485e83` |
| `caljwst.py --match _nrc` | Calibrate only files whose name contains the string. | `700b5e2` |
| `JUMPROPE_dl_threads` | Parallel MAST downloads; default 8, skips files already complete. | `a485e83` |

**Settings in `initialise_variables.R` that can now come from the environment.** If unset, Jordan's defaults apply.

| Setting | Commit |
|---|---|
| `JUMPROPE_SKIP_COMPLETED_FILES` | `3250833` |
| `JUMPROPE_TWEAK_CATALOGUE` (*see open bug O5: currently has no effect*) | `3250833` |
| `JUMPROPE_NAXIS_LONG`, `JUMPROPE_NAXIS_SHORT` | `3250833` |
| `JUMPROPE_MODULE_LIST` | `3250833` |
| `JUMPROPE_PARALLEL_TYPE` | `3250833` |

**Wisp settings**

| Setting | What it does | Commit |
|---|---|---|
| `JUMPROPE_WISP_PARAMS` (JSON) or `additional_params$wisp_params` | Set any wispFixer parameter. JSON `null` for `sigma_lo` turns it off explicitly. | `bb316e1`, `aa5e701` |
| `wisp_params.method = "nmf"` | JADES NMF template fit, F200W only. Downloader: `PROCESS/fetch_wisp_templates.py`. Vendored solver: `PROCESS/vendor/`. | `c7051a6` |
| `wisp_params.method = "masked_dynamic"` | wispFixer with source masks filled by the NMF prediction. Kept for comparison only; it leaves circular background offsets. | `c7051a6` |
| `wisp_params.method = "continuous_dynamic"` | Signed residual templates learned from the other exposures on the same detector. Needs at least 3 exposures per detector/filter, plus `PROCESS/prepare_wisp_continuous.py` run on NMF outputs first. F200W only. Guide: `PROCESS/WISP_NMF.md`. | `c7051a6` |
| Source-mask propagation | When a frame has a `WISP_SOURCE_MASK` extension (only the three methods above write one), 1/f, sky and pedestal estimation also mask those pixels. DQ is unchanged. | `c7051a6` |

Tests: `tests/test_wisp_defaults.R`, `tests/test_wisp_source_mask.R` and `tests/test_wisp_continuous.py`, all run from the repo root.

## 4. NEP-only tools (not needed for a generic run)

| File | Purpose | Commits |
|---|---|---|
| `PROCESS/tile_stack_nep.R` | ProPane mosaics on a fixed grid from the parent project. Needs `JP_ROOT`, a grid JSON, and the patched ProPane 1.12.1.2, which is **not in this repo**. | `d733707`, `1c88b49`, `a3de00c`, `b43ed80`, `43d3c5d`, `dd00717`, `e5f2713` |

`tile_stack_nep.R` options:
- `JUMPROPE_GRID_FILE`
- `JUMPROPE_USE_ALIGNED_WCS`
- interpolation choice
- `JUMPROPE_ALLOW_CLEAR=T`, for NIRISS FILTER=CLEAR
- a median-stack chunk size that avoids ProPane's 1-pixel-remainder failure

| File | Purpose | Commits |
|---|---|---|
| `PROFOUND/profound_nep.R` | Multiband detection plus forced per-filter ProFound catalogs on those mosaics. | `2067593`, `9b0e5e1`, `c4b51d1`, `236b6a4` |
| `initialise_env_nep.sh` | The NEP machine's environment, with Mac paths. An example only. | `9261ae1`, `42e590f`, `3534151` |
| `docs/wisp-validation-12529.md` | Wisp validation for program 12529. | `c7051a6` |

## 5. Known open bugs (not fixed yet)

Line numbers refer to `PROCESS/all_codes_process.R` at `c7051a6`, unless the line names another file.

| # | Bug | Where | Effect |
|---|---|---|---|
| O1 | Concurrent runs in one `REF_DIR` share `sky_info.csv`, the `super_<DET>_<FILT>.fits` files, `cal_sky_info.csv` and `InVar_Stacks/temp_list_<i>.fits`. `do_gen_stack` also deletes every `temp_list_*` it finds. | `:646`, `:737`, `:1145`, `:1279`, `:1415` | Parallel visit runs corrupt each other's super-sky and `cal_sky_renorm`. |
| O2 | NIRISS: `FILT` is forced to `"CLEAR\|NIS"`, and the super-sky is keyed on `FILTER`, which is `CLEAR` for F090W–F200W (band in `PUPIL`). | `run_all_process.R:74,148`; `:737`, `:827` | NIRISS bands share one super-sky. NIRISS F277W–F480M are skipped. |
| O3 | `make_directory_structure()` reads stdin when `JUMPROPE_REF_DIR` is unset. | `:2359` | Unattended runs hang. |
| O4 | `do_gen_stack` filters visits with `grep("^A\|B")`. Only the first part is anchored. | `:1204` | Can match an unrelated visit ID that contains B. |
| O5 | `do_gen_stack` reads `additional_params$ref_cat`, but `initialise_variables.R` defines `tweak_catalogue` (in upstream too). | `:1165` | `JUMPROPE_TWEAK_CATALOGUE` never turns on tweaking. |

**Not bugs, but slow at database scale:**
- **Header scans of the whole database.** `run_all_process.R:164` scans all raw files, `:173` re-lists the raw folder, and `do_cal_sky_info` (`:1113`) rescans all of `cal_sky_renorm/`. These run on every call, whatever the VID.
- **Wisp edits to raw files.** The wisp stage writes into the raw `_cal.fits` files in place (`:1757`). This is upstream behaviour: `SCI_ORIG` is kept, and `PROCESS/reverse_wisp_fix.R` restores the original.
