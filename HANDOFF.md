# PDM Mic / Ultrasonic project — handoff notes

Working notes for continuing this work (e.g. after switching machine/OS). Read this first.

## Goal
Stream TDK **T5838 PDM microphone(s)** through an **XK-AUDIO-316-MC** board
(XU316-1024-TQ128-C24) out over USB Audio. Milestone 1: one mic (DONE).
Milestone 2: **2-mic DDR stereo array (DONE — verified 2026-07-08)**.
End goal: a **4-mic array for beamforming** (colleague handles the algorithm).

## Status (updated 2026-07-08 — all working on LINUX; see "Linux env" below)
- ✅ **1 mic @ 48 kHz** — end-to-end, known-good. Config `2AMi1o8xxxxxx_mictest`.
- ✅ **1 mic @ 96 kHz HighQuality** — builds/runs/records. Config `2AMi1o8xxxxxx_mic96`
  (PDM 3.072 MHz via 48k-family MCLK 24.576/8). Committed `d2488d6`. NOTE: the earlier worry
  that 96k output was "too low / gain bug" was WRONG — benchmarks show 96k level == 48k within
  ~1 dB (the FIR DC gain doesn't depend on the decimation factor). HQ mode caps mic BW at ~20 kHz,
  so 96k adds no content >20 kHz (spec-based, not yet measured — our sweep stopped at 20 kHz).
- ✅ **2-mic DDR stereo array** — WORKS, both channels verified independent (Audacity + tap test).
  Config `2AMi2o8xxxxxx_mic2_48` (48 kHz stereo). Committed `c032bae`. This is the array foundation.
  Benchmarks in `Recordings/mic2_48/` (git-ignored). Pushed to origin/my-changes @ `48bef45`.
- 🅿️ **141.12 kHz ultrasonic** (`2AMi1o8xxxxxx_micus`) — parked. Enumerates at 141.12 kHz on the
  board (clock plumbing proven) but was blocked on Windows Code 10; never recorded/verified.
  True ultrasonic (>20 kHz) is a separate, bigger project (see the ultrasonic section below).

### How the 2-mic DDR array works (key facts for scaling)
- Only TWO 1.8 V pins on tile 1: X1D12 (CLK) + X1D23 (DATA), both used. So a 2nd mic can't get its
  own data line without a level shifter — instead both mics share CLK + DATA via **DDR**: mic #2
  SELECT→1.8 V drives on the opposite clock edge; the port samples both edges and de-interleaves.
- `xua_conf.h` now auto-enables DDR + a 2nd clock block (XS1_CLKBLK_5) when `XUA_NUM_PDM_MICS > 1`,
  so 1-mic configs stay SDR/untouched. Clock blocks used: 1=SPDIF, 2=MCLK, 3=I2S/flash, 4=mic A, 5=mic B.
- **Next: 4 mics.** At the 2-mic ceiling of the two 1.8 V pins (1 clk + 1 DDR data = 2 mics). Going to
  4 needs level shifters (run 3.3 V ports to 1.8 V mics) OR more 1.8 V pins. HARDWARE decision, TBD.

### Linux env (how to build/run — do this each fresh shell)
`cd /home/alice/XMOS/XTC/15.3.1 && source ./SetEnv` (SetEnv derives paths from $PWD; must cd in first).
Deps at `/home/alice/XMOS/lib_xua/` etc. udev rules installed (one-time). Board = card ~3, S32_LE.
Build: `cmake -G "Unix Makefiles" -B build` (in app_usb_aud_xk_316_mc) then `xmake -C build <config>`.
Record: `bash record_bench.sh <label> <rate> <channels>` from repo root (stereo = channels 2).
mic_array.cpp in the lib_xua dep is patched (96000 + 141120 cases); patch committed as
`lib_xua-mic_array-141120.patch`, re-apply after any fresh dep fetch.

## Hardware wiring (single mic, NO level shifter)
Board pins **X1D12** (P1E0/port 1E) and **X1D23** (P1H0/port 1H) are **1.8 V GPIOs**
(confirmed in the HW manual port map — the only two 1.8 V pins on tile 1, provided for exactly
this). So the 1.8 V T5838 wires directly, no level shifter:
- mic **CLK** → X1D12 ; mic **DATA** → X1D23 ; **VDD** → 1.8 V (SparkFun AP3429A buck reg) ;
  **GND** → common ground ; **SELECT** (L/R) → GND. Keep CLK lead short (3 MHz+).

## Build configs (in `app_usb_aud_xk_316_mc/CMakeLists.txt`)
- `2AMi9o8xxxxxx_mic1`   — 8 analog in + 1 mic (9 in), 8 out, 48 kHz.
- `2AMi1o8xxxxxx_mictest`— mic-only (I2S_CHANS_ADC=0 → mic is the single input), 48 kHz. **KNOWN GOOD.**
- `2AMi1o8xxxxxx_micus`  — ULTRASONIC: 141.12 kHz. Needs `-mcmodel=large` (buffers overflow the
  16-bit DP window at this rate). MCLK_441=22.5792 MHz ÷5 = 4.51584 MHz PDM (T5838 ultrasonic mode),
  ÷32 (stage1) ÷1 (stage2) = 141.12 kHz out, Nyquist 70.56 kHz.

## ⚠️ Dependency patch that must be re-applied (NOT in this repo's normal source)
`lib_xua/src/core/pdm_mics/mic_array.cpp` is patched to add the `XUA_PDM_MIC_FREQ==141120` case
(decimation_factor=1, reuse 48k filters). It lives in the **lib_xua dependency**, which xmake
re-fetches fresh — so after fetching deps, re-apply:
```
# from the lib_xua dependency root (…/lib_xua):
git apply /path/to/sw_usb_audio/lib_xua-mic_array-141120.patch
```
(The patch file `lib_xua-mic_array-141120.patch` is committed alongside this HANDOFF.md.)
This first-pass reuses the 48 kHz filter → band-limited to ~29 kHz. **TODO: design a proper wide
141.12 kHz Stage-1 filter** (XMOS `lib_mic_array` filter-design Python script, from upstream repo)
for full ~70 kHz ultrasonic bandwidth.

## Build / run (XTC Tools 15.3.1; on Linux use the Linux XTC tools + `source SetEnv`)
Linux env is set up: tools at `/home/alice/XMOS/XTC/15.3.1`. SetEnv derives paths from `$PWD`,
so it MUST be sourced from inside the tools dir:
```
cd /home/alice/XMOS/XTC/15.3.1 && source ./SetEnv && cd -
# then xmake / xrun / xflash are on PATH (xmake == XMOS's renamed GNU Make)
```
Build/run:
```
cd app_usb_aud_xk_316_mc
cmake -G "Unix Makefiles" -B build       # DONE (configures OK, all 7 configs found)
xmake -C build 2AMi1o8xxxxxx_micus       # DONE (.xe built in bin/2AMi1o8xxxxxx_micus/)
xrun bin/2AMi1o8xxxxxx_micus/app_usb_aud_xk_316_mc_2AMi1o8xxxxxx_micus.xe   # RAM, lost on power-cycle
# xflash <same .xe>  for persistent
```
Deps are fetched to `/home/alice/XMOS/lib_xua/` (and siblings), NOT under build/_deps.
The 141120 patch is ALREADY APPLIED to `/home/alice/XMOS/lib_xua/lib_xua/src/core/pdm_mics/mic_array.cpp`.
`arecord`/`aplay` present. NOTE: board was NOT connected during last session (`xrun -l` = no devices) —
plug the XTAG4 DEBUG micro-B (and USB DEVICE micro-B) before xrun.
Board connects via on-board XTAG4 **DEBUG** micro-B for xrun/flash; the **USB DEVICE** micro-B is
the actual audio interface the host sees (both must be plugged into the host to enumerate audio).

## Key technical facts / decisions
- Resolution = 24-bit (lib_xua default). 48 kHz cap was a firmware choice (mic decimator), not the OS.
- T5838 mode is selected BY CLOCK: HighQuality 2.0–3.7 MHz (20 kHz BW), Ultrasonic 4.2–4.8 MHz (~70 kHz BW).
- lib_xua picks MCLK by `MCLK_48 % rate==0` (48 family) or `MCLK_441 % rate==0` (44.1 family).
  141120 divides MCLK_441 (÷160) so it reuses the existing 44.1 clock infra — no new MCLK family.
- Stage-1 decimation is FIXED at 32 in mic_array v5. Stage-2 = ÷1 IS supported (verified in Decimator.hpp).

## Git history (branch my-changes, pushed to origin @ 48bef45)
- 17649cb — single PDM mic (48k) support + README (Linux build/run/record flow).
- e3e4750 — WIP 141.12 kHz ultrasonic config (parked).
- d2488d6 — 96 kHz HighQuality config; docs corrected (96k level == 48k, NOT a gain bug).
- c032bae — 2-mic DDR array config (2AMi2o8xxxxxx_mic2_48) + record_bench.sh.
- 48bef45 — .gitignore for local recordings.
(History was force-pushed a few times to tidy messages — normal for this personal branch.)

## 96 kHz — DONE (shipped Option A: HighQuality). Kept as reference for the ultrasonic project:
Why a native 96 kHz device that ALSO carries true ultrasonic (>20 kHz) is NOT a small tweak — this
is the crux of the remaining ultrasonic work:
- mic_array uses TwoStageDecimator with Stage 1 hardwired to 32:1 (lib_mic_array v5, VPU 32-bit
  blocks). Only Stage 2 (integer decimation_factor) is adjustable. output = PDM / (32 × dec).
- 96 kHz: dec=1 → PDM 3.072 MHz (HQ mode, ~20 kHz BW); dec=2 → PDM 6.144 MHz (exceeds T5838 4.8 MHz max).
  So NO integer decimation lands 96 kHz on an ULTRASONIC PDM clock (4.2–4.8 MHz). 141.12 works only
  because 4.51584/32/1 hits it exactly.
- Native-96k WITH ultrasonic would need EITHER (1) fork lib_mic_array Stage 1 to 48:1 (PDM 4.608/48
  = 96k; big — VPU asm built around 32), OR (2) a 3rd on-chip resampler stage (PDM 4.608 ÷32÷1 =
  144 kHz, then rational-resample 144→96 = ×2 ÷3).
- We shipped Option A (HQ 96k, `2AMi1o8xxxxxx_mic96`): clean for ≤20 kHz audio, no ultrasonic content.

## Remaining / next
1. **4-mic array** — at the 2-mic ceiling of the two 1.8 V pins (1 clk + 1 DDR data = 2 mics).
   Going to 4 needs level shifters (3.3 V ports ↔ 1.8 V mics) or more 1.8 V pins. HARDWARE decision.
2. **True ultrasonic (>20 kHz)** — the separate project above (Option 1 or 2), if/when needed.
3. **Measure, don't assume** — actually probe the >20 kHz region at 96k (sweep past 20 kHz with an
   ultrasonic-capable source) to turn "HQ mode has no content >20 kHz" from spec-based into measured.
