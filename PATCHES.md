# nep-miri branch: patches for the NEP TDF MIRI/NIRCam run (jwst 3.0.0, CRDS jwst_1584.pmap)

Each patch is marked `## [nep-miri]` in the code.

| Commit | File | What and why |
|---|---|---|
| a485e83 | CALIBRATION/caljwst.py | `--nproc N`: calibrate N uncal files in parallel (spawned processes, each with `--max_cores`). Before this, files ran one after another. |
| a485e83 | CALIBRATION/caljwst.py | Guard for the `*info.csv` concat: VISITID downloads write `<pid>_UNCAL.csv`, so the glob was empty and `pd.concat([])` raised. |
| a485e83 | CALIBRATION/query.py | `vid_query` keeps only NIRCam, MIRI-imager and NIRISS imaging frames, and no MIRI coronagraphic filters. Before this it also took NIRSpec target acquisitions, coronagraphy and the like. Downloads now run in 8 parallel threads (`JUMPROPE_dl_threads`) into the same `mastDownload/JWST/<obs_id>/` layout, keeping complete files. Also `np.core.defchararray` → `np.char` for numpy 2. |
| (next) | CALIBRATION/query.py | Skip the MAST login for the placeholder token 9999; public data need no token. |

Environment file: `initialise_env_nep.sh`. It uses short paths through the symlink `~/JP` → `data/NEP-TDF/JP`, because FITS
keywords hold at most 80 characters.
