#!/bin/bash
# Record a moving source in six distance/speed configurations.
#
#     cfg 1   2 m       1.5 m/s
#     cfg 2   2 m       5   m/s
#     cfg 3  10 m       1.5 m/s
#     cfg 4  10 m       5   m/s
#     cfg 5   2 -> 10 m 3   m/s
#     cfg 6  10 -> 2 m  3   m/s
#
# Every pass is a straight line along +Y (increasing). Configs 1-4 hold the
# distance constant; 5 and 6 fly a diagonal, so the distance changes across the
# pass — still a straight line, not an arc.
#
# Usage:  bash record_bearing_over_time.sh [label]
#         Rate/channels are fixed at 88200/4; card and duration are prompted.
#         Override with e.g. RATE=96000 CHANS=2 bash record_bearing_over_time.sh
#         Run from the repo root with the matching firmware already running.
#
# Output: Recordings/<date>_<label>/<date>_<label>_cfg5_d2-10m_v3mps.wav
#         Date, config, distance and speed are in the filename, so a stray WAV
#         still says what it is after being copied elsewhere.

set -e

DATE_TAG="$(date +%Y%m%d_%H%M)"

ask() {   # ask <prompt> <default> <varname>
  local prompt="$1" def="$2" __var="$3" reply
  read -r -p "  ${prompt} [${def}]: " reply
  printf -v "$__var" '%s' "${reply:-$def}"
}

LABEL="${1:-}"
[ -z "$LABEL" ] && ask "Experiment label (no spaces)" "bot" LABEL
LABEL="${LABEL// /_}"

# Fixed by the mic4_882 firmware — override on the command line if that changes.
RATE="${RATE:-88200}"
CHANS="${CHANS:-4}"

# Addressed by NAME, not number: card numbers are assigned in enumeration order,
# so the board and the internal audio swap places across reboots and replugs.
# "channel count not available" is what that looks like — the request landed on
# the laptop's own mic array instead. 'arecord -l' shows what is present.
echo
ask "ALSA card (name or number)" "MCUAC20" CARD
ask "Seconds per recording"      "20"      SECS

# cfg | distance | speed
CONFIGS=(
  "1|2|1.5"
  "2|2|5"
  "3|10|1.5"
  "4|10|5"
  "5|2-10|3"
  "6|10-2|3"
)

BASE="${DATE_TAG}_${LABEL}"
OUT="Recordings/${BASE}"
mkdir -p "$OUT"
LOG="${OUT}/${BASE}_log.csv"

# Clock health, recorded now rather than assumed later.
SYNCED="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"

{
  echo "# session      ${BASE}"
  echo "# host         $(hostname)"
  echo "# rate         ${RATE} Hz"
  echo "# channels     ${CHANS}"
  echo "# device       hw:${CARD},0   S32_LE (24-bit left-justified in 32 bits)"
  echo "# duration     ${SECS} s requested per take"
  echo "# flight       along +Y (increasing Y)"
  echo "# clock synced ${SYNCED}   (NTPSynchronized at record time)"
  echo "#              'no' is normal in the field — the clock free-runs off the RTC"
  echo "#              once offline. Drift is ~10-50 ppm, i.e. 0.1-4 s per day, so a"
  echo "#              sync before setting out keeps these good to about a second for"
  echo "#              a day's work. No network is needed while recording."
  echo "#"
  echo "# t_launch_utc is taken immediately BEFORE arecord is started, t_return_utc"
  echo "# immediately AFTER it exits. The first captured sample therefore falls"
  echo "# somewhere in [t_launch_utc, t_return_utc - duration], and that window is"
  echo "# the bound on start latency — latency_bound_ms below. It is not a constant,"
  echo "# so use the bound rather than a fixed offset when aligning to drone data."
  echo "#"
  printf 'file,cfg,distance_m,speed_mps,t_launch_utc,t_return_utc,t_launch_epoch_ms,t_return_epoch_ms,requested_s,latency_bound_ms\n'
} > "$LOG"

echo
echo "=== ${#CONFIGS[@]} recordings @ ${SECS}s, ${RATE} Hz, ${CHANS}ch -> ${OUT}/ ==="
echo "    Flight direction: along the +Y axis (increasing Y)"
echo "    Clock synchronized: ${SYNCED}"
echo

for entry in "${CONFIGS[@]}"; do
  IFS='|' read -r cfg dist speed <<< "$entry"
  name="${BASE}_cfg${cfg}_d${dist}m_v${speed}mps.wav"

  echo ">>> cfg ${cfg}/${#CONFIGS[@]}:  ${dist} m  at  ${speed} m/s"
  read -r -p "    Press Enter to record ${SECS}s..."

  T_LAUNCH_MS=$(date -u +%s%3N)
  T_LAUNCH=$(date -u -d "@$(awk "BEGIN{printf \"%.3f\", ${T_LAUNCH_MS}/1000}")" +%Y-%m-%dT%H:%M:%S.%3NZ)
  arecord -D "hw:${CARD},0" -c "${CHANS}" -f S32_LE -r "${RATE}" -d "${SECS}" "${OUT}/${name}"
  T_RETURN_MS=$(date -u +%s%3N)
  T_RETURN=$(date -u -d "@$(awk "BEGIN{printf \"%.3f\", ${T_RETURN_MS}/1000}")" +%Y-%m-%dT%H:%M:%S.%3NZ)

  BOUND_MS=$(( T_RETURN_MS - T_LAUNCH_MS - SECS * 1000 ))
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$name" "$cfg" "$dist" "$speed" "$T_LAUNCH" "$T_RETURN" \
    "$T_LAUNCH_MS" "$T_RETURN_MS" "$SECS" "$BOUND_MS" >> "$LOG"

  echo "    saved ${name}"
  echo "    launched ${T_LAUNCH}  returned ${T_RETURN}  (start latency < ${BOUND_MS} ms)"
  echo
done

echo "=== Done — ${#CONFIGS[@]} recordings in ${OUT}/ ==="
if command -v sox >/dev/null; then
  echo
  for f in "${OUT}"/*.wav; do
    printf '  %-46s ' "$(basename "$f")"
    sox "$f" -n stat 2>&1 | grep -E 'Maximum amplitude|RMS +amplitude' | tr '\n' ' '
    echo
  done
fi
