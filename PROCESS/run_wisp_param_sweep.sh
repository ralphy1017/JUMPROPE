#!/usr/bin/env bash
set -euo pipefail

OBS_ID="${1:-2514132}"
RAW_DIR="${JUMPROPE_RAW_DIR:-/data7/rzi/PEARLSplus/nircam/cal}"
BASE_DIR="${JUMPROPE_WISP_SWEEP_DIR:-/tmp/jumprope_wisp_sweep_${OBS_ID}}"
CORES_PRO="${JUMPROPE_cores_pro:-32}"
CORES_STACK="${JUMPROPE_cores_stack:-8}"
TASKS_STACK="${JUMPROPE_tasks_stack:-4}"

FILTERS='F070W|F090W|F115W|F140M|F150W|F162M|F182M|F200W|F210M|F250M|F277W|F300M|F323N|F335M|F356W|F360M|F405N|F410M|F430M|F444W|F460M|F466N|F470N|F480M'

mkdir -p "${BASE_DIR}"

run_variant() {
  local variant="$1"
  local run_dir="${BASE_DIR}/${variant}"
  local log_file="${BASE_DIR}/${variant}.log"
  local png_dir="${run_dir}/png"

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
    scale_threshold_0975)
      export JUMPROPE_WISP_SCALE_THRESHOLD=0.975
      ;;
    clip_threshold_0999)
      export JUMPROPE_WISP_CLIP_THRESHOLD=0.999
      ;;
    sigma_hi_1)
      export JUMPROPE_WISP_SIGMA_HI=1
      ;;
    *)
      echo "Unknown variant: ${variant}" >&2
      return 1
      ;;
  esac

  Rscript run_all_process.R "${OBS_ID}" > "${log_file}" 2>&1

  python3 make_before_after_filter_pngs.py \
    --raw-dir "${RAW_DIR}" \
    --processed-dir "${run_dir}/Pro1oF/cal_sky_renorm" \
    --output-dir "${png_dir}" \
    --filters "${FILTERS}" \
    --before-label "Before: raw cal" \
    --after-label "After: ${variant}" \
    --overwrite >> "${log_file}" 2>&1
}

run_variant scale_threshold_0975
run_variant clip_threshold_0999
run_variant sigma_hi_1

printf '%s\n' "${BASE_DIR}"
