#!/usr/bin/env bash
# prewarm_cache.sh — Parallel read of Pro1oF/cal/ into Linux page cache.
# Use before running steps 1-6. Files stay hot in cache until memory pressure.
# Usage: bash prewarm_cache.sh
# Does NOT block — reads happen in background xargs workers.

set -euo pipefail

if [ -z "${JUMPROPE_REF_DIR:-}" ]; then
  echo "ERROR: source JUMPROPE env first (source initialise_env.sh)"
  exit 1
fi

NCORES="${JUMPROPE_cores_pro:-32}"
TARGET="${JUMPROPE_REF_DIR}/Pro1oF/cal"
COUNT=$(ls "$TARGET"/*.fits 2>/dev/null | wc -l)

echo "Pre-warming $COUNT files in $TARGET using $NCORES parallel readers..."
time ls "$TARGET"/*.fits | xargs -P "$NCORES" -I{} dd if={} of=/dev/null bs=4M status=none
echo "Cache warm. $(free -h | awk '/Mem/{print $7}') available RAM remaining."
