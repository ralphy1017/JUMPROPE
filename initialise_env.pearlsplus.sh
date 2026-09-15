export JUMPROPE_MAST_TOKEN=9999 #Only needed for exclusive access data.
export JUMPROPE_DOWNLOAD_DIR='/Volumes/Expansion/JWST'
export JUMPROPE_CRDS_PATH='/Volumes/Expansion/crds'
export JUMPROPE_CRDS_CONTEXT='jwst_1140.pmap'

export JUMPROPE_REF_DIR='/home/rzi/jumprope/pearl_stage' ## SSD staging root for PEARLSplus
export JUMPROPE_RAW_DIR='/data7/rzi/PEARLSplus/nircam/cal'
export JUMPROPE_FINAL_CAL_DIR='/data7/rzi/PEARLSplus/jumprope/Pro1oF/cal'
export JUMPROPE_FINAL_CAL_SKY_RENORM_DIR='/data7/rzi/PEARLSplus/jumprope/Pro1oF/cal_sky_renorm'
export JUMPROPE_STAGING_MODE=TRUE
export JUMPROPE_SKIP_COMPLETED_FILES=FALSE
export JUMPROPE_RUN_NAME='PEARLSplus'
export JUMPROPE_TARGET_IDS_FILE='/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/pearlsplus_obs_20260813.txt'
export JUMPROPE_QA_PNG_DIR='/data7/rzi/PEARLSplus/png/live_qc_a34b34'
export JUMPROPE_QA_PNG_PER_OBS=20
export JUMPROPE_QA_PNG_DETECTORS='nrca3|nrca4|nrcb3|nrcb4'

export JUMPROPE_do_NIRISS=F
export JUMPROPE_do_MIRI=F

export JUMPROPE_cores_pro=32
export JUMPROPE_cores_stack=8
export JUMPROPE_tasks_stack=4

export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1

export JUMPROPE_CLEANUP=TRUE
export JUMPROPE_RAM_MODE=FALSE

export JUMPROPE_DUMP_DIR='/data7/rzi/PEARLSplus/jumprope/dump'
export JUMPROPE_WISP_SIGMA_LO=5
export JUMPROPE_WISP_CLIP_THRESHOLD=0.975
export JUMPROPE_STAGE_MULTIPLIER=5.0
export JUMPROPE_MIN_SSD_FREE_GIB=500
