# JumProPe for SKYSURF-IR: development and release plan

Goal: a stable JumProPe that runs the same way Jordan's version does (`source initialise_env.sh`, edit `initialise_variables.R`, `cd PROCESS && Rscript run_all_process.R '<VID>|<VID>|...'`). It keeps the `nep-miri` fixes, works on any Linux or Mac machine and any database, and processes NIRCam and NIRISS out of the box, with MIRI as a smoke-tested extra.

**Required products:** `Pro1oF/cal` and `Pro1oF/cal_sky_renorm`.
**Optional products:** ProPane stacks and mosaics, and ProFound catalogs.

Status: **plan only**. Nothing below has been implemented yet. Line numbers refer to commit `c7051a6`.

---

## 1. Where the code stands

- This branch is `upstream/main` (JordanDSilva/JUMPROPE `0c73324`) plus 50 `[nep-miri]` commits. Nothing in upstream is missing here, so no merge is needed.
- The manual entry point and the stage order are unchanged from upstream:

  ```
  LW:  1oF -> cal_process -> regen_sky_info -> super_sky -> apply_super_sky -> modify_pedestal -> cal_sky_info -> gen_stack
  SW:  wisp_rem -> (same chain again for SW filters)
  then: patch, RGB
  ```

- What is already fixed relative to upstream:
  - jwst ≥ 3 `integer64` DQ.
  - `VID='A|B'` matching.
  - The undefined `s` in `do_cal_sky_info`.
  - PSOCK `wispFixer` export (this was the reason wisps survived in F200W).
  - Wisp resume from `SCI_ORIG`.
  - Empty SW selections.
  - DQ dilation is now configurable.
  - Env-driven `initialise_variables.R`.
- **The dynamic `wispFixer` needs an LW reference.** It looks in `Median_Stacks/` for `*<VISIT_ID>*<MODULE>*short*.fits` (`all_codes_process.R:1606`). So the LW median stacks from the first `do_gen_stack` are a *requirement* of wisp removal, not an optional product. Only the SW stacks, `do_patch`, `do_RGB` and the ProFound catalogs are truly optional.

## 2. Blockers for SKYSURF-IR scale

| # | Problem | Where | Effect on SKYSURF-IR |
|---|---|---|---|
| B1 | Every run reads and writes the same files: `sky_pro/sky_info.csv`, `sky_pro/sky_super/super_<DET>_<FILT>.fits`, `Pro1oF/cal_sky_info.csv` and `InVar_Stacks/temp_list_<i>.fits`. `do_gen_stack` also deletes every `temp_list_*` it finds. | `:646`, `:737`, `:1145`, `:1279-1281`, `:1415` | Two visits running at once in one `REF_DIR` overwrite each other's super-skies and CSVs. This silently corrupts `cal_sky_renorm`. |
| B2 | Passing every visit in one pipe-separated string makes a *single* pass. Super-skies are then built from every frame in the database for each detector and filter. | `run_all_process.R:94` (nep-miri change; upstream meant to loop over each VID) | Memory use grows with the database. One bad file stops the whole run. The super-sky mixes many fields and epochs. |
| B3 | Scans that cover the whole database run once per job: `Rfits_key_scan` over *all* raw files, `load_raw_files` (recursive), and `do_cal_sky_info` over all of `cal_sky_renorm/`. | `run_all_process.R:164,173`; `:1113-1123` | Cost grows quadratically with database size on a hard drive. This is the main I/O drain. |
| B4 | The wisp stage writes into the **raw `_cal.fits` files in `JUMPROPE_RAW_DIR`**. It keeps `SCI_ORIG` and adds extensions (upstream behaviour). | `:1757` | The archive inputs are modified. Use `reverse_wisp_fix.R` to undo. |
| B5 | NIRISS: `FILT` is forced to `"CLEAR\|NIS"`. NIRISS F090W–F200W have `FILTER=CLEAR` with the band in `PUPIL`, while F277W–F480M have `FILTER=F...`. | `run_all_process.R:74,148`; super-sky key `:737,:827` | All CLEAR bands share one `super_NIS_CLEAR` sky. NIRISS LW imaging is skipped silently. |
| B6 | `make_directory_structure()` reads from stdin when `JUMPROPE_REF_DIR` is unset. | `:2359` | Batch runs hang. |
| B7 | `do_gen_stack` reads `additional_params$ref_cat`, but `initialise_variables.R` sets `tweak_catalogue`. Its VID filter is `grep("^A\|B")`. | `:1165`, `:1204` | `JUMPROPE_TWEAK_CATALOGUE` has no effect. A visit can match the middle of an unrelated ID. |
| B8 | Machine-specific setup files: `initialise_env.sh` (`/Volumes/...`) and `initialise_env_nep.sh` (`/Users/ralphy/...`). The `tile_stack_nep.R` and `profound_nep.R` scripts need `JP_ROOT` and the parent project's grid. The patched ProPane 1.12.1.2 is not in the repo. | root, `PROCESS/`, `PROFOUND/` | Not machine-agnostic. The mosaic tools depend on files outside the repo. |
| B9 | `continuous_dynamic`, `nmf` and `masked_dynamic` need F200W-only JADES templates, at least 3 exposures per detector, deep segmentation maps and a separate preparation run. | `WISP_NMF.md` | They cannot be the general SKYSURF-IR default. They stay opt-in for prepared F200W sets. |

## 3. Design decisions (recommended)

1. **Per-visit isolation. This is the unit Jordan's loop was written for.** Each job processes one VID through the whole chain. It uses a private work area for `sky_pro/`, `cal_sky/`, `dump/`, the CSVs and the stack temp lists. Its final products go to the shared `REF_DIR/Pro1oF/{cal,cal_sky_renorm}` and the stack directories; those filenames are unique per exposure or per visit, so nothing collides. Setting `JUMPROPE_GROUP=program` builds super-skies per program instead. Calling `Rscript run_all_process.R <VID>` manually still works exactly as before.
2. **Wisp removal:**
   - The default method is the dynamic `wispFixer` with the PSOCK and resume fixes. It works for every SW filter, F070W–F212N.
   - The parameter profile is a named preset chosen in `initialise_variables.R`:
     - `jordan`: 0.5 / 0.997 / σ_hi 2 / σ_lo 20.
     - `nep_stable`: the current branch default, 0.4 / 1 / 0.5 / NULL.
   - `continuous_dynamic` stays opt-in and needs prepared F200W assets.
   - `do_claws` is unchanged.
3. **Product switches in `initialise_variables.R`** (and the matching env variables):
   - `do_wisp`: default T.
   - `do_stack`: SW stacks, patch and RGB. Default F for SKYSURF-IR. The LW median stacks still run whenever `do_wisp` is on.
   - `do_profound`: runs `PROFOUND/run_all_profound.R` on that visit's stacks. Default F.
4. **I/O:**
   - Cut the raw file list down to the VID's filenames before any header scan.
   - Scope `do_cal_sky_info` to the visit's own files.
   - Put intermediates on `JUMPROPE_SCRATCH_DIR`, ideally `/dev/shm` or local NVMe. On a 750 GB machine, 8 visits in RAM fit easily. Only `cal`, `cal_sky_renorm` and the optional stacks are written to the hard drives.
   - Pin BLAS/OpenMP to 1 thread per worker.
5. **Concurrency:** a thin driver, `run_visits.sh`. It accepts the same pipe string or a file with one VID per line, and runs `K` jobs of `Rscript run_all_process.R <VID>` concurrently. It also:
   - writes a per-visit log;
   - writes a `done/<VID>.<instrument>` marker so it can resume;
   - records failures in a list and keeps going;
   - runs one instrument pass per instrument present in the visit, setting `do_NIRISS`/`do_MIRI` for that pass.

   Starting point for 64 cores and hard-drive I/O: `K=8`, `cores_pro=8`, `cores_stack=4`, `tasks_stack=2`. Tune this using the throughput test in Phase 5.

## 4. Phases

**Phase 0 — inputs (needs you, §6).**

**Phase 1 — portability**
- Generic `initialise_env.sh` template with every variable documented, and no paths from any one machine. Move the NEP env to `examples/`.
- Non-interactive directory creation when `JUMPROPE_REF_DIR` is set, or `JUMPROPE_AUTO_DIRS=T`.
- Fix the B7 wiring.
- Fail fast with a clear message if the run does not start from `PROCESS/`.
- Make `JUMPROPE_DIR` default to the repo root.
- Bundle or pin the patched ProPane and ProFound, with an install script.

**Phase 2 — correctness for multiple instruments**
- NIRISS effective filter = `PUPIL` when `FILTER=CLEAR`, for the super-sky key, grouping and stacks.
- Remove the forced `FILT`, so LW NIRISS gets processed.
- Use `vid_match` in `do_gen_stack`.
- MIRI smoke run.

**Phase 3 — isolation and I/O** (B1–B3). Per-run work dirs and scoped scans, keeping today's layout as the default when `JUMPROPE_WORK_DIR` is unset.

**Phase 4 — driver and switches** (`run_visits.sh`, `do_stack`, `do_profound`, wisp presets). Optionally, `JUMPROPE_WISP_COPY=T` writes wisp-corrected *copies* instead of editing the raw files in place (B4).

**Phase 5 — validation**
- (a) Equivalence: run Jordan's `upstream/main` and this release on one public NIRCam visit with `jordan` wisp settings. The `cal` and `cal_sky_renorm` outputs must match, apart from the documented fixes.
- (b) One NIRISS visit with several bands and one MIRI visit, end to end.
- (c) Wisp before/template/after PNGs on about 20 SKYSURF-IR visits, covering both presets.
- (d) Throughput run on about 50 visits to set `K` × `cores`.
- (e) R tests from `tests/` in CI, using R with Rfits, ProFound and ProPane.

**Phase 6 — release**
- Set `config.R` `jumprope_version` to 2.3.0.
- README quick-start that mirrors the manual workflow.
- `PATCHES.md` entries, then merge to `main` and tag `skysurfir-v1`.

## 5. Intended usage after release

Set up the environment once:

```sh
cp initialise_env.sh my_env.sh    # set RAW_DIR, REF_DIR, SCRATCH_DIR, cores
source my_env.sh                  # edit PROCESS/initialise_variables.R: 1/f mode, wisp preset, do_claws, do_stack
cd PROCESS
```

Process one visit, exactly as before:

```sh
Rscript run_all_process.R 1345001001
```

Process the whole database, `K` visits at a time:

```sh
./run_visits.sh "$(cat skysurfir_vids.txt | paste -sd'|')"
```

## 6. Open questions

1. **Super-sky unit:** per visit (default), per program, or the whole list together (today's behaviour)?
2. **Wisp preset for SKYSURF-IR:** `jordan` or `nep_stable`? `nep_stable` was tuned on 12529 F200W only, and injection tests there recovered about 19% of compact SW-only flux.
3. **Raw-file editing:** keep upstream's in-place wisp edits to `RAW_DIR` (it keeps `SCI_ORIG`), or write copies?
4. **Missing files:** the patched ProPane 1.12.1.2 and the "revised ProFound", from the parent project's `vendor/`. Is there any parent-project orchestration (notebook, `JUMPROPE.md`) that should be brought into this repo?
5. **Database layout:** is `RAW_DIR` flat or nested? Is there local SSD or NVMe space, or should scratch live in `/dev/shm`?
