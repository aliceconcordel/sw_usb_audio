#!/bin/bash
# Build, flash and record the 4-mic ULTRASONIC array config (2AMi4o8xxxxxx_mic4_us).
# For Alice: one command to go from "firmware wired up" to "wav files on disk".
#
# Prereqs (see HANDOFF.md):
#   - XTC Tools env sourced (this script does NOT source it for you, since
#     SetEnv needs to be sourced from inside the tools dir - do that first):
#       cd /path/to/XMOS/XTC/15.3.1 && source ./SetEnv && cd -
#   - The `lib_xua-mic_array-141120.patch` (extended per
#     ULTRASONIC_FILTER_INTEGRATION.md with the CIC-7 filter) already applied
#     to the fetched lib_xua dependency.
#   - Board plugged in: XTAG4 DEBUG micro-B (for xrun/xflash) AND USB DEVICE
#     micro-B (the actual audio interface) both into the host.
#
# Usage: bash run_ultrasonic_test.sh <label> [seconds] [card]
#   e.g.  bash run_ultrasonic_test.sh explosion_test1 10
#
# Output: Recordings/<label>/*.wav (via record_bench.sh), 4ch, 141120 Hz, S32_LE.

set -e

LABEL="${1:?need a label, e.g. explosion_test1}"
SECS="${2:-8}"
CARD="${3:-3}"

CONFIG="2AMi4o8xxxxxx_mic4_us"
APP_DIR="app_usb_aud_xk_316_mc"
XE_PATH="${APP_DIR}/bin/${CONFIG}/app_usb_aud_xk_316_mc_${CONFIG}.xe"

if ! command -v xmake >/dev/null; then
  echo "ERROR: xmake not on PATH - source the XTC Tools SetEnv first (see script header)." >&2
  exit 1
fi

echo "=== Configuring (first run only fetches deps; safe to re-run) ==="
cmake -G "Unix Makefiles" -B "${APP_DIR}/build" -S "${APP_DIR}"

echo
echo "=== Building ${CONFIG} ==="
xmake -C "${APP_DIR}/build" "${CONFIG}"

if [ ! -f "${XE_PATH}" ]; then
  echo "ERROR: expected build output not found at ${XE_PATH}" >&2
  exit 1
fi

echo
echo "=== Flashing (persistent - survives power-cycle) ==="
echo "    If you'd rather load to RAM only for this test, Ctrl-C now and run:"
echo "    xrun ${XE_PATH}"
xflash "${XE_PATH}"

echo
echo "=== Recording 4ch @ 141120 Hz -> Recordings/${LABEL}/ ==="
bash record_bench.sh "${LABEL}" 141120 4 "${CARD}" "${SECS}"

echo
echo "=== Done. Quick sanity check on channel balance (needs sox): ==="
if command -v sox >/dev/null; then
  for f in "Recordings/${LABEL}"/*.wav; do
    printf '%-40s ' "$f"
    sox "$f" -n stat 2>&1 | grep -E 'Maximum amplitude|RMS +amplitude' | tr '\n' ' '
    echo
  done
else
  echo "(install 'sox' to auto-print levels)"
fi
