# JWST UWA MULTIWAVELENGTH PROTOOLS PROCESSING ENDEAVOUR (J U M PRO P E)

Characterised by its ease of use, its speed and its health benefits: JUMPROPE is an all purpose JWST processing suite of codes!

The manual is a living document and can be found on overleaf here: https://www.overleaf.com/read/ksqfmgvhtnhh#3a3d4d

<img src="https://github.com/JordanDSilva/JUMPROPE/blob/main/logo.png" width="500" height="500"/>

## Stable Production Notes

The current stable production configuration is documented in:

- [JUMPROPE.md](/data7/rzi/PEARLSplus/JUMPROPE/JUMPROPE.md)
- [AGENTS.md](/data7/rzi/PEARLSplus/JUMPROPE/AGENTS.md)

Repo-native campaign templates are included as shell env files:

- [initialise_env.pearlsplus.sh](/data7/rzi/PEARLSplus/JUMPROPE/initialise_env.pearlsplus.sh)
- [initialise_env.skysurfir.sh](/data7/rzi/PEARLSplus/JUMPROPE/initialise_env.skysurfir.sh)

Observation manifests used for large supervised runs:

- [PROCESS/pearlsplus_obs_20260813.txt](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/pearlsplus_obs_20260813.txt)
- [PROCESS/skysurfir_obs_20260808.txt](/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/skysurfir_obs_20260808.txt)

Recommended launch mode for large production runs:

1. Copy the appropriate template over `initialise_env.sh`, or source the template and export any local overrides.
2. Keep `JUMPROPE_RAM_MODE=FALSE` for production. The stable path is SSD staging plus selective in-memory reuse, not full tmpfs execution.
3. Use `PROCESS/run_obs_until_done.sh` for named campaigns that should restart automatically until all target observation IDs are complete.
4. Use `PROCESS/run_all_process.R` when the goal is true wisp-removed `cal_sky_renorm`. This path does long-wave first, then wisp removal, then reruns the short-wave branch.

Validated stable production defaults:

- `JUMPROPE_cores_pro=32`
- `JUMPROPE_cores_stack=8`
- `JUMPROPE_tasks_stack=4`
- `OPENBLAS_NUM_THREADS=1`
- `OMP_NUM_THREADS=1`
- `MKL_NUM_THREADS=1`
- `JUMPROPE_WISP_SIGMA_LO=2`

Do not treat JUMPROPE as a fully object-native pipeline yet. Critical stages still rely on on-disk FITS products because of Rfits / ProPane / ProFound behavior.
