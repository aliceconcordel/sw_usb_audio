#!/bin/bash
# Record a series of takes described by an experiment file.
#
# Usage:  bash record_experiment.sh <experiment.csv> [label]
#   e.g.  bash record_experiment.sh experiments/freq_attenuation.csv
#         Rate/channels are fixed at 88200/4; card and duration are prompted.
#         Override with e.g. RATE=96000 CHANS=2 bash record_experiment.sh ...
#         Run from the repo root with the matching firmware already running.
#
# Experiment file: '# key: value' header lines, then a CSV table, one row per take.
#   # title:    shown on screen and in the log
#   # label:    default experiment label
#   # seconds:  default seconds per take
#   # note:     free text, shown and logged (repeatable)
#   # prompt:   <question>|<default>|<column>   asked once, logged with every take (repeatable)
#   # filename: template; {column}, or {column:02} to zero-pad a number
#   <column>,<column>,...
#   <value>,<value>,...
# Values are plain text: no commas, no quotes. Other '#' lines are comments.
#
# Output: Recordings/<date>_<label>/<date>_<label>_<filename>.wav
#         Recordings/<date>_<label>/<date>_<label>_log.csv
#         Every take is UTC-bracketed and, if sox is installed, level-checked.

set -e

EXP="${1:?need an experiment file, e.g. experiments/freq_attenuation.csv}"
[ -f "$EXP" ] || { echo "no such file: $EXP" >&2; exit 1; }

TITLE=""; LABEL_DEF="exp"; SECS_DEF="20"; TEMPLATE=""
NOTES=(); PROMPTS=(); COLS=(); TAKES=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  [ -z "${line// }" ] && continue
  if [[ "$line" =~ ^#[[:space:]]*([a-z]+):[[:space:]]*(.*)$ ]]; then
    val="${BASH_REMATCH[2]}"
    case "${BASH_REMATCH[1]}" in
      title)    TITLE="$val" ;;
      label)    LABEL_DEF="$val" ;;
      seconds)  SECS_DEF="$val" ;;
      note)     NOTES+=("$val") ;;
      prompt)   PROMPTS+=("$val") ;;
      filename) TEMPLATE="$val" ;;
      *) echo "$EXP: unknown key '${BASH_REMATCH[1]}'" >&2; exit 1 ;;
    esac
  elif [[ "$line" == \#* ]]; then
    continue
  elif [ ${#COLS[@]} -eq 0 ]; then
    IFS=',' read -r -a COLS <<< "$line"
  else
    TAKES+=("$line")
  fi
done < "$EXP"

[ -n "$TEMPLATE" ]     || { echo "$EXP: missing '# filename:' line" >&2; exit 1; }
[ ${#TAKES[@]} -gt 0 ] || { echo "$EXP: no takes listed" >&2; exit 1; }

DATE_TAG="$(date +%Y%m%d_%H%M)"

ask() {   # ask <prompt> <default> <varname>
  local prompt="$1" def="$2" __var="$3" reply
  read -r -p "  ${prompt} [${def}]: " reply
  printf -v "$__var" '%s' "${reply:-$def}"
}

slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9.-' '-' | sed 's/^-//; s/-$//'; }

declare -A V
render() {   # fill the filename template from V
  local out="$TEMPLATE" ref col pad val
  while [[ "$out" =~ \{([A-Za-z0-9_]+)(:0([0-9]+))?\} ]]; do
    ref="${BASH_REMATCH[0]}"; col="${BASH_REMATCH[1]}"; pad="${BASH_REMATCH[3]}"
    val="${V[$col]}"
    [ -n "$pad" ] && [[ "$val" =~ ^[0-9]+$ ]] && printf -v val "%0${pad}d" "$((10#$val))"
    out="${out//"$ref"/$(slug "$val")}"
  done
  printf '%s' "$out"
}

LABEL="${2:-}"
echo
[ -n "$TITLE" ] && echo "  ${TITLE}"
[ -z "$LABEL" ] && ask "Experiment label (no spaces)" "$LABEL_DEF" LABEL
LABEL="${LABEL// /_}"

# Fixed by the mic4_882 firmware — override on the command line if that changes.
RATE="${RATE:-88200}"
CHANS="${CHANS:-4}"

# Addressed by NAME, not number: card numbers are assigned in enumeration order,
# so the board and the internal audio swap places across reboots and replugs.
# "channel count not available" is what that looks like — the request landed on
# the laptop's own mic array instead. 'arecord -l' shows what is present.
ask "ALSA card (name or number)" "MCUAC20"   CARD
ask "Seconds per recording"      "$SECS_DEF" SECS

P_COLS=(); P_VALS=()
for p in "${PROMPTS[@]}"; do
  IFS='|' read -r q def col <<< "$p"
  ask "$q" "$def" ans
  P_COLS+=("$col"); P_VALS+=("$ans")
done

# Check every take before recording anything: right number of fields, filename
# template fully resolvable, no two takes writing the same file.
BASE="${DATE_TAG}_${LABEL}"
NAMES=()
declare -A SEEN
for i in "${!TAKES[@]}"; do
  IFS=',' read -r -a F <<< "${TAKES[$i]}"
  [ ${#F[@]} -eq ${#COLS[@]} ] || { echo "$EXP: take $((i+1)) has ${#F[@]} fields, expected ${#COLS[@]}" >&2; exit 1; }
  V=()
  for j in "${!COLS[@]}";   do V[${COLS[$j]}]="${F[$j]}"; done
  for j in "${!P_COLS[@]}"; do V[${P_COLS[$j]}]="${P_VALS[$j]}"; done
  for ref in $(grep -o '{[A-Za-z0-9_]*' <<< "$TEMPLATE" | tr -d '{'); do
    [ -n "${V[$ref]+x}" ] || { echo "$EXP: filename uses unknown column '$ref'" >&2; exit 1; }
  done
  name="${BASE}_$(render).wav"
  [ -z "${SEEN[$name]}" ] || { echo "$EXP: takes $((SEEN[$name])) and $((i+1)) both write ${name}" >&2; exit 1; }
  SEEN[$name]=$((i+1)); NAMES+=("$name")
done

OUT="Recordings/${BASE}"
mkdir -p "$OUT"
LOG="${OUT}/${BASE}_log.csv"

# Clock health, recorded now rather than assumed later.
SYNCED="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"

{
  echo "# session      ${BASE}"
  echo "# experiment   ${TITLE}   (${EXP})"
  echo "# recorded     $(date -Is)"
  echo "# host         $(hostname)"
  echo "# rate         ${RATE} Hz"
  echo "# channels     ${CHANS}"
  echo "# device       hw:${CARD},0   S32_LE (24-bit left-justified in 32 bits)"
  echo "# duration     ${SECS} s requested per take"
  for n in "${NOTES[@]}"; do echo "# note         ${n}"; done
  for j in "${!P_COLS[@]}"; do echo "# ${P_COLS[$j]}$(printf '%*s' $((12 - ${#P_COLS[$j]})) '') ${P_VALS[$j]}"; done
  echo "# clock synced ${SYNCED}   (NTPSynchronized at record time; 'no' is normal offline —"
  echo "#              the clock free-runs at ~10-50 ppm, so sync before setting out)"
  echo "#"
  echo "# t_launch_utc is taken immediately BEFORE arecord is started, t_return_utc"
  echo "# immediately AFTER it exits. The first captured sample therefore falls"
  echo "# somewhere in [t_launch_utc, t_return_utc - duration]; latency_bound_ms is the"
  echo "# width of that window. Use the bound, not a fixed offset, when aligning."
  echo "# peak/rms are dBFS over the whole take, filled in if sox is installed;"
  echo "# peak_dbfs at 0.0 means the take clipped."
  echo "#"
  printf 'file'
  for c in "${COLS[@]}" "${P_COLS[@]}"; do printf ',%s' "$c"; done
  printf ',requested_s,t_launch_utc,t_return_utc,t_launch_epoch_ms,t_return_epoch_ms,latency_bound_ms,peak_dbfs,rms_dbfs\n'
} > "$LOG"

echo
echo "=== ${#TAKES[@]} recordings @ ${SECS}s, ${RATE} Hz, ${CHANS}ch -> ${OUT}/ ==="
for n in "${NOTES[@]}"; do echo "    ${n}"; done
for j in "${!P_COLS[@]}"; do echo "    ${P_COLS[$j]}: ${P_VALS[$j]}"; done
echo "    Clock synchronized: ${SYNCED}"
echo

utc() { date -u -d "@$(awk "BEGIN{printf \"%.3f\", $1/1000}")" +%Y-%m-%dT%H:%M:%S.%3NZ; }
dbfs() { awk "BEGIN{v=$1+0; if (v>0) printf \"%.1f\", 20*log(v)/log(10); else printf \"-inf\"}"; }

for i in "${!TAKES[@]}"; do
  IFS=',' read -r -a F <<< "${TAKES[$i]}"
  name="${NAMES[$i]}"
  desc=""
  for j in "${!COLS[@]}"; do desc+="${COLS[$j]} ${F[$j]}   "; done

  echo ">>> take $((i+1))/${#TAKES[@]}:  ${desc}"
  read -r -p "    Press Enter to record ${SECS}s..."

  T_LAUNCH_MS=$(date -u +%s%3N)
  arecord -D "hw:${CARD},0" -c "${CHANS}" -f S32_LE -r "${RATE}" -d "${SECS}" "${OUT}/${name}"
  T_RETURN_MS=$(date -u +%s%3N)
  BOUND_MS=$(( T_RETURN_MS - T_LAUNCH_MS - SECS * 1000 ))
  echo "    saved ${name}"
  echo "    launched $(utc "$T_LAUNCH_MS")  returned $(utc "$T_RETURN_MS")  (start latency < ${BOUND_MS} ms)"

  PEAK_DB=""; RMS_DB=""
  if command -v sox >/dev/null && [ -f "${OUT}/${name}" ]; then
    STAT=$(sox "${OUT}/${name}" -n stat 2>&1)
    PEAK_LIN=$(awk '/Maximum amplitude/{print $3}' <<< "$STAT")
    RMS_LIN=$(awk '/RMS[ \t]+amplitude/{print $3}' <<< "$STAT")
    PEAK_DB=$(dbfs "$PEAK_LIN"); RMS_DB=$(dbfs "$RMS_LIN")
    echo "    peak ${PEAK_DB} dBFS   rms ${RMS_DB} dBFS"
    awk "BEGIN{exit !($PEAK_LIN+0 >= 0.999)}" && echo "    *** CLIPPED — re-record this take ***"
  fi

  {
    printf '"%s"' "$name"
    for v in "${F[@]}" "${P_VALS[@]}"; do printf ',"%s"' "$v"; done
    printf ',%s,%s,%s,%s,%s,%s,%s,%s\n' "$SECS" "$(utc "$T_LAUNCH_MS")" "$(utc "$T_RETURN_MS")" \
      "$T_LAUNCH_MS" "$T_RETURN_MS" "$BOUND_MS" "$PEAK_DB" "$RMS_DB"
  } >> "$LOG"
  echo
done

echo "=== Done — ${#TAKES[@]} recordings in ${OUT}/, log ${LOG} ==="
