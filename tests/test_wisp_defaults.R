## [nep-miri] Run from the repository root: Rscript tests/test_wisp_defaults.R
## Exercise the actual driver option resolution before file IO and isolate the
## clipping step with identity warp/blur doubles. Real-frame equivalence is a
## separate release check against the cached 12529 templates.
env <- new.env(parent=globalenv())
for(e in parse("PROCESS/all_codes_process.R")) {
  if(is.call(e) && length(e)>=3L && is.symbol(e[[2]]) &&
     as.character(e[[2]]) %in% c("do_wisp_rem", "wispFixer")) eval(e, env)
}
defaults <- formals(env$wispFixer)
stopifnot(identical(defaults$source_threshold, .95),
          identical(defaults$scale_threshold, .95),
          identical(defaults$sky_threshold, .4),
          identical(defaults$clip_threshold, 1),
          identical(defaults$sigma_hi, .5), is.null(defaults$sigma_lo))

env$load_files <- function(...) {
  caller <- parent.frame()
  env$captured <- list(sigma_lo=get("SIGMA_LO", caller), args=get("wisp_args", caller))
  stop(structure(list(message="Captured before file IO", call=NULL),
                 class=c("wisp_capture", "error", "condition")))
}
resolve <- function(params=NULL, legacy=40, json="") {
  old <- Sys.getenv("JUMPROPE_WISP_PARAMS", unset=NA_character_)
  on.exit(if(is.na(old)) Sys.unsetenv("JUMPROPE_WISP_PARAMS") else
          Sys.setenv(JUMPROPE_WISP_PARAMS=old), add=TRUE)
  Sys.setenv(JUMPROPE_WISP_PARAMS=json)
  env$captured <- NULL
  input <- list(filelist=character(), VID="", median_dir=tempdir(), cores_pro=1,
                SIGMA_LO=legacy, additional_params=list(skip_completed_files=FALSE,
                  parallel_type="PSOCK", wisp_params=params))
  tryCatch(env$do_wisp_rem(input), wisp_capture=function(e) NULL)
  stopifnot(!is.null(env$captured))
  env$captured
}
selected <- list(sky_threshold=.4, source_threshold=.95, scale_threshold=.95,
                 clip_threshold=1, sigma_hi=.5, sigma_lo=NULL)
resolved <- resolve(selected)
stopifnot(is.null(resolved$sigma_lo), !"sigma_lo" %in% names(resolved$args),
          identical(resolved$args$clip_threshold, 1), identical(resolved$args$sigma_hi, .5))
stopifnot(is.null(resolve(json='{"clip_threshold":1,"sigma_hi":0.5,"sigma_lo":null}')$sigma_lo))
stopifnot(identical(resolve(list(sigma_hi=.5))$sigma_lo, 40),
          identical(resolve(list(sigma_lo=20))$sigma_lo, 20),
          is.null(resolve(legacy=NULL)$sigma_lo))

`[.wisp_test_image` <- function(x, i, j, ...) x$imDat
image <- function(data) structure(list(imDat=data, keyvalues=list()), class="wisp_test_image")
ref <- image(matrix(seq_len(1024)/1024, 32, 32))
before <- 2*ref$imDat
before[1,1] <- before[1,1]+100
before[2,2] <- NA_real_
env$propaneWarp <- function(x, ...) x
env$propaneTweakImage <- function(...) list(image_post_fix=ref)
env$profoundImBlur <- function(image, sigma) image
unclipped <- env$wispFixer(image(before), ref)
clipped <- env$wispFixer(image(before), ref, clip_threshold=.997)
stopifnot(unclipped$wisp_template[1,1]>90, clipped$wisp_template[1,1]==0,
          unclipped$wisp_template[2,2]==0, all(is.finite(unclipped$wisp_template)),
          max(abs(unclipped$wisp_fix$imDat+unclipped$wisp_template-before), na.rm=TRUE)<1e-10)
cat("PASS: stable defaults, explicit R/JSON null override, legacy/numeric overrides, unclipped peak and subtraction identity\n")
