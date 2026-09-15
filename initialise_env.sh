export JUMPROPE_MAST_TOKEN=9999 #Only needed for exclusive access data. 
export JUMPROPE_DOWNLOAD_DIR='/Volumes/Expansion/JWST'
export JUMPROPE_CRDS_PATH='/Volumes/Expansion/crds'
export JUMPROPE_CRDS_CONTEXT='jwst_1140.pmap'


export JUMPROPE_REF_DIR='/home/rzi/jumprope/pearl_stage' ## SSD staging root for PEARLSplus
export JUMPROPE_RAW_DIR='/data7/rzi/PEARLSplus/nircam/cal'
export JUMPROPE_FINAL_CAL_DIR='/data7/rzi/PEARLSplus/jumprope/Pro1oF/cal'
export JUMPROPE_FINAL_CAL_SKY_RENORM_DIR='/data7/rzi/PEARLSplus/jumprope/Pro1oF/cal_sky_renorm'
export JUMPROPE_STAGING_MODE=TRUE
export JUMPROPE_SKIP_COMPLETED_FILES=TRUE
export JUMPROPE_EXPAND_OBS_TO_VISITS=TRUE
export JUMPROPE_RUN_NAME='PEARLSplus'
export JUMPROPE_TARGET_IDS_FILE='/data7/rzi/PEARLSplus/JUMPROPE/PROCESS/pearlsplus_obs_20260813.txt'
export JUMPROPE_QA_PNG_DIR='/data7/rzi/PEARLSplus/png/live_qc_a34b34'
export JUMPROPE_QA_PNG_PER_OBS=20
export JUMPROPE_QA_PNG_DETECTORS='nrca3|nrca4|nrcb3|nrcb4'

export JUMPROPE_do_NIRISS=F
export JUMPROPE_do_MIRI=F

export JUMPROPE_cores_pro=32 #Number of cores to use for 1/f, sky subtr, wisp rem
export JUMPROPE_cores_stack=8 #Number of cores to use internally for propaneWarpStackInVar
export JUMPROPE_tasks_stack=4 #Number of stacking tasks to run


# e.g., If I have 20 cal files to process, I could set cores_pro = 5 and only do 4 lots of computations.
# I could then set cores_stack = 10 and tasks_stack = 2 to stack two things at once while taking advantage of 10 cores for the WCS warping. 
# cores_stack * tasks_stack < Number of Cores. Use detectCores() in R or other to check system resources. 

# Disable BLAS/OMP background threads so fork() inside PSOCK stacking workers is safe
# (multi-threaded R + fork = potential mutex deadlock in child processes)
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1

export JUMPROPE_CLEANUP=TRUE
export JUMPROPE_RAM_MODE=FALSE  # Keep FALSE when using SSD staging mode in run_all_process.R

export JUMPROPE_DUMP_DIR=/data7/rzi/PEARLSplus/jumprope/dump  # disk path — cfitsio inVar_warp writes fail on tmpfs
export JUMPROPE_WISP_SIGMA_LO=5
export JUMPROPE_WISP_CLIP_THRESHOLD=0.975
export JUMPROPE_STAGE_MULTIPLIER=5.0
export JUMPROPE_MIN_SSD_FREE_GIB=500

# Stage cal_sky_renorm to RAM before stacking: run "source stage_to_ram.sh" first,
# then uncomment this line. Eliminates source-file I/O during propaneStackWarpInVar.
# export JUMPROPE_CAL_SKY_RENORM_DIR=/dev/shm/jumprope_cal_sky_renorm

# With both dump + input in /dev/shm, stacking is CPU-bound -- raise tasks_stack:
# export JUMPROPE_tasks_stack=4   # 8 jobs x 8 cores each when fully RAM-bound
