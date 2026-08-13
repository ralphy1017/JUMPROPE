# JUMPROPE Operating And Revision Guide

This file is synchronized with [`AGENTS.md`](/data7/rzi/PEARLSplus/JUMPROPE/AGENTS.md) and documents the current stable working state of JUMPROPE as of Saturday, August 8, 2026.

It is written for future coding agents and operators who need to understand how JUMPROPE currently works, what was changed recently, and what must not be broken.

## Named Runs

- `PEARLSplus`
  - raw input tree:
    - `/data7/rzi/PEARLSplus/nircam/cal`
  - historical supervised output tree:
    - `/data7/rzi/PEARLSplus/jumprope/Pro1oF/cal_sky_renorm`
  - historical supervisor:
    - `PROCESS/run_all_until_done.sh`

- `SKYSURFIR`
  - raw input tree:
    - `/data4/rzi/NIRCAM/cal`
  - final output tree:
    - `/data5/rzi/JUMPROPE_SKYSURFIR/Pro1oF/cal_sky_renorm`
  - staging root:
    - `/home/rzi/jumprope/tmp_skysurfir`
  - target observation list:
    - [`PROCESS/skysurfir_obs_20260808.txt`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/skysurfir_obs_20260808.txt)
  - supervisor:
    - [`PROCESS/run_obs_until_done.sh`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/run_obs_until_done.sh)

## Scope

Primary user goal:
- Produce calibrated, sky-subtracted, pedestal-corrected, and wisp-removed `cal_sky_renorm` FITS products.
- Durable science products are the files under `Pro1oF/cal_sky_renorm`.
- Intermediate stacks, dump frames, sky frames, `cal`, `cal_sky`, `InVar_Stacks`, and `Median_Stacks` are expendable once final `cal_sky_renorm` files are verified and promoted.

Engineering goal:
- Keep JUMPROPE as functionally close as possible to the original pipeline.
- Improve stability first.
- Use RAM and SSD staging opportunistically, but do not break Rfits / ProPane / ProFound workflows just to reduce I/O.
- Avoid refactors that assume the pipeline can become fully object-native without FITS I/O.

## Current Stable Run Modes

There are two practical entrypoints:

1. `PROCESS/run_all_process.R`
- Preferred for full long-wave + wisp + short-wave processing.
- This is the most stable path for producing properly wisp-removed `cal_sky_renorm`.
- It explicitly runs long-wave preprocessing first, then `do_wisp_rem()`, then reruns the short-wave branch.

2. `PROCESS/zork_process.R`
- Still supports explicit step execution.
- Keep it literal: if the user passes steps `1,2,3,4,5,6,7,8,11`, it should do those steps and not silently append extra processing.

Operational rule:
- If the user wants final wisp-removed products with the fewest ambiguities, prefer `run_all_process.R`.
- If the user wants exact manual control over steps, use `zork_process.R`.

## Current Environment And Runtime Defaults

These values are currently set in [`initialise_env.sh`](/data7/rzi/PEARLSplus/JUMPROPE/initialise_env.sh):

```sh
export JUMPROPE_REF_DIR='/home/rzi/jumprope/tmp'
export JUMPROPE_RAW_DIR='/data4/rzi/NIRCAM/cal'
export JUMPROPE_FINAL_CAL_SKY_RENORM_DIR='/data5/rzi/JUMPROPE/Pro1oF/cal_sky_renorm'
export JUMPROPE_STAGING_MODE=TRUE

export JUMPROPE_cores_pro=64
export JUMPROPE_cores_stack=8
export JUMPROPE_tasks_stack=8

export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1

export JUMPROPE_CLEANUP=TRUE
export JUMPROPE_RAM_MODE=FALSE
export JUMPROPE_DUMP_DIR=/data7/rzi/PEARLSplus/jumprope/dump
```

Important interpretation:
- `JUMPROPE_REF_DIR` is currently being used as an SSD staging base, not the final archive.
- `JUMPROPE_FINAL_CAL_SKY_RENORM_DIR` is the durable output destination for promoted final products.
- `JUMPROPE_STAGING_MODE=TRUE` means `run_all_process.R` creates a fresh per-run session root under a sibling `tmp_sessions` directory and promotes completed outputs at cleanup time.
- `JUMPROPE_RAM_MODE=FALSE` is intentional in this stable version. SSD staging is the preferred stability path. Pure tmpfs RAM mode caused FITS and cfitsio failure modes.
- `JUMPROPE_DUMP_DIR` remains disk-backed because ProPane / cfitsio dump-frame writes were unstable on tmpfs.

These values are currently set in [`PROCESS/initialise_variables.R`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/initialise_variables.R):

```r
skip_completed_files = FALSE
ow_large = TRUE
do_claws = TRUE
parallel_type = 'PSOCK'
```

Important interpretation:
- `skip_completed_files = FALSE` means a normal run rebuilds each requested VID from scratch.
- If the user wants resume behavior, this variable must be changed to `TRUE`, or the code path must explicitly skip complete VIDs.
- `parallel_type = 'PSOCK'` is part of the stability fix set. Do not switch back to forked stacking casually.

## Directory Model

Current working pattern:

- Staging root:
  - `/home/rzi/jumprope/tmp`
- Per-run session root:
  - `/home/rzi/jumprope/tmp_sessions/run_<VID>_<PID>_<timestamp>`
- Durable final products:
  - `/data5/rzi/JUMPROPE/Pro1oF/cal_sky_renorm`

Within a staging run, JUMPROPE expects:

```text
<ref_dir>/
  Pro1oF/
    cal/
    cal_sky/
    cal_sky_renorm/
  sky_pro/
    sky_frames/
    sky_super/
  InVar_Stacks/
  Median_Stacks/
  Patch_Stacks/
  dump/
```

Durable product:
- `Pro1oF/cal_sky_renorm`

Usually disposable after verification:
- `Pro1oF/cal`
- `Pro1oF/cal_sky`
- `sky_pro/sky_frames`
- `sky_pro/sky_super`
- `InVar_Stacks`
- `Median_Stacks`
- `Patch_Stacks`
- `dump`

## Current Pipeline Logic

### `run_all_process.R`

[`PROCESS/run_all_process.R`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/run_all_process.R) is the main stable orchestration layer.

Key behavior:
- Reads env vars for raw dir, ref dir, staging mode, final renorm dir, and core settings.
- Creates isolated session directories when `JUMPROPE_STAGING_MODE=TRUE`.
- Builds `input_args`.
- Runs the main processing round:
  - `do_1of`
  - `do_cal_process`
  - `do_regen_sky_info`
  - `do_super_sky`
  - `do_apply_super_sky`
  - `do_modify_pedestal`
  - `do_cal_sky_info`
  - `do_gen_stack`
- For NIRCam:
  - processes long-wave filters first
  - runs `do_wisp_rem()`
  - reloads raw files
  - reruns the processing round for short-wave filters
- Runs `do_cleanup()` in staging mode.

This long-first, wisp, then short rerun is essential. It is the main reason `run_all_process.R` is more reliable than naïvely calling `zork_process.R` steps in sequence when the goal is true wisp propagation into final files.

### `zork_process.R`

[`PROCESS/zork_process.R`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/zork_process.R) remains step-driven.

Keep this rule:
- Do not make `zork_process.R` silently run extra steps beyond what stdin requested.

Earlier experimentation suggested making `1,2,3,4,5,6,7,8,11` behave more like `run_all_process.R`. That was not kept as the stable policy.

## Recent Structural Improvements

### 1. Isolated staging session roots

Implemented in [`PROCESS/run_all_process.R`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/run_all_process.R).

Problem before:
- multiple runs could share the same SSD staging root
- cleanup from one run could erase another run’s active intermediates

Stable fix:
- each `run_all_process.R` invocation now creates its own session directory:
  - `run_<VID>_<PID>_<timestamp>`
- cleanup only wipes that session root after promotion and validation

### 2. Promotion-aware cleanup

Implemented in [`PROCESS/all_codes_process.R`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/all_codes_process.R) via:
- `jp_expected_renorm_state()`
- `jp_cleanup_vid_intermediates()`
- `do_cleanup()`

Stable behavior:
- cleanup does not blindly delete intermediates
- staged `cal_sky_renorm` outputs are checked for completeness
- outputs are copied to `JUMPROPE_FINAL_CAL_SKY_RENORM_DIR`
- only then are staging products removed

For short-wave wisp-removed products, cleanup also checks for `SCI_ORIG` propagation where appropriate before removing related intermediates.

### 3. Safe FITS copy/write wrappers

Implemented in [`PROCESS/all_codes_process.R`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/all_codes_process.R):
- `copy_fits_with_validation()`
- `fits_write_pix_with_retry()`

### 4. Partial in-memory artifact store

Implemented in [`PROCESS/all_codes_process.R`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/all_codes_process.R):
- `jp_store_enabled()`
- `jp_store_set()`
- `jp_store_get()`
- `jp_store_list_set()`

Purpose:
- allow some pipeline stages to reuse in-memory objects when `use_in_memory_pipeline` is enabled
- avoid unnecessary rereads where practical

Important limitation:
- this is partial only
- JUMPROPE is still fundamentally FITS-centric
- ProPane / Rfits / ProFound still require on-disk FITS at critical points

## Critical Stability Patches By Function

### `do_gen_stack()`

File:
- [`PROCESS/all_codes_process.R`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/all_codes_process.R)

Stable changes kept here:
- PSOCK remains the preferred stable parallel backend
- image lists are kept in R memory rather than round-tripped through temporary FITS list files
- InVar stack write happens before median-stack computation
- `propaneStackWarpMed()` was constrained to avoid unsafe concurrent cfitsio handle behavior inside outer PSOCK tasks
- dump frames remain on disk rather than tmpfs because tmpfs FITS writes proved unstable

Practical rule:
- do not reintroduce temp `temp_list_*.fits` staging inside stack generation
- do not move dump-frame FITS output to `/dev/shm` unless cfitsio behavior is revalidated carefully

### `do_wisp_rem()`

File:
- [`PROCESS/all_codes_process.R`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/all_codes_process.R)

Stable changes kept here:
- missing long-wave reference stacks are now guarded before `propaneFrameFinder()` / `Rfits_key_scan()` are called
- invalid or `NA` reference filenames are filtered out
- missing long overlap no longer hard-crashes the run with:
  - `Assertion on 'filename' failed: 'NA' not readable.`

Observed behavior now:
- short-only or no-overlap cases log messages such as:
  - `No overlapping long wavelength for wisp correction`
  - `No long wavelength - skipping...`
- the run can continue instead of aborting

Important caveat:
- some no-overlap cases still produced sequential retry messages like:
  - `subscript out of bounds`
- the pipeline sometimes continued and still produced outputs
- this means the crash was fixed, but scientific correctness for those no-overlap wisp cases still needs independent verification

### `do_super_sky()`

Stable change:
- ensures `dirname(file_super_sky)` exists before writing

### `do_apply_super_sky()`

Stable change:
- if `sky_info.csv` is absent for a VID/filter combination, the function now skips cleanly rather than crashing

### `do_modify_pedestal()`

Stable behavior:
- uses validated FITS copies and retry-safe writes into `cal_sky_renorm`
- is part of the final product path and should not be bypassed casually

## Current Staging And Resume Semantics

### Full rebuild mode

Current default in `initialise_variables.R`:
- `skip_completed_files = FALSE`

Meaning:
- each requested VID is reset and rebuilt from the raw inputs
- staging intermediates for that VID are removed first
- in staging mode, final promoted outputs for that VID can also be removed before rebuild

### Resume mode

When `skip_completed_files = TRUE`:
- `run_all_process.R` checks final promoted outputs using `jp_expected_renorm_state()`
- fully complete VIDs are skipped
- incomplete VIDs continue processing

Practical rule:
- if the user says "start where it left off", set or confirm `skip_completed_files = TRUE`
- if the user says "rebuild from scratch", set or confirm `skip_completed_files = FALSE`

## RAM Mode Versus SSD Staging

The stable version is not "full RAM mode". It is hybrid.

What worked:
- SSD staging of the active run under `/home/rzi/jumprope/tmp_sessions/...`
- optional in-memory object reuse for selected internal objects

What did not prove stable enough:
- aggressive tmpfs use for all intermediate FITS outputs
- dump-frame FITS writes on `/dev/shm`
- assuming all stack inputs/outputs could stay purely in memory while still satisfying ProPane / Rfits expectations

Practical rule:
- prefer SSD staging mode for production
- treat `JUMPROPE_RAM_MODE` as experimental / partial
- do not market the current pipeline as "all in RAM"

## Self-Monitoring Supervisor Procedure

Use [`PROCESS/run_obs_until_done.sh`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/run_obs_until_done.sh) for named campaigns that should restart automatically until a fixed observation-ID set is complete.

The script:
- works at the observation-ID level
- compares raw `_cal.fits` counts against final `_cal_Pro1oF_sky_rem.fits` counts
- loops until all requested observations are complete
- preserves caller-supplied env overrides after sourcing `initialise_env.sh`

Important operational rule:
- if `run_all_process.R` is a child of `run_obs_until_done.sh` or `run_all_until_done.sh`, killing only `run_all_process.R` will not stop the run permanently
- kill the supervisor shell as well if the user wants the run stopped

## Why Wisp Removal Previously Looked Wrong

Key point:
- running stack generation plus wisp removal is not enough if the pipeline does not then propagate the correction into the final short-wave `cal_sky_renorm` branch correctly
- `run_all_process.R` handles this by:
  - long-wave processing
  - wisp removal
  - short-wave rerun

Earlier user observations of persistent wisps were partly due to:
- using `zork_process.R` step sequences that did not reproduce the full `run_all_process.R` ordering
- crashy stack/wisp paths
- some no-overlap cases where wisp correction could not be cleanly derived

Practical rule:
- if the scientific goal is truly wisp-removed `cal_sky_renorm`, use `run_all_process.R` unless there is a very specific reason not to

## Monitoring Guidance

Low-cost monitoring is preferred.

Useful checks:

```sh
ps -o pid,etime,%cpu,%mem,cmd -p <MASTER_PID>
tail -n 80 <logfile>
find <final_cal_sky_renorm_dir> -type f -name '*.fits' | wc -l
```

For staging runs, also inspect the session root:

```sh
find /home/rzi/jumprope/tmp_sessions/run_<...>/Pro1oF/cal -type f | wc -l
find /home/rzi/jumprope/tmp_sessions/run_<...>/Pro1oF/cal_sky_renorm -type f | wc -l
```

Interpretation:
- no new final files does not necessarily mean the run is dead
- JUMPROPE often spends long periods building staging intermediates before promotion

## PNG Inspection Helper

New helper script:
- [`PROCESS/make_random_png_samples.py`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/make_random_png_samples.py)

Purpose:
- generate asinh-stretched PNG inspection images from final `cal_sky_renorm` FITS files
- currently filters to:
  - `nrca1`
  - `nrca2`
  - `nrcb1`
  - `nrcb2`

## Files Most Important To Future Agents

Start here:
- [`initialise_env.sh`](/data7/rzi/PEARLSplus/JUMPROPE/initialise_env.sh)
- [`PROCESS/initialise_variables.R`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/initialise_variables.R)
- [`PROCESS/run_all_process.R`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/run_all_process.R)
- [`PROCESS/zork_process.R`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/zork_process.R)
- [`PROCESS/all_codes_process.R`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/all_codes_process.R)
- [`PROCESS/make_random_png_samples.py`](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/make_random_png_samples.py)
- [`AGENTS.md`](/data7/rzi/PEARLSplus/JUMPROPE/AGENTS.md)

## Rules For Future Revisions

1. Do not break `run_all_process.R` long-wave -> wisp -> short-wave ordering.
2. Do not silently make `zork_process.R` run extra steps.
3. Do not remove isolated staging session roots.
4. Do not delete staging outputs until final promoted `cal_sky_renorm` files are verified.
5. Do not move dump-frame FITS I/O to tmpfs without revalidating cfitsio stability.
6. Do not assume "RAM mode" means "no FITS I/O".
7. Treat no-overlap wisp cases as scientifically suspect until visually verified.
8. Prefer PSOCK over more aggressive fork-heavy parallel layouts.
9. Keep BLAS/OMP/MKL thread counts pinned to `1` when using the current parallel model.
10. When the user asks to resume, verify `skip_completed_files` semantics before launching.

## Recommended First Actions For A New Agent

1. Read `initialise_env.sh`.
2. Read `PROCESS/initialise_variables.R`.
3. Confirm whether the user wants:
   - rebuild from scratch
   - resume and skip complete outputs
4. Confirm whether the user wants:
   - `run_all_process.R`
   - `zork_process.R`
5. Inspect current staging and final output directories before editing cleanup logic.
6. If changing stack or wisp logic, test on one problematic VID first before launching a large batch.
