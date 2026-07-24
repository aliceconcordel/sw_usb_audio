# PDM Mic / Ultrasonic project — handoff notes

Working notes for continuing this work (e.g. after switching machine/OS). Read this first.

## 2026-07-24 update: filter decision made, code regenerated from scratch
Decision on "the decision" below: **accept ~-55 dBFS** (target use case is explosions - loud,
transient sources, so bandwidth matters more than noise floor). Of the tested filters, **CIC
order 7** (`test_us_ma7.wav`) was picked over the custom FIR designs: ~46-48 kHz passband
(wider) vs ~-51 dBFS floor (a bit worse than the FIR's -55/-57, an acceptable trade for this
use case).

Alice's local uncommitted `mic_array.cpp` patch + `filter_design/` scripts for this were lost.
They've been regenerated from scratch (not from memory - re-derived using XMOS's public
`lib_mic_array` filter-design toolchain) on branch `pm-ultrasonic-tests`:
- `filter_design/design_ultrasonic_cic7.py` — regenerates the CIC-7 filter `.pkl`.
- `ULTRASONIC_FILTER_INTEGRATION.md` — exact steps to turn that into a header and wire it into
  `mic_array.cpp` (this part needs a human with the actual file in front of them - it wasn't
  possible to blind-edit a file that isn't in this repo).
- `run_ultrasonic_test.sh` — one command to build/flash/record the `2AMi4o8xxxxxx_mic4_us`
  config once the above is wired in.
- New CMake config `2AMi4o8xxxxxx_mic4_us` in `app_usb_aud_xk_316_mc/CMakeLists.txt` (4-mic
  SDR/PORT_4F wiring, identical to mic4_48/mic4_96 - no rewiring - with the ultrasonic clock:
  MCLK 22.5792 MHz / PDM 4.51584 MHz / 141.12 kHz out).

## Goal
Stream TDK **T5838 PDM microphone(s)** through an **XK-AUDIO-316-MC** board
(XU316-1024-TQ128-C24) out over USB Audio. Milestone 1: one mic (DONE).
Milestone 2: **2-mic DDR stereo array (DONE — verified 2026-07-08)**.
Milestone 3: **4-mic array (DONE — verified 2026-07-21)**.
End goal: a **4-mic array for beamforming** (colleague handles the algorithm) — HW is now in place.

## Status (updated 2026-07-10 — all working on LINUX; see "Linux env" below)
- ✅ **1 mic @ 48 kHz** — end-to-end, known-good. Config `2AMi1o8xxxxxx_mictest`.
- ✅ **1 mic @ 96 kHz HighQuality** — builds/runs/records. Config `2AMi1o8xxxxxx_mic96`
  (PDM 3.072 MHz via 48k-family MCLK 24.576/8). Committed `d2488d6`. NOTE: the earlier worry
  that 96k output was "too low / gain bug" was WRONG — benchmarks show 96k level == 48k within
  ~1 dB (the FIR DC gain doesn't depend on the decimation factor). HQ mode caps mic BW at ~20 kHz,
  so 96k adds no content >20 kHz (spec-based, not yet measured — our sweep stopped at 20 kHz).
- ✅ **2-mic DDR stereo array** — WORKS, both channels verified independent (Audacity + tap test).
  Config `2AMi2o8xxxxxx_mic2_48` (48 kHz stereo). Committed `c032bae`. This is the array foundation.
  Benchmarks in `Recordings/mic2_48/` (git-ignored). Pushed to origin/my-changes @ `48bef45`.
- ✅ **2-mic DDR stereo @ 96 kHz** — WORKS, both channels verified (tap test). Config
  `2AMi2o8xxxxxx_mic2_96` — a straight combine of the DDR 2-mic + 96k HQ clocking. Benchmarks in
  `Recordings/mic2_96/` (git-ignored). Levels healthy, in line with the other configs.
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
1. **4-mic array @ 48k/96k** — DONE (verified, committed d9f4634).
2. **Ultrasonic (141.12 kHz) on the 4-mic array** — IN PROGRESS. Config `2AMi4o8xxxxxx_mic4_us`
   (UNCOMMITTED). Rate now WORKS; blocked on NOISE. See "Ultrasonic 141kHz" section below.
3. **Measure with an ULTRASONIC source** — jingling keys / "sssss" / finger snaps. Normal speakers &
   20kHz sweep files CANNOT emit >20kHz, so they can't reveal the extended band.

## Ultrasonic 141.12 kHz — status (config 2AMi4o8xxxxxx_mic4_us, UNCOMMITTED)  RESUME HERE
Reviving ultrasonic = (a) faster PDM clock (mic ultrasonic mode), (b) accept non-standard 141.12kHz
USB rate, (c) design a wide Stage-2 filter. (a)+(b) done; (c) later.
- Config `mic4_us` = 4-mic SDR/PORT_4F setup + ultrasonic clocking (MCLK 22.5792MHz ÷5 = 4.51584MHz
  PDM = T5838 ultrasonic; ÷32÷1 = 141.12kHz out, Nyq 70.56kHz). Needs -mcmodel=large. Same wiring as
  mic4_48/96 (clock stays 1.8V direct). Added to CMakeLists (uncommitted).

### ✅ SOLVED: USB "no configurations available" / empty Rates (the 141kHz wall)
- ROOT CAUSE: 141120 is NON-STANDARD. lib_xua's UAC2 clock RANGE handler (xua_ep0_uacreqs.xc ~L892)
  only advertises STANDARD rates via hardcoded doubling logic. MIN=MAX=141120 matches none -> clock
  advertises ZERO rates -> `/proc/asound/cardN/stream0` shows `Rates:` EMPTY -> arecord "no
  configurations available". (Same reason the old micus got Windows Code 10 — invalid rate all along.)
- FIX (NO lib_xua patch): lib_xua has a built-in `SAMPLE_RATE_LIST` hook (xua_ep0_uacreqs.xc:946).
  Added `-DSAMPLE_RATE_LIST=141120` to the mic4_us build config -> clock advertises 141120 -> ALSA
  records. It's in OUR CMakeLists, not a dependency patch. (micus would need the same if revived.)

### 141kHz NOISE — fully diagnosed 2026-07-23. lib_mic_array decimator CEILING ~ -55 dBFS.  <-- DECISION POINT
THE PROBLEM: mic4_us records at 141kHz but noise floor is ~-44 to -55 dBFS (vs -108/-114 clean at
48/96k). The T5838 in ultrasonic mode (5th-order sigma-delta) pushes shaped quantisation noise into
the bands that fold down during the /32 decimation; the anti-alias filter can't reject it enough.

RULED OUT (all tested empirically):
- Wiring: shortened mic3 DATA leads (no change); shortened mic2 CLOCK + only 1 mic clocked (no change,
  still -44). Disconnected-clock channels read TRUE ZERO -> the noise is generated by the CLOCKED mic,
  not pickup. So NOT data leads, NOT clock, NOT the TXB0104.
- Wrong clock/mode: datasheet Table (user) — HQ 2.0-3.7MHz, ULTRASONIC 4.2-4.8MHz, both SNR 68 dBA.
  We run 4.51584MHz = dead centre of ultrasonic. So mode is correct AND the mic is CAPABLE of a clean
  ~-109 dBFS floor. The -55 is OUR decimation, not the mic.
- The mic itself: same T5838 on an Arduino (nRF52840 PDM, HARDWARE decimator) gave CLEAN ~40kHz
  content. Arduino PDM lib does NO software filtering — all decimation is nRF SILICON. So clean US IS
  achievable; the gap is lib_mic_array's software int16 filter vs a hardware decimator.

FILTER PROGRESSION (numpy floor of quiet recordings, 4ch, all in Recordings/ or app dir):
  CIC(moving-avg) order5 = -44 ; order7 = -50 ; order9 = OVERFLOW (int gain, Right-shift=INT32_MIN).
  Custom FIR stage1 kaiser 256-tap = -56.7 (40k band) ; remez 256-tap = -55.1 (48k band, SILENT).
=> HARD CEILING ~ -55 dBFS. Two different 256-tap FIR designs land the same -> it's the int16 /
   256-tap-fixed Stage-1, NOT filter design. lib_mic_array Stage-1 is HARDWIRED to 256 taps
   (Decimator.hpp: 8-word PDM history + fir_1x16_bit VPU op) so 512 taps is NOT possible either.

CURRENT mic_array.cpp STATE (UNCOMMITTED, in the lib_xua dep): 141120 case routed to its OWN
  stage1_us_coefs (256-tap remez FIR, pass 48k / stop 93k) + stage2_us_coefs (96-tap, shift 1).
  48k/96k unchanged. Built clean, records 4ch@141120, floor -55.1 dBFS, passband covers 48kHz.

### THE DECISION (needs user's application requirement)
User needs >= 48kHz bandwidth (confirmed). We have that at ~-55 dBFS. Options:
1. ACCEPT ~-55 dBFS + 4-mic beamforming (~+6dB -> ~-61 effective). Fine for LOUD ultrasonic sources
   (leaks/emitters/transducers). Need to know: how loud are the sources / what SNR does the beamformer need?
2. CUSTOM higher-precision decimator on the XU316 VPU (bypass lib_mic_array's int16 Stage-1, do
   PDM->PCM like the nRF hardware). Real DSP project. Only if faint ultrasound is required.

### Ultrasonic filter-design toolchain (repo: filter_design/)
- venv ~/fdesign: scipy, matplotlib, `pip install -e /home/alice/XMOS/lib_mic_array/python`.
- `design_ultrasonic.py` = CIC/moving-average approach (DEAD END, kept for history).
- `design_ultrasonic_fir.py` = custom FIR stage1 (remez), int16 + stage2-sum-cap<2^31 (avoids the
  emitter's shr int64 overflow). Knobs: S1_PASS/S1_STOP/S1_WEIGHT, S2_CUTOFF. THIS is the live one.
- Emit C: `~/fdesign/bin/python lib_mic_array/python/stage1.py ultrasonic_filter_int.pkl` (+ stage2.py).
  Paste both blocks -> wire stage1_us_coefs / stage2_us_coefs / stage2_us_shift into mic_array.cpp.
- ⚠️ ALL ultrasonic work UNCOMMITTED: mic_array.cpp (dep, must fold into lib_xua-mic_array-141120.patch),
  CMakeLists mic4_us/mic4_96 + SAMPLE_RATE_LIST, filter_design/ scripts. Commit once the path is chosen.

## 4-mic array — port investigation (2026-07-08)
Assume T5838 is **1.8 V only** (user is confirming with TDK; 3.3 V explored, datasheet says no) →
level shifters ARE required to reach 4 mics.

### Level shifting (only the DATA lines need it)
- Clock stays on X1D12 (1E, 1.8 V) direct to all mics — NO shifter needed (fan-out is fine).
- Each PDM data line needs a FAST unidirectional 1.8 V→3.3 V translator. PDM toggles at 3.072 MHz
  (HQ) / ~4.5 MHz (ultrasonic).
- ⚠️ Do NOT use BSS138 "logic level converter" breakouts (I2C-speed, ≤~1 MHz).
- Reliable endgame part: fixed-direction TI SN74LVC2T45 / SN74AVC2T245 (or 4-ch SN74LVC4T245 for
  the 4 SDR data lines). A-side=1.8 V (mics), B-side=3.3 V (XMOS).
- **TXB0104 (user HAS one) = OK for PROTOTYPING the 4 data lines.** It's 4-ch = exactly 4 SDR mics.
  Its worst cases (bidirectional buses, continuous clocks) are BOTH avoided here: PDM data is
  unidirectional, and the clock stays 1.8 V direct on 1E (never through the shifter). 3 MHz << its
  ~100 Mbps rating. Real risk = weak drivers (~4 kΩ) drooping with trace capacitance → noise/glitches.
  Wire: A=1.8 V mics (VCCA=1.8), B=3.3 V XMOS PORT_4F (VCCB=3.3), **OE pin HIGH**, common gnd,
  SHORT traces. If recordings are noisy/garbled → swap to LVC. Good enough to prove 4 mics work.

### Port map facts (authoritative — from XTC tools configs/XS3-UnA-1024-TQ128.pkg)
Re-derive with: `awk '...' configs/XS3-UnA-1024-TQ128.pkg` (parse <Pin>/<Port> blocks; filter X1D).
- **XS3 has NO 2-bit ports** (widths are 1/4/8/16/32). >1 data line ⇒ need a 4-bit port.
- The "free" ADC pins 1I–1L (X1D24/25/34/35) are **1-bit-only** → useless for a multi-line data port.
- Chip-free 4-bit ports were 4C/4D/4E/4F; had to cross-check the BOARD net table (hardware manual)
  to see which are physically broken out — that's the real gate.

### THE GATE — RESOLVED (board net table, XK-AUDIO-316-MC hardware manual, 2026-07-08)
Checked the board "Pin / Port / Board Net" table. Findings for the candidate 4-bit ports:
- **PORT_4D (X1D16–19) = NO GOOD** — board net XL_UP*/XL_DN* = **xSCOPE DEBUG xLink**. Using it
  sacrifices xSCOPE trace/debug output and the pins route to the debug circuit. Avoid.
- **PORT_4F (X1D28,29,30,31) = ✅ TARGET for 4 mics.** All four are broken-out **GPIO** (board net =
  pin name), contiguous → easy to route. 4 mics SDR (all SELECT→GND) or 8 mics DDR.
- **PORT_4E (X1D26,27,32,33) = ✅** also all GPIO, but split pins (less convenient).
- **PORT_8C (X1D26–X1D33) = ✅ full 8-bit GPIO port** → up to 8 SDR / 16 DDR mics. Use THIS if the
  array may grow past 4 (future-proof).
- Lone GPIO pins also broken out: X1D09, X1D12 (=1.8V, current mic clk), X1D15 — but 1-bit only.

### Firmware for 4 mics — ✅ VERIFIED ON HARDWARE 2026-07-21
- `xua_conf.h` REFACTORED: `MIC_ARRAY_CONFIG_USE_DDR` and `_PORT_PDM_DATA` are now `#ifndef`-guarded
  so a build config can override them. Existing mic1/mic2 configs unchanged (still DDR-on-1H).
- Config `2AMi4o8xxxxxx_mic4_48`: XUA_NUM_PDM_MICS=4, 48kHz, I2S_CHANS_ADC=0, SDR
  (`-DMIC_ARRAY_CONFIG_USE_DDR=0`), `-DMIC_ARRAY_CONFIG_PORT_PDM_DATA=XS1_PORT_4F`.
- Built clean — NO PORT_16B/4F (MCLK_COUNT_2) clash after all. Enumerates 4ch UAC2.0.
- Tap test (analysed in numpy): all 4 mics live, ~30-40 dB channel isolation, SDR de-interleave
  correct. **Channel map = natural port-bit order: X1D28->ch1, X1D29->ch2, X1D30->ch3, X1D31->ch4.**
- Wired via Adafruit TXB0104 (1875) level shifter, OE self-enabled (onboard 10k pull-up), NO
  decoupling caps — and they turn out NOT to be needed: controlled benchmarks show a clean matched
  noise floor (the earlier ~-90 dBFS was an uncontrolled/handling recording, not the real floor).
- `2AMi4o8xxxxxx_mic4_96` — same 4-mic SDR array @ 96kHz (adds the 96k HQ clocking; PDM is 3.072MHz
  at BOTH rates so NO rewiring). VERIFIED 2026-07-21.
- BENCHMARKS (Recordings/mic4_{48,96}/, 4ch, git-ignored):
  * 48k silence ~-108 dBFS (all 4 ch matched); 96k silence ~-114 dBFS (all 4 ch matched, best yet).
  * Channels balanced within ~1 dB on speech; all-positive correlation on speech (shared voice).
  * 1kHz tone: mic pairs (1,3) & (2,4) at ~-1.00 correlation (half-wavelength anti-phase) → real
    spatial diversity. Array is beamformer-ready.
- TODO polish (optional): tie unused-bit port inputs to GND if a config ever uses < full port width.

### Wiring the 4 mics (BOM + connections)
- BOM: 4× T5838 (on breakouts), the TXB0104 (4-ch, user has it), 1.8V supply (AP3429A buck),
  **4× 0.1µF ceramic decoupling caps — MUST ADD, user confirmed breakouts have NONE** (one per mic
  VDD, close to the pin — else supply noise → hiss), short hook-up wire.
- CLOCK: X1D12 (1.8V, PORT_1E) → fan out to all 4 mics' CLK. DIRECT, no shifter.
- DATA (through TXB0104, A=1.8V in, B=3.3V out): mic1→X1D28(P4F0), mic2→X1D29(P4F1),
  mic3→X1D30(P4F2), mic4→X1D31(P4F3).
- ALL 4 mics SELECT→GND (SDR). TXB: VCCA=1.8V, VCCB=3.3V, **OE→HIGH**, all grounds common.
- Confirm X1D28-31 are on a reachable header/pad (net table says GPIO → should be broken out).
- ⚠️ data through TXB, clock stays 1.8V direct (don't route clock through the shifter).
⚠️ BUILD-TIME CHECK: 4E/4F/8C share pins with PORT_16B (declared PORT_MCLK_COUNT_2 in the .xn). If
the firmware uses MCLK_COUNT_2 on tile 1, the tools will flag a port-resource clash when claiming
4F/8C — resolve by relocating/dropping MCLK_COUNT_2 (likely unused in the mic config).

### Still required regardless: level shifters
3.3 V port ↔ 1.8 V mics. Data lines only (clock stays 1.8 V on 1E). FAST fixed-direction translators
(SN74LVC2T45 / LVC4T245); NOT BSS138 breakouts, NOT auto-dir TXB/TXS. See level-shifting notes above.
