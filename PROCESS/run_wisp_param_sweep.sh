#!/usr/bin/env bash
set -euo pipefail

OBS_ID="${1:-2514132}"
RAW_DIR="${JUMPROPE_RAW_DIR:-/data7/rzi/PEARLSplus/nircam/cal}"
BASE_DIR="${JUMPROPE_WISP_SWEEP_DIR:-/tmp/jumprope_wisp_sweep_${OBS_ID}}"
CORES_PRO="${JUMPROPE_cores_pro:-32}"
CORES_STACK="${JUMPROPE_cores_stack:-8}"
TASKS_STACK="${JUMPROPE_tasks_stack:-4}"

mkdir -p "${BASE_DIR}"

run_variant() {
  local variant="$1"
  local run_dir="${BASE_DIR}/${variant}"
  local log_file="${BASE_DIR}/${variant}.log"
  local png_dir="${run_dir}/png"
  local triptych_input_dir="${run_dir}/triptych_inputs"

  mkdir -p "${run_dir}"

  export JUMPROPE_REF_DIR="${run_dir}"
  export JUMPROPE_RAW_DIR="${RAW_DIR}"
  export JUMPROPE_FINAL_CAL_DIR=""
  export JUMPROPE_FINAL_CAL_SKY_RENORM_DIR=""
  export JUMPROPE_STAGING_MODE=FALSE
  export JUMPROPE_SKIP_COMPLETED_FILES=FALSE
  export JUMPROPE_RUN_NAME="wisp_param_sweep_${variant}"
  export JUMPROPE_do_NIRISS=F
  export JUMPROPE_do_MIRI=F
  export JUMPROPE_cores_pro="${CORES_PRO}"
  export JUMPROPE_cores_stack="${CORES_STACK}"
  export JUMPROPE_tasks_stack="${TASKS_STACK}"
  export JUMPROPE_CLEANUP=TRUE
  export JUMPROPE_RAM_MODE=FALSE
  export OPENBLAS_NUM_THREADS=1
  export OMP_NUM_THREADS=1
  export MKL_NUM_THREADS=1

  unset JUMPROPE_WISP_SOURCE_THRESHOLD
  unset JUMPROPE_WISP_SCALE_THRESHOLD
  unset JUMPROPE_WISP_SKY_THRESHOLD
  unset JUMPROPE_WISP_CLIP_THRESHOLD
  unset JUMPROPE_WISP_SIGMA_HI
  unset JUMPROPE_WISP_SIGMA_LO

  case "${variant}" in
    clip_threshold_099)
      export JUMPROPE_WISP_CLIP_THRESHOLD=0.99
      ;;
    sigma_lo_10)
      export JUMPROPE_WISP_SIGMA_LO=10
      ;;
    scale_threshold_095)
      export JUMPROPE_WISP_SCALE_THRESHOLD=0.95
      ;;
    *)
      echo "Unknown variant: ${variant}" >&2
      return 1
      ;;
  esac

  Rscript run_all_process.R "${OBS_ID}" > "${log_file}" 2>&1

  rm -rf "${triptych_input_dir}"
  mkdir -p "${triptych_input_dir}"
  find "${run_dir}/Pro1oF/cal_sky_renorm" -maxdepth 1 -type f \
    \( -name "jw*_nrcb3_cal_Pro1oF_sky_rem.fits" -o -name "jw*_nrcb4_cal_Pro1oF_sky_rem.fits" \) \
    -exec ln -sf {} "${triptych_input_dir}/" \; >> "${log_file}" 2>&1 || true

  python3 make_wisp_triptych_pngs.py \
    --processed-dir "${triptych_input_dir}" \
    --output-dir "${png_dir}" \
    --overwrite >> "${log_file}" 2>&1
}

run_variant clip_threshold_099
run_variant sigma_lo_10
run_variant scale_threshold_095

printf '%s\n' "${BASE_DIR}"
