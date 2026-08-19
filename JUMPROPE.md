# JUMPROPE Stable Architecture And Operations Guide

This file documents the current stable working state of JUMPROPE as of Wednesday, August 19, 2026.

It is the repo-native handoff for future agents and operators who need to know:

- how the stable version is structured
- what changed from the original workflow
- what failure modes were already diagnosed
- how to configure large PEARLSplus and SKYSURFIR production runs
- what must not be casually changed

## Scope

Primary science goal:

- Produce fully processed JWST exposure products in:
  - `Pro1oF/cal`
  - `Pro1oF/cal_sky_renorm`
- `cal` is needed for calibrated, non-sky-subtracted science use.
- `cal_sky_renorm` is needed for sky-subtracted, pedestal-corrected, wisp-removed science use and mosaic input.

Primary engineering goal:

- Keep JUMPROPE close to the original code path.
- Stabilize it for large databases.
- Use RAM and SSD staging opportunistically.
- Do not break the FITS-centric workflow required by Rfits / ProPane / ProFound.

## Stable Entry Points

There are two real execution modes.

1. `PROCESS/run_all_process.R`

- Preferred for final science production.
- This is the stable path for real wisp removal.
- It does:
  - long-wave preprocessing first
  - `do_wisp_rem()`
  - raw reload
  - short-wave rerun
- This ordering is essential.

2. `PROCESS/zork_process.R`

- Keep this literal and step-driven.
- If the user passes steps `1,2,3,4,5,6,7,8,11`, it should do exactly those steps.
- Do not silently append extra work to mimic `run_all_process.R`.

Operational rule:

- Use `run_all_process.R` for durable wisp-removed products.
- Use `zork_process.R` only when explicit manual step control matters more than convenience.

## What Actually Made Wisp Removal Work

This was the central debugging result.

The successful behavior was not just a parameter tweak. The stable solution required all of the following:

1. Correct orchestration

- Long-wave data must be processed first.
- Wisp removal must run after long-wave stacks exist.
- The short-wave branch must then be rerun so the wisp correction propagates into final products.

2. Stable short-grid long-wave references

- The corrected code path uses the short-grid reference stacks for short-wave correction.
- Earlier broken behavior could select or infer the wrong reference context and leave wisps effectively uncorrected.

3. Stable defaults

- `JUMPROPE_WISP_SIGMA_LO=2` is the validated production default in this stable version.
- This value was empirically verified on the PEARLSplus `2514` observations where wisp removal was visually confirmed.

4. Diagnostics preserved in products

- The pipeline preserves key extensions and metadata that let us verify what happened:
  - `SCI_ORIG`
  - `REF_WISP_WARP`
  - `WISP_TEMPLATE`

Practical rule:

- If wisps appear to persist, first verify that the run used `run_all_process.R`, the stable code path, and `JUMPROPE_WISP_SIGMA_LO=2`.

## Stable Production Defaults

Validated defaults for large production campaigns:

```sh
export JUMPROPE_cores_pro=32
export JUMPROPE_cores_stack=8
export JUMPROPE_tasks_stack=4

export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1

export JUMPROPE_STAGING_MODE=TRUE
export JUMPROPE_CLEANUP=TRUE
export JUMPROPE_RAM_MODE=FALSE

export JUMPROPE_WISP_SIGMA_LO=2
export JUMPROPE_STAGE_MULTIPLIER=5.0
export JUMPROPE_MIN_SSD_FREE_GIB=500
```

Interpretation:

- `32` cores per database is the stable large-run setting.
- `tasks_stack=4` and `cores_stack=8` keep stacking parallel enough without reviving the old failure modes.
- BLAS/OMP/MKL threads stay pinned to `1` because the stable model uses explicit parallel workers and nested threaded math caused instability.
- `RAM_MODE=FALSE` is intentional. Production uses SSD staging, not full tmpfs mode.

## Repo-Native Campaign Templates

The repo now contains stable campaign env templates:

- [initialise_env.pearlsplus.sh](/data7/rzi/PEARLSplus/JUMPROPE/initialise_env.pearlsplus.sh)
- [initialise_env.skysurfir.sh](/data7/rzi/PEARLSplus/JUMPROPE/initialise_env.skysurfir.sh)

These are templates for the two major databases.

### PEARLSplus template

- raw input:
  - `/data7/rzi/PEARLSplus/nircam/cal`
- staging root:
  - `/home/rzi/jumprope/pearl_stage`
- final outputs:
  - `/data7/rzi/PEARLSplus/jumprope/Pro1oF/cal`
  - `/data7/rzi/PEARLSplus/jumprope/Pro1oF/cal_sky_renorm`
- target manifest:
  - [PROCESS/pearlsplus_obs_20260813.txt](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/pearlsplus_obs_20260813.txt)
- QA PNG output:
  - `/data7/rzi/PEARLSplus/png/live_qc_nrcb34`

### SKYSURFIR template

- raw input:
  - `/data4/rzi/NIRCAM/cal`
- staging root:
  - `/home/rzi/jumprope/skysurfir_stage`
- final outputs:
  - `/data5/rzi/jumprope-skysurfir/Pro1oF/cal`
  - `/data5/rzi/jumprope-skysurfir/Pro1oF/cal_sky_renorm`
- target manifest:
  - [PROCESS/skysurfir_obs_20260808.txt](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/skysurfir_obs_20260808.txt)
- QA PNG output:
  - `/data5/rzi/jumprope-skysurfir/png_qc_nrcb34`
- overlap avoidance:
  - `JUMPROPE_SHARED_SKIP_CAL_DIR=/data7/rzi/PEARLSplus/jumprope/Pro1oF/cal`
  - `JUMPROPE_SHARED_SKIP_RENORM_DIR=/data7/rzi/PEARLSplus/jumprope/Pro1oF/cal_sky_renorm`

Practical rule:

- Keep `initialise_env.sh` as the active local config.
- Keep the two template files as durable repo-native references.

## Observation Manifests

Stable large-run manifests are stored in:

- [PROCESS/pearlsplus_obs_20260813.txt](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/pearlsplus_obs_20260813.txt)
- [PROCESS/skysurfir_obs_20260808.txt](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/skysurfir_obs_20260808.txt)

These are intended for automated restartable supervisors, not just ad hoc manual runs.

## Current Supervisor Model

The stable production supervisor is:

- [PROCESS/run_obs_until_done.sh](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/run_obs_until_done.sh)

This script is part of the stable architecture, not just a convenience wrapper.

Key behavior:

- sources `initialise_env.sh`
- preserves caller overrides after sourcing
- normalizes observation-ID manifests
- computes completeness by comparing raw `_cal.fits` counts to final promoted outputs
- launches `run_all_process.R` repeatedly until the requested observation-ID set is complete
- holds a per-run lock file to avoid duplicate supervisors
- renders QA PNGs for completed observations if configured
- stops after repeated no-progress passes instead of looping forever

## Staging Strategy

The stable production model is hybrid SSD staging, not true all-RAM execution.

What is stable:

- active run products staged on SSD
- selective in-memory reuse of some R objects
- final promotion into durable output directories only after completeness checks

What is not stable enough to call production:

- forcing all intermediates onto `/dev/shm`
- treating all FITS artifacts as temporary in-memory objects only
- moving ProPane / cfitsio dump products to tmpfs

Practical rule:

- Use RAM where the code already safely supports it.
- Do not redesign around the assumption that JUMPROPE can run without intermediate FITS files. It cannot yet.

## Current Directory Model

For a staging run, JUMPROPE expects:

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

Product meaning:

- `Pro1oF/cal`
  - calibrated products used for non-sky-subtracted science and background analysis
- `Pro1oF/cal_sky_renorm`
  - calibrated, sky-subtracted, pedestal-corrected, wisp-removed products used for mosaics and general science

Disposable after successful promotion:

- `sky_pro`
- `InVar_Stacks`
- `Median_Stacks`
- `Patch_Stacks`
- `dump`
- staged `Pro1oF/cal`
- staged `Pro1oF/cal_sky`
- staged `Pro1oF/cal_sky_renorm`

## Structural Changes That Were Kept

### 1. Isolated session roots

Implemented in [PROCESS/run_all_process.R](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/run_all_process.R).

Stable behavior:

- each `run_all_process.R` call gets its own session root
- cleanup only wipes that session root after promotion succeeds

Why it matters:

- one run can no longer erase another run's active staging products

### 2. Promotion-aware cleanup

Implemented in [PROCESS/all_codes_process.R](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/all_codes_process.R).

Stable behavior:

- staged final products are validated before cleanup
- outputs are promoted to final `cal` and `cal_sky_renorm` directories
- intermediates are only removed after the promoted state is complete

Why it matters:

- this prevents cleanup from turning partial runs into silent data loss

### 3. Retry-safe FITS writes

Implemented in [PROCESS/all_codes_process.R](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/all_codes_process.R).

Stable behavior:

- key FITS write paths use validation and retry wrappers

Why it matters:

- transient FITS I/O failures were a recurring crash source

### 4. Partial in-memory store

Implemented in [PROCESS/all_codes_process.R](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/all_codes_process.R).

Stable behavior:

- selected objects can be reused in memory where safe

Why it matters:

- it cuts avoidable rereads without pretending the whole pipeline is object-native

## Critical Failure Modes Already Diagnosed

### Stack-generation crashes

Main fixes kept in `do_gen_stack()`:

- use `PSOCK`
- avoid round-tripping image lists through temporary FITS list files
- write InVar stacks before median stacks
- keep dump frames on disk
- constrain `propaneStackWarpMed()` to avoid unsafe concurrent cfitsio handle usage

Practical rule:

- do not reintroduce `temp_list_*.fits` staging for stack inputs
- do not move dump-frame FITS output to tmpfs without revalidation

### Wisp-removal hard crashes on missing long-wave overlap

Main fixes kept in `do_wisp_rem()`:

- guard missing long-wave references before `propaneFrameFinder()` and `Rfits_key_scan()`
- filter invalid and `NA` filenames

Practical rule:

- a non-crashing no-overlap case is not the same as a scientifically good correction

### Directory-creation failures

Main fix kept in `do_super_sky()`:

- ensure parent directories exist before writing

### Partial sky-info cases

Main fix kept in `do_apply_super_sky()`:

- skip cleanly if `sky_info.csv` is absent for a specific VID or filter context

## Why Earlier Runs Looked Wrong

Several things were previously conflated.

1. Wrong entrypoint

- Step-driven `zork_process.R` runs were sometimes treated as equivalent to full `run_all_process.R`.
- They are not equivalent for reliable wisp propagation.

2. Old parameter defaults

- Stable production now assumes `JUMPROPE_WISP_SIGMA_LO=2`.
- Earlier values could leave obvious structured residuals.

3. Broken or stale before/after checks

- A valid before/after comparison must use the true raw input-side `cal` file as the before image, not a file that JUMPROPE already rewrote.

4. Mixed or compromised output trees

- If final output trees contain results from earlier unstable runs, visual QA becomes ambiguous.
- Clean rebuilds or carefully resumed runs are required.

## Monitoring And QA

Low-cost monitoring commands:

```sh
ps -o pid,etime,%cpu,%mem,cmd -p <MASTER_PID>
tail -n 80 <logfile>
find <final_dir> -type f -name '*.fits' | wc -l
```

The supervisor also supports automatic QA PNG generation for completed observations through:

- [PROCESS/make_obs_png_samples.py](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/make_obs_png_samples.py)

Current QA convention:

- `20` random files per completed observation
- `nrcb3|nrcb4` by default

## Practical Launch Pattern

Large runs should be launched from `PROCESS/` with the correct active `initialise_env.sh`.

PEARLSplus:

```sh
cd /data7/rzi/PEARLSplus/JUMPROPE/PROCESS
bash ./run_obs_until_done.sh 2>&1 | tee ../logs/PEARLSplus/nohup.log
```

SKYSURFIR:

```sh
cd /data5/rzi/JUMPROPE/PROCESS
bash ./run_obs_until_done.sh 2>&1 | tee ../logs/SKYSURFIR/nohup.log
```

If the user wants resume behavior:

- keep `JUMPROPE_SKIP_COMPLETED_FILES=TRUE`

If the user wants a full rebuild:

- change `JUMPROPE_SKIP_COMPLETED_FILES=FALSE`

## Files Future Agents Should Read First

- [initialise_env.sh](/data7/rzi/PEARLSplus/JUMPROPE/initialise_env.sh)
- [initialise_env.pearlsplus.sh](/data7/rzi/PEARLSplus/JUMPROPE/initialise_env.pearlsplus.sh)
- [initialise_env.skysurfir.sh](/data7/rzi/PEARLSplus/JUMPROPE/initialise_env.skysurfir.sh)
- [PROCESS/initialise_variables.R](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/initialise_variables.R)
- [PROCESS/run_all_process.R](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/run_all_process.R)
- [PROCESS/run_obs_until_done.sh](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/run_obs_until_done.sh)
- [PROCESS/all_codes_process.R](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/all_codes_process.R)
- [PROCESS/make_obs_png_samples.py](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/make_obs_png_samples.py)
- [AGENTS.md](/data7/rzi/PEARLSplus/JUMPROPE/AGENTS.md)

## Rules For Future Revisions

1. Do not break long-wave first -> wisp removal -> short-wave rerun ordering.
2. Do not make `zork_process.R` silently execute extra steps.
3. Do not remove isolated session roots.
4. Do not delete staging products before promoted outputs are verified.
5. Do not move dump-frame FITS output to tmpfs without fresh validation.
6. Do not describe the current system as fully RAM-native.
7. Prefer `PSOCK` over more aggressive fork-heavy models.
8. Keep BLAS/OMP/MKL thread counts pinned to `1` in the current stable parallel model.
9. Preserve `JUMPROPE_WISP_SIGMA_LO=2` as the stable default unless new validation disproves it.
10. When comparing before and after wisp removal, use true raw input `cal` files as the before image.
