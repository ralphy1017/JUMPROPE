## Edit the paths for your machine, then: source initialise_env.sh

export JUMPROPE_MAST_TOKEN=9999 #Only needed for exclusive access data. 9999 = no login.
export JUMPROPE_DOWNLOAD_DIR='/path/to/JWST'
export JUMPROPE_CRDS_PATH='/path/to/crds_cache'
export JUMPROPE_CRDS_CONTEXT='jwst_1140.pmap'

## Where the outputs go (Pro1oF/cal, Pro1oF/cal_sky_renorm, sky_pro, stacks...). The directories are created if missing.
## If you leave it commented, the code will prompt you for it (interactive runs only).
#export JUMPROPE_REF_DIR='/path/to/JWST/'
## Where the input *_cal.fits are. Every .fits below this directory is read (recursively).
export JUMPROPE_RAW_DIR='/path/to/JWST/'

## Which instrument to process in this run: NIRCam when both are F, NIRISS or MIRI otherwise.
export JUMPROPE_do_NIRISS=F
export JUMPROPE_do_MIRI=F

export JUMPROPE_cores_pro=1 #Number of cores to use for 1/f, sky subtr, wisp rem
export JUMPROPE_cores_stack=1 #Number of cores to use internally for propaneWarpStackInVar
export JUMPROPE_tasks_stack=1 #Number of stacking tasks to run


# e.g., If I have 20 cal files to process, I could set cores_pro = 5 and only do 4 lots of computations.
# I could then set cores_stack = 10 and tasks_stack = 2 to stack two things at once while taking advantage of 10 cores for the WCS warping.
# cores_stack * tasks_stack < Number of Cores. Use detectCores() in R or other to check system resources.
#
# Several runs at once: each Rscript run_all_process.R call keeps its sky/stack bookkeeping files per VID,
# so separate terminals can process different VIDs into the same JUMPROPE_REF_DIR at the same time.
# Keep (number of runs) x cores_pro below the number of physical cores.
