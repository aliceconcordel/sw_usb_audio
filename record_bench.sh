#!/bin/bash
# Record the benchmark sound set from the XMOS PDM mic(s).
# Usage:  bash record_bench.sh <label> <rate_hz> [channels] [card] [seconds]
#   e.g.  bash record_bench.sh mic2_48 48000 2      # stereo 2-mic, card 3, 8s each
#         bash record_bench.sh mictest 48000 1      # mono single mic
#
# Run from the repo root. The firmware for the matching config must already be
# running (xrun/xflash) first. Output: Recordings/<label>/<name>.wav
# (S32_LE = 24-bit left-justified in 32-bit; matches the XMOS UAC2.0 device).

set -e
LABEL="${1:?need a label, e.g. mic2_48}"
RATE="${2:?need a sample rate, e.g. 48000 or 96000}"
CHANS="${3:-1}"
CARD="${4:-3}"
SECS="${5:-8}"
OUT="Recordings/${LABEL}"
mkdir -p "$OUT"

# name : on-screen instruction
SOUNDS=(
  "1_silence|Ambient silence (office)"
  "2_tone1k|Play a steady 1 kHz sine tone"
  "3_sweep|Play a log sweep 20 Hz -> 20 kHz"
  "4_speech|Speak: count clearly 1 to 10"
  "5_explosion|Ficelle détonante / firecracker x3"
)

echo "=== Benchmark '${LABEL}' @ ${RATE} Hz, ${CHANS}ch, device hw:${CARD},0, ${SECS}s each -> ${OUT}/ ==="
[ "$CHANS" -ge 2 ] && echo "    (stereo: tap one mic at a time to check each lands on its own channel)"
for entry in "${SOUNDS[@]}"; do
  name="${entry%%|*}"
  instr="${entry#*|}"
  echo
  echo ">>> ${name}: ${instr}"
  read -r -p "    Press Enter to start the ${SECS}s recording..."
  arecord -D "hw:${CARD},0" -c "${CHANS}" -f S32_LE -r "${RATE}" -d "${SECS}" "${OUT}/${name}.wav"
  echo "    saved ${OUT}/${name}.wav"
done

echo
echo "=== Done. Level summary (needs sox): ==="
if command -v sox >/dev/null; then
  for f in "${OUT}"/*.wav; do
    printf '%-34s ' "$f"
    sox "$f" -n stat 2>&1 | grep -E 'Maximum amplitude|RMS +amplitude' | tr '\n' ' '
    echo
  done
else
  echo "(install 'sox' to auto-print levels)"
fi
