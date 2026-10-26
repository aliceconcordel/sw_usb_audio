#!/bin/bash
# Record firecracker explosions at four distances, for two cracker types, to
# measure how the spectrum attenuates with range.
#
#     Ficelle Detonante   1 m / 5 m / 10 m / 20 m
#     Allevi              1 m / 5 m / 10 m / 20 m
#
# Four explosions per recording, eight recordings in total. The source stays in
# the plane of the sensors throughout — only the range changes, so a difference
# between takes is attenuation rather than geometry.
#
# Usage:  bash record_freq_attenuation.sh [label]
#         Rate/channels are fixed at 88200/4; card and duration are prompted.
#         Override with e.g. RATE=96000 CHANS=2 bash record_freq_attenuation.sh
#         Run from the repo root with the matching firmware already running.
#
# Output: Recordings/<date>_<label>/
#           <date>_<label>_ficelle_d05m.wav
#           <date>_<label>_log.csv
#         Date, cracker and distance are in the filename, so a stray WAV still
#         says what it is after being copied elsewhere.

set -e

DATE_TAG="$(date +%Y%m%d_%H%M)"

ask() {   # ask <prompt> <default> <varname>
  local prompt="$1" def="$2" __var="$3" reply
  read -r -p "  ${prompt} [${def}]: " reply
  printf -v "$__var" '%s' "${reply:-$def}"
}

LABEL="${1:-}"
[ -z "$LABEL" ] && ask "Experiment label (no spaces)" "freqatt" LABEL
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
ask "Seconds per recording"      "30"      SECS
ask "Explosions per recording"   "4"       NBANGS

# cracker name | distance_m
CONFIGS=(
  "Ficelle Detonante|1"
  "Ficelle Detonante|5"
  "Ficelle Detonante|10"
  "Ficelle Detonante|20"
  "Allevi|1"
  "Allevi|5"
  "Allevi|10"
  "Allevi|20"
)

BASE="${DATE_TAG}_${LABEL}"
OUT="Recordings/${BASE}"
mkdir -p "$OUT"
LOG="${OUT}/${BASE}_log.csv"

{
  echo "# session    ${BASE}"
  echo "# recorded   $(date -Is)"
  echo "# host       $(hostname)"
  echo "# rate       ${RATE} Hz"
  echo "# channels   ${CHANS}"
  echo "# device     hw:${CARD},0   S32_LE (24-bit left-justified in 32 bits)"
  echo "# duration   ${SECS} s per take"
  echo "# events     ${NBANGS} explosions per take"
  echo "# position   source in the plane of the sensors, all takes"
  echo "#"
  echo "# peak/rms are dBFS over the whole take, filled in if sox is installed."
  echo "# They are a field sanity check, not the analysis: peak_dbfs at 0.0 means"
  echo "# the take clipped and cannot anchor an attenuation curve."
  echo "#"
  printf 'file,cracker,distance_m,n_events,duration_s,peak_dbfs,rms_dbfs\n'
} > "$LOG"

echo
echo "=== ${#CONFIGS[@]} recordings @ ${SECS}s, ${RATE} Hz, ${CHANS}ch -> ${OUT}/ ==="
echo "    ${NBANGS} explosions per take, source in the plane of the sensors"
echo

for entry in "${CONFIGS[@]}"; do
  IFS='|' read -r name dist <<< "$entry"
  # Filename key: first word of the cracker name, lowercased — no spaces in filenames.
  key="$(printf '%s' "${name%% *}" | tr '[:upper:]' '[:lower:]')"
  printf -v dist_pad '%02d' "$dist" 2>/dev/null || dist_pad="$dist"
  wav="${BASE}_${key}_d${dist_pad}m.wav"

  echo ">>> ${name}  at  ${dist} m   (${NBANGS} explosions)"
  read -r -p "    Press Enter to record ${SECS}s..."

  arecord -D "hw:${CARD},0" -c "${CHANS}" -f S32_LE -r "${RATE}" -d "${SECS}" "${OUT}/${wav}"
  echo "    saved ${wav}"

  # Levels, when there is a file to measure and sox to do it with. They are the
  # measurement here, and reading them now catches a clipped take while the setup
  # is still standing. Guarded on the file existing so the log survives either way.
  PEAK_DB=""; RMS_DB=""
  if command -v sox >/dev/null && [ -f "${OUT}/${wav}" ]; then
    PEAK_LIN=$(sox "${OUT}/${wav}" -n stat 2>&1 | awk '/Maximum amplitude/{print $3}')
    RMS_LIN=$(sox "${OUT}/${wav}" -n stat 2>&1 | awk '/RMS[ \t]+amplitude/{print $3}')
    PEAK_DB=$(awk "BEGIN{v=$PEAK_LIN+0; printf (v>0 ? \"%.1f\" : \"-inf\"), (v>0 ? 20*log(v)/log(10) : 0)}")
    RMS_DB=$(awk "BEGIN{v=$RMS_LIN+0;  printf (v>0 ? \"%.1f\" : \"-inf\"), (v>0 ? 20*log(v)/log(10) : 0)}")
    echo "    peak ${PEAK_DB} dBFS   rms ${RMS_DB} dBFS"
    awk "BEGIN{exit !($PEAK_LIN+0 >= 0.999)}" && echo "    *** CLIPPED — re-record this take ***"
  fi

  # Always logged, levels or not: the filename-to-configuration map is the point,
  # and it should survive a dry run or a machine without sox.
  printf '"%s","%s",%s,%s,%s,%s,%s\n' \
    "$wav" "$name" "$dist" "$NBANGS" "$SECS" "$PEAK_DB" "$RMS_DB" >> "$LOG"
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
  echo
  echo "  The 1 m takes are the ones at risk of clipping, and a clipped take cannot"
  echo "  anchor an attenuation curve — its true peak is unknown."
fi
