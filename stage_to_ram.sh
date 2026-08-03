#!/usr/bin/env bash
# stage_to_ram.sh — Copy cal_sky_renorm to /dev/shm before stacking.
# Run once per session. Files stay in RAM until reboot or manual rm.
# Usage: source stage_to_ram.sh   (so the env var is set in your shell)

set -euo pipefail

SRC="${JUMPROPE_REF_DIR}/Pro1oF/cal_sky_renorm"
DST="/dev/shm/jumprope_cal_sky_renorm"
NCORES="${JUMPROPE_cores_pro:-32}"

if [ -z "${JUMPROPE_REF_DIR:-}" ]; then
  echo "ERROR: source JUMPROPE env first (source initialise_env.sh)"
  return 1 2>/dev/null || exit 1
fi

SHM_FREE=$(df --output=avail -k /dev/shm | tail -1)   # kB
SRC_SIZE=$(du -sk "$SRC" | cut -f1)                    # kB
echo "Source : $SRC  ($(( SRC_SIZE / 1024 / 1024 )) GB)"
echo "shm free: $(( SHM_FREE / 1024 / 1024 )) GB"

if (( SRC_SIZE > SHM_FREE * 9 / 10 )); then
  echo "ERROR: not enough /dev/shm space — $(( SRC_SIZE/1024 )) MB needed, $(( SHM_FREE/1024 )) MB free"
  return 1 2>/dev/null || exit 1
fi

mkdir -p "$DST"

# Count already-staged files to support incremental re-runs
ALREADY=$(ls "$DST"/*.fits 2>/dev/null | wc -l)
TOTAL=$(ls "$SRC"/*.fits | wc -l)
echo "Staging $TOTAL files to $DST  ($ALREADY already present)..."

time ls "$SRC"/*.fits | xargs -P "$NCORES" -I{} bash -c \
  'dst="'"$DST"'/$(basename {})"; [ -f "$dst" ] || cp "{}" "$dst"'

echo ""
echo "Done. $(ls "$DST"/*.fits | wc -l) files in $DST"
echo ""
echo "To use for stacking, export in your shell (or add to run command):"
echo "  export JUMPROPE_CAL_SKY_RENORM_DIR=$DST"
export JUMPROPE_CAL_SKY_RENORM_DIR="$DST"
echo "  (already exported in this shell)"
