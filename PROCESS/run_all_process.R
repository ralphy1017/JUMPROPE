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

jp_extract_visit_ids_from_filenames = function(paths){
  base = basename(paths)
  hit = grepl("^jw0?[0-9]{10}_", base)
  out = rep(NA_character_, length(base))
  out[hit] = sub("^jw0?([0-9]{10})_.*$", "\\1", base[hit])
  out
}

jp_expand_obs_ids_to_visit_ids = function(vid_list, raw_files, staging_mode){
  expand = jp_truthy(Sys.getenv(
    "JUMPROPE_EXPAND_OBS_TO_VISITS",
    unset = ifelse(staging_mode, "TRUE", "FALSE")
  ))
  if(!isTRUE(expand) || length(vid_list) == 0 || identical(vid_list, "")){
    return(vid_list)
  }

  visit_ids = jp_extract_visit_ids_from_filenames(raw_files)
  visit_ids = visit_ids[!is.na(visit_ids) & nzchar(visit_ids)]

  expanded_obs = 0L
  expanded_visits = 0L
  verbose_expand = jp_truthy(Sys.getenv("JUMPROPE_VERBOSE_VISIT_EXPANSION"))
  expanded = unlist(lapply(vid_list, function(id){
    id = trimws(id)
    if(grepl("^[0-9]{7}$", id)){
      hits = sort(unique(visit_ids[startsWith(visit_ids, id)]))
      if(length(hits) > 0){
        expanded_obs <<- expanded_obs + 1L
        expanded_visits <<- expanded_visits + length(hits)
        if(isTRUE(verbose_expand)){
          message("Expanding observation ID ", id, " to ", length(hits), " visit ID(s): ", paste(hits, collapse = "|"))
        }
        return(hits)
      }
    }
    id
  }), use.names = FALSE)

  expanded = unique(expanded[nzchar(expanded)])
  if(expanded_obs > 0L){
    message("Expanded ", expanded_obs, " observation ID(s) into ", expanded_visits, " visit ID staging unit(s).")
  }
  expanded
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
  VID_list = jp_expand_obs_ids_to_visit_ids(VID_list, raw_files, staging_mode = staging_mode)
  long_wave_filters = "F277W|F322W2|F356W|F444W|F250M|F300M|F335M|F360M|F410M|F430M|F460M|F480M|F323N|F405N|F466N|F470N"
  short_wave_filters = "F070W|F090W|F115W|F150W|F200W|F140M|F162M|F182M|F210M|F164N|F187N|F212N"
  if(staging_mode){
    staging_session_root = file.path(dirname(staging_base_dir), paste0(basename(staging_base_dir), "_sessions"))
    dir.create(staging_session_root, recursive = TRUE, showWarnings = FALSE)
    message("Staging mode enabled.")
    message("  staging base dir -> ", staging_base_dir)
    message("  session root     -> ", staging_session_root)
    message("  final renorm dir -> ", cal_sky_renorm_persistent_dir)
  }else{
    staging_session_root = ""
  }

  require_final_cal = !is.null(pro1of_cal_persistent_dir) && nzchar(pro1of_cal_persistent_dir)
  if(staging_mode && isTRUE(additional_params$skip_completed_files)){
    message("Resume mode enabled: completed observations will be skipped using final product directories.")
    if(require_final_cal){
      message("  final cal dir       -> ", pro1of_cal_persistent_dir)
    }
    message("  final renorm dir    -> ", cal_sky_renorm_persistent_dir)
  }

  for(VID in VID_list){
    local({
      vid_completed = FALSE
      current_vid = VID
      current_ref_dir = ""

      on.exit({
        if(staging_mode && !vid_completed && nzchar(current_ref_dir) && dir.exists(current_ref_dir)){
          message("VID ", current_vid, " aborted before cleanup. Removing incomplete staging root: ", current_ref_dir)
          jp_remove_tree(current_ref_dir)
        }
      }, add = TRUE)

      if(staging_mode){
        stage_vid = if(nzchar(VID)) VID else "all"
        stage_vid = gsub("[^A-Za-z0-9_-]", "_", stage_vid)
        stage_tag = format(Sys.time(), "%Y%m%d_%H%M%S")
        ref_dir = file.path(staging_session_root, paste0("run_", stage_vid, "_", Sys.getpid(), "_", stage_tag))
        current_ref_dir = ref_dir
        jp_reap_stale_stage_sessions(staging_session_root, current_ref_dir = ref_dir)
        message("  staging run dir  -> ", ref_dir)
      }else{
        ref_dir = staging_base_dir
      }

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

        SIGMA_LO = jp_env_numeric("JUMPROPE_WISP_SIGMA_LO", 5) # validated production default for wisp template low-frequency smoothing
      )

      jp_write_runtime_manifest(
        ref_dir = ref_dir,
        input_args = input_args,
        run_name = Sys.getenv("JUMPROPE_RUN_NAME")
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
          if(staging_mode && dir.exists(ref_dir)){
            jp_remove_tree(ref_dir)
          }
          vid_completed = TRUE
          return(invisible(NULL))
        }

        if(isTRUE(renorm_state$complete) && !isTRUE(cal_state$complete) && require_final_cal){
          message("VID ", VID, ": final cal_sky_renorm complete, but final Pro1oF cal incomplete. Running cal-only backfill.")
          backfill_args = input_args
          backfill_args$FILT = ""
          backfill_args$force_refresh_pro1of = TRUE
          do_1of(backfill_args)
          jp_promote_cal_only(backfill_args)
          vid_completed = TRUE
          return(invisible(NULL))
        }

        if(!isTRUE(renorm_state$complete) || !isTRUE(cal_state$complete)){
          persistent_root = dirname(dirname(cal_sky_renorm_persistent_dir))
          message(
            "VID ", VID, ": final outputs are not fully complete/valid",
            " (renorm=", renorm_state$reason,
            ", cal=", cal_state$reason, ").",
            " Resetting this VID and rebuilding from raw inputs."
          )
          jp_cleanup_vid_intermediates(ref_dir, VID, remove_final_products = TRUE)
          if(dir.exists(persistent_root)){
            jp_cleanup_vid_intermediates(
              persistent_root,
              VID,
              remove_final_products = TRUE,
              remove_cal_products = TRUE,
              remove_cal_sky_products = TRUE
            )
          }
          jp_prepare_ref_dir(ref_dir)
          input_args$additional_params$skip_completed_files = FALSE
          input_args$force_refresh_pro1of = TRUE
        }
      }

      if(length(args) <= 1 & !input_args$do_NIRISS){
          input_args$FILT = long_wave_filters ## Process long wavelengths first

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
          input_args$FILT = short_wave_filters
        }

        frame_info = data.frame(Rfits_key_scan(
          filelist = raw_files,
          keylist = c('FILTER'),
          cores = cores_pro
        ))

        if(length(grep(input_args$FILT, frame_info$FILTER)) > 0){
          if(staging_mode){
            message("Early promotion/prune: flushing completed long-wave staged products before wisp propagation.")
            jp_promote_stage_products(
              input_args,
              filter_regex = long_wave_filters,
              promote_cal = TRUE,
              promote_renorm = TRUE
            )
            jp_prune_stage_products(
              input_args,
              filter_regex = long_wave_filters,
              remove_cal_products = TRUE,
              remove_cal_sky_products = TRUE,
              remove_final_products = TRUE,
              remove_sky_frames = TRUE,
              remove_sky_super = FALSE,
              remove_dump = TRUE
            )
          }

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
      vid_completed = TRUE
    })
  }

}

if(sys.nframe()==0){
  main()
}
