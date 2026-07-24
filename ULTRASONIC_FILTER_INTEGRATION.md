# Wiring the CIC-order-7 ultrasonic filter into `mic_array.cpp`

Context: Alice's local copy of the patched `lib_xua/src/core/pdm_mics/mic_array.cpp`
(the one `lib_xua-mic_array-141120.patch` extends) was lost. This doc + the
`filter_design/design_ultrasonic_cic7.py` script let you regenerate the CIC-7
filter (the one behind `test_us_ma7.wav`: ~46-48 kHz passband, ~-51 dBFS floor)
from scratch, using XMOS's own public filter-design toolchain (`lib_mic_array`'s
`filter_design/design_filter.py` + `stage1.py`/`stage2.py`/`combined.py`) - no
hand-typed coefficients.

## 1. Generate the filter header

In the venv that already has `lib_mic_array`'s python package installed
(`pip install -e <lib_mic_array>/python`, per HANDOFF.md's `~/fdesign` venv):

```bash
# from the sw_usb_audio repo root
python filter_design/design_ultrasonic_cic7.py
# -> writes filter_design/ultrasonic_cic7_int.pkl

# combined.py needs to run from lib_mic_array's python/ dir so its local
# imports (mic_array.filters, header_utils) resolve
cd <lib_mic_array>/python
python combined.py <path-to-sw_usb_audio>/filter_design/ultrasonic_cic7_int.pkl \
    -fp ultrasonic_cic7 -fd <path-to-sw_usb_audio>/filter_design
```

This produces `filter_design/ultrasonic_cic7.h`, containing:
- `uint32_t ultrasonic_cic7_stg1_coef[...]`
- `int32_t ultrasonic_cic7_stg2_coef[...]`
- `#define ULTRASONIC_CIC7_STG1_TAP_COUNT`, `_STG2_TAP_COUNT`, `_STG2_SHR`,
  `_STG2_DECIMATION_FACTOR`

Sanity check before touching any C++: the script prints the raw stage-1 tap
count, which must be 218 (7-stage moving average) - if it prints something
else, the `ma_stages` parameter was changed and the analysis below no longer
applies.

## 2. Wire it into `mic_array.cpp`

This is the part I can't do blind - I don't have the current content of your
local `lib_xua/src/core/pdm_mics/mic_array.cpp` (it's fetched as an external
dependency, not vendored in this repo), only the fragment shown by
`lib_xua-mic_array-141120.patch`, which has this shape:

```cpp
constexpr int decimation_factor = (XUA_PDM_MIC_FREQ == 141120 || XUA_PDM_MIC_FREQ == 96000) ? 1 : ...
constexpr int stage_2_tap_count = (XUA_PDM_MIC_FREQ == 48000 || XUA_PDM_MIC_FREQ == 141120 || XUA_PDM_MIC_FREQ == 96000) ? MIC_ARRAY_48K_STAGE_2_TAP_COUNT : ...
constexpr const uint32_t* stage_1_filter() {
    return (XUA_PDM_MIC_FREQ == 48000 || XUA_PDM_MIC_FREQ == 141120 || XUA_PDM_MIC_FREQ == 96000) ? &stage1_48k_coefs[0] : ...
}
constexpr const int32_t* stage_2_filter() { ... }
constexpr const right_shift_t* stage_2_shift() { ... }
```

Copy `filter_design/ultrasonic_cic7.h` next to `mic_array.cpp` (or add its
directory to the include path), then:

1. `#include "ultrasonic_cic7.h"` near the top of `mic_array.cpp`.
2. In `stage_1_filter()`, split the `141120` case out of the shared
   `48000 || 141120 || 96000` group and point it at the new array:
   ```cpp
   constexpr const uint32_t* stage_1_filter() {
       if (XUA_PDM_MIC_FREQ == 141120) return &ultrasonic_cic7_stg1_coef[0];
       return (XUA_PDM_MIC_FREQ == 48000 || XUA_PDM_MIC_FREQ == 96000) ? &stage1_48k_coefs[0] : ...;
   }
   ```
3. Same split in `stage_2_filter()` and `stage_2_shift()`, pointing the
   `141120` case at `&ultrasonic_cic7_stg2_coef[0]` and
   `ULTRASONIC_CIC7_STG2_SHR` respectively.
4. Update `stage_2_tap_count` for the `141120` case to
   `ULTRASONIC_CIC7_STG2_TAP_COUNT` instead of the reused
   `MIC_ARRAY_48K_STAGE_2_TAP_COUNT`.
5. `decimation_factor` for `141120` stays `1` (unchanged - stage 2 doesn't
   decimate further, it's just the compensation filter).

Re-fold the result into `lib_xua-mic_array-141120.patch` (`git diff` against a
clean `lib_xua` checkout, from the `lib_xua` dependency root - see HANDOFF.md's
"re-apply after any fresh dep fetch" note) so it survives a `xmake` dependency
refetch.

## 3. Build, flash, record

Use `run_ultrasonic_test.sh` (repo root) - see its header comment for usage.
It wraps the build/flash/record steps documented in HANDOFF.md for the new
`2AMi4o8xxxxxx_mic4_us` config.

## Expected result

Quiet room, channel 1: flat ~-14 to -15 dB from DC to ~44 kHz, rolling off to
a floor around -51 dB by ~52-60 kHz (this is what `test_us_ma7.wav` measured -
see the analysis in-conversation). If the floor or rolloff point is
noticeably different, something in the filter regeneration or the
`mic_array.cpp` wiring drifted from the original - re-check step 2.
