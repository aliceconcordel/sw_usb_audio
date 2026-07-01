# PDM Mic / Ultrasonic project — handoff notes

Working notes for continuing this work (e.g. after switching machine/OS). Read this first.

## Goal
Stream TDK **T5838 PDM microphone(s)** through an **XK-AUDIO-316-MC** board
(XU316-1024-TQ128-C24) out over USB Audio. Milestone 1: one mic (DONE).
End goal: a **4-mic array for beamforming** (colleague handles the algorithm).

## Status
- ✅ **Single mic @ 48 kHz works end-to-end** (mic → USB → recorded in Audacity on Windows).
  Config `2AMi1o8xxxxxx_mictest`. Committed in `a04cc8f`.
- 🚧 **96 kHz-rate / ultrasonic in progress.** User needs ~48 kHz bandwidth (ultrasonic),
  accepts non-standard sample rate. Config `2AMi1o8xxxxxx_micus` (141.12 kHz) **builds and
  the device ENUMERATES at 141.12 kHz on the board** — clock plumbing proven. BUT Windows'
  built-in USB-audio driver refuses to start it (**Problem Code 10**) because 141120 Hz is a
  non-standard rate. **Switching to Linux** (ALSA is permissive with odd rates + does
  multichannel natively — no ASIO/Thesycon needed) to get past this and set up for the array.

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
```
cd app_usb_aud_xk_316_mc
cmake -G "Unix Makefiles" -B build
xmake -C build 2AMi1o8xxxxxx_micus     # build one config
xrun bin/2AMi1o8xxxxxx_micus/app_usb_aud_xk_316_mc_2AMi1o8xxxxxx_micus.xe   # RAM, lost on power-cycle
# xflash <same .xe>  for persistent
```
Board connects via on-board XTAG4 **DEBUG** micro-B for xrun/flash; the **USB DEVICE** micro-B is
the actual audio interface the host sees (both must be plugged into the host to enumerate audio).

## Key technical facts / decisions
- Resolution = 24-bit (lib_xua default). 48 kHz cap was a firmware choice (mic decimator), not the OS.
- T5838 mode is selected BY CLOCK: HighQuality 2.0–3.7 MHz (20 kHz BW), Ultrasonic 4.2–4.8 MHz (~70 kHz BW).
- lib_xua picks MCLK by `MCLK_48 % rate==0` (48 family) or `MCLK_441 % rate==0` (44.1 family).
  141120 divides MCLK_441 (÷160) so it reuses the existing 44.1 clock infra — no new MCLK family.
- Stage-1 decimation is FIXED at 32 in mic_array v5. Stage-2 = ÷1 IS supported (verified in Decimator.hpp).

## Next steps on Linux
1. Install XTC Tools for Linux; `git clone` this repo; let xmake fetch deps; re-apply the patch above.
2. Build `2AMi1o8xxxxxx_micus`, `xrun` it, confirm it appears via ALSA (`arecord -l`) and records
   (set rate 141120). Windows Code 10 should NOT occur on ALSA.
3. Then Milestone 2: design the wide ultrasonic Stage-1 filter; scale to 4 mics (DDR vs SDR, port width).
