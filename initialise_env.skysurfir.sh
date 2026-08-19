export JUMPROPE_MAST_TOKEN=9999 #Only needed for exclusive access data.
export JUMPROPE_DOWNLOAD_DIR='/Volumes/Expansion/JWST'
export JUMPROPE_CRDS_PATH='/Volumes/Expansion/crds'
export JUMPROPE_CRDS_CONTEXT='jwst_1140.pmap'

export JUMPROPE_REF_DIR='/home/rzi/jumprope/skysurfir_stage' ## SSD staging root for SKYSURFIR
export JUMPROPE_RAW_DIR='/data4/rzi/NIRCAM/cal'
export JUMPROPE_FINAL_CAL_DIR='/data5/rzi/jumprope-skysurfir/Pro1oF/cal'
export JUMPROPE_FINAL_CAL_SKY_RENORM_DIR='/data5/rzi/jumprope-skysurfir/Pro1oF/cal_sky_renorm'
export JUMPROPE_SHARED_SKIP_CAL_DIR='/data7/rzi/PEARLSplus/jumprope/Pro1oF/cal'
export JUMPROPE_SHARED_SKIP_RENORM_DIR='/data7/rzi/PEARLSplus/jumprope/Pro1oF/cal_sky_renorm'
export JUMPROPE_STAGING_MODE=TRUE
export JUMPROPE_SKIP_COMPLETED_FILES=TRUE
export JUMPROPE_RUN_NAME='SKYSURFIR'
export JUMPROPE_TARGET_IDS_FILE='/data5/rzi/JUMPROPE/PROCESS/skysurfir_obs_20260808.txt'
export JUMPROPE_QA_PNG_DIR='/data5/rzi/jumprope-skysurfir/png_qc_nrcb34'
export JUMPROPE_QA_PNG_PER_OBS=20
export JUMPROPE_QA_PNG_DETECTORS='nrcb3|nrcb4'

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

export JUMPROPE_DUMP_DIR='/data5/rzi/jumprope-skysurfir/dump'
export JUMPROPE_WISP_SIGMA_LO=2
export JUMPROPE_STAGE_MULTIPLIER=5.0
export JUMPROPE_MIN_SSD_FREE_GIB=500
