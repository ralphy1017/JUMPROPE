## Control-flow test of PROCESS/run_all_process.R with the processing stages replaced by recorders.
## Needs foreach and doParallel. Run from the repository root:  Rscript tests/test_run_all.R
check = function(ok, what){ if(!isTRUE(ok)) stop("FAILED: ", what); cat("ok  ", what, "\n") }
suppressMessages({library(foreach); library(doParallel)})

run = function(args, env_vars = list(), make_stacks = TRUE, fail_vid = NULL, files = NULL){
  env = new.env(parent = globalenv())
  for(e in parse("PROCESS/run_all_process.R")){
    if(is.call(e) && identical(e[[1]], as.name("=")) && is.symbol(e[[2]])) eval(e, env)
  }
  log = character(0)
  rec = function(name){ force(name); function(input_args){
    if(!is.null(fail_vid) && input_args$VID == fail_vid && name == "do_super_sky") stop("boom")
    log <<- c(log, paste(input_args$VID, name, input_args$FILT))
  }}
  for(f in c("do_1of", "do_cal_process", "do_regen_sky_info", "do_super_sky", "do_apply_super_sky",
             "do_modify_pedestal", "do_cal_sky_info", "do_gen_stack", "do_wisp_rem", "do_patch", "do_RGB")){
    assign(f, rec(f), envir = env)
  }
  if(is.null(files)) files = c("jw01345001001_x_nrca1_cal.fits", "jw01345001001_x_nrcalong_cal.fits",
                               "jw02736001001_x_nrcb3_cal.fits", "jw02736001001_x_nrcblong_cal.fits")
  assign("load_files", function(input_args, which_module){
    f = files[grepl(input_args$VID, files)]
    if(input_args$do_NIRISS) f = f[grepl("_nis_", f)] else if(input_args$do_MIRI) f = f[grepl("_mirimage_", f)] else f = f[grepl("_nrc", f)]
    if(input_args$FILT == "") return(f)
    if(grepl("F444W", input_args$FILT)) return(f[grepl("long", f)])
    f[!grepl("long", f)]
  }, envir = env)
  assign("load_raw_files", function(dir_raw) files, envir = env)
  assign("create_directory_structure", function(ref_dir) ref_dir, envir = env)
  assign("initialise_params", function() list(additional_params = list(make_stacks = make_stacks, parallel_type = NULL)), envir = env)
  assign("commandArgs", function(trailingOnly = TRUE) args, envir = env)
  status = 0
  assign("quit", function(status = 0, ...) status <<- status, envir = env)
  vars = modifyList(list(JUMPROPE_RAW_DIR = "/raw", JUMPROPE_REF_DIR = tempdir(), JUMPROPE_do_NIRISS = "F", JUMPROPE_do_MIRI = "F",
                         JUMPROPE_cores_pro = "1", JUMPROPE_cores_stack = "1", JUMPROPE_tasks_stack = "1"), env_vars)
  do.call(Sys.setenv, vars)
  suppressMessages(env$main())
  list(log = log, status = status)
}

## NIRCam, two VIDs: each processed on its own, LW first, then wisp + SW, then patch/RGB
r = run("1345001001|2736001001")
v1 = r$log[startsWith(r$log, "1345001001 ")]
v2 = r$log[startsWith(r$log, "2736001001 ")]
check(length(v1) > 0 && length(v2) > 0, "both VIDs of 'A|B' are processed (ifelse bug)")
check(!any(grepl("\\|", sub(" .*", "", r$log))), "each VID runs on its own")
check(which(v1 == "1345001001 do_gen_stack F250M|F277W|F300M|F322W2|F323N|F335M|F356W|F360M|F405N|F410M|F430M|F444W|F460M|F466N|F470N|F480M") <
      which(startsWith(v1, "1345001001 do_wisp_rem")), "LW stacks are made before wisp removal")
check(any(grepl("do_1of F070W", v1)) && any(grepl("do_RGB $", v1)), "SW pass after wisp removal, then patch/RGB")
check(r$status == 0, "exit status 0 when all VIDs succeed")

## make_stacks = FALSE: only the LW stacks (wisp reference), no SW stacks, patch or RGB
r = run("1345001001", make_stacks = FALSE)
check(sum(grepl("do_gen_stack", r$log)) == 1 && !any(grepl("do_patch|do_RGB", r$log)), "make_stacks = FALSE")

## A failing VID does not stop the others; failure is reported with a non-zero exit status
r = run("1345001001|2736001001", fail_vid = "1345001001")
check(any(grepl("^2736001001 do_RGB", r$log)) && r$status == 1, "one failing VID does not stop the rest")

## NIRISS / MIRI: no NIRCam LW filter list and no forced 'CLEAR'
nis = c("jw01345001001_x_nis_cal.fits")
r = run("1345001001", env_vars = list(JUMPROPE_do_NIRISS = "T"), files = nis)
check(any(r$log == "1345001001 do_1of ") && any(r$log == "1345001001 do_patch "), "NIRISS processes all bands (FILT '')")
check(!any(grepl("do_wisp_rem", r$log)), "no wisp removal for NIRISS")
r = run("1345001001", env_vars = list(JUMPROPE_do_NIRISS = "F", JUMPROPE_do_MIRI = "T"), files = c("jw01345001001_x_mirimage_cal.fits"))
check(any(r$log == "1345001001 do_1of "), "MIRI processes all filters (was given the NIRCam LW list)")

## An SW-only selection skips the LW chain cleanly and still runs wisp removal + SW
r = run("1345001001", env_vars = list(JUMPROPE_do_MIRI = "F"), files = c("jw01345001001_x_nrca3_cal.fits"))
check(!any(grepl("do_super_sky F250M", r$log)) && any(grepl("do_wisp_rem", r$log)), "no LW frames: LW chain skipped")

cat("\nAll tests passed\n")
