#######################
## Script to run all ##
#######################

## Make sure to edit the proper things in the "main" function
##
## Usage (from this PROCESS directory, after `source initialise_env.sh`):
##   Rscript run_all_process.R <VID>          e.g. 1345001001, or a PID such as 1345
##   Rscript run_all_process.R 'VID1|VID2|...' each VID is processed in turn, on its own
##   Rscript run_all_process.R <VID> <FILT>   only this filter regex
## Settings (1/f mode, wisp/claw removal, stacks) are in initialise_variables.R.

library(magicaxis)
library(Rwcs)
library(Rfits)
library(ProPane)
library(ProFound)
library(stringr)
library(utils)
library(Cairo)
library(data.table)
library(foreach)
library(doParallel)
library(dplyr)

source("all_codes_process.R")
source("initialise_variables.R")

## NIRCam filters. [fix] F322W2 was missing from the long list, so it was never processed.
LW_FILT = "F250M|F277W|F300M|F322W2|F323N|F335M|F356W|F360M|F405N|F410M|F430M|F444W|F460M|F466N|F470N|F480M"
SW_FILT = "F070W|F090W|F115W|F140M|F150W2|F150W|F162M|F164N|F182M|F187N|F200W|F210M|F212N"

process_visit = function(input_args, FILT_given){

  make_stacks = !isFALSE(input_args$additional_params$make_stacks)

  ## [fix] the long-wavelength-first filter list is for NIRCam only. Before, it was also applied
  ## to NIRISS and MIRI runs, which then skipped most or all of their filters.
  if(!FILT_given & !input_args$do_NIRISS & !input_args$do_MIRI){
    input_args$FILT = LW_FILT ## Process long wavelengths first
  }

  ## [fix] skip cleanly when the visit has nothing for this instrument/filter selection
  if(length(load_files(input_args, which_module = "1oF")) > 0){
    do_1of(input_args)
    do_cal_process(input_args)
    do_regen_sky_info(input_args)
    do_super_sky(input_args)
    do_apply_super_sky(input_args)
    do_modify_pedestal(input_args)
    do_cal_sky_info(input_args)
    ## NIRCam always needs these stacks: the long wavelength median stacks are the wisp reference
    if(make_stacks | (!input_args$do_NIRISS & !input_args$do_MIRI)){
      do_gen_stack(input_args)
    }
  }else{
    message("No frames for VID ", input_args$VID, " and FILT ", input_args$FILT, " - skipping")
  }

  if(input_args$do_NIRISS | input_args$do_MIRI){
    ## [fix] NIRISS used FILT = "CLEAR" here, which missed F277W-F480M (see band_of)
    if(make_stacks) do_patch(input_args)
    return(invisible(NULL))
  }

  if(!FILT_given){
    input_args$FILT = SW_FILT
  }

  ## [fix] only look at this visit's raw files (was a header scan of every raw file, on every run)
  sw_files = load_files(input_args, which_module = "1oF")
  sw_files = sw_files[grepl("_nrc[ab][1-4]_", basename(sw_files))] ## short wavelength detectors only

  if( length(sw_files) > 0 ){
    do_wisp_rem(input_args)

    ## Wisp removal edits the raw files in place (keeping SCI_ORIG), so the file list is unchanged.
    do_1of(input_args)
    do_cal_process(input_args)
    do_regen_sky_info(input_args)
    do_super_sky(input_args)
    do_apply_super_sky(input_args)
    do_modify_pedestal(input_args)
    if(make_stacks){
      do_cal_sky_info(input_args)
      do_gen_stack(input_args)
    }
  }

  if(make_stacks){
    input_args$FILT = ""
    do_patch(input_args)
    do_RGB(input_args)
  }
  invisible(NULL)
}

main = function(){
  args = commandArgs(trailingOnly = T)
  if (length(args)==0) {
    message("Specify VID")
    message("Running all")
    VID = ""
    FILT = ""
  } else if (length(args)==1) {
    VID = toString(args[1])
    FILT = ""
  } else if (length(args)==2) {
    VID = toString(args[1])
    FILT = toString(args[2])
  } else {
    message(paste0("Error Nargs wrong: ", length(args)))
    q()
  }
  FILT_given = length(args) == 2

  additional_params_var = initialise_params()
  list2env(additional_params_var, .GlobalEnv)

  env_var = Sys.getenv(
    x = c('JUMPROPE_RAW_DIR',
          'JUMPROPE_do_NIRISS',
          'JUMPROPE_do_MIRI',
          'JUMPROPE_cores_pro',
          'JUMPROPE_cores_stack',
          'JUMPROPE_tasks_stack')
  )

  if(any(env_var == "")){
    message("Please set the env variables.")
    q()
  }

  do_NIRISS = ifelse(grepl("T|TRUE|True", env_var['JUMPROPE_do_NIRISS']), T, F)
  do_MIRI = ifelse(grepl("T|TRUE|True", env_var['JUMPROPE_do_MIRI']), T, F)

  cores_pro = as.integer(env_var['JUMPROPE_cores_pro'])
  cores_stack = as.integer(env_var['JUMPROPE_cores_stack'])
  tasks_stack = as.integer(env_var['JUMPROPE_tasks_stack'])

  dir_raw = env_var['JUMPROPE_RAW_DIR']

  ref_dir = Sys.getenv(x = 'JUMPROPE_REF_DIR')

  if(ref_dir == ""){
    ref_dir = make_directory_structure()
  }else{
    create_directory_structure(ref_dir) ## [fix] no prompt when JUMPROPE_REF_DIR is set
  }

  ## [fix] NIRISS no longer forces FILT = "CLEAR|NIS": NIRISS F090W-F200W are FILTER=CLEAR with the
  ## band in PUPIL, and F277W-F480M are not CLEAR at all. All NIRISS imaging bands are now processed.

  cal_sky_info_save_dir = paste0(ref_dir, "/Pro1oF/")
  Pro1oF_dir = paste0(ref_dir, "/Pro1oF/cal/")
  cal_sky_dir = paste0(ref_dir, "/Pro1oF/cal_sky/")
  cal_sky_renorm_dir = paste0(ref_dir, "/Pro1oF/cal_sky_renorm/")
  sky_pro_dir = paste0(ref_dir, "/sky_pro/")
  sky_frames_dir = paste0(ref_dir, "/sky_pro/sky_frames/")
  sky_super_dir = paste0(ref_dir, "/sky_pro/sky_super/")
  dump_dir = paste0(ref_dir, "/dump/")
  invar_dir = paste0(ref_dir, "/InVar_Stacks/")
  median_dir = paste0(ref_dir, "/Median_Stacks/")
  patch_dir = paste0(ref_dir, "/Patch_Stacks/")

  raw_files = load_raw_files(dir_raw = dir_raw)

  ## [fix] ifelse() returned only the first element, so only the first of 'A|B|C' was ever processed.
  ## Each VID is now processed in turn, as intended.
  VID_list = if(VID == "") "" else unique(trimws(strsplit(VID, "|", fixed = T)[[1]]))
  VID_list = VID_list[VID_list != "" | VID == ""]
  failed = character(0)

  for(k in seq_along(VID_list)){
    VID = VID_list[k]
    message("\n######## VID ", ifelse(VID == "", "(all)", VID), "  [", k, " of ", length(VID_list), "] ########")

    input_args = list(
      filelist = raw_files,
      additional_params = additional_params,

      ref_dir = ref_dir,

      Pro1oF_dir = Pro1oF_dir,
      cal_sky_dir = cal_sky_dir,
      cal_sky_renorm_dir = cal_sky_renorm_dir,
      cal_sky_info_save_dir = cal_sky_info_save_dir,

      sky_frames_dir = sky_frames_dir,
      sky_super_dir = sky_super_dir,
      sky_pro_dir = sky_pro_dir,

      invar_dir = invar_dir,
      median_dir = median_dir,
      patch_dir = patch_dir,
      dump_dir = dump_dir,

      magzero = 23.9,

      VID = VID,
      FILT = FILT,

      do_NIRISS = do_NIRISS,
      do_MIRI = do_MIRI,

      cores_pro = cores_pro,
      cores_stack = cores_stack,
      tasks_stack = tasks_stack,

      SIGMA_LO = NULL ## wisp settings are in initialise_variables.R (wisp_params)
    )

    ## [fix] one failing visit no longer stops the remaining visits; failures are listed at the end
    ok = tryCatch({
      process_visit(input_args, FILT_given)
      TRUE
    }, error = function(e){
      message("\n!!!!!!!! VID ", VID, " FAILED: ", conditionMessage(e), " !!!!!!!!\n")
      try(stopImplicitCluster(), silent = TRUE)
      if(!is.null(additional_params$parallel_type)) closeAllConnections() ## ends orphaned PSOCK workers
      registerDoSEQ()
      FALSE
    })
    if(!ok) failed = c(failed, VID)
  }

  if(length(failed) > 0){
    fail_file = paste0(ref_dir, "/failed_VIDs_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".txt")
    writeLines(failed, fail_file)
    message("\n", length(failed), " of ", length(VID_list), " VIDs failed (listed in ", fail_file, "):")
    message(paste(failed, collapse = "|"))
    quit(status = 1)
  }
  message("\nAll ", length(VID_list), " VIDs done.")
}

if(sys.nframe()==0){
  main()
}
