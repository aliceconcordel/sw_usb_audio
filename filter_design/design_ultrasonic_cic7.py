# Copyright 2026 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

"""
Design the CIC-order-7 stage-1/stage-2 decimation filter for the T5838
Ultrasonic-mode, 4-mic array capture (config `2AMi4o8xxxxxx_mic4_us`).

Background
----------
The T5838 in Ultrasonic mode (PDM clock 4.51584 MHz) is decimated on-chip by
lib_mic_array to 141.12 kHz (stage 1 /32, stage 2 /1). lib_mic_array's stage-1
filter is a fixed 256-coefficient block (`Stage1Filter.BLOCK_SIZE`), so the
only stage-1 knob is an N-stage moving-average (CIC) filter, built with
`design_filter.design_2_stage(..., ma_stages=N)`.

We benchmarked several stage-1 designs on real hardware, quiet room, ch1 RMS:
  order 5  -> -44.1 dBFS   (raw tap count 32+4*31=156)
  order 7  -> -50.2 dBFS   (raw tap count 32+6*31=218)  <-- CHOSEN
  order 9  -> raw tap count 32+8*31=280 > 256 -> exceeds Stage1Filter's
              hard 256-tap block size, breaks (this is what "order 9
              overflowed" meant - not a numeric overflow, a structural limit)
  custom FIR (Kaiser/remez) stage-1 -> -55 to -57 dBFS, but narrower passband

Order 7 was chosen over the custom FIR designs: for our use case (loud,
transient ultrasonic sources - explosions), the wider ~46-48 kHz passband
matters more than the extra ~6-7 dB of stopband rejection the FIR gives.

Usage
-----
Run inside the venv that already has lib_mic_array's python package installed
(`pip install -e <lib_mic_array>/python`, per HANDOFF.md):

    python filter_design/design_ultrasonic_cic7.py

This writes `ultrasonic_cic7_int.pkl` next to this script. Then generate the
C header (from the lib_mic_array python/ dir, so combined.py's imports resolve):

    cd <lib_mic_array>/python
    python combined.py <path>/ultrasonic_cic7_int.pkl -fp ultrasonic_cic7 -fd <path>

That produces `ultrasonic_cic7.h` with arrays `ultrasonic_cic7_stg1_coef[]`,
`ultrasonic_cic7_stg2_coef[]` and defines `ULTRASONIC_CIC7_STG1_TAP_COUNT`,
`ULTRASONIC_CIC7_STG2_TAP_COUNT`, `ULTRASONIC_CIC7_STG2_SHR`,
`ULTRASONIC_CIC7_STG2_DECIMATION_FACTOR`. See
`ULTRASONIC_FILTER_INTEGRATION.md` in this repo for how to wire that header
into the lib_xua `mic_array.cpp` patch.
"""

import os
import sys

# so `import filter_design.design_filter` works whether this is run from the
# repo root or from inside filter_design/
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from filter_design.design_filter import design_2_stage, stage_params
from filter_design import filter_tools as ft


def ultrasonic_cic7_filter(int_coeffs=True):
    """
    2-stage decimation filter: T5838 Ultrasonic-mode PDM (4.51584 MHz) ->
    141.12 kHz PCM, 4-mic array.

    Stage 1: 7-stage moving-average (CIC), decimation /32.
    Stage 2: windowed-FIR compensation filter, decimation /1 (no further
    rate change - it exists purely to flatten stage-1's passband droop and
    reject images/aliases up to Nyquist).
    """

    # PDM clock in T5838 Ultrasonic mode (datasheet range 4.2-4.8 MHz; this is
    # the exact value used by the `micus`/`mic4_us` build configs: MCLK_441
    # 22.5792 MHz / 5).
    fs_0 = 4515840

    # /32 (stage 1, fixed by lib_mic_array) then /1 (stage 2) -> 141.12 kHz out.
    decimations = [32, 1]

    # Stage 1: 7-stage moving average. Raw tap count = 32 + 6*31 = 218,
    # safely under lib_mic_array's 256-tap block size (order 9 would be 280 -
    # over the limit, which is why it broke).
    ma_stages = 7

    # Stage 2: compensate stage-1 rolloff and reject aliases beyond ~46 kHz.
    # cutoff/transition chosen to match the measured passband of the original
    # order-7 recording (test_us_ma7.wav): flat to ~44-46 kHz, floor by ~52 kHz.
    cutoff = 46000
    transition_bandwidth = 4000
    taps_2 = 256
    fir_window = ("kaiser", 7)
    stage_2 = stage_params(cutoff, transition_bandwidth, taps_2, fir_window)

    coeffs = design_2_stage(fs_0, decimations, ma_stages, stage_2,
                             int_coeffs=int_coeffs, compensate_s1=True)

    return coeffs


def main():
    coeffs = ultrasonic_cic7_filter(int_coeffs=True)
    out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ultrasonic_cic7_int.pkl")
    ft.save_packed_filter(out_path, coeffs)
    print(f"Wrote {out_path}")
    print(f"Stage 1: {len(coeffs[0][0])} raw taps (moving-average order 7), decimation /{coeffs[0][1]}")
    print(f"Stage 2: {len(coeffs[1][0])} taps, decimation /{coeffs[1][1]}")
    print()
    print("Next: generate the C header with combined.py, e.g. from the")
    print("lib_mic_array python/ directory:")
    print(f"  python combined.py {out_path} -fp ultrasonic_cic7 -fd .")


if __name__ == "__main__":
    main()
