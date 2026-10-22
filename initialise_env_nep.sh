## [nep-miri] NEP TDF MIRI (6616, 8303, 12529) + 12529 NIRCam. Short paths via the symlink ~/JP -> data/NEP-TDF/JP
## (FITS keywords are limited to 80 characters). Usage: source initialise_env_nep.sh; export JUMPROPE_do_MIRI=T|F
export JUMPROPE_MAST_TOKEN=9999
export JUMPROPE_DOWNLOAD_DIR='/Users/ralphy/JP/RAW'
export JUMPROPE_RAW_DIR='/Users/ralphy/JP/CAL'   ## only *_cal.fits (links), since load_raw_files() takes every .fits recursively
export JUMPROPE_REF_DIR='/Users/ralphy/JP/PRO'
export JUMPROPE_CRDS_PATH='/Users/ralphy/crds_cache'
export JUMPROPE_CRDS_CONTEXT='jwst_1584.pmap'   ## operational context on 2026-10-21 (crds.client.get_default_context)
export CRDS_PATH=$JUMPROPE_CRDS_PATH
export CRDS_SERVER_URL='https://jwst-crds.stsci.edu'
export JUMPROPE_do_NIRISS=F
export JUMPROPE_do_MIRI=${JUMPROPE_do_MIRI:-T}
export JUMPROPE_cores_pro=12      ## 14 logical cores / 36 GB RAM on this machine
export JUMPROPE_cores_stack=4
export JUMPROPE_tasks_stack=3
export JUMPROPE_dl_threads=8
export JUMPROPE_dq_dilate=1     ## no dilation of the DQ mask when warping (tile_stack); upstream default 3
