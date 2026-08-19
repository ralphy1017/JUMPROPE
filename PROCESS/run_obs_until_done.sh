#!/bin/bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROC="$ROOT/PROCESS"
RSCRIPT=${RSCRIPT:-Rscript}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    printf 'Missing required env var: %s\n' "$name" >&2
    exit 1
  fi
}

normalize_target_ids() {
  python - <<'PY'
import os
import re
from pathlib import Path

target_ids = os.environ.get("JUMPROPE_TARGET_IDS", "").strip()
target_file = os.environ.get("JUMPROPE_TARGET_IDS_FILE", "").strip()

if target_file:
    text = Path(target_file).read_text()
    tokens = re.split(r"[\s|,]+", text.strip())
else:
    tokens = re.split(r"[\s|,]+", target_ids.strip())

ids = [tok for tok in tokens if tok]
print("|".join(ids))
PY
}

incomplete_obs_ids() {
  python - <<'PY'
import os
import re
from collections import Counter, defaultdict

raw_dir = os.environ["JUMPROPE_RAW_DIR"]
final_dir = os.environ["JUMPROPE_FINAL_CAL_SKY_RENORM_DIR"]
final_cal_dir = os.environ.get("JUMPROPE_FINAL_CAL_DIR", "").strip()
shared_final_dir = os.environ.get("JUMPROPE_SHARED_SKIP_RENORM_DIR", "").strip()
shared_final_cal_dir = os.environ.get("JUMPROPE_SHARED_SKIP_CAL_DIR", "").strip()
target_ids = [tok for tok in os.environ["JUMPROPE_TARGET_IDS_NORMALIZED"].split("|") if tok]

pat = re.compile(r"^jw(?P<visit11>\d{11})_")

raw = Counter()
out_renorm = defaultdict(set)
out_cal = defaultdict(set)

for name in os.listdir(raw_dir):
    m = pat.match(name)
    if m and name.endswith("_cal.fits"):
        obs = m.group("visit11")[-10:-3]
        if obs in target_ids:
            raw[obs] += 1

def add_completed(dir_path, suffixes, target):
    if not dir_path or not os.path.isdir(dir_path):
        return
    for name in os.listdir(dir_path):
        m = pat.match(name)
        if not m or not any(name.endswith(s) for s in suffixes):
            continue
        obs = m.group("visit11")[-10:-3]
        if obs in target_ids:
            target[obs].add(name)

add_completed(final_dir, ("_cal_Pro1oF_sky_rem.fits", "_cal_MIRI_sky_rem.fits"), out_renorm)
add_completed(shared_final_dir, ("_cal_Pro1oF_sky_rem.fits", "_cal_MIRI_sky_rem.fits"), out_renorm)
add_completed(final_cal_dir, ("_cal_Pro1oF.fits", "_cal_MIRI.fits"), out_cal)
add_completed(shared_final_cal_dir, ("_cal_Pro1oF.fits", "_cal_MIRI.fits"), out_cal)

remaining = []
for obs in target_ids:
    raw_count = raw.get(obs, 0)
    if raw_count <= 0:
        continue
    renorm_done = len(out_renorm.get(obs, set())) >= raw_count
    require_cal = bool(final_cal_dir or shared_final_cal_dir)
    cal_done = True if not require_cal else len(out_cal.get(obs, set())) >= raw_count
    if not (renorm_done and cal_done):
        remaining.append(obs)

print("|".join(remaining))
PY
}

next_launch_unit() {
  python - <<'PY'
import os
import re
import shutil
from collections import Counter, defaultdict
from pathlib import Path

raw_dir = os.environ["JUMPROPE_RAW_DIR"]
final_dir = os.environ["JUMPROPE_FINAL_CAL_SKY_RENORM_DIR"]
final_cal_dir = os.environ.get("JUMPROPE_FINAL_CAL_DIR", "").strip()
shared_final_dir = os.environ.get("JUMPROPE_SHARED_SKIP_RENORM_DIR", "").strip()
shared_final_cal_dir = os.environ.get("JUMPROPE_SHARED_SKIP_CAL_DIR", "").strip()
target_ids = [tok for tok in os.environ["JUMPROPE_TARGET_IDS_NORMALIZED"].split("|") if tok]
stage_root = os.environ["JUMPROPE_REF_DIR"]
stage_multiplier = float(os.environ.get("JUMPROPE_STAGE_MULTIPLIER", "5.0"))
min_ssd_free_gib = float(os.environ.get("JUMPROPE_MIN_SSD_FREE_GIB", "500"))

pat = re.compile(r"^jw(?P<visit11>\d{11})_")

obs_raw_count = Counter()
obs_raw_bytes = Counter()
vid_raw_count = Counter()
vid_raw_bytes = Counter()
obs_visits = defaultdict(list)

for name in os.listdir(raw_dir):
    if not name.endswith("_cal.fits"):
        continue
    m = pat.match(name)
    if not m:
        continue
    visit11 = m.group("visit11")
    obs = visit11[-10:-3]
    vid = visit11[-10:]
    if obs not in target_ids:
        continue
    path = os.path.join(raw_dir, name)
    size = os.path.getsize(path)
    obs_raw_count[obs] += 1
    obs_raw_bytes[obs] += size
    vid_raw_count[vid] += 1
    vid_raw_bytes[vid] += size
    if vid not in obs_visits[obs]:
        obs_visits[obs].append(vid)

out_renorm_obs = defaultdict(set)
out_cal_obs = defaultdict(set)
out_renorm_vid = defaultdict(set)
out_cal_vid = defaultdict(set)

def add_completed(dir_path, suffixes, obs_target, vid_target):
    if not dir_path or not os.path.isdir(dir_path):
        return
    for name in os.listdir(dir_path):
        m = pat.match(name)
        if not m or not any(name.endswith(s) for s in suffixes):
            continue
        visit11 = m.group("visit11")
        obs = visit11[-10:-3]
        vid = visit11[-10:]
        if obs in target_ids:
            obs_target[obs].add(name)
            vid_target[vid].add(name)

add_completed(final_dir, ("_cal_Pro1oF_sky_rem.fits", "_cal_MIRI_sky_rem.fits"), out_renorm_obs, out_renorm_vid)
add_completed(shared_final_dir, ("_cal_Pro1oF_sky_rem.fits", "_cal_MIRI_sky_rem.fits"), out_renorm_obs, out_renorm_vid)
add_completed(final_cal_dir, ("_cal_Pro1oF.fits", "_cal_MIRI.fits"), out_cal_obs, out_cal_vid)
add_completed(shared_final_cal_dir, ("_cal_Pro1oF.fits", "_cal_MIRI.fits"), out_cal_obs, out_cal_vid)

check_path = Path(stage_root)
while not check_path.exists() and check_path != check_path.parent:
    check_path = check_path.parent
usage = shutil.disk_usage(str(check_path))
free_gib = usage.free / 1024**3
available_stage_gib = free_gib - min_ssd_free_gib

deferred = []
for obs in target_ids:
    raw_count = obs_raw_count.get(obs, 0)
    if raw_count <= 0:
        continue

    renorm_done = len(out_renorm_obs.get(obs, set())) >= raw_count
    require_cal = bool(final_cal_dir or shared_final_cal_dir)
    cal_done = True if not require_cal else len(out_cal_obs.get(obs, set())) >= raw_count
    if renorm_done and cal_done:
        continue

    obs_raw_gib = obs_raw_bytes[obs] / 1024**3
    obs_stage_gib = obs_raw_gib * stage_multiplier

    incomplete_vids = []
    max_vid_raw_gib = 0.0
    max_vid_stage_gib = 0.0
    for vid in obs_visits[obs]:
        vid_raw = vid_raw_count.get(vid, 0)
        if vid_raw <= 0:
            continue
        vid_renorm_done = len(out_renorm_vid.get(vid, set())) >= vid_raw
        vid_cal_done = True if not require_cal else len(out_cal_vid.get(vid, set())) >= vid_raw
        if vid_renorm_done and vid_cal_done:
            continue
        incomplete_vids.append(vid)
        vid_raw_gib = vid_raw_bytes[vid] / 1024**3
        vid_stage_gib = vid_raw_gib * stage_multiplier
        max_vid_raw_gib = max(max_vid_raw_gib, vid_raw_gib)
        max_vid_stage_gib = max(max_vid_stage_gib, vid_stage_gib)

    if obs_stage_gib <= available_stage_gib:
        print(f"RUN\tobs\t{obs}\t{obs}\t1\t{obs_raw_gib:.2f}\t{obs_stage_gib:.2f}\t{free_gib:.2f}")
        raise SystemExit

    if incomplete_vids and max_vid_stage_gib <= available_stage_gib:
        payload = "|".join(incomplete_vids)
        print(f"RUN\tvisit\t{obs}\t{payload}\t{len(incomplete_vids)}\t{max_vid_raw_gib:.2f}\t{max_vid_stage_gib:.2f}\t{free_gib:.2f}")
        raise SystemExit

    deferred.append((obs, obs_stage_gib, max_vid_stage_gib, free_gib))

if deferred:
    obs, obs_stage_gib, max_vid_stage_gib, free_gib = deferred[0]
    print(f"WAIT\tobs\t{obs}\t{obs}\t0\t0.00\t{max(obs_stage_gib, max_vid_stage_gib):.2f}\t{free_gib:.2f}")
else:
    print("DONE\tobs\tNA\tNA\t0\t0.00\t0.00\t0.00")
PY
}

count_completed_outputs() {
  python - <<'PY'
import os
import re

final_dir = os.environ["JUMPROPE_FINAL_CAL_SKY_RENORM_DIR"]
final_cal_dir = os.environ.get("JUMPROPE_FINAL_CAL_DIR", "").strip()
pat = re.compile(r"^jw\d{11}_.*")

renorm = 0
cal = 0

if os.path.isdir(final_dir):
    for name in os.listdir(final_dir):
        if pat.match(name) and (name.endswith("_cal_Pro1oF_sky_rem.fits") or name.endswith("_cal_MIRI_sky_rem.fits")):
            renorm += 1

if final_cal_dir and os.path.isdir(final_cal_dir):
    for name in os.listdir(final_cal_dir):
        if pat.match(name) and (name.endswith("_cal_Pro1oF.fits") or name.endswith("_cal_MIRI.fits")):
            cal += 1

print(f"{renorm}|{cal}")
PY
}

completed_obs_ids() {
  python - <<'PY'
import os

before = {tok for tok in os.environ.get("JUMPROPE_BEFORE_INCOMPLETE", "").split("|") if tok}
after = {tok for tok in os.environ.get("JUMPROPE_AFTER_INCOMPLETE", "").split("|") if tok}
completed = sorted(before - after)
print("|".join(completed))
PY
}

render_completed_obs_pngs() {
  local completed_obs="$1"
  local qa_dir="${JUMPROPE_QA_PNG_DIR:-}"
  if [[ -z "$completed_obs" || -z "$qa_dir" ]]; then
    return 0
  fi
  local per_obs="${JUMPROPE_QA_PNG_PER_OBS:-20}"
  local detectors="${JUMPROPE_QA_PNG_DETECTORS:-nrcb3|nrcb4}"
  python "$PROC/make_obs_png_samples.py" \
    --input-dir "$JUMPROPE_FINAL_CAL_SKY_RENORM_DIR" \
    --output-dir "$qa_dir" \
    --obs-ids "$completed_obs" \
    --detectors "$detectors" \
    --per-obs "$per_obs" \
    --overwrite
}

preserve_run_name="${JUMPROPE_RUN_NAME-}"
preserve_target_ids="${JUMPROPE_TARGET_IDS-}"
preserve_target_ids_file="${JUMPROPE_TARGET_IDS_FILE-}"
preserve_raw_dir="${JUMPROPE_RAW_DIR-}"
preserve_ref_dir="${JUMPROPE_REF_DIR-}"
preserve_final_cal_dir="${JUMPROPE_FINAL_CAL_DIR-}"
preserve_final_dir="${JUMPROPE_FINAL_CAL_SKY_RENORM_DIR-}"
preserve_shared_skip_cal_dir="${JUMPROPE_SHARED_SKIP_CAL_DIR-}"
preserve_shared_skip_renorm_dir="${JUMPROPE_SHARED_SKIP_RENORM_DIR-}"
preserve_staging_mode="${JUMPROPE_STAGING_MODE-}"
preserve_ram_mode="${JUMPROPE_RAM_MODE-}"
preserve_skip_completed="${JUMPROPE_SKIP_COMPLETED_FILES-}"

source "$ROOT/initialise_env.sh"

[[ -n "${preserve_run_name}" ]] && export JUMPROPE_RUN_NAME="${preserve_run_name}"
[[ -n "${preserve_target_ids}" ]] && export JUMPROPE_TARGET_IDS="${preserve_target_ids}"
[[ -n "${preserve_target_ids_file}" ]] && export JUMPROPE_TARGET_IDS_FILE="${preserve_target_ids_file}"
[[ -n "${preserve_raw_dir}" ]] && export JUMPROPE_RAW_DIR="${preserve_raw_dir}"
[[ -n "${preserve_ref_dir}" ]] && export JUMPROPE_REF_DIR="${preserve_ref_dir}"
[[ -n "${preserve_final_cal_dir}" ]] && export JUMPROPE_FINAL_CAL_DIR="${preserve_final_cal_dir}"
[[ -n "${preserve_final_dir}" ]] && export JUMPROPE_FINAL_CAL_SKY_RENORM_DIR="${preserve_final_dir}"
[[ -n "${preserve_shared_skip_cal_dir}" ]] && export JUMPROPE_SHARED_SKIP_CAL_DIR="${preserve_shared_skip_cal_dir}"
[[ -n "${preserve_shared_skip_renorm_dir}" ]] && export JUMPROPE_SHARED_SKIP_RENORM_DIR="${preserve_shared_skip_renorm_dir}"
[[ -n "${preserve_staging_mode}" ]] && export JUMPROPE_STAGING_MODE="${preserve_staging_mode}"
[[ -n "${preserve_ram_mode}" ]] && export JUMPROPE_RAM_MODE="${preserve_ram_mode}"
[[ -n "${preserve_skip_completed}" ]] && export JUMPROPE_SKIP_COMPLETED_FILES="${preserve_skip_completed}"

require_env JUMPROPE_RUN_NAME
require_env JUMPROPE_RAW_DIR
require_env JUMPROPE_REF_DIR
require_env JUMPROPE_FINAL_CAL_SKY_RENORM_DIR

JUMPROPE_TARGET_IDS_NORMALIZED="$(normalize_target_ids)"
export JUMPROPE_TARGET_IDS_NORMALIZED

if [[ -z "$JUMPROPE_TARGET_IDS_NORMALIZED" ]]; then
  printf 'No target observation IDs supplied.\n' >&2
  exit 1
fi

LOGDIR="$ROOT/logs/${JUMPROPE_RUN_NAME}"
MAINLOG="$LOGDIR/run_obs_until_done.log"
mkdir -p "$LOGDIR"

LOCKFILE="$LOGDIR/run_obs_until_done.lock"
exec 9>"$LOCKFILE"
if ! flock -n 9; then
  printf '[%s] Another %s supervisor is already active. Exiting.\n' "$(date '+%F %T')" "$JUMPROPE_RUN_NAME" | tee -a "$MAINLOG"
  exit 1
fi

pass_num=1
no_progress_streak=0
while true; do
  obs_ids="$(incomplete_obs_ids)"
  if [[ -z "$obs_ids" ]]; then
    printf '[%s] %s: all target observation IDs complete.\n' "$(date '+%F %T')" "$JUMPROPE_RUN_NAME" | tee -a "$MAINLOG"
    exit 0
  fi

  count=$(awk -F'|' '{print NF}' <<<"$obs_ids")
  unit_info="$(next_launch_unit)"
  IFS=$'\t' read -r action mode focus_obs payload unit_count raw_gib pred_gib free_gib <<<"$unit_info"

  if [[ "$action" == "DONE" ]]; then
    printf '[%s] %s: all target observation IDs complete.\n' "$(date '+%F %T')" "$JUMPROPE_RUN_NAME" | tee -a "$MAINLOG"
    exit 0
  fi

  if [[ "$action" == "WAIT" ]]; then
    printf '[%s] %s: waiting for SSD headroom before processing %s (predicted stage %.2f GiB, SSD free %.2f GiB).\n' \
      "$(date '+%F %T')" "$JUMPROPE_RUN_NAME" "$focus_obs" "$pred_gib" "$free_gib" | tee -a "$MAINLOG"
    sleep 60
    continue
  fi

  before_snapshot="$(count_completed_outputs)"
  before_renorm="${before_snapshot%%|*}"
  before_cal="${before_snapshot##*|}"
  pass_log="$LOGDIR/run_obs_until_done_pass$(printf '%03d' "$pass_num").log"
  printf '[%s] %s: pass %d starting with %d incomplete observation IDs; launching %s %s for obs %s (%s unit(s), raw %.2f GiB, predicted stage %.2f GiB, SSD free %.2f GiB).\n' \
    "$(date '+%F %T')" "$JUMPROPE_RUN_NAME" "$pass_num" "$count" "$mode" "$payload" "$focus_obs" "$unit_count" "$raw_gib" "$pred_gib" "$free_gib" | tee -a "$MAINLOG"

  set +e
  (
    cd "$PROC"
    "$RSCRIPT" run_all_process.R "$payload"
  ) 2>&1 | tee "$pass_log"
  status=${PIPESTATUS[0]}
  set -e

  printf '[%s] %s: pass %d exited with status %d.\n' "$(date '+%F %T')" "$JUMPROPE_RUN_NAME" "$pass_num" "$status" | tee -a "$MAINLOG"

  next_obs_ids="$(incomplete_obs_ids)"
  if [[ -z "$next_obs_ids" ]]; then
    export JUMPROPE_BEFORE_INCOMPLETE="$obs_ids"
    export JUMPROPE_AFTER_INCOMPLETE=""
    completed_obs="$(completed_obs_ids)"
    if [[ -n "$completed_obs" ]]; then
      render_completed_obs_pngs "$completed_obs" 2>&1 | tee -a "$MAINLOG"
    fi
    printf '[%s] %s: all target observation IDs complete.\n' "$(date '+%F %T')" "$JUMPROPE_RUN_NAME" | tee -a "$MAINLOG"
    exit 0
  fi
  next_count=$(awk -F'|' '{print NF}' <<<"$next_obs_ids")
  after_snapshot="$(count_completed_outputs)"
  after_renorm="${after_snapshot%%|*}"
  after_cal="${after_snapshot##*|}"

  if (( next_count < count || after_renorm > before_renorm || after_cal > before_cal )); then
    no_progress_streak=0
  else
    no_progress_streak=$((no_progress_streak + 1))
    printf '[%s] %s: no progress detected on pass %d (streak=%d).\n' "$(date '+%F %T')" "$JUMPROPE_RUN_NAME" "$pass_num" "$no_progress_streak" | tee -a "$MAINLOG"
  fi

  export JUMPROPE_BEFORE_INCOMPLETE="$obs_ids"
  export JUMPROPE_AFTER_INCOMPLETE="$next_obs_ids"
  completed_obs="$(completed_obs_ids)"
  if [[ -n "$completed_obs" ]]; then
    render_completed_obs_pngs "$completed_obs" 2>&1 | tee -a "$MAINLOG"
  fi

  if (( no_progress_streak >= 3 )); then
    printf '[%s] %s: stopping after %d consecutive no-progress passes.\n' "$(date '+%F %T')" "$JUMPROPE_RUN_NAME" "$no_progress_streak" | tee -a "$MAINLOG"
    exit 2
  fi

  pass_num=$((pass_num + 1))
  sleep 2
done
