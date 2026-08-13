source("/data7/rzi/PEARLSplus/JUMPROPE/original/JUMPROPE/config.R")
source("/data7/rzi/PEARLSplus/JUMPROPE/original/JUMPROPE/PROCESS/all_codes_process.R")

raw_dir <- Sys.getenv(
  "JUMPROPE_RAW_DIR",
  "/data7/rzi/PEARLSplus/JUMPROPE/tests/original_2514132_20260813/raw_cal"
)
ref_dir <- Sys.getenv("JUMPROPE_REF_DIR", "/tmp/jro2514132")

dir.create(ref_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(ref_dir, "Pro1oF", "cal"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(ref_dir, "Pro1oF", "cal_sky"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(ref_dir, "Pro1oF", "cal_sky_renorm"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(ref_dir, "sky_pro", "sky_frames"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(ref_dir, "sky_pro", "sky_super"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(ref_dir, "InVar_Stacks"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(ref_dir, "Median_Stacks"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(ref_dir, "Patch_Stacks"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(ref_dir, "dump"), recursive = TRUE, showWarnings = FALSE)

additional_params <<- list(
  parallel_type = NULL,
  skip_completed_files = FALSE,
  do_claws = FALSE,
  ID_large = data.frame(VISIT_ID = character(0), MODULE = character(0)),
  ID_vlarge = data.frame(VISIT_ID = character(0), MODULE = character(0))
)

build_args <- function(filt) {
  list(
    filelist = load_raw_files(raw_dir),
    additional_params = additional_params,
    ref_dir = ref_dir,
    Pro1oF_dir = file.path(ref_dir, "Pro1oF", "cal"),
    cal_sky_dir = file.path(ref_dir, "Pro1oF", "cal_sky"),
    cal_sky_renorm_dir = file.path(ref_dir, "Pro1oF", "cal_sky_renorm"),
    cal_sky_info_save_dir = file.path(ref_dir, "Pro1oF"),
    sky_frames_dir = file.path(ref_dir, "sky_pro", "sky_frames"),
    sky_super_dir = file.path(ref_dir, "sky_pro", "sky_super"),
    sky_pro_dir = file.path(ref_dir, "sky_pro"),
    invar_dir = file.path(ref_dir, "InVar_Stacks"),
    median_dir = file.path(ref_dir, "Median_Stacks"),
    patch_dir = file.path(ref_dir, "Patch_Stacks"),
    dump_dir = file.path(ref_dir, "dump"),
    magzero = 23.9,
    VID = "2514132",
    FILT = filt,
    do_NIRISS = FALSE,
    do_MIRI = FALSE,
    cores_pro = 1L,
    cores_stack = 1L,
    tasks_stack = 1L,
    SIGMA_LO = NULL
  )
}

run_round <- function(input_args) {
  do_1of(input_args)
  do_cal_process(input_args)
  do_regen_sky_info(input_args)
  do_super_sky(input_args)
  do_apply_super_sky(input_args)
  do_modify_pedestal(input_args)
  do_cal_sky_info(input_args)
  do_gen_stack(input_args)
}

long_filters <- "F277W|F356W|F444W|F250M|F300M|F335M|F360M|F410M|F430M|F460M|F480M|F323N|F405N|F466N|F470N"
short_filters <- "F070W|F090W|F115W|F150W|F200W|F140M|F162M|F182M|F210M|F164N|F187N|F212N"

message("Running original long-wave round")
run_round(build_args(long_filters))

frame_info <- data.frame(Rfits_key_scan(
  filelist = load_raw_files(raw_dir),
  keylist = c("FILTER"),
  cores = 1
))

if (length(grep(short_filters, frame_info$FILTER)) > 0) {
  message("Running original wisp-removal stage")
  short_args <- build_args(short_filters)
  do_wisp_rem(short_args)
  short_args$filelist <- load_raw_files(raw_dir)
  message("Running original short-wave round")
  run_round(short_args)
}

message("Original test run complete")
