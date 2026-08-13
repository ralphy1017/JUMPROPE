############################################
## Script to run specific process code V2 ##
############################################

## Make sure to edit the proper things in the "zork" function

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

select_code_func = function(){
  message("
          ############################################################
          ############################################################
          ## Thank you for choosing ZORK for your JWST processing!  ##
          ## Press:                                                 ##
          ## 0 = Set up directory structure                         ##
          ## 1 = Pro1oF                                             ##
          ## 2 = Create sky                                         ##
          ## 3 = Regen sky info                                     ##
          ## 4 = Make super sky                                     ##
          ## 5 = Remove super sky                                   ##
          ## 6 = Modify pedestal                                    ##
          ## 7 = Cal sky info                                       ##
          ## 8 = Stack                                              ##
          ## 9 = Patch                                              ##
          ## 10 = RGB                                               ##
          ## 11 = Wisp remove                                       ##
          ## 12 = Reverse wisp removal                              ##
          ## 13 = Help                                              ##
          ## 14 = Cleanup                                            ##
          ##                                                        ##
          ##  e.g., 1,2,3,4,5,6,7,8,11 for everything + wisp rem    ##
          ## CONTROL + /\ to EXIT                                    ##
          ############################################################
          ############################################################
          "
  )
  select_code = toString(readLines("stdin", n=1))
  
  select_vector = as.integer(
    strsplit(
      select_code, ","
    )[[1]]
  )
  if( sum(select_vector %in% 0:13) == 0){
    message("Oops, I think you made a mistake. Trying again.")
    select_code_func()
  }
  else{
    return(
      select_vector+1 ## Plus one since can't index list with 0
    )
  }
}

zork = function(){
  
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
    if(FILT == "short"){
      FILT = "F070W|F090W|F115W|F150W|F200W|F140M|F162M|F182M|F210M|F164N|F187N|F212N"
    }else if(FILT == "long"){
      FILT = "F277W|F356W|F444W|F250M|F300M|F335M|F360M|F410M|F430M|F460M|F480M|F323N|F405N|F466N|F470N"
    }
  } else {
    message(paste0("Error Nargs wrong: ", length(args)))
    q()
  }
  
  last_input_args = NULL
  ram_work_dir = NULL
  
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
  }
  
  ## For NIRISS, leave FILT empty unless the user explicitly supplied a real science filter.
  
  cal_sky_info_save_dir = paste0(ref_dir, "/Pro1oF/")
  Pro1oF_dir = paste0(ref_dir, "/Pro1oF/cal/")
  cal_sky_dir = paste0(ref_dir, "/Pro1oF/cal_sky/")
  cal_sky_renorm_dir_env = Sys.getenv("JUMPROPE_CAL_SKY_RENORM_DIR")
  cal_sky_renorm_dir = if(nzchar(cal_sky_renorm_dir_env)) cal_sky_renorm_dir_env else paste0(ref_dir, "/Pro1oF/cal_sky_renorm/")
  sky_pro_dir = paste0(ref_dir, "/sky_pro/")
  sky_frames_dir = paste0(ref_dir, "/sky_pro/sky_frames/")
  sky_super_dir = paste0(ref_dir, "/sky_pro/sky_super/")
  dump_dir_env = Sys.getenv("JUMPROPE_DUMP_DIR")
  dump_dir = if(nzchar(dump_dir_env)) dump_dir_env else paste0(ref_dir, "/dump/")
  invar_dir = paste0(ref_dir, "/InVar_Stacks/")
  median_dir = paste0(ref_dir, "/Median_Stacks/")
  patch_dir = paste0(ref_dir, "/Patch_Stacks/")


  ## ── RAM mode: stage only the highest-I/O Pro1oF products to /dev/shm ──
  ## On cleanup: SCI_ORIG verified in staging dir, cal_sky_renorm copied to
  ## ref_dir/Pro1oF/cal_sky_renorm/ on disk, then /dev/shm is wiped.
  ## Works for 7-digit obs IDs (1176211) and 10-digit visit IDs (1176211001).
  cal_sky_renorm_persistent_dir = cal_sky_renorm_dir   # always the on-disk final destination
  ram_mode = grepl("T|TRUE|True", Sys.getenv("JUMPROPE_RAM_MODE"))
  cleanup_flag = grepl("T|TRUE|True", Sys.getenv("JUMPROPE_CLEANUP"))
  if(ram_mode){
    df_raw = tryCatch(system("df -k /dev/shm", intern=TRUE), error=function(e) character(0))
    shm_avail_gb = if(length(df_raw) >= 2){
      parts = strsplit(trimws(df_raw[2]), "\\s+")[[1]]
      as.numeric(parts[4]) / 1048576   # kB -> GB
    } else Inf
    message(sprintf("RAM MODE: /dev/shm has %.0f GB available", shm_avail_gb))
    if(shm_avail_gb < 50){
      message(sprintf("  Only %.0f GB free in /dev/shm — falling back to disk mode", shm_avail_gb))
      ram_mode = FALSE
    } else if(shm_avail_gb < 150){
      message(sprintf("  WARNING: %.0f GB free — heavy observations may be tight", shm_avail_gb))
    }
  }
  if(ram_mode){
    ram_work_dir          = "/dev/shm/jumprope_work"
    message(paste0("  Staging Pro1oF intermediates + cal_sky_renorm -> ", ram_work_dir))
    message(paste0("  Final cal_sky_renorm (disk) -> ", cal_sky_renorm_persistent_dir))
    cal_sky_info_save_dir = paste0(ram_work_dir, "/Pro1oF/")
    Pro1oF_dir            = paste0(ram_work_dir, "/Pro1oF/cal/")
    cal_sky_dir           = paste0(ram_work_dir, "/Pro1oF/cal_sky/")
    cal_sky_renorm_dir    = paste0(ram_work_dir, "/Pro1oF/cal_sky_renorm/")
    ## Keep stack prerequisites + outputs on disk; large FITS writes to tmpfs
    ## remain unstable for some filters (for example 1208023 F182M NRCA_short).
    sky_pro_dir           = paste0(ref_dir, "/sky_pro/")
    sky_frames_dir        = paste0(ref_dir, "/sky_pro/sky_frames/")
    sky_super_dir         = paste0(ref_dir, "/sky_pro/sky_super/")
    ## dump_dir intentionally NOT staged to RAM — cfitsio inVar_warp writes
    ## fail on tmpfs; dump files are small (~17MB each) and suit disk fine.
    ## dump_dir already set to disk path above (ref_dir/dump/).
    invar_dir             = paste0(ref_dir, "/InVar_Stacks/")
    median_dir            = paste0(ref_dir, "/Median_Stacks/")
    patch_dir             = paste0(ref_dir, "/Patch_Stacks/")
    ## cal_sky_renorm_persistent_dir stays on disk — copied from RAM in do_cleanup
    ## Create RAM and disk directories upfront so pipeline steps can write immediately
    for(d in c(cal_sky_info_save_dir, Pro1oF_dir, cal_sky_dir, cal_sky_renorm_dir,
               sky_pro_dir, sky_frames_dir, sky_super_dir,
               invar_dir, median_dir, patch_dir)){
      dir.create(d, recursive = TRUE, showWarnings = FALSE)
    }
    message("  RAM directories created.")
    message("  sky_pro / InVar_Stacks / Median_Stacks / Patch_Stacks stay on disk for FITS-write stability.")
    ## Clean and create the disk dump_dir for this run
    if(dir.exists(dump_dir)) unlink(dump_dir, recursive = TRUE)
    dir.create(dump_dir, recursive = TRUE, showWarnings = FALSE)
    message(paste0("  dump_dir (disk) -> ", dump_dir))
    on.exit({
      if(!is.null(last_input_args) && dir.exists(ram_work_dir)){
        do_cleanup(last_input_args, force = TRUE)
      }else if(!is.null(ram_work_dir) && dir.exists(ram_work_dir)){
        unlink(ram_work_dir, recursive = TRUE)
        message("Forced RAM cleanup complete: ", ram_work_dir)
      }
    }, add = TRUE)
  }
  ensure_ram_mode_dirs = function(){
    if(!ram_mode){
      return(invisible(NULL))
    }
    for(d in c(cal_sky_info_save_dir, Pro1oF_dir, cal_sky_dir, cal_sky_renorm_dir,
               sky_pro_dir, sky_frames_dir, sky_super_dir,
               invar_dir, median_dir, patch_dir)){
      dir.create(d, recursive = TRUE, showWarnings = FALSE)
    }
    if(dir.exists(dump_dir)) unlink(dump_dir, recursive = TRUE)
    dir.create(dump_dir, recursive = TRUE, showWarnings = FALSE)
    invisible(NULL)
  }
  

  
  raw_files = load_raw_files(dir_raw = dir_raw)
  
  select_code = select_code_func()
  selected_steps = sort(unique(select_code - 1L))
  use_in_memory_pipeline = ram_mode &&
    identical(selected_steps, c(1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L, 11L))
  artifact_store = if(use_in_memory_pipeline) new.env(parent = emptyenv()) else NULL
  if(use_in_memory_pipeline){
    message("RAM MODE full-run handoff enabled: reusing manifests, metadata, and super-sky artifacts in-process.")
  }

  make_dir_temp_func = function(input_args){make_directory_structure()}
  code_organiser = list(
    'make_directory_structure'=make_dir_temp_func, ## Hack to handle input_args
    'do_1oF'=do_1of,
    'do_cal_process'=do_cal_process,
    'do_regen_sky_info' = do_regen_sky_info,
    'do_super_sky'=do_super_sky,
    'do_apply_super_sky' = do_apply_super_sky,
    'do_modify_pedestal' = do_modify_pedestal,
    'do_cal_sky_info' = do_cal_sky_info,
    'do_gen_stack' = do_gen_stack,
    'do_patch' = do_patch,
    'do_rgb' = do_RGB,
    'do_wisp_rem' = do_wisp_rem,
    'do_wisp_reverse' = do_wisp_reverse,
    'do_help' = do_help,
    'do_cleanup' = do_cleanup
  )
  
  #VID_list = ifelse(VID != "", unlist(strsplit(VID, "|", fixed = T)), list(c("")))
  if(VID != ""){
   VID_list = unlist(strsplit(VID, "|", fixed = T)) 
  }else{
   VID_list = list(c("")) 
  }
  
  for(VID in VID_list){
    ensure_ram_mode_dirs()
    
    input_args = list(
      filelist = raw_files,
      additional_params = additional_params,
      
      ref_dir = ref_dir,
      
      Pro1oF_dir = Pro1oF_dir,
      cal_sky_dir = cal_sky_dir,
      cal_sky_renorm_dir = cal_sky_renorm_dir,
      cal_sky_renorm_persistent_dir = cal_sky_renorm_persistent_dir,
      cal_sky_info_save_dir = cal_sky_info_save_dir,
      
      sky_frames_dir = sky_frames_dir,
      sky_super_dir = sky_super_dir,
      sky_pro_dir = sky_pro_dir,
      
      invar_dir = invar_dir, 
      median_dir = median_dir, 
      patch_dir = patch_dir,
      dump_dir = dump_dir, 
      raw_dir = dir_raw,
      
      magzero = 23.9,
      
      VID = VID,
      FILT = FILT,
      
      do_NIRISS = do_NIRISS,
      do_MIRI = do_MIRI,
      
      cores_pro = cores_pro,
      cores_stack = cores_stack,
      tasks_stack = tasks_stack,
      use_in_memory_pipeline = use_in_memory_pipeline,
      artifact_store = artifact_store,
      
      SIGMA_LO = NULL #keep blurring at wisp rem stage off by default
    )
    
    last_input_args = input_args
    lapply(select_code,function(x){code_organiser[[x]](input_args)})
    if(ram_mode && cleanup_flag){
      message("Per-VID RAM cleanup for ", VID)
      do_cleanup(last_input_args)
    }
  }
  if(cleanup_flag){
    message("JUMPROPE_CLEANUP=TRUE: running post-run cleanup sweep over all VIDs...")
    do_cleanup(last_input_args)
  }
}

if(sys.nframe()==0){
  zork()
}
