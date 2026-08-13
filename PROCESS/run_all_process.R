#######################
## Script to run all ##
#######################

## Make sure to edit the proper things in the "main" function

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
  
  additional_params_var = initialise_params()
  list2env(additional_params_var, .GlobalEnv)
  
  env_var = Sys.getenv(
    x = c('JUMPROPE_RAW_DIR', 
          'JUMPROPE_do_NIRISS', 
          'JUMPROPE_do_MIRI',
          'JUMPROPE_cores_pro',
          'JUMPROPE_cores_stack',
          'JUMPROPE_tasks_stack',
          'JUMPROPE_FINAL_CAL_DIR',
          'JUMPROPE_FINAL_CAL_SKY_RENORM_DIR')
  )
  
  required_env = env_var[c('JUMPROPE_RAW_DIR',
                           'JUMPROPE_do_NIRISS',
                           'JUMPROPE_do_MIRI',
                           'JUMPROPE_cores_pro',
                           'JUMPROPE_cores_stack',
                           'JUMPROPE_tasks_stack')]
  if(any(required_env == "")){
    message("Please set the env variables.")
    q()
  }
  
  do_NIRISS = ifelse(grepl("T|TRUE|True", env_var['JUMPROPE_do_NIRISS']), T, F) 
  do_MIRI = ifelse(grepl("T|TRUE|True", env_var['JUMPROPE_do_MIRI']), T, F) 
  
  cores_pro = as.integer(env_var['JUMPROPE_cores_pro'])
  cores_stack = as.integer(env_var['JUMPROPE_cores_stack'])
  tasks_stack = as.integer(env_var['JUMPROPE_tasks_stack'])
  ram_mode = jp_truthy(Sys.getenv("JUMPROPE_RAM_MODE"))
  staging_mode = jp_truthy(Sys.getenv("JUMPROPE_STAGING_MODE"))
  
  dir_raw = env_var['JUMPROPE_RAW_DIR']
  
  ref_dir = Sys.getenv(x = 'JUMPROPE_REF_DIR')

  if(ref_dir == ""){
    ref_dir = make_directory_structure()
  }
  staging_base_dir = ref_dir

  pro1of_cal_persistent_dir = env_var[['JUMPROPE_FINAL_CAL_DIR']]
  cal_sky_renorm_persistent_dir = env_var[['JUMPROPE_FINAL_CAL_SKY_RENORM_DIR']]
  if(staging_mode){
    if(cal_sky_renorm_persistent_dir == ""){
      stop("JUMPROPE_STAGING_MODE=TRUE requires JUMPROPE_FINAL_CAL_SKY_RENORM_DIR to be set.")
    }
    ref_dir_norm = normalizePath(staging_base_dir, winslash = "/", mustWork = FALSE)
    final_dir_norm = normalizePath(cal_sky_renorm_persistent_dir, winslash = "/", mustWork = FALSE)
    if(identical(ref_dir_norm, final_dir_norm)){
      stop("JUMPROPE_REF_DIR staging root must differ from JUMPROPE_FINAL_CAL_SKY_RENORM_DIR.")
    }
  }else{
    pro1of_cal_persistent_dir = NULL
    cal_sky_renorm_persistent_dir = NULL
  }

  use_in_memory_pipeline = ram_mode
  artifact_store = if(use_in_memory_pipeline) new.env(parent = emptyenv()) else NULL
  
  ## For NIRISS, leave FILT empty unless the user explicitly supplied a real science filter.
  
  raw_files = load_raw_files(dir_raw = dir_raw)
  
  if (VID == "") {
    VID_list = c("")
  } else {
    VID_list = unlist(strsplit(VID, "|", fixed = TRUE))
  }
  if(staging_mode){
    stage_vid = if(length(VID_list) > 0 && nzchar(VID_list[1])) VID_list[1] else "all"
    stage_vid = gsub("[^A-Za-z0-9_-]", "_", stage_vid)
    stage_tag = format(Sys.time(), "%Y%m%d_%H%M%S")
    staging_session_root = file.path(dirname(staging_base_dir), paste0(basename(staging_base_dir), "_sessions"))
    dir.create(staging_session_root, recursive = TRUE, showWarnings = FALSE)
    ref_dir = file.path(staging_session_root, paste0("run_", stage_vid, "_", Sys.getpid(), "_", stage_tag))
    jp_reap_stale_stage_sessions(staging_session_root, current_ref_dir = ref_dir)
    message("Staging mode enabled.")
    message("  staging base dir -> ", staging_base_dir)
    message("  session root     -> ", staging_session_root)
    message("  staging run dir  -> ", ref_dir)
    message("  final renorm dir -> ", cal_sky_renorm_persistent_dir)
  }

  require_final_cal = !is.null(pro1of_cal_persistent_dir) && nzchar(pro1of_cal_persistent_dir)

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
  
  for(VID in VID_list){
    if(staging_mode){
      jp_reset_ref_dir(ref_dir)
    }else{
      jp_prepare_ref_dir(ref_dir)
    }

    if(!isTRUE(additional_params$skip_completed_files)){
      message("Resetting intermediates for VID ", VID, " because skip_completed_files=FALSE")
      jp_cleanup_vid_intermediates(ref_dir, VID, remove_final_products = TRUE)
      if(staging_mode && !is.null(cal_sky_renorm_persistent_dir) && nzchar(cal_sky_renorm_persistent_dir)){
        jp_cleanup_vid_intermediates(dirname(dirname(cal_sky_renorm_persistent_dir)), VID, remove_final_products = TRUE)
      }
      jp_prepare_ref_dir(ref_dir)
    }
    if(staging_mode){
      jp_write_stage_marker(
        ref_dir,
        run_name = Sys.getenv("JUMPROPE_RUN_NAME"),
        raw_dir = dir_raw,
        final_dir = cal_sky_renorm_persistent_dir
      )
    }
    
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
      raw_dir = dir_raw,
      pro1of_cal_persistent_dir = pro1of_cal_persistent_dir,
      cal_sky_renorm_persistent_dir = cal_sky_renorm_persistent_dir,
      staging_mode = staging_mode,
      staging_root = if(staging_mode) ref_dir else "",
      cleanup_all_filters = length(args) <= 1,
      use_in_memory_pipeline = use_in_memory_pipeline,
      artifact_store = artifact_store,
  
      SIGMA_LO = NULL #keep blurring at wisp rem stage off by default
    )

    if(jp_store_enabled(input_args)){
      rm(list = ls(envir = artifact_store, all.names = TRUE), envir = artifact_store)
    }

    if(staging_mode && isTRUE(additional_params$skip_completed_files)){
      renorm_state = jp_expected_renorm_state(input_args, renorm_dir = cal_sky_renorm_persistent_dir)
      cal_state = if(require_final_cal){
        jp_expected_cal_state(input_args, cal_dir = pro1of_cal_persistent_dir)
      }else{
        list(complete = TRUE, reason = "disabled", invalid_files = character(0))
      }

      if(isTRUE(renorm_state$complete) && isTRUE(cal_state$complete)){
        message("Skipping VID ", VID, ": final cal_sky_renorm products already complete in ", cal_sky_renorm_persistent_dir)
        next
      }

      if(isTRUE(renorm_state$complete) && !isTRUE(cal_state$complete) && require_final_cal){
        message("VID ", VID, ": final cal_sky_renorm complete, but final Pro1oF cal incomplete. Running cal-only backfill.")
        backfill_args = input_args
        backfill_args$FILT = ""
        backfill_args$force_refresh_pro1of = TRUE
        do_1of(backfill_args)
        jp_promote_cal_only(backfill_args)
        next
      }
    }
   
    if(length(args) <= 1 & !input_args$do_NIRISS){
      input_args$FILT = "F277W|F356W|F444W|F250M|F300M|F335M|F360M|F410M|F430M|F460M|F480M|F323N|F405N|F466N|F470N" ## Process long wavelengths first

    }

    run_processing_round = function(args_local){
      do_1of(args_local)
      do_cal_process(args_local)
      do_regen_sky_info(args_local)
      do_super_sky(args_local)
      do_apply_super_sky(args_local)
      do_modify_pedestal(args_local)
      do_cal_sky_info(args_local)
      do_gen_stack(args_local)
      invisible(args_local)
    }

    run_processing_round(input_args)
  
    if(input_args$do_NIRISS){
      input_args$FILT = ""
    }else if(input_args$do_MIRI){
    }else{
      if(length(args) <= 1){
        input_args$FILT = "F070W|F090W|F115W|F150W|F200W|F140M|F162M|F182M|F210M|F164N|F187N|F212N"
      }
      
      frame_info = data.frame(Rfits_key_scan(
        filelist = raw_files, 
        keylist = c('FILTER'), 
        cores = cores_pro
      ))
      
      if(length(grep(input_args$FILT, frame_info$FILTER)) > 0){
        do_wisp_rem(input_args)
        
        input_args$filelist = load_raw_files(dir_raw = dir_raw)
        input_args$force_refresh_pro1of = TRUE
        run_processing_round(input_args)
        input_args$force_refresh_pro1of = FALSE
      }
    }

    if(staging_mode){
      do_cleanup(input_args)
    }
  }

}

if(sys.nframe()==0){
  main()
}
