## Regression tests for the fixes in CHANGES.md that do not need JWST data or ProPane/ProFound.
## Needs Rfits, data.table, foreach. Run from the repository root:  Rscript tests/test_fixes.R
suppressMessages({library(Rfits); library(data.table); library(foreach)})

## Load the function definitions without running the config.R source() line
env = new.env(parent = globalenv())
for(e in parse("PROCESS/all_codes_process.R")){
  if(is.call(e) && identical(e[[1]], as.name("=")) && is.symbol(e[[2]])) eval(e, env)
}
check = function(ok, what){ if(!isTRUE(ok)) stop("FAILED: ", what); cat("ok  ", what, "\n") }

## vid_match: several VIDs, prefixes, no mid-string matches
v = c(1345001001, 1345001002, 2736001001, 12345001001)
check(identical(env$vid_match(v, "1345001001|2736"), c(TRUE, FALSE, TRUE, FALSE)), "vid_match 'A|B' and PID prefix")
check(all(env$vid_match(v, "")), "vid_match empty VID selects all")
check(!any(env$vid_match(v, "2345001001")), "vid_match does not match inside another visit ID")

## band_of: NIRISS CLEAR + pupil band, NIRCam pupil-wheel filters, normal filters, MIRI (no PUPIL)
check(identical(env$band_of(c("CLEAR", "F277W", "F444W", "F150W2", "F200W", "GR150R", "F770W"),
                            c("F150W", "CLEARP", "F405N", "F162M", "CLEAR", "F150W", NA)),
                c("F150W", "F277W", "F405N", "F162M", "F200W", "F150W", "F770W")), "band_of")
check(identical(env$is_imaging(c("NRC_IMAGE", "NIS_WFSS", "NIS_IMAGE", "MIR_IMAGE", NA, "NRS_FIXEDSLIT")),
                c(TRUE, FALSE, TRUE, TRUE, TRUE, FALSE)), "is_imaging")

## run_tag and per-run bookkeeping files
ia = list(VID = "1345001001", sky_pro_dir = "/x/sky_pro/", sky_super_dir = tempfile(), cal_sky_info_save_dir = "/x/Pro1oF/")
check(env$sky_info_file(ia) == "/x/sky_pro//sky_info_1345001001.csv", "per-VID sky_info file")
check(env$cal_sky_info_file(ia) == "/x/Pro1oF//cal_sky_info_1345001001.csv", "per-VID cal_sky_info file")
check(grepl("/1345001001/$", env$super_sky_dir(ia)) && dir.exists(env$super_sky_dir(ia)), "per-VID super sky directory")
ia$VID = ""
check(env$sky_info_file(ia) == "/x/sky_pro//sky_info.csv" && env$cal_sky_info_file(ia) == "/x/Pro1oF//cal_sky_info.csv",
      "VID '' keeps the original file names")
check(nchar(env$run_tag(paste(1345001001 + 0:999, collapse = "|"))) <= 60, "long VID lists give a short tag")

## scan_frames on real FITS headers: VID, band, imaging, and file order kept
dir = tempfile(); dir.create(dir)
mk = function(name, keys){
  f = file.path(dir, name); Rfits_write_image(matrix(1, 4, 4), f)
  for(k in names(keys)) Rfits_write_key(f, keyname = k, keyvalue = keys[[k]], ext = 1)
  f
}
f1 = mk("jw01345001001_02101_00001_nis_cal.fits", list(VISIT_ID = "01345001001", FILTER = "CLEAR", PUPIL = "F150W", EXP_TYPE = "NIS_IMAGE"))
f2 = mk("jw01345001001_02101_00002_nis_cal.fits", list(VISIT_ID = "01345001001", FILTER = "GR150R", PUPIL = "F150W", EXP_TYPE = "NIS_WFSS"))
f3 = mk("jw01345001001_02101_00003_nis_cal.fits", list(VISIT_ID = "01345001001", FILTER = "F277W", PUPIL = "CLEARP", EXP_TYPE = "NIS_IMAGE"))
f4 = mk("jw02736001001_02101_00001_nis_cal.fits", list(VISIT_ID = "02736001001", FILTER = "CLEAR", PUPIL = "F200W", EXP_TYPE = "NIS_IMAGE"))
fl = c(f1, f2, f3, f4)
check(identical(env$scan_frames(fl, "1345001001", ""), c(f1, f3)), "scan_frames keeps imaging frames of the VID only")
check(identical(env$scan_frames(fl, "1345001001|2736001001", "F150W|F200W"), c(f1, f4)), "scan_frames selects NIRISS bands from PUPIL")
check(identical(env$scan_frames(fl, "1345001001", "CLEAR"), character(0)), "NIRISS frames no longer match 'CLEAR'")

## jwst >= 3 DQ: integer64 -> numeric matrix (the inline fix)
temp_mask = bit64::as.integer64(c(0, 1, 3, 4294967295)); dim(temp_mask) = c(2, 2)
temp_mask = array(as.numeric(temp_mask), dim = dim(temp_mask))
check(is.matrix(temp_mask) && is.numeric(temp_mask) && identical(c(temp_mask %% 2 == 1), c(FALSE, TRUE, TRUE, TRUE)), "integer64 DQ conversion")

## wispFixer: requested defaults, and the fixes, with identity stand-ins for the ProPane/ProFound calls
wf = formals(env$wispFixer)
check(identical(c(wf$source_threshold, wf$scale_threshold, wf$sky_threshold, wf$clip_threshold, wf$sigma_hi, wf$sigma_lo),
                c(0.95, 0.95, 0.5, 0.9999, 2, 2)), "wispFixer defaults 0.95/0.95/0.5/0.9999/2/2")
assign("propaneWarp", function(x, ...) x, envir = env)
assign("propaneTweakImage", function(image_ref, image_pre_fix, ...) list(image_post_fix = image_pre_fix), envir = env)
assign("profoundImBlur", function(image, sigma) image, envir = env)
set.seed(1)
sw = matrix(rnorm(100^2, 1, 0.1), 100); sw[40:60, 40:60] = sw[40:60, 40:60] + 2; sw[5, 5] = NA
lw = matrix(rnorm(100^2, 0, 0.1), 100); lw[10:12, 10:12] = 50
kv = list(NAXIS1 = 100, NAXIS2 = 100)
wisp = Rfits_create_image(sw, keyvalues = kv); ref = Rfits_create_image(lw, keyvalues = kv)
out = env$wispFixer(wisp, ref)
ok = is.finite(sw)
check(!anyNA(out$wisp_template), "low-pass fill leaves no NA template pixels")
check(max(abs((out$wisp_fix$imDat + out$wisp_template - sw)[ok])) < 1e-10, "corrected = original - template")
out1 = env$wispFixer(Rfits_create_image(abs(sw) + 10, keyvalues = kv), ref, clip_threshold = 0.9999)
check(!anyNA(out1$wisp_template), "clipping guard with an empty negative tail")

## do_wisp_rem settings: wisp_params from initialise_variables.R, explicit NULL, unknown names rejected
assign("load_files", function(...) stop("captured"), envir = env)
settings = function(params, SIGMA_LO = NULL){
  input = list(filelist = character(), VID = "", median_dir = tempdir(), cores_pro = 1, SIGMA_LO = SIGMA_LO,
               additional_params = list(skip_completed_files = FALSE, parallel_type = NULL, wisp_params = params))
  msg = capture.output(r <- tryCatch(env$do_wisp_rem(input), error = function(e) conditionMessage(e)), type = "message")
  list(result = r, msg = paste(msg, collapse = "\n"))
}
source("PROCESS/initialise_variables.R", local = TRUE)
p = initialise_params()$additional_params$wisp_params
s = settings(p)
check(s$result == "captured" && grepl("clip_threshold=0.9999", s$msg) && grepl("sigma_hi=2", s$msg) && grepl("sigma_lo=2", s$msg),
      "initialise_variables.R wisp_params reach do_wisp_rem")
check(grepl("sigma_lo=NULL", settings(list(sigma_lo = NULL))$msg), "explicit sigma_lo = NULL turns the low-pass off")
check(grepl("Unknown wisp_params", settings(list(method = "nmf"))$result), "unknown wisp_params are rejected")
check(isTRUE(initialise_params()$additional_params$make_stacks), "make_stacks defaults to TRUE (Jordan's behaviour)")

cat("\nAll tests passed\n")
