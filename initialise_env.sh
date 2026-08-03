export JUMPROPE_MAST_TOKEN=9999 #Only needed for exclusive access data. 
export JUMPROPE_DOWNLOAD_DIR='/Volumes/Expansion/JWST'
export JUMPROPE_CRDS_PATH='/Volumes/Expansion/crds'
export JUMPROPE_CRDS_CONTEXT='jwst_1140.pmap'


export JUMPROPE_REF_DIR='/data7/rzi/PEARLSplus/jumprope' ## I recommend you keep this commented. Only add when you are certain the directory structure has been made. The code will auto prompt you to create it on first run.
export JUMPROPE_RAW_DIR='/data7/rzi/PEARLSplus/nircam/cal'

export JUMPROPE_do_NIRISS=F
export JUMPROPE_do_MIRI=F

export JUMPROPE_cores_pro=64 #Number of cores to use for 1/f, sky subtr, wisp rem
export JUMPROPE_cores_stack=16 #Number of cores to use internally for propaneWarpStackInVar
export JUMPROPE_tasks_stack=4 #Number of stacking tasks to run


# e.g., If I have 20 cal files to process, I could set cores_pro = 5 and only do 4 lots of computations.
# I could then set cores_stack = 10 and tasks_stack = 2 to stack two things at once while taking advantage of 10 cores for the WCS warping. 
# cores_stack * tasks_stack < Number of Cores. Use detectCores() in R or other to check system resources. 

# Disable BLAS/OMP background threads so fork() inside PSOCK stacking workers is safe
# (multi-threaded R + fork = potential mutex deadlock in child processes)
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1

export JUMPROPE_CLEANUP=TRUE  # TRUE = auto-delete intermediates after each run when wisp-verified

export JUMPROPE_DUMP_DIR=/dev/shm/jumprope_dump  # RAM disk — eliminates dump frame I/O bottleneck (751 GB available on omega)

# Stage cal_sky_renorm to RAM before stacking: run "source stage_to_ram.sh" first,
# then uncomment this line. Eliminates source-file I/O during propaneStackWarpInVar.
# export JUMPROPE_CAL_SKY_RENORM_DIR=/dev/shm/jumprope_cal_sky_renorm

# With both dump + input in /dev/shm, stacking is CPU-bound -- raise tasks_stack:
# export JUMPROPE_tasks_stack=8   # 8 jobs x 8 cores each when fully RAM-bound
