source(file.path(dirname(sys.frame(1)$ofile), "..", "config.R"))

jwst_dq_do_not_use_mask = function(temp_mask){
  mask_dim = dim(temp_mask)
  output = as.numeric(temp_mask) %% 2 == 1
  if(!is.null(mask_dim)){
    dim(output) = mask_dim
  }
  output
}

jwst_read_cal_core = function(filename){
  output = list(
    Rfits_read_header(filename, ext=1),
    SCI = Rfits_read_image(filename, ext="SCI"),
    DQ = Rfits_read_image(filename, ext="DQ")
  )
  names(output)[1] = ""
  class(output) = "Rfits_list"
  attributes(output)$filename = filename
  output
}

jwst_read_sky_masks = function(filename){
  output = list(
    PIXELMASK = Rfits_read_image(filename, ext="PIXELMASK"),
    OBJECTMASK = Rfits_read_image(filename, ext="OBJECTMASK")
  )
  class(output) = "Rfits_list"
  attributes(output)$filename = filename
  output
}

jwst_read_cal_sky_core = function(filename){
  output = list(
    SCI = Rfits_read_image(filename, ext="SCI"),
    SKY_Super = Rfits_read_image(filename, ext="SKY_Super")
  )
  class(output) = "Rfits_list"
  attributes(output)$filename = filename
  output
}

jp_store_enabled = function(input_args){
  isTRUE(input_args$use_in_memory_pipeline) &&
    !is.null(input_args$artifact_store) &&
    is.environment(input_args$artifact_store)
}

jp_store_set = function(input_args, name, value){
  if(jp_store_enabled(input_args)){
    assign(name, value, envir = input_args$artifact_store)
  }
  invisible(value)
}

jp_store_get = function(input_args, name, default = NULL){
  if(jp_store_enabled(input_args) &&
     exists(name, envir = input_args$artifact_store, inherits = FALSE)){
    get(name, envir = input_args$artifact_store, inherits = FALSE)
  }else{
    default
  }
}

jp_store_list_set = function(input_args, slot, key, value){
  if(!jp_store_enabled(input_args)){
    return(invisible(value))
  }
  temp_list = jp_store_get(input_args, slot, default = list())
  temp_list[[key]] = value
  jp_store_set(input_args, slot, temp_list)
  invisible(value)
}

jp_truthy = function(x){
  length(x) == 1L && !is.na(x) && grepl("^(T|TRUE)$", as.character(x), ignore.case = TRUE)
}

jp_short_detectors = function(additional_params){
  if(isTRUE(additional_params$do_claws)){
    c("nrca1", "nrca2", "nrca3", "nrca4", "nrcb1", "nrcb2", "nrcb3", "nrcb4")
  }else{
    c("nrca3", "nrca4", "nrcb3", "nrcb4")
  }
}

jp_prepare_ref_dir = function(ref_dir){
  dir.create(file.path(ref_dir, "Pro1oF", "cal"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(ref_dir, "Pro1oF", "cal_sky"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(ref_dir, "Pro1oF", "cal_sky_renorm"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(ref_dir, "sky_pro", "sky_frames"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(ref_dir, "sky_pro", "sky_super"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(ref_dir, "dump"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(ref_dir, "InVar_Stacks"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(ref_dir, "Median_Stacks"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(ref_dir, "Patch_Stacks"), recursive = TRUE, showWarnings = FALSE)
  invisible(ref_dir)
}

jp_stage_marker_path = function(ref_dir){
  file.path(ref_dir, ".jumprope_session_meta")
}

jp_write_stage_marker = function(ref_dir, run_name = "", raw_dir = "", final_dir = ""){
  dir.create(ref_dir, recursive = TRUE, showWarnings = FALSE)
  marker = jp_stage_marker_path(ref_dir)
  marker_data = c(
    paste0("pid=", Sys.getpid()),
    paste0("started=", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    paste0("run_name=", run_name),
    paste0("raw_dir=", raw_dir),
    paste0("final_dir=", final_dir)
  )
  writeLines(marker_data, marker, useBytes = TRUE)
  invisible(marker)
}

jp_stage_owner_pid = function(ref_dir){
  marker = jp_stage_marker_path(ref_dir)
  if(!file.exists(marker)){
    return(NA_integer_)
  }
  marker_lines = tryCatch(readLines(marker, warn = FALSE), error = function(e) character(0))
  pid_line = marker_lines[grepl("^pid=", marker_lines)]
  if(length(pid_line) == 0){
    return(NA_integer_)
  }
  suppressWarnings(as.integer(sub("^pid=", "", pid_line[[1]])))
}

jp_pid_is_alive = function(pid){
  if(length(pid) != 1L || is.na(pid) || pid <= 0L){
    return(FALSE)
  }
  dir.exists(file.path("/proc", as.character(pid)))
}

jp_reap_stale_stage_sessions = function(session_root, current_ref_dir = "", stale_age_hours = 6){
  if(is.null(session_root) || !nzchar(session_root) || !dir.exists(session_root)){
    return(invisible(NULL))
  }

  stale_age_seconds = max(0, as.numeric(stale_age_hours)) * 3600
  now_time = Sys.time()
  session_dirs = list.dirs(session_root, recursive = FALSE, full.names = TRUE)
  if(length(session_dirs) == 0){
    return(invisible(NULL))
  }

  for(session_dir in session_dirs){
    if(nzchar(current_ref_dir) && identical(normalizePath(session_dir, winslash = "/", mustWork = FALSE),
                                            normalizePath(current_ref_dir, winslash = "/", mustWork = FALSE))){
      next
    }

    owner_pid = jp_stage_owner_pid(session_dir)
    if(jp_pid_is_alive(owner_pid)){
      next
    }

    marker_exists = file.exists(jp_stage_marker_path(session_dir))
    dir_info = file.info(session_dir)
    dir_age_seconds = if(!is.na(dir_info$mtime)) as.numeric(difftime(now_time, dir_info$mtime, units = "secs")) else Inf
    if(!marker_exists && is.finite(stale_age_seconds) && dir_age_seconds < stale_age_seconds){
      next
    }

    unlink(session_dir, recursive = TRUE)
    message("Reaped stale staging session: ", session_dir)
  }

  invisible(NULL)
}

jp_reset_ref_dir = function(ref_dir){
  if(dir.exists(ref_dir)){
    unlink(ref_dir, recursive = TRUE)
  }
  jp_prepare_ref_dir(ref_dir)
}

jp_expected_renorm_state = function(input_args, renorm_dir = NULL){
  if(is.null(renorm_dir)){
    renorm_dir = input_args$cal_sky_renorm_dir
  }

  raw_inputs = load_files(input_args, which_module = "1oF")
  raw_inputs = unique(raw_inputs)

  if(length(raw_inputs) == 0){
    return(list(
      complete = FALSE,
      reason = "no_inputs",
      expected_files = character(0),
      short_files = character(0),
      invalid_files = character(0)
    ))
  }

  output_suffix = if(isTRUE(input_args$do_MIRI)) "_MIRI_sky_rem.fits" else "_Pro1oF_sky_rem.fits"
  expected_files = file.path(
    renorm_dir,
    paste0(sub("\\.fits$", "", basename(raw_inputs), ignore.case = TRUE), output_suffix)
  )
  expected_files = unique(expected_files)

  valid_fits = vapply(
    expected_files,
    function(f) is_valid_fits_file(f, required_ext = "SCI"),
    logical(1)
  )
  if(!all(valid_fits)){
    return(list(
      complete = FALSE,
      reason = "missing_or_invalid",
      expected_files = expected_files,
      short_files = character(0),
      invalid_files = expected_files[!valid_fits]
    ))
  }

  short_files = character(0)
  if(!isTRUE(input_args$do_NIRISS) && !isTRUE(input_args$do_MIRI)){
    raw_info = data.frame(Rfits_key_scan(
      filelist = raw_inputs,
      keylist = c("CHANNEL"),
      extlist = 1,
      fileinfo = NULL,
      cores = min(input_args$cores_pro, length(raw_inputs))
    ))
    if("CHANNEL" %in% names(raw_info)){
      short_idx = toupper(as.character(raw_info$CHANNEL)) == "SHORT"
      short_files = expected_files[short_idx]
    }
  if(length(short_files) > 0){
      sci_orig_ok = vapply(short_files, function(f){
        "SCI_ORIG" %in% na.omit(Rfits_extnames(f))
      }, logical(1))
      if(!all(sci_orig_ok)){
        return(list(
          complete = FALSE,
          reason = "missing_sci_orig",
          expected_files = expected_files,
          short_files = short_files,
          invalid_files = short_files[!sci_orig_ok]
        ))
      }
    }
  }

  raw_mtime = file.info(raw_inputs)$mtime
  output_mtime = file.info(expected_files)$mtime
  stale_idx = is.na(raw_mtime) | is.na(output_mtime) | output_mtime < raw_mtime
  if(any(stale_idx)){
    return(list(
      complete = FALSE,
      reason = "stale_outputs",
      expected_files = expected_files,
      short_files = short_files,
      invalid_files = expected_files[stale_idx]
    ))
  }

  list(
    complete = TRUE,
    reason = "ok",
    expected_files = expected_files,
    short_files = short_files,
    invalid_files = character(0)
  )
}

jp_expected_cal_state = function(input_args, cal_dir = NULL){
  if(is.null(cal_dir)){
    cal_dir = input_args$Pro1oF_dir
  }

  raw_inputs = load_files(input_args, which_module = "1oF")
  raw_inputs = unique(raw_inputs)

  if(length(raw_inputs) == 0){
    return(list(
      complete = FALSE,
      reason = "no_inputs",
      expected_files = character(0),
      short_files = character(0),
      invalid_files = character(0)
    ))
  }

  output_suffix = if(isTRUE(input_args$do_MIRI)) "_MIRI.fits" else "_Pro1oF.fits"
  expected_files = file.path(
    cal_dir,
    paste0(sub("\\.fits$", "", basename(raw_inputs), ignore.case = TRUE), output_suffix)
  )
  expected_files = unique(expected_files)

  valid_fits = vapply(
    expected_files,
    function(f) is_valid_fits_file(f, required_ext = "SCI"),
    logical(1)
  )
  if(!all(valid_fits)){
    return(list(
      complete = FALSE,
      reason = "missing_or_invalid",
      expected_files = expected_files,
      short_files = character(0),
      invalid_files = expected_files[!valid_fits]
    ))
  }

  short_files = character(0)
  if(!isTRUE(input_args$do_NIRISS) && !isTRUE(input_args$do_MIRI)){
    raw_info = data.frame(Rfits_key_scan(
      filelist = raw_inputs,
      keylist = c("CHANNEL"),
      extlist = 1,
      fileinfo = NULL,
      cores = min(input_args$cores_pro, length(raw_inputs))
    ))
    if("CHANNEL" %in% names(raw_info)){
      short_idx = toupper(as.character(raw_info$CHANNEL)) == "SHORT"
      short_files = expected_files[short_idx]
    }
  if(length(short_files) > 0){
      sci_orig_ok = vapply(short_files, function(f){
        "SCI_ORIG" %in% na.omit(Rfits_extnames(f))
      }, logical(1))
      if(!all(sci_orig_ok)){
        return(list(
          complete = FALSE,
          reason = "missing_sci_orig",
          expected_files = expected_files,
          short_files = short_files,
          invalid_files = short_files[!sci_orig_ok]
        ))
      }
    }
  }

  raw_mtime = file.info(raw_inputs)$mtime
  output_mtime = file.info(expected_files)$mtime
  stale_idx = is.na(raw_mtime) | is.na(output_mtime) | output_mtime < raw_mtime
  if(any(stale_idx)){
    return(list(
      complete = FALSE,
      reason = "stale_outputs",
      expected_files = expected_files,
      short_files = short_files,
      invalid_files = expected_files[stale_idx]
    ))
  }

  list(
    complete = TRUE,
    reason = "ok",
    expected_files = expected_files,
    short_files = short_files,
    invalid_files = character(0)
  )
}

load_files = function(input_args, which_module, sky_info = NULL){
  ## Load the correct files for what ever task
  ## Correctly place files into whatever module
  ## Which module tells me which step to load files for
  
  VID = input_args$VID
  FILT = input_args$FILT
  cores = input_args$cores_pro
  
  Pro1oF_dir = input_args$Pro1oF_dir
  sky_pro_dir = input_args$sky_pro_dir
  sky_frames_dir = input_args$sky_frames_dir
  sky_super_dir = input_args$sky_super_dir
  cal_sky_dir = input_args$cal_sky_dir
  raw_dir = input_args$raw_dir
  
  do_NIRISS = input_args$do_NIRISS
  do_MIRI = input_args$do_MIRI

  keep_readable_fits = function(filelist){
    filelist = unique(filelist)
    filelist = filelist[!is.na(filelist) & nzchar(filelist)]
    filelist = filelist[file.exists(filelist) & file.access(filelist, 4) == 0]
    filelist[grepl(".fits$", filelist)]
  }
  
  if(which_module == "1oF"){
    files_1oF = input_args$filelist
    files_1oF = files_1oF[grepl(VID, files_1oF) & grepl(".fits$", files_1oF)]
    if(do_NIRISS){
      files_1oF = files_1oF[!grepl('_mirimage_',files_1oF) & grepl('_nis_',files_1oF) & grepl(".fits$", files_1oF)]
    }else if (do_MIRI){
      files_1oF = files_1oF[grepl('_mirimage_',files_1oF) & !grepl('_nis_',files_1oF) & grepl(".fits$", files_1oF)]
    }else{
      files_1oF = files_1oF[!grepl('_mirimage_',files_1oF) & !grepl('_nis_', files_1oF) & grepl(".fits$", files_1oF)]
    }
    files_1oF = keep_readable_fits(files_1oF)
    if(length(files_1oF) == 0){
      message("No readable raw FITS files matched VID/FILT under ", raw_dir)
      return(character(0))
    }
    
    scan_1oF = safe_key_scan(files_1oF, keylist = c("FILTER", "PROGRAM", "VISIT_ID"), cores = cores, context = paste0("1oF VID ", VID))
    if(nrow(scan_1oF) == 0){
      return(character(0))
    }
    corr_pid = grep(VID, scan_1oF$VISIT_ID, fixed = T, value = T)
    corr_pid = corr_pid[substring(corr_pid, 1, nchar(VID)) == VID] ## Make sure 4 digit PID is embedded in 10 digit VID
    pid_idx = scan_1oF$VISIT_ID %in% corr_pid
    
    files_1oF = scan_1oF$full[pid_idx]
    files_1oF = files_1oF[grepl(FILT, scan_1oF$FILTER[pid_idx])]
    return(files_1oF)
  }
  
  if(which_module == "cal_process"){
    files_cal = jp_store_get(input_args, "pro1of_files", default = NULL)
    if(is.null(files_cal)){
      files_cal = c(
        list.files(Pro1oF_dir,
                   full.names = TRUE,
                   pattern = glob2rx(paste0("*",VID,"*.fits")))
      )
    }
    if(do_NIRISS){
      files_cal = files_cal[!grepl('_mirimage_',files_cal) & grepl('_nis_',files_cal) & grepl(".fits$", files_cal)]
    }else if (do_MIRI){
      files_cal = files_cal[grepl('_mirimage_',files_cal) & !grepl('_nis_',files_cal) & grepl(".fits$", files_cal)]
    }else{
      files_cal = files_cal[!grepl('_mirimage_',files_cal) & !grepl('_nis_', files_cal) & grepl(".fits$", files_cal)]
    }
    files_cal = keep_readable_fits(files_cal)
    if(length(files_cal) == 0){
      return(character(0))
    }
    
    scan_cal = safe_key_scan(files_cal, keylist = c("FILTER", "PROGRAM", "VISIT_ID"), cores = cores, context = paste0("cal_process VID ", VID))
    if(nrow(scan_cal) == 0){
      return(character(0))
    }
    corr_pid = grep(VID, scan_cal$VISIT_ID, fixed = T, value = T)
    corr_pid = corr_pid[substring(corr_pid, 1, nchar(VID)) == VID] ## Make sure 4 digit PID is embedded in 10 digit VID
    pid_idx = scan_cal$VISIT_ID %in% corr_pid
    
    files_cal = scan_cal$full[pid_idx]
    files_cal = files_cal[grepl(FILT, scan_cal$FILTER[pid_idx])]
    return(files_cal)
  }
  
  if(which_module == "super_sky"){
    # sky_frames_dir = paste0(sky_pro_dir, "/sky_frames/")
    # sky_super_dir = paste0(sky_pro_dir, "/sky_super/")
    files_sky = jp_store_get(input_args, "sky_frame_files", default = NULL)
    if(is.null(files_sky)){
      files_sky = list.files(sky_frames_dir,
                             full.names = TRUE,
                             pattern = glob2rx(paste0("*", VID, "*.fits")))
    }

    if(do_NIRISS){
      files_sky = files_sky[!grepl('_mirimage_',files_sky) & grepl('_nis_',files_sky) & grepl(".fits$", files_sky)]
    }else if (do_MIRI){
      files_sky = files_sky[grepl('_mirimage_',files_sky) & !grepl('_nis_',files_sky) & grepl(".fits$", files_sky)]
    }else{
      files_sky = files_sky[!grepl('_mirimage_',files_sky) & !grepl('_nis_', files_sky) & grepl(".fits$", files_sky)]
    }
    files_sky = keep_readable_fits(files_sky)
    if(length(files_sky) == 0){
      return(character(0))
    }
    
    scan_sky = safe_key_scan(files_sky, keylist = c("FILTER", "PROGRAM", "VISIT_ID"), cores = cores, context = paste0("super_sky VID ", VID))
    if(nrow(scan_sky) == 0){
      return(character(0))
    }
    corr_pid = grep(VID, scan_sky$VISIT_ID, fixed = T, value = T)
    corr_pid = corr_pid[substring(corr_pid, 1, nchar(VID)) == VID] ## Make sure 4 digit PID is embedded in 10 digit VID
    pid_idx = scan_sky$VISIT_ID %in% corr_pid
    
    files_sky = scan_sky$full[pid_idx]
    files_sky = files_sky[grepl(FILT, scan_sky$FILTER[pid_idx])]
    return(files_sky)
  }
  
  if(which_module == "apply_super"){
    
    corr_pid = grep(VID, sky_info$visit_id, fixed = T, value = T)
    corr_pid = corr_pid[substring(corr_pid, 1, nchar(VID)) == VID] ## Make sure 4 digit PID is embedded in 10 digit VID
    pid_idx = paste0(sky_info$visit_id) %in% corr_pid
    
    sky_info = sky_info[grepl(VID, sky_info$fileim) & pid_idx & grepl(FILT, sky_info$filter), ]
    
    if(do_NIRISS){
      sky_info = sky_info[grepl("NIS", sky_info$detector), ]
    }else if (do_MIRI){
      sky_info = sky_info[grepl("MIRIMAGE", sky_info$detector), ]
    }else{
      sky_info = sky_info[!grepl("MIRIMAGE", sky_info$detector) & !grepl("NIS", sky_info$detector), ]
    }
    return(list('sky_info' = sky_info, 'sky_filelist', sky_info$filesky))
  }
  
  if(which_module == "modify_pedestal"){
    files_cal_sky = jp_store_get(input_args, "cal_sky_files", default = NULL)
    if(is.null(files_cal_sky)){
      files_cal_sky = c(
        list.files(cal_sky_dir, full.names = TRUE, pattern = glob2rx(paste0("*", VID, "*.fits"))) #If running Pro1/F outputs
      )
    }
    
    if(do_NIRISS){
      files_cal_sky = files_cal_sky[!grepl('_mirimage_',files_cal_sky) & grepl('_nis_',files_cal_sky) & grepl(".fits$", files_cal_sky)]
    }else if (do_MIRI){
      files_cal_sky = files_cal_sky[grepl('_mirimage_',files_cal_sky) & !grepl('_nis_',files_cal_sky) & grepl(".fits$", files_cal_sky)]
    }else{
      files_cal_sky = files_cal_sky[!grepl('_mirimage_',files_cal_sky) & !grepl('_nis_', files_cal_sky) & grepl(".fits$", files_cal_sky)]
    }
    files_cal_sky = keep_readable_fits(files_cal_sky)
    if(length(files_cal_sky) == 0){
      return(character(0))
    }
    
    scan_cal_sky = safe_key_scan(files_cal_sky, keylist = c("FILTER", "PROGRAM", "VISIT_ID"), cores = cores, context = paste0("modify_pedestal VID ", VID))
    if(nrow(scan_cal_sky) == 0){
      return(character(0))
    }
    corr_pid = grep(VID, scan_cal_sky$VISIT_ID, fixed = T, value = T)
    corr_pid = corr_pid[substring(corr_pid, 1, nchar(VID)) == VID] ## Make sure 4 digit PID is embedded in 10 digit VID
    pid_idx = scan_cal_sky$VISIT_ID %in% corr_pid
    
    files_cal_sky = scan_cal_sky$full[pid_idx]
    files_cal_sky = files_cal_sky[grepl(FILT, scan_cal_sky$FILTER[pid_idx])]
    return(files_cal_sky)
  }
  
  if(which_module == "wisp_rem"){
    files_wisp = input_args$filelist
    files_wisp = files_wisp[grepl(VID, files_wisp) & grepl(".fits$", files_wisp)]
    files_wisp = keep_readable_fits(files_wisp)
    if(length(files_wisp) == 0){
      return(character(0))
    }
    
    scan_1oF = safe_key_scan(files_wisp, keylist = c("FILTER", "PROGRAM", "VISIT_ID"), cores = cores, context = paste0("wisp_rem VID ", VID))
    if(nrow(scan_1oF) == 0){
      return(character(0))
    }
    corr_pid = grep(VID, scan_1oF$VISIT_ID, fixed = T, value = T)
    corr_pid = corr_pid[substring(corr_pid, 1, nchar(VID)) == VID]
    pid_idx = scan_1oF$VISIT_ID %in% corr_pid
    
    files_wisp = scan_1oF$full[pid_idx]
    return(files_wisp)
  }
  
}

register_jumprope_backend = function(cores, parallel_type, outfile = "", fallback = c("multicore", "serial")){
  fallback = match.arg(fallback)
  
  if(is.null(parallel_type)){
    if(fallback == "serial" || cores <= 1L){
      registerDoSEQ()
      return(NULL)
    }
    registerDoParallel(cores = cores)
    return(NULL)
  }
  
  cl = tryCatch(
    makeCluster(spec = cores, type = parallel_type, outfile = outfile),
    error = function(e){
      message(
        "makeCluster(type=", parallel_type, ", cores=", cores, ") failed: ",
        conditionMessage(e),
        ". Falling back to ", fallback, "."
      )
      NULL
    }
  )
  
  if(is.null(cl)){
    if(fallback == "serial" || cores <= 1L){
      registerDoSEQ()
      return(NULL)
    }
    registerDoParallel(cores = cores)
    return(NULL)
  }
  
  registerDoParallel(cl)
  cl
}

stop_jumprope_backend = function(cl){
  if(is.null(cl)){
    stopImplicitCluster()
  }else{
    stopCluster(cl)
  }
  registerDoSEQ()
}

jp_cap_write_cores = function(cores, nfiles){
  if(nfiles >= 128L){
    return(min(cores, 8L))
  }
  if(nfiles >= 64L){
    return(min(cores, 16L))
  }
  cores
}

jp_cap_task_cores = function(cores, ntasks){
  ntasks = suppressWarnings(as.integer(ntasks))
  if(is.na(ntasks) || ntasks <= 1L){
    return(1L)
  }
  min(as.integer(cores), ntasks)
}

copy_with_retry = function(from, to, overwrite = TRUE, attempts = 3L, wait_seconds = 1){
  dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
  for(attempt in seq_len(attempts)){
    ok = tryCatch(file.copy(from, to, overwrite = overwrite), error = function(e) FALSE)
    if(isTRUE(ok)){
      return(invisible(TRUE))
    }
    if(attempt < attempts){
      gc()
      Sys.sleep(wait_seconds * attempt)
    }
  }
  stop("Failed to copy ", from, " -> ", to, " after ", attempts, " attempts")
}

copy_fits_with_validation = function(from, to, overwrite = TRUE, attempts = 3L, wait_seconds = 1, required_ext = "SCI"){
  dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
  tmp_to = paste0(to, ".tmpcopy.", Sys.getpid())
  last_error = NULL
  on.exit(unlink(tmp_to), add = TRUE)
  
  for(attempt in seq_len(attempts)){
    unlink(tmp_to)
    ok = tryCatch({
      copied = file.copy(from, tmp_to, overwrite = overwrite)
      if(!isTRUE(copied) || !file.exists(tmp_to) || file.info(tmp_to)$size <= 0){
        stop("file.copy returned FALSE or produced an empty file")
      }
      Rfits_nhdu(tmp_to)
      if(!is.null(required_ext)){
        extloc = if(is.numeric(required_ext)) required_ext else Rfits_extname_to_ext(tmp_to, required_ext)
        if(is.na(extloc)){
          stop("Missing required extension ", required_ext)
        }
      }
      if(file.exists(to)){
        file.remove(to)
      }
      if(!file.rename(tmp_to, to)){
        stop("file.rename failed for ", tmp_to, " -> ", to)
      }
      TRUE
    }, error = function(e){
      last_error <<- e
      FALSE
    })
    if(ok){
      return(invisible(TRUE))
    }
    unlink(tmp_to)
    if(attempt < attempts){
      gc()
      Sys.sleep(wait_seconds * attempt)
    }
  }
  
  stop("Failed to copy/validate FITS ", from, " -> ", to, " after ", attempts, " attempts: ", conditionMessage(last_error))
}

jp_cleanup_vid_intermediates = function(root_dir, vid, remove_final_products = FALSE, remove_cal_products = TRUE, remove_cal_sky_products = TRUE){
  if(is.null(root_dir) || !nzchar(root_dir) || !dir.exists(root_dir) || is.null(vid) || !nzchar(vid)){
    return(invisible(NULL))
  }

  dump_dir = file.path(root_dir, "dump")
  dump_vid_dir = file.path(dump_dir, vid)
  if(dir.exists(dump_vid_dir)){
    unlink(dump_vid_dir, recursive = TRUE)
    message("  Removed ", dump_vid_dir)
  }

  flat_dump_vid_dir = file.path(root_dir, paste0("dump", vid))
  if(dir.exists(flat_dump_vid_dir)){
    unlink(flat_dump_vid_dir, recursive = TRUE)
    message("  Removed ", flat_dump_vid_dir)
  }

  invar_dir = file.path(root_dir, "InVar_Stacks")
  del_invar = list.files(invar_dir, pattern = glob2rx(paste0("stack_", vid, "_*.fits")), full.names = TRUE)
  if(length(del_invar) > 0){
    file.remove(del_invar)
    message("  Removed ", length(del_invar), " InVar stack files from ", invar_dir)
  }

  median_dir = file.path(root_dir, "Median_Stacks")
  del_median = list.files(median_dir, pattern = glob2rx(paste0("med_", vid, "_*.fits")), full.names = TRUE)
  if(length(del_median) > 0){
    file.remove(del_median)
    message("  Removed ", length(del_median), " Median stack files from ", median_dir)
  }

  patch_dir = file.path(root_dir, "Patch_Stacks")
  del_patch = list.files(patch_dir, pattern = glob2rx(paste0("patch_", vid, "_*.fits")), full.names = TRUE)
  if(length(del_patch) > 0){
    file.remove(del_patch)
    message("  Removed ", length(del_patch), " Patch stack files from ", patch_dir)
  }

  pro1of_cal_dir = file.path(root_dir, "Pro1oF", "cal")
  if(isTRUE(remove_cal_products)){
    del_cal = list.files(pro1of_cal_dir, pattern = glob2rx(paste0("*", vid, "*.fits")), full.names = TRUE)
    if(length(del_cal) > 0){
      file.remove(del_cal)
      message("  Removed ", length(del_cal), " Pro1oF cal files from ", pro1of_cal_dir)
    }
  }

  pro1of_cal_sky_dir = file.path(root_dir, "Pro1oF", "cal_sky")
  if(isTRUE(remove_cal_sky_products)){
    del_cal_sky = list.files(pro1of_cal_sky_dir, pattern = glob2rx(paste0("*", vid, "*.fits")), full.names = TRUE)
    if(length(del_cal_sky) > 0){
      file.remove(del_cal_sky)
      message("  Removed ", length(del_cal_sky), " cal_sky files from ", pro1of_cal_sky_dir)
    }
  }

  pro1of_cal_sky_renorm_dir = file.path(root_dir, "Pro1oF", "cal_sky_renorm")
  if(isTRUE(remove_final_products)){
    del_cal_sky_renorm = list.files(pro1of_cal_sky_renorm_dir, pattern = glob2rx(paste0("*", vid, "*.fits")), full.names = TRUE)
    if(length(del_cal_sky_renorm) > 0){
      file.remove(del_cal_sky_renorm)
      message("  Removed ", length(del_cal_sky_renorm), " cal_sky_renorm files from ", pro1of_cal_sky_renorm_dir)
    }
  }

  sky_frames_dir = file.path(root_dir, "sky_pro", "sky_frames")
  del_sky_frames = list.files(sky_frames_dir, pattern = glob2rx(paste0("*", vid, "*.fits")), full.names = TRUE)
  if(length(del_sky_frames) > 0){
    file.remove(del_sky_frames)
    message("  Removed ", length(del_sky_frames), " sky frame files from ", sky_frames_dir)
  }

  sky_super_dir = file.path(root_dir, "sky_pro", "sky_super")
  del_sky_super = list.files(sky_super_dir, pattern = glob2rx(paste0("*", vid, "*.fits")), full.names = TRUE)
  if(length(del_sky_super) > 0){
    file.remove(del_sky_super)
    message("  Removed ", length(del_sky_super), " super sky files from ", sky_super_dir)
  }

  invisible(NULL)
}

is_valid_fits_file = function(filename, required_ext = NULL){
  if(!file.exists(filename) || file.info(filename)$size <= 0){
    return(FALSE)
  }
  tryCatch({
    Rfits_nhdu(filename)
    if(!is.null(required_ext)){
      extloc = if(is.numeric(required_ext)) required_ext else Rfits_extname_to_ext(filename, required_ext)
      if(is.na(extloc)){
        stop("Missing required extension ", required_ext)
      }
    }
    TRUE
  }, error = function(e) FALSE)
}

safe_key_scan = function(filelist, keylist, cores = 1L, context = ""){
  filelist = unique(filelist)
  filelist = filelist[!is.na(filelist) & nzchar(filelist)]
  if(length(filelist) == 0){
    out = setNames(vector("list", length(keylist) + 1L), c("full", keylist))
    out[] = lapply(out, function(x) character(0))
    return(as.data.frame(out, stringsAsFactors = FALSE))
  }

  scan = tryCatch(
    Rfits_key_scan(filelist = filelist, keylist = keylist, cores = cores),
    error = function(e) e
  )
  if(!inherits(scan, "error")){
    scan$full = filelist
    return(scan)
  }

  message(
    "Rfits_key_scan failed", ifelse(nzchar(context), paste0(" for ", context), ""),
    "; falling back to per-file header scan: ", conditionMessage(scan)
  )

  scan_rows = lapply(filelist, function(f){
    tryCatch({
      keyvalues = Rfits_read_header(f, ext = 1)$keyvalues
      row = c(full = f, setNames(lapply(keylist, function(k){
        value = keyvalues[[k]]
        if(length(value) == 0){
          NA_character_
        }else{
          as.character(value[[1]])
        }
      }), keylist))
      as.data.frame(row, stringsAsFactors = FALSE)
    }, error = function(e){
      message("Skipping unreadable FITS during key scan ", basename(f), ": ", conditionMessage(e))
      NULL
    })
  })
  scan_rows = Filter(Negate(is.null), scan_rows)

  if(length(scan_rows) == 0){
    out = setNames(vector("list", length(keylist) + 1L), c("full", keylist))
    out[] = lapply(out, function(x) character(0))
    return(as.data.frame(out, stringsAsFactors = FALSE))
  }

  scan = do.call(rbind, scan_rows)
  rownames(scan) = NULL
  scan
}

jp_process_wisp_file = function(ii, info_wisp, idx_wisp_skip, ref_im_list, additional_params, SIGMA_LO){
  if(!idx_wisp_skip[ii]){
    return(NULL)
  }

  vid = paste0(info_wisp$VISIT_ID[ii])
  modl = paste0("NRC", info_wisp$MODULE[ii])

  ref_im = ref_im_list[[ii]]
  if(is.null(ref_im)){
    message("No long wavelength - skipping...")
    return(NULL)
  }
  ref_path = attr(ref_im, "filename")
  if(is.null(ref_path) || !nzchar(ref_path)){
    ref_path = NA_character_
  }

  wisp_frame = Rfits_read_image(info_wisp$full[ii], ext = 2)

  check_Nhdu = Rfits_nhdu(info_wisp$full[ii])
  extloc = Rfits_extname_to_ext(info_wisp$full[ii], 'SCI_ORIG')

  if(is.na(extloc)){
    Rfits_write_image(wisp_frame, filename = info_wisp$full[ii], create_file = FALSE)
    Rfits_write_key(filename = info_wisp$full[ii], ext = check_Nhdu + 1, keyname = 'EXTNAME', keyvalue = 'SCI_ORIG', keycomment = 'No wisp corr')
  }

  if(any((vid == additional_params$ID_vlarge$VISIT_ID & modl == additional_params$ID_vlarge$MODULE) |
         (vid == additional_params$ID_large$VISIT_ID & modl == additional_params$ID_large$MODULE))){
    sigma_lo = NULL
  }else{
    sigma_lo = SIGMA_LO
  }
  poly = NULL

  wisp_fix = wispFixer(wisp_im = wisp_frame, ref_im = ref_im, poly = poly, sigma_lo = sigma_lo)
  delta_im = wisp_fix$wisp_fix$imDat - wisp_frame$imDat
  template_data = if(is.list(wisp_fix$wisp_template) && !is.null(wisp_fix$wisp_template$imDat)){
    wisp_fix$wisp_template$imDat
  }else{
    wisp_fix$wisp_template
  }
  template_image = if(is.list(wisp_fix$wisp_template) && !is.null(wisp_fix$wisp_template$imDat)){
    wisp_fix$wisp_template
  }else{
    Rfits_create_image(template_data, keyvalues = wisp_fix$wisp_fix$keyvalues)
  }
  template_vals = template_data[is.finite(template_data)]
  delta_vals = delta_im[is.finite(delta_im)]
  template_sd = if(length(template_vals) > 1) stats::sd(template_vals) else NA_real_
  delta_sd = if(length(delta_vals) > 1) stats::sd(delta_vals) else NA_real_
  delta_mean = if(length(delta_vals) > 0) mean(delta_vals) else NA_real_
  message(
    "Wisp diag: short=", basename(info_wisp$full[ii]),
    " ref=", basename(ref_path),
    " tmpl_sd=", format(signif(template_sd, 4), scientific = FALSE),
    " delta_mean=", format(signif(delta_mean, 4), scientific = FALSE),
    " delta_sd=", format(signif(delta_sd, 4), scientific = FALSE)
  )
  Rfits_write_pix(data = wisp_fix$wisp_fix$imDat, filename = info_wisp$full[ii], ext = 2)

  check_Nhdu = Rfits_nhdu(info_wisp$full[ii])
  extloc = Rfits_extname_to_ext(info_wisp$full[ii], 'REF_WISP_WARP')
  if(is.na(extloc)){
    Rfits_write_image(wisp_fix$ref_im_warp, filename = info_wisp$full[ii], create_file = FALSE)
    Rfits_write_key(filename = info_wisp$full[ii], ext = check_Nhdu + 1, keyname = 'EXTNAME', keyvalue = 'REF_WISP_WARP', keycomment = 'Reference long wavelength for wisp corr')
  }else{
    Rfits_write_pix(wisp_fix$ref_im_warp$imDat, filename = info_wisp$full[ii], ext = extloc)
  }

  check_Nhdu = Rfits_nhdu(info_wisp$full[ii])
  extloc = Rfits_extname_to_ext(info_wisp$full[ii], 'WISP_TEMPLATE')
  if(is.na(extloc)){
    Rfits_write_image(template_image, filename = info_wisp$full[ii], create_file = FALSE)
    Rfits_write_key(filename = info_wisp$full[ii], ext = check_Nhdu + 1, keyname = 'EXTNAME', keyvalue = 'WISP_TEMPLATE', keycomment = 'Wisp template')
  }else{
    Rfits_write_pix(template_data, filename = info_wisp$full[ii], ext = extloc)
  }

  NULL
}

fits_write_pix_with_retry = function(data, filename, ext, attempts = 3L, wait_seconds = 1){
  last_error = NULL
  for(attempt in seq_len(attempts)){
    ok = tryCatch({
      Rfits_write_pix(data = data, filename = filename, ext = ext)
      TRUE
    }, error = function(e){
      last_error <<- e
      FALSE
    })
    if(ok){
      return(invisible(TRUE))
    }
    if(attempt < attempts){
      gc()
      Sys.sleep(wait_seconds * attempt)
    }
  }
  stop("Rfits_write_pix failed for ", filename, " ext=", ext, ": ", conditionMessage(last_error))
}

rfits_write_with_retry = function(data, filename, attempts = 3L, wait_seconds = 1){
  dir.create(dirname(filename), recursive = TRUE, showWarnings = FALSE)
  tmpfile = paste0(filename, ".tmpwrite")
  last_error = NULL
  for(attempt in seq_len(attempts)){
    if(file.exists(tmpfile)){
      unlink(tmpfile)
    }
    ok = tryCatch({
      Rfits_write(data = data, filename = tmpfile)
      if(file.exists(filename)){
        unlink(filename)
      }
      if(!file.rename(tmpfile, filename)){
        stop("Failed to rename ", tmpfile, " -> ", filename)
      }
      TRUE
    }, error = function(e){
      last_error <<- e
      FALSE
    })
    if(ok){
      return(invisible(TRUE))
    }
    if(file.exists(tmpfile)){
      unlink(tmpfile)
    }
    if(file.exists(filename) && isTRUE(file.info(filename)$size == 0)){
      unlink(filename)
    }
    if(attempt < attempts){
      gc()
      Sys.sleep(wait_seconds * attempt)
    }
  }
  stop("Rfits_write failed for ", filename, ": ", conditionMessage(last_error))
}

## Processing codes
do_1of = function(input_args){
  
  cat("\n")
  message("## Removing 1/f ##")
  cat("\n")

  additional_params = input_args$additional_params
  Pro1oF_dir = input_args$Pro1oF_dir
  VID = input_args$VID
  FILT = input_args$FILT
  cores = input_args$cores_pro
  parallel_type = input_args$additional_params$parallel_type
  
  do_MIRI = input_args$do_MIRI ## Because we need to alter the dimensions of the image for processing
  trend_block_vlarge = 101 #good for larger sources
  trend_block_large = 501 # good for frames with fairly large sources
  
  skip_completed_files = additional_params$skip_completed_files
  force_refresh_pro1of = isTRUE(input_args$force_refresh_pro1of)
  if(force_refresh_pro1of){
    skip_completed_files = FALSE
  }
  ID_vlarge = additional_params$ID_vlarge
  ID_large = additional_params$ID_large
  
  ow_vlarge = additional_params$ow_vlarge
  ow_large = additional_params$ow_large
  
  filelist = load_files(input_args, which_module = "1oF")
  if(length(filelist) == 0){
    message("No 1/f inputs found for VID ", VID, ifelse(FILT == "", "", paste0(" FILT ", FILT)))
    return(invisible(NULL))
  }

  keep_idx = vapply(
    filelist,
    function(f) is_valid_fits_file(f, required_ext = "SCI") && is_valid_fits_file(f, required_ext = "DQ"),
    logical(1)
  )
  if(any(!keep_idx)){
    bad_files = basename(filelist[!keep_idx])
    message(
      "Skipping ", sum(!keep_idx), " unreadable 1/f input file(s) for VID ", VID,
      ifelse(FILT == "", "", paste0(" FILT ", FILT)),
      ": ", paste(bad_files, collapse = ", ")
    )
    filelist = filelist[keep_idx]
  }
  if(length(filelist) == 0){
    message("No usable 1/f inputs remain for VID ", VID, ifelse(FILT == "", "", paste0(" FILT ", FILT)))
    return(invisible(NULL))
  }
  
  message("Showing first <10 files:")
  cat(head(filelist, 10), sep='\n')
  cat("...")
  cat('Processing',length(filelist),'files\n')
  message(
    "Skip completed files is ",
    ifelse(skip_completed_files, "ON", "OFF"),
    ifelse(force_refresh_pro1of, " (forced Pro1oF refresh)", "")
  )
  
  lo_loop = 1
  hi_loop = length(filelist)
  worker_cores = jp_cap_task_cores(cores = cores, ntasks = hi_loop)
  
  cl <- register_jumprope_backend(cores = worker_cores, parallel_type = parallel_type, fallback = "serial")

  dummy = foreach(i = lo_loop:hi_loop, .inorder = FALSE, .packages = c("Rfits", "Rwcs", "ProFound"), .export = c("jwst_dq_do_not_use_mask", "jwst_read_cal_core"))%dopar%{
    if(i %% 100 == 0){
      message('File ',i,' of ', hi_loop)
    }
    file_image = filelist[i]
    basename = strsplit(basename(file_image),'.fits$')[[1]]
    fullbase = paste(Pro1oF_dir,basename,sep='/')
    
    if( !(skip_completed_files & file.exists(paste0(fullbase,'_Pro1oF.fits'))) ){
      tryCatch({
        temp_image = jwst_read_cal_core(filelist[i])
    
        if(do_MIRI){
          keep_trend = FALSE
          if(ow_large & ow_vlarge){
            message("Can't use both LARGE and VLARGE keep_trend \n Defaulting to keep_trend FALSE")
            keep_trend = FALSE
          }else{
    
            if(ow_vlarge){
              keep_trend = TRUE
              trend_block = trend_block_vlarge
              message("KT: TRUE", " TB ", trend_block_vlarge)
            }
    
            if(ow_large){
              keep_trend = TRUE
              trend_block = trend_block_large
              message("KT: TRUE", " TB ", trend_block_large)
            }
          }
    
          temp_mask = temp_image$DQ$imDat
          JWST_cal_mask = profoundDilate(jwst_dq_do_not_use_mask(temp_mask), size=3)
    
          temp_zap = profoundSkyScan(image = temp_image$SCI$imDat,
                                     mask = (temp_image$SCI$imDat==0) | JWST_cal_mask,
                                     clip = c(0.0,0.9),
                                     scan_block = c(nrow(temp_image$SCI$imDat), ncol(temp_image$SCI$imDat)),
                                     trend_block = trend_block,
                                     keep_trend = keep_trend)
    
          file.copy(filelist[i], paste0(fullbase,'_MIRI.fits'), overwrite=TRUE)
          Rfits_write_pix(temp_zap$image_fix, paste0(fullbase,'_MIRI.fits'), ext=2)
    
          check_Nhdu = Rfits_nhdu(paste0(fullbase,'_MIRI.fits'))
          extloc = Rfits_extname_to_ext(paste0(fullbase,'_MIRI.fits'), 'SKY_Pro1oF')
    
          if(is.na(extloc)){
            Rfits_write_image(temp_zap$row_map + temp_zap$col_map, filename=paste0(fullbase,'_MIRI.fits'), create_file=FALSE)
            Rfits_write_key(filename=paste0(fullbase,'_MIRI.fits'), ext=check_Nhdu+1, keyname='EXTNAME', keyvalue='SKY_Pro1oF', keycomment='extension name')
          }else{
            Rfits_write_pix(temp_zap$row_map + temp_zap$col_map, paste0(fullbase,'_MIRI.fits'), ext=extloc)
          }
        }else{
          if(!(any(c(ow_vlarge, ow_large)))){
            if(any(temp_image[[1]]$keyvalues$VISIT_ID == ID_vlarge$VISIT_ID & temp_image[[1]]$keyvalues$MODULE == ID_vlarge$MODULE)){
              trend_block = trend_block_vlarge
              keep_trend = TRUE
              message(temp_image[[1]]$keyvalues$VISIT_ID,' ',temp_image[[1]]$keyvalues$MODULE, ' KT: TRUE', ' TB: ',trend_block)
            }else if(any(temp_image[[1]]$keyvalues$VISIT_ID == ID_large$VISIT_ID & temp_image[[1]]$keyvalues$MODULE == ID_large$MODULE)){
              trend_block = trend_block_large
              keep_trend = TRUE
              message(temp_image[[1]]$keyvalues$VISIT_ID,' ',temp_image[[1]]$keyvalues$MODULE, ' KT: TRUE', ' TB: ',trend_block)
            }else if(any(temp_image[[1]]$keyvalues$VISIT_ID == ID_large$VISIT_ID & temp_image[[1]]$keyvalues$INSTRUME == ID_large$MODULE)){
              trend_block = trend_block_large
              keep_trend = TRUE
              message(temp_image[[1]]$keyvalues$VISIT_ID,' ',temp_image[[1]]$keyvalues$INSTRUME, ' KT: TRUE', ' TB: ',trend_block)
            }else{
              keep_trend = FALSE
              message(temp_image[[1]]$keyvalues$VISIT_ID,' ',temp_image[[1]]$keyvalues$MODULE, ' KT: FALSE')
            }
          }else{
            if(ow_large & ow_vlarge){
              message("Can't use both LARGE and VLARGE keep_trend \n Defaulting to keep_trend FALSE")
              keep_trend = FALSE
            }else{
              if(ow_vlarge){
                keep_trend = TRUE
                trend_block = trend_block_vlarge
                message("KT: TRUE", " TB ", trend_block_vlarge)
              }
              if(ow_large){
                keep_trend = TRUE
                trend_block = trend_block_large
                message("KT: TRUE", " TB ", trend_block_large)
              }
            }
          }
    
          temp_mask = temp_image$DQ$imDat
          JWST_cal_mask = profoundDilate(jwst_dq_do_not_use_mask(temp_mask), size=3)
    
          if(nrow(temp_image$SCI$imDat) != 2048 | ncol(temp_image$SCI$imDat) != 2048){
            scan_block = c(
              nrow(temp_image$SCI$imDat),
              ncol(temp_image$SCI$imDat)
            )
          }else{
            scan_block = c(512, 2048)
          }
    
          temp_zap = profoundSkyScan(image = temp_image$SCI$imDat,
                                     mask = (temp_image$SCI$imDat==0) | JWST_cal_mask | is.na(temp_image$SCI$imDat),
                                     clip = c(0.0,0.9),
                                     scan_block = scan_block,
                                     trend_block = trend_block,
                                     keep_trend = keep_trend)
    
          file.copy(filelist[i], paste0(fullbase,'_Pro1oF.fits'), overwrite=TRUE)
          Rfits_write_pix(temp_zap$image_fix, paste0(fullbase,'_Pro1oF.fits'), ext=2)
    
          check_Nhdu = Rfits_nhdu(paste0(fullbase,'_Pro1oF.fits'))
          extloc = Rfits_extname_to_ext(paste0(fullbase,'_Pro1oF.fits'), 'SKY_Pro1oF')
    
          if(is.na(extloc)){
            Rfits_write_image(temp_zap$row_map + temp_zap$col_map, filename=paste0(fullbase,'_Pro1oF.fits'), create_file=FALSE)
            Rfits_write_key(filename=paste0(fullbase,'_Pro1oF.fits'), ext=check_Nhdu+1, keyname='EXTNAME', keyvalue='SKY_Pro1oF', keycomment='extension name')
          }else{
            Rfits_write_pix(temp_zap$row_map + temp_zap$col_map, paste0(fullbase,'_Pro1oF.fits'), ext=extloc)
          }
        }
        NULL
      }, error = function(e){
        message("Skipping unreadable 1/f input ", basename(file_image), ": ", conditionMessage(e))
        NULL
      })
    }
  }
  
  stop_jumprope_backend(cl)
  if(jp_store_enabled(input_args)){
    output_suffix = if(do_MIRI) "_MIRI.fits" else "_Pro1oF.fits"
    output_files = file.path(
      Pro1oF_dir,
      paste0(sub(".fits$", "", basename(filelist)), output_suffix)
    )
    output_files = unique(output_files)
    output_files = output_files[vapply(output_files, is_valid_fits_file, logical(1), required_ext = "SCI")]
    jp_store_set(input_args, "pro1of_files", output_files)
  }
  gc()
}
do_cal_process = function(input_args, filelist = NULL){
  
  cat("\n")
  message("## Calculating sky statistics ##")
  cat("\n")

  Pro1oF_dir = input_args$Pro1oF_dir
  sky_frames_dir = input_args$sky_frames_dir
  VID = input_args$VID
  FILT = input_args$FILT
  cores = input_args$cores_pro
  do_NIRISS = input_args$do_NIRISS
  do_MIRI = input_args$do_MIRI
  parallel_type = input_args$additional_params$parallel_type
  skip_completed_files = additional_params$skip_completed_files
  
  if(is.null(filelist)){
    filelist = (load_files(input_args, which_module = "cal_process"))
  }
  if(length(filelist) == 0){
    message("No sky-stat inputs found for VID ", VID, ifelse(FILT == "", "", paste0(" FILT ", FILT)))
    return(invisible(NULL))
  }
  
  message("Showing first <10 files:")
  cat(head(filelist, 10), sep='\n')
  cat("...")
  cat('Processing',length(filelist),'files...\n')
  message("Skip completed files is ", ifelse(skip_completed_files, "ON", "OFF"))
  
  #get main info:
  obs_info = Rfits_key_scan(
    filelist = filelist,
    keylist = c('VISIT_ID','OBS_ID','EXPOSURE','DETECTOR','FILTER','DATE-OBS','EFFEXPTM','CAL_VER','CRDS_CTX'),
    extlist = 1,
    fileinfo = 'all'
  )
  obs_info = data.frame(obs_info)
  if(jp_store_enabled(input_args)){
    sky_output_files = file.path(
      sky_frames_dir,
      paste0(
        sub(".fits$", "", basename(obs_info$full)),
        "_sky_",
        obs_info$FILTER,
        ".fits"
      )
    )
    jp_store_set(input_args, "sky_frame_files", unique(sky_output_files))
  }
  
  lo_loop = 1
  hi_loop = dim(obs_info)[1]
  worker_cores = jp_cap_task_cores(cores = cores, ntasks = hi_loop)
  
  cl <- register_jumprope_backend(cores = worker_cores, parallel_type = parallel_type)
  
  dummy = foreach(i = lo_loop:hi_loop, .inorder=FALSE, .packages = c("Rfits", "Rwcs", "ProFound"), .export = c("jumprope_version", "jwst_dq_do_not_use_mask"))%dopar%{
    if(i %% 100 == 0){
      message('File ',i,' of ', hi_loop)
    }
    tryCatch({
      #setup files
      file_image = as.character(obs_info[i,"full"])
      basename = strsplit(basename(file_image),'.fits',fixed=T)[[1]]
      fullbase = paste(sky_frames_dir,basename,sep='/')
      file_sky = paste0(fullbase,'_sky_',obs_info[i,"FILTER"],'.fits')
      
      if( !(skip_completed_files & file.exists(file_sky)) ){
        #get cal data
        JWST_cal_image = Rfits_read_image(file_image, ext=2)
        temp_mask = Rfits_read_image(file_image, ext=4, header = FALSE)
        JWST_cal_mask = profoundDilate(jwst_dq_do_not_use_mask(temp_mask), size=3)
      
        #basic info
        suppressMessages({ #do not really want to see lots of SIP warnings!
          RA_im = centre(JWST_cal_image)[1]
          Dec_im = centre(JWST_cal_image)[2]
        })
        NAXIS1 = JWST_cal_image$keyvalues$NAXIS1
        NAXIS2 = JWST_cal_image$keyvalues$NAXIS2
        Npix = NAXIS1*NAXIS2
      
        if(do_MIRI){
          box = 64
          redoskysize = 21
          sky_poly_deg = 2
        }else{
          box = 512
          redoskysize = 101
          sky_poly_deg = 2
        }
      
        ## TryCatch for ProFound in case there are not enough sky pixels to be sampled.
        ## Usually caused by zealous object dilation => lower redoskysize
        pro_func = function(x){
          tryCatch(
            {
              pro = profoundProFound(x$image, mask = x$mask, 
                                     skycut=2, 
                                     pixcut=5, 
                                     box=x$box, 
                                     redoskysize = x$redoskysize, 
                                     roughpedestal = TRUE, 
                                     tolerance=Inf 
              )
              return(list(pro = pro, redoskysize=101))
            },
            error = function(cond){
              redoskysize = 21
              message("Adjusting redoskysize=", redoskysize, " from 101: ", basename)
              pro = profoundProFound(x$image, mask = x$mask, 
                                     skycut=2, 
                                     pixcut=5, 
                                     box=x$box, 
                                     redoskysize = redoskysize, 
                                     roughpedestal = TRUE, 
                                     tolerance=Inf)
              return(list(pro=pro, redoskysize=redoskysize))
            },
            warning = function(cond){
              NULL
            },
            finally = {
              NULL
            }
          )
        }
      
        pro_out = pro_func(list(image = JWST_cal_image$imDat, mask = JWST_cal_mask, box = box, redoskysize = redoskysize))
        pro = pro_out$pro
        redoskysize = pro_out$redoskysize
      
        sky_redo_func = function(x){
          tryCatch(
            {
              sky_redo = profoundSkyPoly(x$image, objects=x$pro$objects_redo, degree=x$sky_poly_deg, quancut=0.99, mask=x$mask)
              return(sky_redo)
            },
            error = function(cond){
              message("Adjusting object mask for polynomial skies")
              sky_redo = profoundSkyPoly(x$image, objects=x$pro$objects, degree=x$sky_poly_deg, quancut=0.99, mask=x$mask)
              return(sky_redo)
            },
            warning = function(cond){
              message("Adjusting object mask for polynomial skies")
              sky_redo = profoundSkyPoly(x$image, objects=x$pro$objects, degree=x$sky_poly_deg, quancut=0.99, mask=x$mask)
              return(sky_redo)
            },
            finally = {
              NULL
            }
          )
        }
      
        if(do_MIRI){
          ## Do not do polynomial sky for MIRI - too hard
          sky_redo = list(sky = pro$sky)
          pro_redo = pro
        }else{
          sky_redo = sky_redo_func(list(image = JWST_cal_image$imDat, pro = pro, mask = JWST_cal_mask, sky_poly_deg = sky_poly_deg))
          pro_redo = profoundProFound(JWST_cal_image$imDat, mask=JWST_cal_mask, skycut=2, pixcut=5, box=box, grid = box, redoskysize=redoskysize, sky=sky_redo$sky, redosky=FALSE, tolerance=Inf)
        }
      
        if(is.null(sky_redo$sky)){
        ## if the polynomial sky is NULL, replace with the original profound sky
        ## If NULL it probably means that the polynomial sky had some problem as per the try-catch
        sky_redo$sky = pro$sky
      }
        if(is.null(pro_redo$skyRMS)){
        ## if the polynomial skyRMS is NULL, replace with the original profound skyRMS
        pro_redo$skyRMS = pro$skyRMS 
      }
        if(is.null(pro_redo$objects_redo)){
        pro_redo$objects_redo = pro$objects_redo 
      }
      
        if(is.null(pro_redo$skyChiSq)){
        pro_redo$skyChiSq = 1e6
      }
        if(is.na(pro_redo$skyChiSq)){
        pro_redo$skyChiSq = 1e6
      }
        if(is.infinite(pro_redo$skyChiSq)){
        pro_redo$skyChiSq = 1e6
      }
      
        if(pro_redo$skyChiSq >= 1e6){
          if(sum(pro_redo$objects_redo == 1) / prod(dim(pro_redo$objects_redo)) > 0.9){
            pro_redo$objects_redo = pro$objects 
          }else{
            pro_redo$objects_redo = pro$objects_redo
          }
        }
      
      # if(sum(pro_redo$objects_redo == 1)/prod(dim(pro_redo$objects_redo)) > 0.9){ ## Need to at least have 10% sky pixels?
      #   pro_redo$objects_redo = pro_redo$objects ## polynomial skies way below RMS of the true sky, whole frame is objects. Open clusters for example...
      # }
      
        sky_med = median(sky_redo$sky[JWST_cal_mask == 0 & pro_redo$objects_redo == 0], na.rm=TRUE)
        skyRMS_med = median(pro_redo$skyRMS[JWST_cal_mask == 0 & pro_redo$objects_redo == 0], na.rm=TRUE)
      
      ## Sky statistics being NULL/NA/Inf likely problem with the array slicing above, e.g., if the whole frame has objects 
        if(is.null(sky_med)){
        sky_med = 0.0 
      }
        if(is.na(sky_med)){
        sky_med = 0.0 
      }
        if(is.infinite(sky_med)){
        sky_med = 0.0 
      }
      
        if(is.null(skyRMS_med)){
        skyRMS_med = 1.0 
      }
        if(is.na(skyRMS_med)){
        skyRMS_med = 1.0 
      }
        if(is.infinite(skyRMS_med)){
        skyRMS_med = 1.0 
      }
      
        maskpix = sum(JWST_cal_mask!=0, na.rm=TRUE)/Npix
        objpix = sum(pro_redo$objects_redo!=0, na.rm=TRUE)/Npix
        goodpix = sum(JWST_cal_mask==0 & pro_redo$objects_redo==0, na.rm=TRUE)/Npix
      
        if(file.exists(file_sky)){
          message('Removing old sky file: ',file_sky)
          file.remove(file_sky)
        }
      
        Rfits_write_header(keyvalues = list(
          FILEIM = basename(file_image),
          PATHIM = dirname(file_image),
          FILESKY = basename(file_sky),
          PATHSKY = dirname(file_sky),
          VERSION = jumprope_version,
          VISIT_ID = obs_info$VISIT_ID[i],
          OBS_ID = obs_info$OBS_ID[i],
          EXPOSURE = obs_info$EXPOSURE[i],
          DETECTOR = obs_info$DETECTOR[i],
          FILTER = obs_info$FILTER[i],
          DATE = obs_info$`DATE-OBS`[i],
          EXPTIME =  obs_info$EFFEXPTM[i],
          CAL_VER =  obs_info$CAL_VER[i],
          CRDS_CTX =  obs_info$CRDS_CTX[i],
          RA = RA_im,
          DEC = Dec_im,
          NAXIS1 = NAXIS1,
          NAXIS2 = NAXIS2,
          NPIX = Npix,
          SKY = sky_med,
          SKYRMS = skyRMS_med,
          SKYCHI = pro_redo$skyChiSq,
          MASK = maskpix,
          OBJ = objpix,
          GOODPIX = goodpix
        ), filename=file_sky, create_file=TRUE, overwrite_file=TRUE)
        Rfits_write_key(filename=file_sky, ext=1, keyname='EXTNAME', keyvalue='INFO', keycomment='extension name')
      
        Rfits_write_image(sky_redo$sky, filename=file_sky, create_file=FALSE)
        Rfits_write_key(filename=file_sky, ext=2, keyname='EXTNAME', keyvalue='SKY', keycomment='extension name')
      
        Rfits_write_image(pro_redo$skyRMS, filename=file_sky, create_file=FALSE)
        Rfits_write_key(filename=file_sky, ext=3, keyname='EXTNAME', keyvalue='SKYRMS', keycomment='extension name')
      
        Rfits_write_image(JWST_cal_mask, filename=file_sky, create_file=FALSE)
        Rfits_write_key(filename=file_sky, ext=4, keyname='EXTNAME', keyvalue='PIXELMASK', keycomment='extension name')
      
        Rfits_write_image(pro_redo$objects_redo, filename=file_sky, create_file=FALSE)
        Rfits_write_key(filename=file_sky, ext=5, keyname='EXTNAME', keyvalue='OBJECTMASK', keycomment='extension name')
        return(NULL)
      }else{
        return(NULL)
      }
    }, error = function(e){
      message("Skipping unreadable/calculation-failed Pro1oF input ", basename(as.character(obs_info[i, 'full'])), ": ", conditionMessage(e))
      return(NULL)
    })
  }
  
  stop_jumprope_backend(cl)
  gc()
}
do_regen_sky_info = function(input_args){
  
  cat("\n")
  message("## Generating sky statistics info ##")
  cat("\n")
  
  Pro1oF_dir = input_args$Pro1oF_dir
  sky_pro_dir = input_args$sky_pro_dir
  sky_frames_dir = input_args$sky_frames_dir
  
  cores = input_args$cores_pro
  parallel_type = input_args$additional_params$parallel_type
  
  # sky_frames_dir = paste0(sky_pro_dir, "/sky_frames/")
  filelist = jp_store_get(input_args, "sky_frame_files", default = NULL)
  if(is.null(filelist)){
    filelist = list.files(sky_frames_dir, full.names = TRUE, pattern = glob2rx(paste0("*", input_args$VID, "*.fits")))
  }else{
    filelist = filelist[grepl(input_args$VID, filelist)]
  }
  filelist = grep('.fits$', filelist, value=TRUE)
  if(length(filelist) == 0){
    message("No sky frame files found for sky-info regeneration for VID ", input_args$VID)
    return(invisible(NULL))
  }

  cat('Processing',length(filelist),'files\n')
  cl <- register_jumprope_backend(
    cores = jp_cap_task_cores(cores = cores, ntasks = length(filelist)),
    parallel_type = parallel_type
  )
  
  sky_info = foreach(i = 1:length(filelist), .combine="rbind", .packages = c("Rfits"))%dopar%{
    temp_info = Rfits_read_header(filelist[i])$keyvalues
    temp_info[1:4] = NULL
    temp_info$EXTNAME = NULL
    temp_info$FILESKY = basename(filelist[i])
    temp_info$PATHSKY = dirname(filelist[i])
    temp_info$PATHIM = Pro1oF_dir
    return(temp_info)
  }
  if(length(filelist)==1){
    class(sky_info) = "list"
    sky_info = data.frame((sky_info))
  }
  colnames(sky_info) = tolower(colnames(sky_info))
  jp_store_set(input_args, "sky_info", sky_info)
  write.csv(sky_info, paste0(sky_pro_dir, '/sky_info.csv'), row.names=FALSE)
  stop_jumprope_backend(cl)
}
do_super_sky = function(input_args){
  
  cat("\n")
  message("## Making super skies ##")
  cat("\n")

  sky_pro_dir = input_args$sky_pro_dir
  sky_frames_dir = input_args$sky_frames_dir
  sky_super_dir = input_args$sky_super_dir
  VID = input_args$VID
  cores = input_args$cores_pro
  do_NIRISS = input_args$do_NIRISS
  parallel_type = input_args$additional_params$parallel_type

  sky_ChiSq_cut = 1.1
  good_pix_cut = 0.15
  
  filelist = load_files(input_args, which_module = "super_sky")
  if(length(filelist) == 0){
    message("No sky frames found for super-sky generation for VID ", VID, ifelse(input_args$FILT == "", "", paste0(" FILT ", input_args$FILT)))
    return(invisible(NULL))
  }
  sky_info = jp_store_get(input_args, "sky_info", default = NULL)
  if(is.null(sky_info)){
    sky_info = fread(paste0(sky_pro_dir, '/sky_info.csv'))
  }
  
  ## Match the sky_info table to the discovered sky-frame files by basename.
  ## This is more robust than path normalization when the table and filelist
  ## come from slightly different path spellings.
  selected_files = basename(filelist)
  sky_info = sky_info[sky_info$filesky %in% selected_files, ]
  if(nrow(sky_info) == 0){
    message("No sky_info rows remained after path matching for VID ", VID, ifelse(input_args$FILT == "", "", paste0(" FILT ", input_args$FILT)))
    return(invisible(NULL))
  }

  niriss_det = c("NIS")
  miri_det = c("MIRIMAGE")
  short_det = c("NRCA1", "NRCA2", "NRCA3", "NRCA4", "NRCB1", "NRCB2", "NRCB3", "NRCB4")
  long_det = c("NRCALONG", "NRCBLONG")
  
  short_filt = sort(unique(sky_info$filter[sky_info$detector %in% short_det]))
  long_filt = sort(unique(sky_info$filter[sky_info$detector %in% long_det]))
  nis_filt = sort(unique(sky_info$filter[sky_info$detector %in% niriss_det]))
  miri_filt = sort(unique(sky_info$filter[sky_info$detector %in% miri_det]))
  
  combine_grid_short = expand.grid(short_det, short_filt, stringsAsFactors=FALSE)
  combine_grid_long = expand.grid(long_det, long_filt, stringsAsFactors=FALSE)
  combine_grid_nis = expand.grid(niriss_det, nis_filt, stringsAsFactors=FALSE)
  combine_grid_miri = expand.grid(miri_det, miri_filt, stringsAsFactors=FALSE)
  combine_grid = rbind(combine_grid_short, combine_grid_long, combine_grid_nis, combine_grid_miri)
  
  sky_filelist = list.files(as.character(sky_info$pathsky[[1]]), pattern = ".fits$")
  
  sky_info = data.frame(sky_info)
  
  worker_cores = jp_cap_task_cores(cores = cores, ntasks = dim(combine_grid)[1])
  cl <- register_jumprope_backend(cores = worker_cores, parallel_type = parallel_type)
  
  dummy = foreach(i = 1:dim(combine_grid)[1], .inorder=FALSE, .packages = c("Rfits", "Rwcs", "ProFound", "ProPane"))%dopar%{
    if(combine_grid[i,1] %in% c('NRCA1','NRCA2','NRCA3','NRCA4','NRCB1','NRCB2','NRCB3','NRCB4')){
      temp_info = sky_info[sky_info$detector == combine_grid[i,1] & sky_info$filter == combine_grid[i,2] & sky_info$skychi < sky_ChiSq_cut & sky_info$goodpix >= good_pix_cut, ]
    }else if (combine_grid[i,1] %in% c('MIRIMAGE')){
      temp_info = sky_info[sky_info$detector == combine_grid[i,1] & sky_info$filter == combine_grid[i,2] & sky_info$skychi < sky_ChiSq_cut*1.5, ] ## Allow a little bit more legroom for MIRI?
    }else{
      temp_info = sky_info[sky_info$detector == combine_grid[i,1] & sky_info$filter == combine_grid[i,2] & sky_info$skychi < sky_ChiSq_cut, ]
    }
    
    Nsky = dim(temp_info)[1]
    
    message(combine_grid[i,1], ' ', combine_grid[i,2],': ', Nsky)
    
    if(Nsky > 0){
      sky_frames_list = lapply(1:dim(temp_info)[1], function(j){
        file_sky = temp_info[j,'filesky']
        file_sky = grep(temp_info[j,'filesky'], sky_filelist, value=TRUE)
        if(length(file_sky) > 0){
          sky_temp = Rfits_point(paste(temp_info[j,'pathsky'], file_sky, sep='/'), ext=2)  - temp_info[j,'sky']
          return(sky_temp)
        }
      })
      sky_mean = ProPane::propaneStackFlatFunc(sky_frames_list, imager_func = function(xx){imager::average(xx, na.rm = TRUE)}, cores =1)$image 
    }else{
      message("No usable data for ", combine_grid[i,1]," ",combine_grid[i,2])
      temp_file = sky_info[sky_info$detector == combine_grid[i,1] & sky_info$filter == combine_grid[i,2],'fileim'][1]
      NAXIS1 = sky_info[sky_info$detector == combine_grid[i,1] & sky_info$filter == combine_grid[i,2],'naxis1'][1]
      NAXIS2 = sky_info[sky_info$detector == combine_grid[i,1] & sky_info$filter == combine_grid[i,2],'naxis2'][1]
      if(is.na(NAXIS1) | is.na(NAXIS2)){
        sky_mean = NULL
      }else{
        sky_mean = matrix(0, NAXIS1, NAXIS2)
      }
    }
    
    if(!is.null(sky_mean)){
      
      file_super_sky = paste0(sky_super_dir,'/super_',combine_grid[i,1],'_',combine_grid[i,2],'.fits')
      dir.create(dirname(file_super_sky), recursive = TRUE, showWarnings = FALSE)
      Rfits_write_image(sky_mean, filename=file_super_sky)
      
      header_super_sky = list(Nsky = Nsky)
      
      if(Nsky > 0){
        header_super_sky = c(header_super_sky, as.list(temp_info$filesky))
        names(header_super_sky) = c('NSKY', paste0('FILE',1:Nsky))
      }
      
      Rfits_write_header(file_super_sky, keyvalues=header_super_sky)
      return(list(file_super_sky = file_super_sky, image = sky_mean, header = header_super_sky))
    }
    NULL
  }
  
  stop_jumprope_backend(cl)
  if(jp_store_enabled(input_args) && length(dummy) > 0){
    for(temp_super in dummy){
      if(is.null(temp_super)){
        next
      }
      jp_store_list_set(input_args, "super_sky_images", temp_super$file_super_sky, temp_super$image)
      jp_store_list_set(input_args, "super_sky_headers", temp_super$file_super_sky, temp_super$header)
    }
  }
  gc()
}
do_apply_super_sky = function(input_args){
  
  cat("\n")
  message("## Applying super skies ##")
  cat("\n")

  Pro1oF_dir = input_args$Pro1oF_dir
  cal_sky_dir = input_args$cal_sky_dir
  sky_pro_dir = input_args$sky_pro_dir
  sky_super_dir = input_args$sky_super_dir
  VID = input_args$VID
  FILT = input_args$FILT
  cores = input_args$cores_pro
  do_NIRISS = input_args$do_NIRISS
  do_MIRI = input_args$do_MIRI
  parallel_type = input_args$additional_params$parallel_type
  skip_completed_files = additional_params$skip_completed_files
  
  sky_info = jp_store_get(input_args, "sky_info", default = NULL)
  if(is.null(sky_info)){
    sky_info_path = paste0(sky_pro_dir, "/sky_info.csv")
    if(!file.exists(sky_info_path)){
      message(
        "No sky_info.csv found for super-sky application for VID ",
        VID,
        ifelse(FILT == "", "", paste0(" FILT ", FILT)),
        " -- skipping apply_super_sky."
      )
      return(invisible(NULL))
    }
    sky_info = fread(sky_info_path)
  }
  # sky_super_dir = paste0(sky_pro_dir, "/sky_super/")
  
  setcal_sky_remfile = function(file_image, cal_sky_dir){
    path = paste0(strsplit(dirname(file_image), '/cal',fixed=T),'/cal_sky/')
    if(path != cal_sky_dir){
      path = cal_sky_dir ## For scripting mode, normally JP will have pre-setup directories
    }
    base = strsplit(basename(file_image),'.fits',fixed=T)[[1]]
    return(paste0(path,base,'_sky_rem.fits'))
  }
  
  sky_filelist = list.files(as.character(sky_info$pathsky[[1]]))
  corr_pid = grep(VID, as.character(sky_info$visit_id), fixed = TRUE, value = TRUE)
  corr_pid = corr_pid[substring(corr_pid, 1, nchar(VID)) == VID]
  pid_idx = as.character(sky_info$visit_id) %in% corr_pid
  sky_info = sky_info[
    grepl(VID, as.character(sky_info$fileim)) &
    pid_idx &
    grepl(FILT, as.character(sky_info$filter)),
  ]
  if(do_NIRISS){
    sky_info = sky_info[grepl("NIS", as.character(sky_info$detector)), ]
  }else if(do_MIRI){
    sky_info = sky_info[grepl("MIRIMAGE", as.character(sky_info$detector)), ]
  }else{
    sky_info = sky_info[!grepl("MIRIMAGE", as.character(sky_info$detector)) &
                          !grepl("NIS", as.character(sky_info$detector)), ]
  }
  if(nrow(sky_info) == 0){
    message("No sky_info rows matched super-sky application for VID ", VID, ifelse(FILT == "", "", paste0(" FILT ", FILT)))
    return(invisible(NULL))
  }
  sky_filelist = sky_info$filesky

  sky_info = data.frame(sky_info)
  
  cat('Processing',length(sky_filelist),'files...\n')
  message("Skip completed files is ", ifelse(skip_completed_files, "ON", "OFF"))
  if(jp_store_enabled(input_args)){
    cal_sky_files = vapply(
      seq_len(nrow(sky_info)),
      function(i) setcal_sky_remfile(paste(sky_info[i,'pathim'], sky_info[i,'fileim'], sep='/'), cal_sky_dir),
      FUN.VALUE = character(1)
    )
    jp_store_set(input_args, "cal_sky_files", unique(cal_sky_files))
  }
  
  lo_loop = 1
  hi_loop = length(sky_filelist)
  
  write_cores = jp_cap_task_cores(
    cores = jp_cap_write_cores(cores = cores, nfiles = hi_loop),
    ntasks = hi_loop
  )
  if(write_cores != cores){
    message("Large apply_super_sky batch detected (", hi_loop, " files). Using write_cores=", write_cores, ".")
  }
  
  cl <- register_jumprope_backend(cores = write_cores, parallel_type = parallel_type)
  
  dummy = foreach(i = lo_loop:hi_loop, .inorder=FALSE, .packages = c("Rfits", "Rwcs", "ProFound", "magicaxis"), .export = c("jwst_read_cal_core", "jwst_read_sky_masks", "copy_fits_with_validation", "fits_write_pix_with_retry", "is_valid_fits_file"))%dopar%{
    if(i %% 100 == 0){
      message('File ',i,' of ', hi_loop)
    }
    file_image = paste(sky_info[i,'pathim'], sky_info[i,'fileim'], sep='/')
    file_cal_sky = setcal_sky_remfile(file_image, cal_sky_dir)
    
    if( !(skip_completed_files & is_valid_fits_file(file_cal_sky, required_ext = "SCI")) ){
      temp_cal = jwst_read_cal_core(file_image)
      temp_cal$DQ$keyvalues$BZERO = 0
      #safe name (since sometimes the sky file name gets truncated due to 80 character FITS limits)
      file_sky = sky_info[i,'filesky']
      file_sky = grep(sky_info[i,'filesky'], sky_filelist, value=TRUE)
      if(length(file_sky) == 0){
        stop('Missing file_sky ',i)
      }
      
      file_sky = paste(sky_info[i,'pathsky'], file_sky, sep='/')
      temp_sky = jwst_read_sky_masks(file_sky)
      
      file_super_sky = paste0(sky_super_dir,'/super_',temp_cal[[1]]$keyvalues$DETECTOR,'_',temp_cal[[1]]$keyvalues$FILTER,'.fits')
      super_sky = Rfits_read_image(file_super_sky, header=FALSE)
      
      obj_idx = temp_sky$PIXELMASK$imDat==0 & temp_sky$OBJECTMASK$imDat==0
      if(sum(obj_idx) == 0){ ## otherwise the linear model is going to fail
        obj_idx = temp_sky$PIXELMASK$imDat==0 & temp_cal$SCI$imDat <= quantile(temp_cal$SCI$imDat, probs =  0.5, na.rm = TRUE) ## minimally select stuff less than the median
      }
      
      ## linear model to each pixel 
      temp_lm = lm(temp_cal$SCI$imDat[obj_idx] ~ super_sky[obj_idx])$coefficients
      
      if(is.na(temp_lm[2])){
        temp_lm[2] = 0
      }
      
      if(temp_lm[2] < 0){ #force to be positive
        temp_lm[2] = 0
      }
      
      if(temp_lm[2] > 2){ #do not allow extreme values (expect to be near 1)
        temp_lm[2] = 2
      }
      
      sky_map = super_sky*temp_lm[2] + temp_lm[1]
      
      #maybe an extra sky stage here to clean things up per frame?
      
      rezero = which(temp_cal$SCI$imDat==0)
      temp_cal_sky = temp_cal$SCI$imDat - sky_map
      temp_cal_sky[!(obj_idx)] = NA
      
      #pedestal check - basically use the extremes of the frame to find a safe pedestal:
      
      pix_buffer = 10+1 ## Ignore first 10 pixels since these are often ratty
      imdim = dim(temp_cal_sky)
      
      edge_pix = (pix_buffer):(pix_buffer+4)
      
      LHS = median(temp_cal_sky[edge_pix,], na.rm=TRUE)
      RHS = median(temp_cal_sky[imdim[1]-edge_pix,], na.rm=TRUE)
      BHS = median(temp_cal_sky[,edge_pix], na.rm=TRUE)
      THS = median(temp_cal_sky[,imdim[2]-edge_pix], na.rm=TRUE)
      
      #corners (with masking, this gives about as many pixels as the edge above):
      corner_pix = (pix_buffer):(pix_buffer*10)
      BL = median(temp_cal_sky[corner_pix,corner_pix], na.rm=TRUE)
      TL = median(temp_cal_sky[corner_pix,imdim[2]-corner_pix], na.rm=TRUE)
      TR = median(temp_cal_sky[imdim[1]-corner_pix,imdim[2]-corner_pix], na.rm=TRUE)
      BR = median(temp_cal_sky[imdim[1]-corner_pix,corner_pix], na.rm=TRUE)
      
      #centre
      CC = median( magcutout(temp_cal_sky, box = c(100, 100))$image, na.rm=TRUE)
      
      pedestals = c(BL, LHS, TL, THS, TR, RHS, BR, BHS, CC)
      
      final_pedestal = quantile(pedestals, 0.5, na.rm=TRUE) #logic being a real issue due to a large object
      
      if(!is.finite(final_pedestal)){
        final_pedestal = 0
      }
      
      sky_map = sky_map + final_pedestal
      
      temp_cal$SCI$imDat = temp_cal$SCI$imDat - sky_map
      
      if(length(rezero) > 0){
        temp_cal$SCI$imDat[rezero] = 0
      }
      
      if(file.exists(file_cal_sky)){
        message('Removing old cal_sky file: ',file_cal_sky)
        file.remove(file_cal_sky)
      }
      
      copy_fits_with_validation(file_image, file_cal_sky, required_ext = "SCI")
      fits_write_pix_with_retry(temp_cal$SCI$imDat, file_cal_sky, ext=2)
      Rfits_write_key(file_cal_sky, keyname='SKY_M', keyvalue=temp_lm[2], keycomment='SKY M coef in SKY = M.SuperSky + B + P', ext=2)
      Rfits_write_key(file_cal_sky, keyname='SKY_B', keyvalue=temp_lm[1], keycomment='SKY B coef in SKY = M.SuperSky + B + P', ext=2)
      Rfits_write_key(file_cal_sky, keyname='SKY_P', keyvalue=final_pedestal, keycomment='SKY P coef in SKY = M.SuperSky + B + P', ext=2)
      
      check_Ndhu = Rfits_nhdu(file_cal_sky)
      extloc = Rfits_extname_to_ext(file_cal_sky, 'SKY_Super')
      
      if(is.na(extloc)){
        Rfits_write_image(sky_map, file_cal_sky, create_file=FALSE, create_ext=TRUE)
        Rfits_write_key(filename=file_cal_sky, ext=check_Ndhu+1, keyname='EXTNAME', keyvalue='SKY_Super', keycomment='extension name')
      }else{
        fits_write_pix_with_retry(sky_map, file_cal_sky, ext=extloc)
      }
      
      return(list(
        full = file_cal_sky,
        file = basename(file_cal_sky),
        VISIT_ID = temp_cal[[1]]$keyvalues$VISIT_ID,
        OBS_ID = temp_cal[[1]]$keyvalues$OBS_ID,
        EXPOSURE = temp_cal[[1]]$keyvalues$EXPOSURE,
        DETECTOR = temp_cal[[1]]$keyvalues$DETECTOR,
        MODULE = temp_cal[[1]]$keyvalues$MODULE,
        CHANNEL = temp_cal[[1]]$keyvalues$CHANNEL,
        FILTER = temp_cal[[1]]$keyvalues$FILTER,
        SKY_M = temp_lm[2],
        SKY_B = temp_lm[1],
        SKY_P = final_pedestal
      ))
    }else{
      return(NULL)
    }
  }
  
  stop_jumprope_backend(cl)
  if(jp_store_enabled(input_args)){
    cal_sky_meta = Filter(Negate(is.null), dummy)
    if(length(cal_sky_meta) == nrow(sky_info) && length(cal_sky_meta) > 0){
      jp_store_set(input_args, "cal_sky_metadata", data.frame(data.table::rbindlist(cal_sky_meta, fill = TRUE)))
    }
  }
  gc()
}
do_modify_pedestal = function(input_args){
  
  cat("\n")
  message("## Modifying pedestal ##")
  cat("\n")

  cal_sky_dir = input_args$cal_sky_dir
  cal_sky_renorm_dir = input_args$cal_sky_renorm_dir
  VID = input_args$VID
  FILT = input_args$FILT
  cores = input_args$cores_pro
  do_NIRISS = input_args$do_NIRISS
  do_MIRI = input_args$do_MIRI
  parallel_type = input_args$additional_params$parallel_type
  skip_completed_files = additional_params$skip_completed_files
  
  filelist = load_files(input_args, which_module = "modify_pedestal")
  if(length(filelist) == 0){
    message("No cal_sky files found for pedestal modification for VID ", VID, ifelse(FILT == "", "", paste0(" FILT ", FILT)))
    return(invisible(NULL))
  }
  
  cat('Processing',length(filelist),'files...\n')
  message("Skip completed files is ", ifelse(skip_completed_files, "ON", "OFF"))
  
  cal_sky_info = jp_store_get(input_args, "cal_sky_metadata", default = NULL)
  if(!is.null(cal_sky_info)){
    cal_sky_info = data.frame(cal_sky_info)
    cal_sky_info = cal_sky_info[cal_sky_info$full %in% filelist, , drop = FALSE]
  }
  if(is.null(cal_sky_info) || nrow(cal_sky_info) != length(filelist)){
    cal_sky_info_ext1 = Rfits_key_scan(filelist = filelist,
                                       keylist = c('VISIT_ID', 'OBS_ID', 'EXPOSURE', 'DETECTOR', 'MODULE', 'CHANNEL', 'FILTER'),
                                       extlist = 1,
                                       fileinfo = c('Full','File'),
                                       cores = cores
    )
    
    cal_sky_info_ext2 = Rfits_key_scan(filelist = filelist,
                                       keylist = c('SKY_M', 'SKY_B', 'SKY_P'),
                                       extlist = 2,
                                       fileinfo = NULL,
                                       cores = cores
    )
    
    cal_sky_info = as.data.table(cbind(cal_sky_info_ext1, cal_sky_info_ext2))
  }else{
    cal_sky_info = as.data.table(cal_sky_info)
  }
  if(jp_store_enabled(input_args)){
    file_col = if("file" %in% names(cal_sky_info)) "file" else "File"
    jp_store_set(
      input_args,
      "cal_sky_renorm_files",
      unique(file.path(cal_sky_renorm_dir, cal_sky_info[[file_col]]))
    )
  }
  
  ped_info = cal_sky_info[,list(ped_mean = mean(SKY_B + SKY_P), ped_med = median(SKY_B + SKY_P), ped_max = max(SKY_B + SKY_P), ped_min = min(SKY_B + SKY_P)), by=list(OBS_ID, EXPOSURE)]
  ped_info[,ped_diff := (ped_max - ped_min) / ped_mean]
  
  cal_sky_info = data.frame(cal_sky_info)
  
  lo_loop = 1
  hi_loop = dim(cal_sky_info)[1]
  write_cores = jp_cap_task_cores(
    cores = jp_cap_write_cores(cores = cores, nfiles = hi_loop),
    ntasks = hi_loop
  )
  if(write_cores != cores){
    message("Large pedestal batch detected (", hi_loop, " files). Using write_cores=", write_cores, ".")
  }
  
  cl <- register_jumprope_backend(cores = write_cores, parallel_type = parallel_type)
  
  if(do_NIRISS){
    dummy = foreach(i = lo_loop:hi_loop, .packages = c("Rfits", "Rwcs", "ProFound"), .export = c("copy_fits_with_validation", "is_valid_fits_file"))%dopar%{
      if(i %% 100 == 0){
        message('File ',i,' of ', hi_loop)
      }
      file_cal_sky_renorm = paste0(cal_sky_renorm_dir,'/',cal_sky_info[i,'file'])
      
      if( !(skip_completed_files & is_valid_fits_file(file_cal_sky_renorm, required_ext = "SCI")) ){
        if(file.exists(file_cal_sky_renorm)){
          message('Removing old cal_sky file: ',file_cal_sky_renorm)
          file.remove(file_cal_sky_renorm)
        }
        copy_fits_with_validation(cal_sky_info[i,'full'], file_cal_sky_renorm, required_ext = "SCI") #no pedestal adjustment for NIRISS
        return(NULL)
      }else{
        return(NULL)
      }
    }
  }else if(do_MIRI){
    dummy = foreach(i = lo_loop:hi_loop, .packages = c("Rfits", "Rwcs", "ProFound"), .export = c("copy_fits_with_validation", "is_valid_fits_file"))%dopar%{
      if(i %% 100 == 0){
        message('File ',i,' of ', hi_loop)
      }
      file_cal_sky_renorm = paste0(cal_sky_renorm_dir,'/',cal_sky_info[i,'file'])

      if( !(skip_completed_files & is_valid_fits_file(file_cal_sky_renorm, required_ext = "SCI")) ){
        if(file.exists(file_cal_sky_renorm)){
          message('Removing old cal_sky file: ',file_cal_sky_renorm)
          file.remove(file_cal_sky_renorm)
        }
        copy_fits_with_validation(cal_sky_info[i,'full'], file_cal_sky_renorm, required_ext = "SCI") 
        return(NULL)
      }else{
        return(NULL)
      }
    }
  }else{
    dummy = foreach(i = lo_loop:hi_loop, .packages = c("Rfits", "Rwcs", "ProFound"), .export = c("jwst_read_cal_sky_core", "jwst_dq_do_not_use_mask", "copy_fits_with_validation", "fits_write_pix_with_retry", "is_valid_fits_file"))%dopar%{
      if(i %% 100 == 0){
        message('File ',i,' of ', hi_loop)
      }
      file_cal_sky_renorm = paste0(cal_sky_renorm_dir,'/',cal_sky_info[i,'file'])
      
      if( !(skip_completed_files & is_valid_fits_file(file_cal_sky_renorm, required_ext = "SCI")) ){
        if(file.exists(file_cal_sky_renorm)){
          message('Removing old cal_sky file: ',file_cal_sky_renorm)
          file.remove(file_cal_sky_renorm)
        }
        copy_fits_with_validation(cal_sky_info[i,'full'], file_cal_sky_renorm, required_ext = "SCI")
        
        if(cal_sky_info[i,'CHANNEL'] == 'SHORT'){
          temp_cal_sky = jwst_read_cal_sky_core(cal_sky_info[i,'full'])
          
          temp_mask = Rfits_read_image(cal_sky_info[i,'full'], ext = "DQ", header = F)
          JWST_cal_mask = profoundDilate(jwst_dq_do_not_use_mask(temp_mask), size=3)
          
          pro_current_sky = profoundProFound(temp_cal_sky$SCI[,]$imDat, mask=JWST_cal_mask, sky=0, box=683, redosky = FALSE)
          
          if(is.null(pro_current_sky$skyChiSq)){
            pro_current_sky$skyChiSq = 1e6
          }
          if(is.na(pro_current_sky$skyChiSq)){
            pro_current_sky$skyChiSq = 1e6
          }
          if(is.infinite(pro_current_sky$skyChiSq)){
            pro_current_sky$skyChiSq = 1e6
          }
          
          if(pro_current_sky$skyChiSq < 0.9 | pro_current_sky$skyChiSq > 1.1){
            message('Bad Sky: ',cal_sky_info[i,'file'],'. Current: ',round(pro_current_sky$skyChiSq,2),' Trying to make better sky with ProFound')
            # if(sum(pro_current_sky$objects) / prod(dim(temp_cal_sky$SCI)) < 0.2){ ## What was this for?
            
            pro_new_sky = profoundProFound(temp_cal_sky$SCI[,]$imDat, mask=JWST_cal_mask, box=683, roughpedestal = TRUE)
            
            if(is.null(pro_new_sky$skyChiSq)){
              pro_new_sky$skyChiSq = 1e6
            }
            if(is.na(pro_new_sky$skyChiSq)){
              pro_new_sky$skyChiSq = 1e6
            }
            if(is.infinite(pro_new_sky$skyChiSq)){
              pro_new_sky$skyChiSq = 1e6
            }
            
            if(pro_new_sky$skyChiSq > 0.9 & pro_new_sky$skyChiSq < 1.1){
              message('Using better ProFound Sky: ',cal_sky_info[i,'file'],' Old: ',round(pro_current_sky$skyChiSq,2),' New: ',round(pro_new_sky$skyChiSq,2))
              replace_SCI = temp_cal_sky$SCI[,]$imDat - pro_new_sky$sky
              replace_SKY_Super = temp_cal_sky$SKY_Super[,]$imDat + pro_new_sky$sky
              replace_SKY_P = temp_cal_sky$SCI$keyvalues$SKY_P + mean(pro_new_sky$sky, na.rm=TRUE)
              
              fits_write_pix_with_retry(replace_SCI, file_cal_sky_renorm, ext=Rfits_extname_to_ext(file_cal_sky_renorm, 'SCI'))
              fits_write_pix_with_retry(replace_SKY_Super, file_cal_sky_renorm, ext=Rfits_extname_to_ext(file_cal_sky_renorm, 'SKY_Super'))
              Rfits_write_key(file_cal_sky_renorm, keyname='SKY_P', keyvalue=replace_SKY_P, keycomment='SKY P coef in SKY = M.SuperSky + B + P', ext=2)
              Rfits_write_key(file_cal_sky_renorm, keyname='SKY_CHI', keyvalue=pro_new_sky$skyChiSq, keycomment='SKY Chi-Sq', ext=2)
            }else{
              Rfits_write_key(file_cal_sky_renorm, keyname='SKY_CHI', keyvalue=pro_current_sky$skyChiSq, keycomment='SKY Chi-Sq', ext=2)
            }
          }
        }
        return(NULL)
      }else{
        return(NULL)
      }
    }
  }
  
  stop_jumprope_backend(cl)
  gc()
}
do_cal_sky_info = function(input_args){

  cat("\n")
  message("## Collecting cal_sky_renorm info for ProPane ##")
  cat("\n")
  
  cal_sky_renorm_dir = input_args$cal_sky_renorm_dir
  cal_sky_renorm_persistent_dir = input_args$cal_sky_renorm_persistent_dir
  cal_sky_info_save_dir = input_args$cal_sky_info_save_dir
  cores = input_args$cores_pro
  filelist = jp_store_get(input_args, "cal_sky_renorm_files", default = NULL)
  if(is.null(filelist)){
    filelist = list.files(cal_sky_renorm_dir, full.names = TRUE, pattern = ".fits$")
  }
  if(length(filelist) == 0 && !is.null(cal_sky_renorm_persistent_dir) && dir.exists(cal_sky_renorm_persistent_dir)){
    persistent_filelist = list.files(cal_sky_renorm_persistent_dir, full.names = TRUE, pattern = ".fits$")
    if(length(persistent_filelist) > 0){
      message("No staged cal_sky_renorm FITS files found in ", cal_sky_renorm_dir, "; falling back to persistent disk products in ", cal_sky_renorm_persistent_dir)
      filelist = persistent_filelist
    }
  }
  if(length(filelist) == 0){
    message("No cal_sky_renorm FITS files found in ", cal_sky_renorm_dir)
    return(invisible(NULL))
  }
  
  cal_sky_info_WCS = Rfits_key_scan(filelist=filelist,
                                    keylist = c('PHOTMJSR','PIXAR_SR','CRVAL1', 'CRVAL2', 'CD1_1', 'CD1_2', 'CD2_1', 'CD2_2'),
                                    extlist = 2,
                                    fileinfo = 'all',
                                    cores = cores
  )
  cal_sky_info = Rfits_key_scan(filelist=filelist,
                                keylist = c('VISIT_ID','DATE-OBS', 'DETECTOR', 'FILTER', 'EFFEXPTM', 'CRDS_CTX'),
                                extlist = 1,
                                fileinfo = 'none',
                                cores = cores
  )
  cal_sky_info = cbind(cal_sky_info_WCS, cal_sky_info)
  cal_sky_info$MAGZERO = -2.5*log10(cal_sky_info$PIXAR_SR*1e6) + 8.9 #note the -ve
  cal_sky_info = as.data.table(cal_sky_info)
  
  pmap = cal_sky_info[,list(PHOTMJSR=mean(PHOTMJSR)), keyby=list(CRDS_CTX,DETECTOR,FILTER)]
  
  cal_sky_info$MAGZERO_FIX = 0.0
  ## get most recent pmap
  most_recent_pmap_ctx = max(unique(gsub(".*jwst_(\\d+)\\.pmap.*", "\\1", pmap$CRDS_CTX)))
  
  for(i in 1:dim(cal_sky_info)[1]){
    #below is then Eqn [1] below
    ## Tie to pmap 1179 for now
    temp_MAGZERO_FIX = cal_sky_info[i,MAGZERO] -2.5*log10(as.numeric(pmap[CRDS_CTX==paste0('jwst_', most_recent_pmap_ctx, '.pmap') & DETECTOR==cal_sky_info[i,'DETECTOR'] & FILTER==cal_sky_info[i,'FILTER'],PHOTMJSR]) / cal_sky_info[i,PHOTMJSR])
    if(length(temp_MAGZERO_FIX) == 1){
      cal_sky_info[i,MAGZERO_FIX := temp_MAGZERO_FIX] 
    }else{
      cal_sky_info[i,MAGZERO_FIX := cal_sky_info[i,MAGZERO]]
    }
  }
  jp_store_set(input_args, "cal_sky_info", cal_sky_info)
  write.csv(cal_sky_info, paste0(cal_sky_info_save_dir, '/cal_sky_info.csv'), row.names = FALSE)
}
do_gen_stack = function(input_args){
  
  cat("\n")
  message("## Making ProPane stacks ##")
  cat("\n")

  VID = input_args$VID
  FILT = input_args$FILT
  ref_dir = input_args$ref_dir
  do_NIRISS = input_args$do_NIRISS
  do_MIRI = input_args$do_MIRI
  magzero = input_args$magzero
  cores = input_args$cores_stack
  tasks = input_args$tasks_stack
  effective_cores = ifelse(tasks > 1L, max(1L, floor(input_args$cores_pro / tasks)), input_args$cores_pro)  ## full budget when serial, divided when parallel
  ram_mode = grepl("T|TRUE|True", Sys.getenv("JUMPROPE_RAM_MODE"))
  
  skip_completed_files = additional_params$skip_completed_files
  parallel_type = input_args$additional_params$parallel_type
  
  ref_cat = input_args$additional_params$ref_cat
  if(is.null(ref_cat)){
    do_tweak = FALSE
  }else{
    do_tweak = TRUE
    ref_cat = data.frame(fread(ref_cat))
  }
  
  ## Optional editable params
  clip_tol = c(40,20) #default (80,40) hot and cold
  clip_sigma = 20
  clip_dilate = 3
  doclip = F
  
  ## Allow user to change these
  NAXIS_short = ifelse(
    is.null(input_args$additional_params$NAXIS_short), 
    6000, #good for ceers, need 6000 for cosmos web
    input_args$additional_params$NAXIS_short
  ) 
  NAXIS_long = ifelse(
    is.null(input_args$additional_params$NAXIS_long), 
    3000, 
    input_args$additional_params$NAXIS_long
  ) 
  
  ## Better for scripting mode
  invar_dir = input_args$invar_dir
  median_dir = input_args$median_dir
  sky_frames_dir = input_args$sky_frames_dir
  dump_dir_stub = input_args$dump_dir
  orig_cal_sky_info = jp_store_get(input_args, "cal_sky_info", default = NULL)
  if(is.null(orig_cal_sky_info)){
    orig_cal_sky_info = fread(paste0(input_args$cal_sky_info_save_dir, '/cal_sky_info.csv'))
  }
  
  unique_visits = unique(orig_cal_sky_info$VISIT_ID)
  
  message("Now running stack!")
  message("Skip completed files is ", ifelse(skip_completed_files, "ON", "OFF"))
  
  temp_vid = VID
  VID_list = grep(paste0("^",temp_vid), unique_visits, value = T)

  for(VID in VID_list){
    if(do_NIRISS){
      cal_sky_info = orig_cal_sky_info[grepl(VID, orig_cal_sky_info$VISIT_ID) & grepl("NIS", orig_cal_sky_info$DETECTOR),]
    }else if(do_MIRI){
      cal_sky_info = orig_cal_sky_info[grepl(VID, orig_cal_sky_info$VISIT_ID) & grepl("MIRIMAGE", orig_cal_sky_info$DETECTOR),]
    }else{
      cal_sky_info = orig_cal_sky_info[grepl(VID, orig_cal_sky_info$VISIT_ID) & !grepl("NIS|MIRIMAGE", orig_cal_sky_info$DETECTOR),]
    }
    cal_sky_info$MAGZERO_FIX[is.na(cal_sky_info$MAGZERO_FIX)] = cal_sky_info$MAGZERO[is.na(cal_sky_info$MAGZERO_FIX)]
    
    stack_grid = cal_sky_info[,list(FILTER=unique(FILTER)), keyby=VISIT_ID]
    stack_grid = stack_grid[grepl(FILT, stack_grid$FILTER), ]
    
    if(dim(stack_grid)[1] == 0){
      next ## If the FILTER/VID combo is null then skip 
    }else{
      print(stack_grid)
    }
    
    module_A_WCS_short = cal_sky_info[grepl('NRCA[1-4]', DETECTOR),list(CRVAL1=mean(CRVAL1), CRVAL2=mean(CRVAL2), CD1_1=mean(CD1_1), CD1_2=mean(CD1_2)), keyby=VISIT_ID]
    module_B_WCS_short = cal_sky_info[grepl('NRCB[1-4]', DETECTOR),list(CRVAL1=mean(CRVAL1), CRVAL2=mean(CRVAL2), CD1_1=mean(CD1_1), CD1_2=mean(CD1_2)), keyby=VISIT_ID]

    module_A_WCS_long = cal_sky_info[grepl('NRCALONG', DETECTOR),list(CRVAL1=mean(CRVAL1), CRVAL2=mean(CRVAL2), CD1_1=mean(CD1_1), CD1_2=mean(CD1_2)), keyby=VISIT_ID]
    module_B_WCS_long = cal_sky_info[grepl('NRCBLONG', DETECTOR),list(CRVAL1=mean(CRVAL1), CRVAL2=mean(CRVAL2), CD1_1=mean(CD1_1), CD1_2=mean(CD1_2)), keyby=VISIT_ID]

    if(dim(module_A_WCS_long)[1] == 0){
      module_A_WCS_long = module_A_WCS_short
      module_A_WCS_long$CD1_1 = module_A_WCS_long$CD1_1*2.0
      module_A_WCS_long$CD1_2 = module_A_WCS_long$CD1_2*2.0
    }

    if(dim(module_B_WCS_long)[1] == 0){
      module_B_WCS_long = module_B_WCS_short
      module_B_WCS_long$CD1_1 = module_B_WCS_long$CD1_1*2.0
      module_B_WCS_long$CD1_2 = module_B_WCS_long$CD1_2*2.0
    }

    if(dim(module_A_WCS_short)[1] == 0){
      module_A_WCS_short = module_A_WCS_long
      module_A_WCS_short$CD1_1 = module_A_WCS_short$CD1_1/2.0
      module_A_WCS_short$CD1_2 = module_A_WCS_short$CD1_2/2.0
    }

    if(dim(module_B_WCS_short)[1] == 0){
      module_B_WCS_short = module_B_WCS_long
      module_B_WCS_short$CD1_1 = module_B_WCS_short$CD1_1/2.0
      module_B_WCS_short$CD1_2 = module_B_WCS_short$CD1_2/2.0
    }

    module_NIS = cal_sky_info[grepl('NIS', DETECTOR),list(CRVAL1=mean(CRVAL1), CRVAL2=mean(CRVAL2), CD1_1=mean(CD1_1), CD1_2=mean(CD1_2)), keyby=VISIT_ID]

    module_MIRIMAGE = cal_sky_info[grepl('MIRIMAGE', DETECTOR),list(CRVAL1=median(CRVAL1), CRVAL2=median(CRVAL2), CD1_1=mean(CD1_1), CD1_2=mean(CD1_2)), keyby=VISIT_ID]
    
    module_idx = sapply(list(module_A_WCS_long, module_A_WCS_short, 
                             module_B_WCS_long, module_B_WCS_short,
                             module_NIS, module_MIRIMAGE), 
                        function(x){y = dim(x)[1]
                        y > 0})
    module_list = c('NRCA_long', 'NRCA_short', 'NRCB_long', 'NRCB_short', 'NIS', 'MIRIMAGE')[module_idx]
    
    if(!is.null(input_args$additional_params$module_list)){
      module_list_temp = input_args$additional_params$module_list
      module_list = module_list[module_list %in% module_list_temp]
    }

    lo_loop = 1
    hi_loop = dim(stack_grid)[1]
    
    stack_grid = stack_grid[sample(hi_loop),] #randomise to spread out the CPU load (else all of the SMACS stacking end up in a single task and takes much longer)
    
    stack_grid = data.frame(stack_grid)
    cal_sky_info = data.frame(cal_sky_info)
    
    list_residual_temp_files = list.files(invar_dir, pattern = "temp_list_.+", full.names = T)
    if(length(list_residual_temp_files)>0){
      unlink(list_residual_temp_files, recursive = T)
    }
    
    task_budget = tasks
    stack_cores_cap = effective_cores
    if(ram_mode && nrow(cal_sky_info) >= 400L){
      task_budget = 1L
      stack_cores_cap = min(stack_cores_cap, 8L)
      message(
        "Large RAM-mode visit detected (", nrow(cal_sky_info),
        " inputs). Using task_budget=", task_budget,
        " and stack_cores_cap=", stack_cores_cap, "."
      )
    }
    
    outer_cores = jp_cap_task_cores(cores = task_budget, ntasks = hi_loop)
    cl <- register_jumprope_backend(
      cores = outer_cores,
      parallel_type = if(task_budget > 1L) parallel_type else NULL,
      fallback = "serial"
    )  ## fall back cleanly if the outer PSOCK backend cannot start
    
   dummy = foreach(
     i = lo_loop:hi_loop,
     .packages = c('Rwcs', 'Rfits', 'ProPane', 'ProFound', 'celestial'),
     .export = c("jwst_dq_do_not_use_mask", "rfits_write_with_retry", "is_valid_fits_file")
   )%dopar%{
     message('Stacking ', i,' of ',hi_loop)
      for(j in module_list){
        if( !(skip_completed_files & file.exists(paste0(invar_dir, '/stack_',stack_grid[i,'VISIT_ID'],'_',stack_grid[i,'FILTER'],'_',j,'.fits'))) ){
          message('  Processing ',stack_grid[i,'VISIT_ID'],' ',stack_grid[i,'FILTER'], ' ', j)
          
          if(j == 'MIRIMAGE'){
            input_info = cal_sky_info[cal_sky_info[['VISIT_ID']]==stack_grid[i,'VISIT_ID'] & cal_sky_info[['FILTER']]==stack_grid[i,'FILTER'] & grepl('MIRIMAGE', cal_sky_info[['DETECTOR']]),]
            CRVAL1 = module_MIRIMAGE[module_MIRIMAGE[['VISIT_ID']] == stack_grid[i,'VISIT_ID'], 'CRVAL1']
            CRVAL2 = module_MIRIMAGE[module_MIRIMAGE[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CRVAL2']
            CD1_1 = module_MIRIMAGE[module_MIRIMAGE[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CD1_1']
            CD1_2 = module_MIRIMAGE[module_MIRIMAGE[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CD1_2']
            NAXIS = NAXIS_long
            CRPIX = NAXIS_long/2.0
          }
          
          if(j == 'NIS'){
            input_info = cal_sky_info[cal_sky_info[['VISIT_ID']]==stack_grid[i,'VISIT_ID'] & cal_sky_info[['FILTER']]==stack_grid[i,'FILTER'] & grepl('NIS', cal_sky_info[['DETECTOR']]),]
            CRVAL1 = module_NIS[module_NIS[['VISIT_ID']] == stack_grid[i,'VISIT_ID'], 'CRVAL1']
            CRVAL2 = module_NIS[module_NIS[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CRVAL2']
            CD1_1 = module_NIS[module_NIS[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CD1_1']
            CD1_2 = module_NIS[module_NIS[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CD1_2']
            NAXIS = NAXIS_long
            CRPIX = NAXIS_long/2.0
          }
          
          if(j == 'NRCA_short'){
            input_info = cal_sky_info[cal_sky_info[['VISIT_ID']]==stack_grid[i,'VISIT_ID'] & cal_sky_info[['FILTER']]==stack_grid[i,'FILTER'] & grepl('NRCA', cal_sky_info[['DETECTOR']]),]
            CRVAL1 = module_A_WCS_short[module_A_WCS_short[['VISIT_ID']] == stack_grid[i,'VISIT_ID'], 'CRVAL1']
            CRVAL2 = module_A_WCS_short[module_A_WCS_short[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CRVAL2']
            CD1_1 = module_A_WCS_short[module_A_WCS_short[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CD1_1']
            CD1_2 = module_A_WCS_short[module_A_WCS_short[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CD1_2']
            NAXIS = NAXIS_short
            CRPIX = NAXIS_short/2.0
          }
          
          if(j == 'NRCB_short'){
            input_info = cal_sky_info[cal_sky_info[['VISIT_ID']]==stack_grid[i,'VISIT_ID'] & cal_sky_info[['FILTER']]==stack_grid[i,'FILTER'] & grepl('NRCB', cal_sky_info[['DETECTOR']]),]
            CRVAL1 = module_B_WCS_short[module_B_WCS_short[['VISIT_ID']] == stack_grid[i,'VISIT_ID'], 'CRVAL1']
            CRVAL2 = module_B_WCS_short[module_B_WCS_short[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CRVAL2']
            CD1_1 = module_B_WCS_short[module_B_WCS_short[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CD1_1']
            CD1_2 = module_B_WCS_short[module_B_WCS_short[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CD1_2']
            NAXIS = NAXIS_short
            CRPIX = NAXIS_short/2.0
          }
          
          if(j == 'NRCA_long'){
            input_info = cal_sky_info[cal_sky_info[['VISIT_ID']]==stack_grid[i,'VISIT_ID'] & cal_sky_info[['FILTER']]==stack_grid[i,'FILTER'] & grepl('NRCA', cal_sky_info[['DETECTOR']]),]
            CRVAL1 = module_A_WCS_long[module_A_WCS_long[['VISIT_ID']] == stack_grid[i,'VISIT_ID'], 'CRVAL1']
            CRVAL2 = module_A_WCS_long[module_A_WCS_long[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CRVAL2']
            CD1_1 = module_A_WCS_long[module_A_WCS_long[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CD1_1']
            CD1_2 = module_A_WCS_long[module_A_WCS_long[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CD1_2']
            NAXIS = NAXIS_long
            CRPIX = NAXIS_long/2.0
          }
          
          if(j == 'NRCB_long'){
            input_info = cal_sky_info[cal_sky_info[['VISIT_ID']]==stack_grid[i,'VISIT_ID'] & cal_sky_info[['FILTER']]==stack_grid[i,'FILTER'] & grepl('NRCB', cal_sky_info[['DETECTOR']]),]
            CRVAL1 = module_B_WCS_long[module_B_WCS_long[['VISIT_ID']] == stack_grid[i,'VISIT_ID'], 'CRVAL1']
            CRVAL2 = module_B_WCS_long[module_B_WCS_long[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CRVAL2']
            CD1_1 = module_B_WCS_long[module_B_WCS_long[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CD1_1']
            CD1_2 = module_B_WCS_long[module_B_WCS_long[['VISIT_ID']]  == stack_grid[i,'VISIT_ID'], 'CD1_2']
            NAXIS = NAXIS_long
            CRPIX = NAXIS_long/2.0
          }

          if(dim(input_info)[1] > 0){
            keep_idx = vapply(
              as.character(input_info[['full']]),
              function(f) is_valid_fits_file(f, required_ext = "SCI"),
              logical(1)
            )
            if(any(!keep_idx)){
              bad_files = as.character(input_info[['file']][!keep_idx])
              message(
                '  Skipping ', sum(!keep_idx), ' unreadable stack input file(s) for ',
                stack_grid[i,'VISIT_ID'], ' ', stack_grid[i,'FILTER'], ' ', j, ': ',
                paste(bad_files, collapse = ', ')
              )
              input_info = input_info[keep_idx, , drop = FALSE]
            }
          }

          if(dim(input_info)[1] == 0){
            message('  No usable stack input files remain for ',stack_grid[i,'VISIT_ID'],' ',stack_grid[i,'FILTER'], ' ', j)
            next
          }
          
          image_list = {}
          inVar_list = {}
          
          for(k in seq_len(dim(input_info)[1])){
            temp_image = Rfits_read_image(input_info[k,'full'], ext=2)
            
            temp_mask = Rfits_read_image(input_info[k,'full'], ext=4, header=FALSE)
            
            temp_image = propaneBadPix(
              image = temp_image,
              patch = T
            )
            
            JWST_cal_mask = profoundDilate(jwst_dq_do_not_use_mask(temp_mask), size=3)
            temp_image$imDat[JWST_cal_mask==1] = NA
            
            if(do_tweak){
              pro_test = suppressMessages(profoundProFound(
                image = temp_image, 
                mask = JWST_cal_mask == 1,
                sky = 0,
                redosky = F,
                pixcut = 10,
                skycut = 3.0,
                cliptol = 100,
                tolerance = 1,
                iters = 0,
                redosegim = F,
                box = dim(temp_image)[1]/10.0,
                rem_mask = T
              ))
              
              match_cat_idx = coordmatch(
                coordref = ref_cat[, c("RA", "Dec")],
                coordcompare = pro_test$segstats[,c("RAmax", "Decmax")],
                rad = 2.0
              )
              tweak_solution = suppressMessages(propaneTweakCat(
                cat_ref = ref_cat[match_cat_idx$bestmatch$refID, c("RA", "Dec")], 
                cat_pre_fix = pro_test$segstats[match_cat_idx$bestmatch$compareID,c("RAmax", "Decmax")], 
                mode = "coord", keyvalues_pre_fix = temp_image$keyvalues, delta_max = c(100, 100)
              ))
              temp_image = propaneWCSmod(
                temp_image, 
                delta_x = tweak_solution$par[1], 
                delta_y = tweak_solution$par[2],
                delta_rot = tweak_solution$par[3]
              )
            }
            
            rm(temp_mask)
            rm(JWST_cal_mask)
            image_list = c(image_list, list(temp_image))
            
            sky_file = paste0(sky_frames_dir, sub('_rem', '', input_info[k,'stub']),'_',input_info[k,'FILTER'],'.fits')
            inVar_list = c(inVar_list, Rfits::Rfits_read_key(sky_file, 'SKYRMS')^-2)
          }
          
          image_list_point = image_list  ## keep in-memory; fork workers use Rfits_image (pure-R path, no cfitsio handle to race on)
          rm(image_list)
          gc()
          
          dump_stub = paste0(dump_dir_stub, stack_grid[i,'VISIT_ID'], "/", stack_grid[i,'FILTER'], "/", j, "/")
          if(dir.exists(dump_stub)){
            unlink(dump_stub, recursive = T)
          }
          dir.create(dump_stub, recursive = T)
          
          temp_proj = propaneGenWCS(
            image_list = image_list_point,
            CRVAL1 = as.numeric(CRVAL1),
            CRVAL2 = as.numeric(CRVAL2),
            CRPIX1 = as.numeric(CRPIX),
            CRPIX2 = as.numeric(CRPIX),
            CD1_1 = as.numeric(CD1_1),
            CD1_2 = as.numeric(CD1_2),
            CD2_1 = as.numeric(CD1_2),
            CD2_2 = -as.numeric(CD1_1),
            NAXIS1 = as.numeric(NAXIS),
            NAXIS2 = as.numeric(NAXIS)
          )
          
          temp_proj$DATE_BEG = as.character(min(as.POSIXlt.Date(input_info[["DATE.OBS"]]), na.rm=TRUE))
          temp_proj$DATE_END = as.character(max(as.POSIXlt.Date(input_info[["DATE.OBS"]]), na.rm=TRUE))
          
          stack_cores = min(
            stack_cores_cap,
            ifelse(task_budget > 1L, max(1L, floor(input_args$cores_pro / task_budget)), input_args$cores_pro)
          )
          
          output_stack = propaneStackWarpInVar(
            image_list = image_list_point,
            inVar_list = inVar_list,
            exp_list = input_info$EFFEXPTM,
            magzero_in = input_info$MAGZERO_FIX,
            magzero_out = magzero,
            keyvalues_out = temp_proj,
            cores = stack_cores, 
            direction = 'backward',
            doclip = doclip,
            clip_tol = clip_tol,
            clip_dilate = clip_dilate,
            clip_sigma = clip_sigma,
            keep_extreme_pix = FALSE,
            dump_frames = TRUE,
            dump_dir = dump_stub,
            multitype = ifelse(task_budget > 1L, "fork", "cluster")  ## fork inside PSOCK outer avoids PSOCK-in-PSOCK deadlock
          )
          
          output_stack$image$keyvalues$CLIP_MIN = clip_tol[1]
          output_stack$image$keyvalues$CLIP_MAX = clip_tol[2]
          output_stack$image$keyvalues$CLIP_DIL = clip_dilate
          
          exp_min = min(output_stack$exp$imDat[output_stack$weight$imDat > 0], na.rm=TRUE)
          exp_max = max(output_stack$exp$imDat[output_stack$weight$imDat > 0], na.rm=TRUE)
          
          mask_frc = sum(output_stack$weight$imDat==0 & output_stack$exp$imDat >= exp_min, na.rm=TRUE) / length(which(output_stack$weight$imDat > 0))
          clip_frc = sum(output_stack$clip$imDat>0, na.rm=TRUE) / length(which(output_stack$weight$imDat > 0))
          
          output_stack$image$keyvalues$CLIP_FRC = clip_frc
          output_stack$image$keyvalues$MASK_FRC = mask_frc
          output_stack$image$keyvalues$EXP_MIN = exp_min
          output_stack$image$keyvalues$EXP_MAX = exp_max
          output_stack$image$keyvalues$MAGZERO = magzero
          output_stack$image$keyvalues$BUNIT = "microJy"
          
          rms_min = 1/sqrt(max(output_stack$inVar$imDat[output_stack$weight$imDat > 0], na.rm=TRUE))
          rms_max = 1/sqrt(min(output_stack$inVar$imDat[output_stack$weight$imDat > 0], na.rm=TRUE))
          
          output_stack$image$keyvalues$RMS_MIN = rms_min
          output_stack$image$keyvalues$RMS_MAX = rms_max
          
          output_stack = c(output_stack, list(info = input_info[,c(1,5:20)]))
          
          output_stack$image$keynames = unique(names(output_stack$image$keyvalues))
          output_stack$image$keycomments = rep(list(''), length(unique(names(output_stack$image$keyvalues))))
          names(output_stack$image$keycomments) = output_stack$image$keynames
          
          rm(image_list_point)
          gc()

          filestub = paste0(invar_dir, '/stack_',stack_grid[i,'VISIT_ID'],'_',stack_grid[i,'FILTER'],'_',j)

          rfits_write_with_retry(
            data = output_stack,  ## write InVar BEFORE propaneStackWarpMed: avoids cfitsio dump-handle interference
            filename = paste0(filestub,'.fits')
          )

          median_stack = propaneStackWarpMed(dirlist = dump_stub,
                                             pattern = glob2rx('*image_warp*'), 
                                             keyvalues_out = output_stack$image$keyvalues, 
                                             cores = ifelse(task_budget > 1L, 1L, stack_cores),  ## 1L inside PSOCK: sequential chunks avoid cfitsio fork race
                                             multitype = ifelse(task_budget > 1L, "fork", "cluster"))  ## fork inside PSOCK outer

          gc()  ## flush propaneStackWarpMed cfitsio dump handles before median write
          gc()  ## run finalizers that may only execute after the first GC pass

          filestub_med = paste0(median_dir, '/med_',stack_grid[i,'VISIT_ID'],'_',stack_grid[i,'FILTER'],'_',j)

          rfits_write_with_retry(
            data = median_stack,
            filename = paste0(filestub_med,'.fits')
          )
          gc()
        }
      }
     return(NULL)
    }
   stop_jumprope_backend(cl)
   gc()
  }
}
do_wisp_rem = function(input_args){
  
  cat("\n")
  message("## Removing wisps ##")
  cat("\n")

  filelist = input_args$filelist
  VID = input_args$VID
  median_dir = input_args$median_dir
  cores = input_args$cores_pro
  additional_params  = input_args$additional_params
  SIGMA_LO = input_args$SIGMA_LO
  
  skip_completed_files = additional_params$skip_completed_files
  parallel_type = additional_params$parallel_type
  
  if(is.null(SIGMA_LO)){
    message("No smoothing on wisp removal")
  }else{
    message(paste0("Using smoothing kernel SIGMA_LO = ", SIGMA_LO))
  }
  
  filelist = load_files(input_args, which_module = "wisp_rem")
  if(length(filelist) == 0){
    message("No wisp-removal inputs found for VID ", VID)
    return(invisible(NULL))
  }
  
  info = Rfits_key_scan(filelist = filelist,
                        keylist=c('DETECTOR', 'MODULE', 'FILTER', 'VISIT_ID'), cores = cores)
  
  
  wcs_info = Rfits_key_scan(filelist = filelist, extlist = 2,
                            keylist = c("CRVAL1", "CRVAL2")) ## Find longest overlapping wisp frame
  info = bind_cols(info, wcs_info[,c("CRVAL1", "CRVAL2")])
  
  if(additional_params$do_claws){
    info_wisp = info[DETECTOR %in% c('NRCA1', 'NRCA2', 'NRCA3','NRCA4', 'NRCB1','NRCB2', 'NRCB3','NRCB4'),] ## Try do all short wavelength chips
  }else{
    info_wisp = info[DETECTOR %in% c('NRCA3','NRCA4', 'NRCB3','NRCB4'),] 
  }
  mod_visit_grid = info_wisp[,c("stub", "MODULE", "VISIT_ID", "CRVAL1", "CRVAL2", "DETECTOR")]
  
  cat('Processing',dim(info_wisp)[1],'files\n')
  message("Skip completed files is ", ifelse(skip_completed_files, "ON", "OFF"))
  
  idx_wisp_skip = !(unname(sapply( info_wisp$full, function(x){any(na.omit(Rfits_extnames(x)) == "SCI_ORIG")} )) & skip_completed_files)
  
  ref_im_list = vector("list", dim(mod_visit_grid)[1])
  for(ii in 1:dim(mod_visit_grid)[1]){
    if(idx_wisp_skip[ii]){
      ## Look for long-wave filters stacked on the short-grid mosaic, as in the original code.
      ref_files = list.files(
        median_dir, 
        pattern = glob2rx(paste0(
          "*", mod_visit_grid$VISIT_ID[ii], "*", mod_visit_grid$MODULE[ii], "*", "short", "*.fits"
        )),
        full.names = T)
      ref_files = ref_files[!grepl("F150W2|F070W|F090W|F115W|F150W|F200W|F140M|F162M|F182M|F210M|F164N|F187N|F212N", ref_files)] ## Remove the short wavelength filters
      
      if(length(ref_files) == 0){
        ## If no same-visit short-grid reference exists, find an overlapping short-grid long-wave stack.
        short_stack_pool = list.files(median_dir, pattern = "short.+fits$", full.names = TRUE)
        short_stack_pool = short_stack_pool[!is.na(short_stack_pool) & nzchar(short_stack_pool) & file.exists(short_stack_pool)]
        if(length(short_stack_pool) > 0 &&
           !is.na(mod_visit_grid$CRVAL1[ii]) && !is.na(mod_visit_grid$CRVAL2[ii])){
          ref_files = tryCatch(
            propaneFrameFinder(
              dirlist = median_dir, 
              RAcen = mod_visit_grid$CRVAL1[ii],
              Deccen = mod_visit_grid$CRVAL2[ii],
              rad = 0.1/3600, ## match within 0.1 asec
              plot = FALSE, 
              cores = cores
            )$full,
            error = function(e){
              message("No usable overlapping long wavelength for wisp correction search on ", mod_visit_grid$VISIT_ID[ii], " ", mod_visit_grid$DETECTOR[ii], ": ", conditionMessage(e))
              character(0)
            }
          ) ## Now do a frame finder to try and find long channel NOT in VISITID (but could be in PROGRAM)
          ref_files = ref_files[!is.na(ref_files) & nzchar(ref_files) & grepl("short.+fits$", ref_files) & file.exists(ref_files)]
        }else{
          ref_files = character(0)
        }
      }
      
      filter_long = c(
        str_match(ref_files, "F\\s*(.*?)\\s*[WMN]")[,2]
      )
      
	      if(length(filter_long) == 0){
	        message("No overlapping long wavelength for wisp correction")
	        load_ref = NULL
	      }else{
	        message(paste("Loading reference for:", paste0(mod_visit_grid$VISIT_ID[ii]), mod_visit_grid$DETECTOR[ii], mod_visit_grid$stub[ii] ))
	        filter_long[is.na(filter_long)] = -1
	        long_num = max(filter_long, na.rm = T)
	        ref_file_long = ref_files[ which(grepl(long_num, ref_files))[1] ] #Get the longest filter
	        load_ref = list(Rfits_point(ref_file_long))
          if(length(load_ref) > 0){
            attr(load_ref[[1]], "filename") = ref_file_long
            message("Selected wisp ref file: ", basename(ref_file_long))
          }
	      }
	      ref_im_list[[ii]] = if(length(load_ref) == 0) NULL else load_ref[[1]]
	    }
	  }
  
  worker_cores = jp_cap_task_cores(cores = cores, ntasks = dim(info_wisp)[1])
  cl <- register_jumprope_backend(cores = worker_cores, parallel_type = parallel_type)
  
  temp = foreach(ii = 1:dim(info_wisp)[1], .errorhandling = "pass", .packages = c("Rwcs", "Rfits", "ProPane", "ProFound"), .export = c("wispFixer", "jp_process_wisp_file"))%dopar%{
    jp_process_wisp_file(
      ii = ii,
      info_wisp = info_wisp,
      idx_wisp_skip = idx_wisp_skip,
      ref_im_list = ref_im_list,
      additional_params = additional_params,
      SIGMA_LO = SIGMA_LO
    )
  }
  
  stop_jumprope_backend(cl)
  failed_idx = which(vapply(temp, inherits, logical(1), what = "error"))
  if(length(failed_idx) > 0){
    message("Retrying ", length(failed_idx), " wisp-removal file(s) sequentially after parallel error(s).")
    for(ii in failed_idx){
      message("Retrying wisp removal for ", basename(info_wisp$full[ii]), ": ", conditionMessage(temp[[ii]]))
      tryCatch(
        jp_process_wisp_file(
          ii = ii,
          info_wisp = info_wisp,
          idx_wisp_skip = idx_wisp_skip,
          ref_im_list = ref_im_list,
          additional_params = additional_params,
          SIGMA_LO = SIGMA_LO
        ),
        error = function(e){
          message("Sequential wisp retry failed for ", basename(info_wisp$full[ii]), ": ", conditionMessage(e))
        }
      )
    }
  }
  gc()
}
do_patch = function(input_args){
  
  cat("\n")
  message("## Patching ProPane stacks ##")
  cat("\n")

  VID = input_args$VID
  FILT = input_args$FILT
  invar_dir = input_args$invar_dir
  median_dir = input_args$median_dir
  patch_dir = input_args$patch_dir
  cores = input_args$cores_stack
  do_NIRISS = input_args$do_NIRISS
  do_MIRI = input_args$do_MIRI
  skip_completed_files = additional_params$skip_completed_files
  parallel_type = input_args$additional_params$parallel_type
  
  patch_stub = patch_dir
  
  if(do_NIRISS){
    pixscale_list = c("NIS")
  }else if(do_MIRI){
    pixscale_list = c("MIRIMAGE")
  }else{
    pixscale_list = c("short", "long")
  }
  
  for(j in pixscale_list){
    invar_files = list.files(path=invar_dir, pattern = glob2rx(paste0("*stack*", j, "*.fits$")), full.names = T)
    median_files = list.files(path=median_dir, pattern = glob2rx(paste0("*med*", j, "*.fits$")), full.names = T)
    ## Don't match if number precedes VID?
    invar_files = invar_files[grepl(paste0("(?<![0-9])(", VID, ")"), invar_files, perl = TRUE) & grepl(FILT, invar_files) & !grepl("patch", invar_files)]
    median_files = median_files[grepl(paste0("(?<![0-9])(", VID, ")"), median_files, perl = TRUE) & grepl(FILT, median_files) & !grepl("patch", median_files)]

    if(length(median_files)==0){
      message("No frames") 
    }else{
      if(is.null(parallel_type)){
        registerDoParallel(cores = cores)
      }else{
        cl <- makeCluster(spec = cores, type = parallel_type, outfile = "")
        registerDoParallel(cl)
      }
      
      dummy = foreach(i = 1:length(invar_files), .packages = c("Rfits", "ProPane", "stringr"))%dopar%{
        
        message(paste0("Patching: ", invar_files[i]))
        info_load_invar = Rfits_read(invar_files[i], pointer=TRUE)
        info_temp = info_load_invar$image
        
        fstub = stringr::str_remove(stringr::str_remove(string = info_temp$filename, pattern = dirname(info_temp$filename)), ".+stack")
        
        if( !(skip_completed_files & file.exists(paste0(patch_stub, "patch", fstub))) ){
          
          load_invar = Rfits_read(invar_files[i], pointer=FALSE)
          load_median = Rfits_read(median_files[i], pointer=FALSE)
          temp = load_invar$image
          
          med_patch=propanePatch(image_inVar = temp, 
                                 image_med = load_median$image)
          
          ## compute the bounding box
          edge_mask = matrix(0L, nrow = dim(temp)[1], ncol = dim(temp)[2])
          rough_mask = is.na(temp$imDat)
          mask_label = as.matrix(imager::label(imager::as.cimg(rough_mask)))
          tally_pixels = tabulate(mask_label)
          sel = which(tally_pixels > 0)
          mask_loc = which(matrix(mask_label %in% sel, dim(temp)[1], dim(temp)[2]), arr.ind=TRUE)
          edge_mask[mask_loc] = 1
          edge_mask = 1- edge_mask
          
          big_NA_mask = matrix(0L, nrow = dim(temp)[1], ncol = dim(temp)[2])
          rough_mask = is.na(temp$imDat)
          mask_label = as.matrix(imager::label(imager::as.cimg(rough_mask)))
          tally_pixels = tabulate(mask_label)
          sel = which(tally_pixels > 150 & tally_pixels < max(tally_pixels))
          mask_loc = which(matrix(mask_label %in% sel, dim(temp)[1], dim(temp)[2]), arr.ind=TRUE)
          big_NA_mask[mask_loc] = 1
          # magimage(big_NA_mask)
          
          propane_mask_fix = propanePatchPix(
            image = med_patch$image, 
            mask = (edge_mask + big_NA_mask) == 1,
          )
          
          patch_mask = temp - propane_mask_fix
          
          patch = list()
          
          patch$image = propane_mask_fix
          patch$patch = patch_mask
          patch$inVar = load_invar$inVar
          patch$weight = load_invar$weight
          
          patch$image$keyvalues$EXTNAME = "image"
          patch$patch$keyvalues$EXTNAME = "patch"
          patch$inVar$keyvalues$EXTNAME = "inVar"
          patch$weight$keyvalues$EXTNAME = "weight"
          
          class(patch) = "Rfits_list"
          
          Rfits_write_all(
            data = patch, 
            filename = paste0(patch_stub, "patch", fstub)
          )
          return(NULL)
        }else{
          return(NULL)
        }
      }
      
      if(!is.null(parallel_type)){
        stopCluster(cl)
        registerDoSEQ()
      }else{
        stopImplicitCluster()
        registerDoSEQ()
      }
      gc()
    }
  }
}
do_RGB = function(input_args){
  
  cat("\n")
  message("## Making RGB image ##")
  cat("\n")

  VID = input_args$VID
  ref_dir = input_args$ref_dir
  RGB_dir = input_args$RGB_dir
  patch_dir = input_args$patch_dir
  cal_sky_info_save_dir = input_args$cal_sky_info_save_dir
  
  blue_filters = "F070W|F090W|F115W|F150W|F140M|F162M|F164N"
  green_filters = "F200W|F277W|F182M|F210M|F187N|F212N"
  red_filters = "F356W|F444W|F250M|F300M|F335M|F360M|F410M|F430M|F460M|F480M|F323N|F405N|F466N|F470N|F560W|F770W|F1000W|F1130W|F1280W|F1500W|F1800W|F2100W|F2550W"
  locut = 0.6
  hicut = 0.9999
  
  # cal_sky_info = fread(paste0(ref_dir, "/Pro1oF/cal_sky_info.csv"))
  cal_sky_info = fread(paste0(cal_sky_info_save_dir, "/cal_sky_info.csv"))
  vid_temp = VID
  unique_visits = grep(vid_temp, unique(cal_sky_info$VISIT_ID), value = T)
  
  for(VID in unique_visits){
    
    if(is.null(RGB_dir)){
      RGB_dir = paste0(ref_dir, "/RGB/", VID, "/")
      if(is.null(ref_dir)){
        stop('Please provide a parent directory to put the RGB folder')
      }else{
        dir.create(RGB_dir, showWarnings = F, recursive = T)
      }
    }
    
    file_list = list.files(patch_dir, 
                           pattern = glob2rx(paste0("*patch*", VID, "*short*fits")),
                           full.names = T)
    
    frame_info = Rfits_key_scan(filelist = file_list,
                                keylist = c("CRVAL1", "CRVAL2", "CD1_1", "CD1_2", "NAXIS1", "NAXIS2"))
    # temp_proj = Rwcs_keypass(CRVAL1 = mean(frame_info$CRVAL1),
    #                          CRVAL2 = mean(frame_info$CRVAL2),
    #                          CD1_1 = min(frame_info$CD1_1),
    #                          CD1_2 = min(frame_info$CD1_2),
    #                          CD2_1 = min(frame_info$CD1_2),
    #                          CD2_2 = -min(frame_info$CD1_1)
    # )
    temp_proj = propaneGenWCS(
      filelist = file_list, 
      rotation = 'get'
    )
    
    module_list = sapply(strsplit(file_list, "NRC"), function(x)(x[2]))
    
    if(length(unique(module_list))==2){
      temp_proj$NAXIS1 = 2.2 * max(frame_info$NAXIS1) #Modules in NIRCam always colinear
    }else{
      temp_proj$NAXIS1 = 1.2 * max(frame_info$NAXIS1)
    }
    temp_proj$NAXIS2 = 1.2 * max(frame_info$NAXIS1)
    temp_proj$CRPIX1 = temp_proj$NAXIS1/2.0
    temp_proj$CRPIX2 = temp_proj$NAXIS2/2.0
    temp_proj[is.na(temp_proj)] = NULL
    
    message("Making RGBs from")
    cat(file_list, sep="\n")
    blue_files = file_list[grepl(blue_filters, file_list)]
    green_files = file_list[grepl(green_filters, file_list)]
    red_files = file_list[grepl(red_filters, file_list)]
    
    if(length(red_files>0)){
      red_images = lapply(red_files, function(x){Rfits_read(x)$image[,]})
    }else{
      red_images = list(Rfits_create_image(matrix(0L, 
                                                  nrow=temp_proj$NAXIS1, 
                                                  ncol = temp_proj$NAXIS2), 
                                           keyvalues = temp_proj))
    }
    if(length(green_files>0)){
      green_images = lapply(green_files, function(x){Rfits_read(x)$image[,]})
    }else{
      green_images = list(Rfits_create_image(matrix(0L, 
                                                    nrow=temp_proj$NAXIS1, 
                                                    ncol = temp_proj$NAXIS2), 
                                             keyvalues = temp_proj))
    }
    if(length(blue_files>0)){
      blue_images = lapply(blue_files, function(x){Rfits_read(x)$image[,]})
    }else{
      blue_images = list(Rfits_create_image(matrix(0L, 
                                                   nrow=temp_proj$NAXIS1, 
                                                   ncol = temp_proj$NAXIS2), 
                                            keyvalues = temp_proj))
    }
    
    R_stack = propaneStackWarpInVar(red_images, keyvalues_out = temp_proj, magzero_in = 23.9, magzero_out = 23.9, cores=1)
    G_stack = propaneStackWarpInVar(green_images, keyvalues_out = temp_proj, magzero_in = 23.9, magzero_out = 23.9, cores=1)
    B_stack = propaneStackWarpInVar(blue_images, keyvalues_out = temp_proj, magzero_in = 23.9, magzero_out = 23.9, cores=1)
    
    temp = R_stack$image
    edge_mask = matrix(1L, nrow = dim(temp)[1], ncol = dim(temp)[2])
    rough_mask = is.na(temp$imDat)
    mask_label = as.matrix(imager::label(imager::as.cimg(rough_mask)))
    tally_pixels = tabulate(mask_label)
    sel = which(tally_pixels > 0)
    mask_loc = which(matrix(mask_label %in% sel, dim(temp)[1], dim(temp)[2]), arr.ind=TRUE)
    edge_mask[mask_loc] = 0L
    
    R_patch = propanePatchPix(R_stack$image[,], mask = edge_mask)
    G_patch = propanePatchPix(G_stack$image[,], mask = edge_mask)
    B_patch = propanePatchPix(B_stack$image[,], mask = edge_mask)
    
    Rfits_write_image(R_patch, paste0(RGB_dir, "/", VID, "_R.fits"))
    Rfits_write_image(G_patch, paste0(RGB_dir, "/", VID, "_G.fits"))
    Rfits_write_image(B_patch, paste0(RGB_dir, "/", VID, "_B.fits"))
    
    im_width = 12 #inches
    im_height = im_width * (temp_proj$NAXIS2 / temp_proj$NAXIS1)
    
    filestub = paste0(patch_dir, '/RGB_patch_image_',VID, "_all", "_clear.png")
    png(filename = filestub, width=im_width, height=im_height, 
             units='in', res=400, quality=100)
    par(mar=c(0,0,0,0), oma=rep(0,4))
    Rwcs_imageRGB(
      R = R_patch,
      G = G_patch,
      B = B_patch,
      locut=locut,
      hicut=hicut,
      type='quan',
      stretch = 'log',
      sparse=1,
      decorate=F
    )
    dev.off()
  }
}
do_wisp_reverse = function(input_args){
  
  cat("\n")
  message("## Reversing wisp correction ##")
  cat("\n")
  
  filelist_all = input_args$filelist ## raw CAL files - straight from the calibration pipeline
  VID = input_args$VID
  cores = input_args$cores_pro
  do_claws = input_args$additional_params$do_claws
  parallel_type = input_args$additional_params$parallel_type
  
  if(VID != ""){
    scan_wisp_rem = Rfits_key_scan(filelist = filelist_all, keylist = c("FILTER", "PROGRAM"))
    not_pid_idx = sapply(scan_wisp_rem$PROGRAM, function(x)grepl(x, VID, fixed = T)) ## make sure PID is not embedded in string of VID
    filelist = filelist_all[not_pid_idx]
  }else{
    filelist = filelist_all
  }
  ## stop edit 
  
  info = Rfits_key_scan(filelist = filelist,
                        keylist=c('DETECTOR', 'MODULE', 'FILTER', 'VID'), cores=1)
  
  if(do_claws){
    info_wisp = info[DETECTOR %in% c('NRCA1', 'NRCA2', 'NRCA3','NRCA4', 'NRCB1','NRCB2', 'NRCB3','NRCB4', 'MIRIMAGE'),] 
  }else{
    info_wisp = info[DETECTOR %in% c('NRCA3','NRCA4', 'NRCB3','NRCB4', 'MIRIMAGE'),] 
  }
  
  ## WISP remove reverseal for NIRCam (step 11)
  module_list = paste0("NRC", unique(info$MODULE))
  unique_visits = unique(info_wisp$VID)
  
  message("Reversing wisp correction on short wavelength detectors:")
  cat('Processing',dim(info_wisp)[1],'files\n')
  
  message("Showing <10 files")
  print(
    head(info_wisp[, c("stub", "DETECTOR", "MODULE")], 10)
  )
  message("...")
  
  if(is.null(parallel_type)){
    registerDoParallel(cores = cores)
  }else{
    cl <- makeCluster(spec = cores, type = parallel_type, outfile = "")
    registerDoParallel(cl)
  }
  
  temp = foreach(ii = 1:dim(info_wisp)[1], .errorhandling = "stop", .packages = c("Rfits"))%dopar%{
    ## copy original data to directory where we keep the wisps
    vid = paste0(info_wisp$VID[ii])
    modl = paste0("NRC", info_wisp$MODULE[ii])
    wisp_frame = Rfits_read(info_wisp$full[ii])
    if(!is.null(wisp_frame$SCI_ORIG)){
      Rfits_write_pix(data = wisp_frame$SCI_ORIG[,]$imDat, filename = info_wisp$full[ii], ext = 2) 
    }
    return(NULL)
  }
  
  if(!is.null(parallel_type)){
    stopCluster(cl)
    registerDoSEQ()
  }else{
    stopImplicitCluster()
    registerDoSEQ()
  }
  gc()
}

jp_env_numeric = function(name, default = NULL){
  value = Sys.getenv(name, unset = "")
  if(!nzchar(value)){
    return(default)
  }
  parsed = suppressWarnings(as.numeric(value))
  if(length(parsed) != 1 || is.na(parsed) || !is.finite(parsed)){
    warning("Ignoring invalid numeric env override ", name, "=", value)
    return(default)
  }
  parsed
}

wispFixer = function(wisp_im, ref_im,
                     source_threshold=0.95, #Threshold on reference image for definitely real sources
                     scale_threshold=0.95, #When considering the +ve ratio map pixels, quantile to define very blue things
                     sky_threshold=0.5, #Safe threshold to find the correct sky level
                     clip_threshold=0.997, #We avoid very bright pixels in the wisp template
                     sigma_hi=2,
                     sigma_lo=20,
                     poly=NULL,
                     cores=1){
  
  source_threshold = jp_env_numeric("JUMPROPE_WISP_SOURCE_THRESHOLD", source_threshold)
  scale_threshold = jp_env_numeric("JUMPROPE_WISP_SCALE_THRESHOLD", scale_threshold)
  sky_threshold = jp_env_numeric("JUMPROPE_WISP_SKY_THRESHOLD", sky_threshold)
  clip_threshold = jp_env_numeric("JUMPROPE_WISP_CLIP_THRESHOLD", clip_threshold)
  sigma_hi = jp_env_numeric("JUMPROPE_WISP_SIGMA_HI", sigma_hi)
  sigma_lo = jp_env_numeric("JUMPROPE_WISP_SIGMA_LO", sigma_lo)

  ref_im$imdat[is.infinite(ref_im$imdat)] = NA #remove infinities
  wisp_im$imDat[is.infinite(wisp_im$imDat)] = NA
  
  #Step 1
  ref_im_warp_untweak = propaneWarp(ref_im, keyvalues_out=wisp_im$keyvalues, cores=cores, direction = "forward")
  
  ## 1i Align ref to wisp_im using propaneTweak
  ## Use only 1 core in case resources run out
  ref_im_warp = propaneTweakImage(
    image_ref = wisp_im[,], image_pre_fix = ref_im_warp_untweak[,], 
    delta_max = c(2, 0.1), quan_cut = c(0.995, 0.9999),
    shift_int = F, quick = T, verbose = F, cores = 1 
  )$image_post_fix
  
  
  #Step X (not in paper, but put here for sky sub reasons)
  real_source = quantile(ref_im_warp$imDat, source_threshold, na.rm=TRUE)
  sky_level = quantile(wisp_im$imDat[ref_im_warp$imDat < real_source], sky_threshold, na.rm=TRUE)
  wisp_im$imDat = (wisp_im$imDat - sky_level)
  
  #Step 2i
  relflux = (wisp_im$imDat / ref_im_warp$imDat)
  
  #Step 2ii
  #real_source = quantile(ref_im_warp$imDat, source_threshold, na.rm=TRUE) paper location
  relflux = relflux[ref_im_warp$imDat > real_source] #just looks at real sources
  
  #step 2iii
  relflux = relflux[relflux > 0] #ignore -ve noise
  
  #Step 2iv
  scale = quantile(relflux, scale_threshold, na.rm=T) #find blue things
  
  #Step 3
  wisp_template = wisp_im$imDat - ref_im_warp$imDat*scale
  
  #Step 4
  wisp_template[wisp_template > quantile(wisp_template[wisp_template > 0], clip_threshold, na.rm=T)] = NA
  wisp_template[wisp_template < quantile(wisp_template[wisp_template < 0], 1 - clip_threshold, na.rm=T)] = NA
  
  #Step 5
  wisp_template = profoundImBlur(wisp_template, sigma=sigma_hi)
  
  #Step 6
  wisp_template[is.na(wisp_im$imDat) | is.na(ref_im_warp$imDat)] = NA
  wisp_template[wisp_template < 0] = NA
  
  if(!is.null(sigma_lo)){
    #Step 7
    wisp_template_lo = profoundImBlur(wisp_template, sigma=sigma_lo)
    
    #Step 8
    sel = which(is.na(wisp_template) | wisp_template_lo > wisp_template)
    wisp_template[sel] = wisp_template_lo[sel]
  }else{
    wisp_template[is.na(wisp_template)] = 0
  }
  
  if(!is.null(poly)){
    wisp_mask = profoundDrawMask(wisp_im$imDat, poly=poly, mode='apply')$mask
    # wisp_template = magmap(wisp_template * profoundImBlur(image = wisp_mask, sigma = 50), range = c(0,1))$map
    wisp_template[wisp_mask==0L] = 0
  }
  
  #Just make sure we don't create non-zero values where we have missing data
  #Not sure where that's better or worse?
  #wisp_template[is.na(wisp_im$imDat) | is.na(ref_im_warp$imDat)] = 0
  
  #Step 9
  wisp_im$imDat  = wisp_im$imDat - wisp_template + sky_level
  
  return(list(wisp_fix=wisp_im, wisp_template=wisp_template, ref_im_warp=ref_im_warp))
}

do_help = function(input_args){
  
  cat("\n")
  message("## Help ##")
  cat("\n")
  
  message("Author: Jordan C. J. D'Silva")
  message("Date: ", Sys.Date())
  
  message("\n")
  
  message(
    "Running zork: Rscript zork_process.R <VID, e.g., '2738|1176261001'> <FILT, e.g., 'F090W|F444W'> "
  )
  
  message("\n")
  
  message("It is advised to separate the files into organised directories to avoid unwanted clashes occurring during the sub-routines.")
  message("Recommended directory structure is, for example: ")
  message(
    'JP/
  ├─ Pro1oF/
  │  ├─ cal/
  │  ├─ cal_sky/
  │  ├─ cal_sky_renorm/
  │  ├─ cal_sky_info.csv
  ├─ sky_pro/
  │  ├─ sky_frames/
  │  ├─ sky_super/
  │  ├─ sky_info.csv
  ├─ InVar_Stacks/
  ├─ Median_Stacks/
  ├─ Patch_Stacks/
  ├─ dump/
  ├─ RGB/'
  )
  
  message("\n")
  
  message("Input arguments for each of the sub-routines in JP are as follows:")
  message(
    'input_args = list(
      filelist = <path to the cal files produced from stage2 of the calibration pipeline>, ## <-- vector of strings
      additional_params = additional_params, ## <-- extra 1/f settings, wisp removal settings, stacking settings as set in initialise_variables.R, list
      
      ref_dir = ref_dir, ## <-- Reference directory, where you want to put your JUMPROPE files, string
            
      Pro1oF_dir = Pro1oF_dir, ## <-- 1/f corrected file directory, string
      cal_sky_dir = cal_sky_dir, ## <-- Sky removed files directory, string
      cal_sky_renorm_dir = cal_sky_renorm_dir, ## <-- Sky removed and pedestal modified files directory, the input for making mosaics, string
      cal_sky_info_save_dir = cal_sky_info_save_dir, ## <-- Usually the parent directory of above cal stuff, directory to store a CSV file with info about the frames, string
      
      sky_frames_dir = sky_frames_dir, ## <-- sky frames from ProFound directory, string
      sky_super_dir = sky_super_dir, ## <-- super super, combined stack of sky files, directory, string
      sky_pro_dir = sky_pro_dir, ## <-- Usually the parent directory of above sky stuff to keep the sky things together, string

      invar_dir = invar_dir, ## <-- ProPane inverse variance stack directory, string
      median_dir = median_dir, ## <-- Median stack directory, string
      patch_dir = patch_dir, ## <-- Patched stack directory, string
      dump_dir = dump_dir, ## <-- Dump frames directory, save the warp fields from mosaicking, string
      
      RGB_dir = RGB_dir, ## <-- RGB image directory, string
      
      magzero = 23.9, ## <-- Magnitude zero-point for ProPane mosaics, 8.9/16.4/23.9 is Jy,milliJy/microJy, numeric
      
      VID = VID, ## <-- Program ID or visit ID, string, e.g., "1234567890"
      FILT = FILT, ## <-- Set of filters to process, string separated by "|", e.g., "F090W|F150W" to do those 2 filters
      
      do_NIRISS = do_NIRISS, ## <-- Process NIRISS, boolean
      do_MIRI = do_MIRI, ## <-- Process MIRI, boolean
      
      cores_pro = cores_pro, ## <-- Cores for processing, numeric
      cores_stack = cores_stack, ## <-- Cores for stacking with ProPane, numeric
      tasks_stack = tasks_stack, ## <-- Cores for parallel stacking jobs, numeric
  
      SIGMA_LO = NULL #keep blurring at wisp rem stage off by default, otherwise numeric, standard deviation of Gaussian kernel to blur derived wisp template
    )'
  )
  
  message("\n")
  
  message("Contents of initialise_variables.R for some extra parameters to use in JUMPROPE:")
  message(
    "additional_params = list(
    ## Keep trend data determines the aggressiveness of the 1/f. If nothing in this data frame, then default 1/f proceeds. 
    ## Default should be good for most blank fields.
    
    ## vlarge for big objects that fill frame e.g., VV191. Least aggressive 1/f.
    ID_vlarge = data.frame(
      VISIT_ID = c(
        2561001003 #<-- Put 10 digit VISITIDs here, e.g., 1176341001, 1176361001
      ),
      MODULE = c(
       'A'   #<-- Put 'A'/'B' here 
      )
    ),
    
    ## large for crowded fields or wispy fields e.g., SMACS Cluster Module B. Less aggressive 1/f.
    ID_large = data.frame(
      VISIT_ID = c(
        2561001003
      ),
      MODULE = c(
       'B' 
      )
    ),
    
    ## overwrite and use one 1/f setting for everything. 
    ## so you don't have to laboriously type out every single VISITID and MODULE combination :D
    ow_vlarge = FALSE,
    ow_large = FALSE,
    
    ## Claws removal mode
    ## I.e., perform 'wisp removal' algorithm on all NIRCam short wavelength detectors
    ## and not only wisp affected [A3,A4,B3,B4]
    do_claws = FALSE, 
    
    ## Path to reference astrometric catalogue - to make the ProPane stacks
    tweak_catalogue = NULL, ## NULL will have no internal tweak
    
    NAXIS_long = NULL, ## Size of the long pixel scales mosaic, keep NULL for default (3000 pixels) 
    NAXIS_short = NULL, ## Size of the short pixel scales mosaic, keep NULL for default (6000 pixels) 
    module_list = NULL, ## What modules should we stack, options are ('NRCA_short', 'NRCA_long', 'NRCB_short', 'NRCB_long', 'NIS', 'MIRIMAGE')
    
    parallel_type = NULL ## type options for makeCluster in parallel for stacking and wisp removal, type='PSOCK' might be more stable on Linux systems "
  )
}

## Helper functions to set up JP directories
make_directory_structure = function(){
  message("Should I make the directory structure for you? (T/F): ")
  make_dirs = readLines("stdin", n = 1)
  if(make_dirs == "T"){
    message("Where should I make the directory (supply directory or nothing): ")
    ref_dir = readLines("stdin", n=1)
    if(ref_dir==""){
      ref_dir = getwd()
      message("No user input. Making in current working directory.")
    }
    print(ref_dir)
    dir.create(paste0(ref_dir, "/Pro1oF/cal/"), recursive = T, showWarnings = F)
    dir.create(paste0(ref_dir, "/Pro1oF/cal_sky/"), recursive = T, showWarnings = F)
    dir.create(paste0(ref_dir, "/Pro1oF/cal_sky_renorm/"), recursive = T, showWarnings = F)
    dir.create(paste0(ref_dir, "/sky_pro/sky_frames/"), recursive = T, showWarnings = F)
    dir.create(paste0(ref_dir, "/sky_pro/sky_super/"), recursive = T, showWarnings = F)
    dir.create(paste0(ref_dir, "/dump/"), recursive = T, showWarnings = F)
    dir.create(paste0(ref_dir, "/InVar_Stacks/"), recursive = T, showWarnings = F)
    dir.create(paste0(ref_dir, "/Median_Stacks/"), recursive = T, showWarnings = F)
    dir.create(paste0(ref_dir, "/Patch_Stacks/"), recursive = T, showWarnings = F)
    return(ref_dir)
  }else if(make_dirs == "F"){
    message("Continuing...")
    message("Where is the reference directory (supply directory or nothing): ")
    ref_dir = readLines("stdin", n=1)
    if(ref_dir==""){
      ref_dir = getwd()
      message("No user input. Assuming everything in current working directory.")
    }
    return(ref_dir)
  }else{
    message("Must be 'T/F'. Please try again:")
    make_directory_structure()
  }
}
load_raw_files = function(dir_raw){
  
  cal_files = c(
    list.files(dir_raw, pattern = ".fits$", full.names = T, recursive = T),
    NULL
  )
  
  return(cal_files)
}


do_cleanup = function(input_args, force = FALSE){

  cat("\n")
  message("## Running Cleanup ##")
  cat("\n")

  do_cleanup_flag = jp_truthy(Sys.getenv("JUMPROPE_CLEANUP"))
  if(!do_cleanup_flag && !force){
    message("JUMPROPE_CLEANUP is not TRUE. Skipping cleanup.")
    return(invisible(NULL))
  }


  ## ── staged cleanup: verify staged final products, copy to persistent storage, wipe stage ──
  do_ram_mode = jp_truthy(Sys.getenv("JUMPROPE_RAM_MODE"))
  do_staging_mode = isTRUE(input_args$staging_mode) || jp_truthy(Sys.getenv("JUMPROPE_STAGING_MODE"))
  if(do_ram_mode || do_staging_mode){
    pro1of_cal_dir = input_args$Pro1oF_dir
    pro1of_cal_persistent_dir = input_args$pro1of_cal_persistent_dir
    cal_sky_renorm_dir = input_args$cal_sky_renorm_dir
    cal_sky_renorm_persistent_dir = input_args$cal_sky_renorm_persistent_dir
    current_vid = input_args$VID
    staging_root = input_args$staging_root
    persistent_root = if(!is.null(cal_sky_renorm_persistent_dir) && nzchar(cal_sky_renorm_persistent_dir)) dirname(dirname(cal_sky_renorm_persistent_dir)) else ""
    cleanup_args = input_args
    if(isTRUE(input_args$cleanup_all_filters)){
      cleanup_args$FILT = ""
    }
    if(is.null(staging_root) || !nzchar(staging_root)){
      staging_root = if(do_ram_mode) "/dev/shm/jumprope_work" else input_args$ref_dir
    }

    state = jp_expected_renorm_state(cleanup_args, renorm_dir = cal_sky_renorm_dir)
    if(state$reason == "no_inputs"){
      message("No staged outputs matched VID ", current_vid, ".")
      return(invisible(NULL))
    }

    if(!state$complete && !force){
      if(state$reason == "missing_or_invalid"){
        message("Staged cal_sky_renorm incomplete for VID ", current_vid, ". Retaining staging root: ", staging_root)
      }else if(state$reason == "missing_sci_orig"){
        message("Staged short-wave renorm products for VID ", current_vid, " are missing SCI_ORIG. Retaining staging root: ", staging_root)
      }
      return(invisible(NULL))
    }

    if(is.null(cal_sky_renorm_persistent_dir) || !nzchar(cal_sky_renorm_persistent_dir)){
      stop("Cleanup requires cal_sky_renorm_persistent_dir when staging mode is enabled.")
    }

    if(!is.null(pro1of_cal_persistent_dir) && nzchar(pro1of_cal_persistent_dir)){
      dir.create(pro1of_cal_persistent_dir, recursive = TRUE, showWarnings = FALSE)
      cal_to_copy = list.files(pro1of_cal_dir, pattern = "\\.fits$", full.names = TRUE)
      if(length(cal_to_copy) > 0){
        message("VID ", current_vid, " complete. Copying Pro1oF cal -> ", pro1of_cal_persistent_dir)
        cal_copy_targets = file.path(pro1of_cal_persistent_dir, basename(cal_to_copy))
        cal_copied = vapply(seq_along(cal_to_copy), function(i){
          copy_fits_with_validation(cal_to_copy[[i]], cal_copy_targets[[i]], overwrite = TRUE, required_ext = "SCI")
        }, logical(1))
        message(sprintf("  Copied %d / %d cal files to persistent storage", sum(cal_copied), length(cal_copied)))
      }
    }

    dir.create(cal_sky_renorm_persistent_dir, recursive = TRUE, showWarnings = FALSE)
    if(force && !state$complete){
      message("Force cleanup requested. Copying any staged cal_sky_renorm products before wiping staging.")
      to_copy = list.files(cal_sky_renorm_dir, pattern = "\\.fits$", full.names = TRUE)
    }else{
      message("VID ", current_vid, " complete. Copying cal_sky_renorm -> ", cal_sky_renorm_persistent_dir)
      to_copy = state$expected_files
    }
    copy_targets = file.path(cal_sky_renorm_persistent_dir, basename(to_copy))
    copied = vapply(seq_along(to_copy), function(i){
      copy_fits_with_validation(to_copy[[i]], copy_targets[[i]], overwrite = TRUE, required_ext = "SCI")
    }, logical(1))
    message(sprintf("  Copied %d / %d files to persistent storage", sum(copied), length(copied)))

    message("Cleaning staged intermediates for VID ", current_vid)
    jp_cleanup_vid_intermediates(staging_root, current_vid, remove_final_products = TRUE)
    if(nzchar(persistent_root)){
      message("Cleaning persistent intermediates for VID ", current_vid)
      jp_cleanup_vid_intermediates(persistent_root, current_vid, remove_final_products = FALSE, remove_cal_products = FALSE, remove_cal_sky_products = TRUE)
    }

    message("Wiping staging root ", staging_root)
    if(dir.exists(staging_root)){
      unlink(staging_root, recursive = TRUE)
    }
    message("Staging root wiped.")

    if(do_ram_mode){
      dump_dir_stub = input_args$dump_dir
      if(nzchar(current_vid)){
        vid_dump = paste0(dump_dir_stub, current_vid)
        if(dir.exists(vid_dump)){
          unlink(vid_dump, recursive = TRUE)
          message("  Wiped disk dump dir: ", vid_dump)
        }
      }
      disk_dump_dir = paste0(Sys.getenv("JUMPROPE_REF_DIR"), "/dump/")
      if(dir.exists(disk_dump_dir)){
        unlink(disk_dump_dir, recursive = TRUE)
      }
      message("Disk dump dirs wiped — cleanup complete.")
    }
    return(invisible(NULL))
  }
  ## ── end RAM mode cleanup branch ──



  ref_dir            = input_args$ref_dir
  cal_sky_renorm_dir = input_args$cal_sky_renorm_dir
  cal_sky_dir        = input_args$cal_sky_dir
  sky_frames_dir     = input_args$sky_frames_dir
  invar_dir          = input_args$invar_dir
  median_dir         = input_args$median_dir
  patch_dir          = input_args$patch_dir
  dump_dir           = input_args$dump_dir
  additional_params  = input_args$additional_params
  do_claws           = additional_params$do_claws

  # Short-wave detectors targeted by wisp removal
  short_detectors = jp_short_detectors(additional_params)

  # Discover all VIDs present in median_dir (pattern: med_{VID}_{FILTER}_{MODULE}.fits)
  med_files = list.files(median_dir, pattern = "^med_[0-9]+_.*\\.fits$", full.names = FALSE)
  if(length(med_files) == 0){
    message("No median stacks found — nothing to clean up.")
    return(invisible(NULL))
  }
  all_vids = unique(gsub("^med_([0-9]+)_.*$", "\\1", med_files))
  message(paste0("Found ", length(all_vids), " VID(s) with median stacks: ", paste(all_vids, collapse = ", ")))

  for(vid in all_vids){

    message(paste0("\n--- Checking VID ", vid, " ---"))

    # Safeguard 1: cal_sky_renorm files must exist for this VID (steps 1-6 complete)
    renorm_files = list.files(cal_sky_renorm_dir,
                              pattern = glob2rx(paste0("*", vid, "*.fits")),
                              full.names = TRUE)
    if(length(renorm_files) == 0){
      message(paste0("VID ", vid, ": no cal_sky_renorm files — skipping"))
      next
    }
    message(paste0("VID ", vid, ": ", length(renorm_files), " cal_sky_renorm files found"))

    # Safeguard 2: one representative short-wave file per detector must carry SCI_ORIG
    # (confirms wisp removal was applied AND re-propagated into final products)
    wisp_check_files = character(0)
    for(det in short_detectors){
      det_files = renorm_files[grepl(paste0("_", det, "_"), renorm_files)]
      if(length(det_files) > 0){
        wisp_check_files = c(wisp_check_files, det_files[1])
      }
    }

    if(length(wisp_check_files) == 0){
      # No short-wave files (NIRISS/MIRI-only VID) — no wisp removal expected, allow cleanup
      message(paste0("VID ", vid, ": no short-wave files — assuming NIRISS/MIRI-only, skipping wisp check"))
      wisp_done = TRUE
    }else{
      wisp_done = all(sapply(wisp_check_files, function(f){
        "SCI_ORIG" %in% na.omit(Rfits_extnames(f))
      }))
    }

    if(!wisp_done){
      message(paste0("VID ", vid, ": SCI_ORIG missing in one or more short-wave renorm files — wisp removal not fully propagated, skipping cleanup"))
      next
    }
    message(paste0("VID ", vid, ": wisp removal confirmed — cleaning up intermediates"))

    # Remove dump/{vid}/ tree
    dump_vid = file.path(dump_dir, vid)
    if(dir.exists(dump_vid)){
      message(paste0("  Removing ", dump_vid))
      unlink(dump_vid, recursive = TRUE)
    }

    # Remove InVar stack files for this VID
    del_invar = list.files(invar_dir, pattern = glob2rx(paste0("stack_", vid, "_*.fits")), full.names = TRUE)
    if(length(del_invar) > 0){
      message(paste0("  Removing ", length(del_invar), " InVar stack files"))
      file.remove(del_invar)
    }

    # Remove Median stack files for this VID
    del_median = list.files(median_dir, pattern = glob2rx(paste0("med_", vid, "_*.fits")), full.names = TRUE)
    if(length(del_median) > 0){
      message(paste0("  Removing ", length(del_median), " Median stack files"))
      file.remove(del_median)
    }

    # Remove Patch stack files for this VID (may not exist)
    del_patch = list.files(patch_dir, pattern = glob2rx(paste0("patch_", vid, "_*.fits")), full.names = TRUE)
    if(length(del_patch) > 0){
      message(paste0("  Removing ", length(del_patch), " Patch stack files"))
      file.remove(del_patch)
    }

    # Remove cal_sky/ files for this VID (VID embedded in JWST filename)
    del_cal_sky = list.files(cal_sky_dir, pattern = glob2rx(paste0("*", vid, "*.fits")), full.names = TRUE)
    if(length(del_cal_sky) > 0){
      message(paste0("  Removing ", length(del_cal_sky), " cal_sky files"))
      file.remove(del_cal_sky)
    }

    # Remove sky_frames/ files for this VID (VID embedded in JWST filename)
    del_sky_frames = list.files(sky_frames_dir, pattern = glob2rx(paste0("*", vid, "*.fits")), full.names = TRUE)
    if(length(del_sky_frames) > 0){
      message(paste0("  Removing ", length(del_sky_frames), " sky_frames files"))
      file.remove(del_sky_frames)
    }

    message(paste0("VID ", vid, ": cleanup complete"))
  }

  message("\nCleanup sweep finished.")
  return(invisible(NULL))
}

jp_promote_cal_only = function(input_args){
  pro1of_cal_dir = input_args$Pro1oF_dir
  pro1of_cal_persistent_dir = input_args$pro1of_cal_persistent_dir
  current_vid = input_args$VID
  staging_root = input_args$staging_root

  if(is.null(pro1of_cal_persistent_dir) || !nzchar(pro1of_cal_persistent_dir)){
    stop("Cal-only promotion requires pro1of_cal_persistent_dir.")
  }

  dir.create(pro1of_cal_persistent_dir, recursive = TRUE, showWarnings = FALSE)
  cal_to_copy = list.files(pro1of_cal_dir, pattern = "\\.fits$", full.names = TRUE)
  if(length(cal_to_copy) == 0){
    message("No staged Pro1oF cal files found for VID ", current_vid, ".")
    return(invisible(NULL))
  }

  message("VID ", current_vid, " backfill complete. Copying Pro1oF cal -> ", pro1of_cal_persistent_dir)
  cal_copy_targets = file.path(pro1of_cal_persistent_dir, basename(cal_to_copy))
  cal_copied = vapply(seq_along(cal_to_copy), function(i){
    copy_fits_with_validation(cal_to_copy[[i]], cal_copy_targets[[i]], overwrite = TRUE, required_ext = "SCI")
  }, logical(1))
  message(sprintf("  Copied %d / %d cal files to persistent storage", sum(cal_copied), length(cal_copied)))

  if(!is.null(staging_root) && nzchar(staging_root) && dir.exists(staging_root)){
    message("Wiping staging root ", staging_root)
    unlink(staging_root, recursive = TRUE)
    message("Staging root wiped.")
  }

  invisible(NULL)
}
