# AGENTS.md

Guidance for future Codex agents working on this JUMPROPE checkout.

## Working Context

- Repository root: `/media/ralphy/Ext_5n/JUMPROPE`
- Main processing entry points live in `PROCESS/`; run R commands from that directory unless you have verified relative paths.
- The user's active PEARLS+ reference/output directory is usually:
  `/media/ralphy/Ext_7n/PEARLSplus/jumprope`
- The user's detector-level input CAL files are usually:
  `/media/ralphy/Ext_7n/PEARLSplus/cal`
- The worktree may be dirty. Do not revert edits you did not make. Generated directories such as `Pro1oF/`, `Median_Stacks/`, `InVar_Stacks/`, `Patch_Stacks/`, `dump/`, and `sky_pro/` can be large pipeline outputs.

## Important Files

- `config.R`: package imports and `jumprope_version`. It currently requires `Highlander`, `ProPane`, `ProFound`, `Rfits`, `Rwcs`, `foreach`, `doParallel`, and other astronomy/data packages.
- `PROCESS/initialise_variables.R`: user-editable defaults and processing knobs.
- `PROCESS/run_all_process.R`: full pipeline driver.
- `PROCESS/zork_process.R`: interactive/selective pipeline driver. Menu includes `11 = Wisp remove` and `12 = Reverse wisp removal`.
- `PROCESS/all_codes_process.R`: implementation of most pipeline steps, including 1/f, sky, ProPane stacking, patching, RGB, and wisp removal.
- `PROCESS/tile_stack.R`: standalone tile/mosaic stacking helper.
- `PROCESS/reverse_wisp_fix.R`: helper for reversing wisp correction from `SCI_ORIG`.
- QC JPEG renderer, when present in the PEARLS+ ref dir:
  `/media/ralphy/Ext_7n/PEARLSplus/jumprope/Pro1oF/render_cal_sky_renorm_jpegs.py`

## Typical Commands

Set or confirm environment variables before running `zork_process.R` or `run_all_process.R`:

```bash
export JUMPROPE_RAW_DIR=/media/ralphy/Ext_7n/PEARLSplus/cal
export JUMPROPE_REF_DIR=/media/ralphy/Ext_7n/PEARLSplus/jumprope
export JUMPROPE_do_NIRISS=FALSE
export JUMPROPE_do_MIRI=FALSE
export JUMPROPE_cores_pro=32
export JUMPROPE_cores_stack=1
export JUMPROPE_tasks_stack=8
export JUMPROPE_cores_wisp=8
cd /media/ralphy/Ext_5n/JUMPROPE/PROCESS
Rscript zork_process.R "1176231|1199005"
```

For selective processing in ZORK, enter comma-separated menu numbers at the prompt. For example, wisp removal only is `11`; wisp removal then downstream processing is often `11,1,2,3,4,5,6`.

## R/Parallel Rules of Thumb

- `parallel_type = "PSOCK"` is generally safer for top-level `foreach` workers on Linux, but PSOCK workers do not inherit the parent R session. Any function or package used inside `%dopar%` must be explicitly exported, namespaced, or listed in `.packages`.
- When a PSOCK job reports `could not find function "..."`, fix the worker environment. Prefer `Package::function()` for package functions or add the package to `.packages`.
- `Error in unserialize(node$con): error reading from connection` after a worker failure is usually secondary noise from the cluster shutting down after the real task error.
- Always stop clusters in `finally` and call `registerDoSEQ()` after parallel sections. Otherwise later `%dopar%` calls may silently run sequentially or reuse stale backend state.
- If output says `executing %dopar% sequentially: no parallel backend registered`, the code reached `%dopar%` without a registered backend or after a backend was torn down.

## ProPane Stacking Notes

Stacking is controlled by:

- `JUMPROPE_tasks_stack`: number of concurrent stack jobs, usually different visit/filter/module rows.
- `JUMPROPE_cores_stack`: internal ProPane cores per stack job.

Important: ProPane uses global `foreach` backend state internally. Nested parallelism can stall or deadlock, especially PSOCK outer workers plus ProPane internal workers. Current code is intentionally conservative:

- If `tasks_stack > 1`, run multiple stack jobs concurrently and force each ProPane stack to `cores_stack = 1`.
- If `tasks_stack = 1`, a single stack can use `cores_stack > 1`, but avoid PSOCK for ProPane internal parallelism; fork-style internal ProPane parallelism is more reliable.
- Do not set both high `tasks_stack` and high `cores_stack`. That oversubscribes CPUs, file handles, memory, and disk I/O.
- Large idle CPU periods during stacking can be normal if the run is I/O-bound. Check output file mtimes and disk I/O before assuming it is hung.

Useful monitoring commands:

```bash
ps -eo pid,ppid,stat,pcpu,pmem,etimes,cmd | rg 'Rscript|R --slave|R --no-echo'
find /media/ralphy/Ext_7n/PEARLSplus/jumprope -type f -mmin -10 | head
df -h /media/ralphy/Ext_7n /media/ralphy/Ext_5n
```

## Wisp Removal Context

Wisp removal is in `do_wisp_rem()` in `PROCESS/all_codes_process.R`.

Current behavior:

- Operates on detector-level short-wavelength NIRCam `*_cal.fits` files selected by `load_files(..., which_module = "wisp_rem")`.
- Uses long-wavelength median stacks from `Median_Stacks/` as references.
- Same-visit/module long references are preferred.
- Spatial long-reference fallback is intentionally conservative and should remain fallback-only because wide-field WCS warps from nearby but different visits can fail.
- Wisp correction is idempotent when `SCI_ORIG` exists: it reads the original pre-wisp science from `SCI_ORIG` instead of repeatedly subtracting from an already corrected `SCI`.
- The corrected science is written back to FITS extension 2 / `SCI`.
- Diagnostic extensions written or updated include `SCI_ORIG`, `REF_WISP_WARP`, and `WISP_TEMPLATE`.

Key parameters in `PROCESS/initialise_variables.R`:

- `do_claws`: if `TRUE`, run wisp-style correction on all short NIRCam detectors; otherwise only the historically affected A3/A4/B3/B4 chips.
- `max_wisp_visit_refs`: max same-visit/module long stacks.
- `max_wisp_spatial_refs`: max spatial fallback stacks. Current default is `0`.
- `max_wisp_refs_per_file`: cap after combining visit and spatial references.
- `cores_wisp`: top-level wisp-removal workers.
- `wisp_ref_search_radius_arcsec`: search radius for spatial fallback refs.
- `wisp_sigma_lo`: broad Gaussian smoothing scale for the derived wisp template. Current default is `NULL`, which disables smoothing. Set this explicitly, e.g. `20`, when broad wisp templates need to be modeled.

Common wisp-removal messages:

- `No detector-level *_cal.fits files matched...`: selection/header filtering found no matching short detector files for that VID.
- `Loading N long-wavelength reference stack(s) ... (same-visit=X, spatial=Y)`: references selected for one short detector file.
- `Skipping unusable long-wavelength wisp reference ... result would be too long a vector`: WCS warp for that reference is unusable; the code should skip it and continue.
- `Failed s2p conversion` / `wcss2p` / `De-distort error`: WCS conversion failed during a warp, usually from non-overlap or distortion mismatch. Prefer same-visit refs and keep spatial fallback small.
- `Wisp removal summary: ...`: trust this over interleaved worker warnings, but inspect output FITS extensions to verify actual correction strength.

If wisps still appear:

- Confirm you are inspecting a fresh downstream file, not a stale JPEG or previously generated stack.
- Confirm option `11` ran before downstream `1,2,3,4,5,6` when regenerating `cal_sky_renorm`.
- Confirm the downstream FITS contains `SCI_ORIG` and `WISP_TEMPLATE`.
- Compare `SCI_ORIG`, `WISP_TEMPLATE`, and current `SCI`. A weak or nearly zero `WISP_TEMPLATE` means the algorithm ran but did not model the visible structure strongly enough.
- If JPEGs are used, verify the renderer is plotting `SCI` from `cal_sky_renorm`, and ideally inspect a 3-panel view of `SCI_ORIG`, `WISP_TEMPLATE`, and `SCI`.

## FITS Extension Cautions

- Prefer extension names (`SCI`, `DQ`, `SCI_ORIG`, `WISP_TEMPLATE`) over hard-coded numbers when practical.
- Many existing R calls use extension 2 for science and extension 4 for DQ. Verify with `Rfits_extnames()` or Python/astropy before changing behavior.
- `cal_sky_renorm` science should be in `SCI`; wisp diagnostics may be propagated as extra extensions.

## Known Past Failure Modes

- Missing package: `library(Highlander)` can fail if the R environment is incomplete.
- PSOCK worker export issues have appeared as missing `propaneStackFlatFunc`, `Rfits_read`, or similar function names. Namespace calls such as `ProPane::...` and `Rfits::...` are safer.
- `object 's' not found` in cal-sky-info generation came from a bad variable reference in filtering logic. Inspect nearby `gsub`/filename parsing if it recurs.
- `Not a matrix.` during 1/f or image operations usually means a FITS extension or object type was not what the downstream code expected. Inspect the failing file and extension contents.
- Base `png()` does not accept `quality`; that argument belongs to JPEG-style devices, not PNG.
- Warning spam from many PSOCK workers can interleave badly. Find the first real `Error in { : task N failed - "..."` line.

## Editing Guidance

- Use `rg`/`rg --files` first for searches.
- Keep changes scoped. This code mixes package functions, FITS I/O side effects, and long-running data products; broad refactors are risky.
- Do not delete or overwrite generated FITS outputs unless the user explicitly asks.
- For manual edits, use `apply_patch`.
- If editing or writing under `/media/ralphy/Ext_7n/...`, request approval when the sandbox requires it.
- For syntax-only checks that should not write bytecode beside source files, use `Rscript -e 'parse(file="...")'` or Python `ast.parse(...)` rather than commands that create `__pycache__`.

## Validation Checklist

After code edits, prefer lightweight validation first:

```bash
cd /media/ralphy/Ext_5n/JUMPROPE/PROCESS
Rscript -e 'parse(file="all_codes_process.R"); parse(file="zork_process.R"); parse(file="run_all_process.R"); parse(file="initialise_variables.R"); cat("parse ok\n")'
```

For data-path checks, use small VID/filter subsets and low core counts before launching a full run. When validating wisp removal, inspect FITS extensions directly and compare `SCI_ORIG`, `WISP_TEMPLATE`, and `SCI` rather than relying only on stacked images or JPEGs.
