cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)

set(APP_INCLUDES src src/core src/extensions)
set(XMOS_SANDBOX_DIR ${CMAKE_CURRENT_LIST_DIR}/../..)
include(${CMAKE_CURRENT_LIST_DIR}/../deps.cmake)

set(APP_PCA_ENABLE ON)

set(SW_USB_AUDIO_FLAGS ${EXTRA_BUILD_FLAGS} -O3
                                            -report
                                            -lquadflash
                                            -g
                                            -Wall
                                            -fxscope
                                            -DBOARD_SUPPORT_BOARD=XK_AUDIO_316_MC_AB
                                            -DADAT_TX_USE_SHARED_BUFF=1)

#
# HiBW configs
#
include(${CMAKE_CURRENT_LIST_DIR}/configs_hibw.cmake)

project(app_usb_aud_xk_316_mc)
set(APP_HW_TARGET xk-audio-316-mc.xn)


# Build config naming scheme:
#
# Audio Class:   1 or 2
# Sync Mode      A(sync) or S(ync)
# I2S            M(aster) or S(lave)
# Input          enabled: i (channelcount)
# Output         enabled: o (channelcount)
# MIDI           enabled: m, disabled: x
# SPDIF in       enabled: s, disabled: x
# SPDIF out      enabled: s, disabled: x
# ADAT in        enabled: a, disabled: x
# ADAT out       enabled: a, disabled: x
# DSD out        enabled: d, disabled: x
#
# e.g. 2AMi10o10xxsxxx: Audio class 2.0, Asynchronous, I2S Master, input and output enabled (10 channels each), no MIDI, SPDIF output, no SPDIF input, no ADAT
#
# Additional tags may be added to the end of the build config name to indicate special features or configurations.

#
# Tested build configs
#

# Audio Class 2, Async, I2S Master, 8xInput, 8xOutput
set(APP_COMPILER_FLAGS_2AMi8o8xxxxxx ${SW_USB_AUDIO_FLAGS})

# Audio Class 2, Async, I2S Master, 8xInput + 1 PDM mic (9 in), 8xOutput. Locked to 48kHz.
set(APP_COMPILER_FLAGS_2AMi9o8xxxxxx_mic1 ${SW_USB_AUDIO_FLAGS}  -DXUA_NUM_PDM_MICS=1
                                                                -DXUA_PDM_MIC_FREQ=48000
                                                                -DMIN_FREQ=48000
                                                                -DMAX_FREQ=48000)

# TEST: mic-only input - no analog inputs, so the PDM mic is USB input channel 1 (mono).
# Lets Windows/Audacity see it as a plain mono mic (avoids the 2-channel capture limit). 48kHz.
set(APP_COMPILER_FLAGS_2AMi1o8xxxxxx_mictest ${SW_USB_AUDIO_FLAGS} -DXUA_NUM_PDM_MICS=1
                                                                   -DXUA_PDM_MIC_FREQ=48000
                                                                   -DMIN_FREQ=48000
                                                                   -DMAX_FREQ=48000
                                                                   -DI2S_CHANS_ADC=0)

# TEST: ULTRASONIC mic. 44.1k-family MCLK (22.5792MHz) / 5 = 4.51584MHz PDM = T5838 ultrasonic mode.
# /32 (stage1) /1 (stage2) = 141.12kHz output, Nyquist 70.56kHz. First-pass reuses 48k filter
# (band-limited ~29kHz) to validate clock/USB plumbing before designing the wide ultrasonic filter.
set(APP_COMPILER_FLAGS_2AMi1o8xxxxxx_micus ${SW_USB_AUDIO_FLAGS} -DXUA_NUM_PDM_MICS=1
                                                                -DXUA_PDM_MIC_FREQ=141120
                                                                -DMIN_FREQ=141120
                                                                -DMAX_FREQ=141120
                                                                -DI2S_CHANS_ADC=0
                                                                -DMIC_ARRAY_CONFIG_MCLK_FREQ=22579200
                                                                -DMIC_ARRAY_CONFIG_PDM_FREQ=4515840
                                                                -mcmodel=large)

# 96kHz HighQuality mic. 48k-family MCLK (24.576MHz) / 8 = 3.072MHz PDM = T5838 HighQuality mode.
# /32 (stage1) /1 (stage2) = 96kHz output. Reuses 48k filter; in HQ mode mic BW is ~20kHz so the
# ~24kHz filter passband is no real loss. Standard USB rate -> no Windows Code 10.
set(APP_COMPILER_FLAGS_2AMi1o8xxxxxx_mic96 ${SW_USB_AUDIO_FLAGS} -DXUA_NUM_PDM_MICS=1
                                                                -DXUA_PDM_MIC_FREQ=96000
                                                                -DMIN_FREQ=96000
                                                                -DMAX_FREQ=96000
                                                                -DI2S_CHANS_ADC=0
                                                                -DMIC_ARRAY_CONFIG_MCLK_FREQ=24576000
                                                                -DMIC_ARRAY_CONFIG_PDM_FREQ=3072000)

# Audio Class 2, Async, I2S Master, 10xInput, 10xOutput, S/PDIF Tx, S/PDIF Rx
set(APP_COMPILER_FLAGS_2AMi10o10xssxxx ${SW_USB_AUDIO_FLAGS}   -DXUA_SPDIF_TX_EN=1
                                                               -DXUA_SPDIF_RX_EN=1)
# Audio Class 2, Async, I2S Master, 16xInput, 16xOutput, ADAT Tx, ADAT Rx
set(APP_COMPILER_FLAGS_2AMi16o16xxxaax ${SW_USB_AUDIO_FLAGS}   -DXUA_ADAT_RX_EN=1
                                                               -DXUA_ADAT_TX_EN=1)

# Audio Class 2, Async, I2S Master, 16xInput, 16xOutput, ADAT Tx, ADAT Rx
# Note, limited to 96kHz sample rate
set(APP_COMPILER_FLAGS_2AMi18o18mssaax ${SW_USB_AUDIO_FLAGS}   -DMIDI=1
                                                               -DXUA_ADAT_RX_EN=1
                                                               -DXUA_ADAT_TX_EN=1
                                                               -DXUA_SPDIF_TX_EN=1
                                                               -DXUA_SPDIF_RX_EN=1
                                                               -DMAX_FREQ=96000)

#
# Partially-tested build configs
#
include(${CMAKE_CURRENT_LIST_DIR}/configs_partial.cmake)

#
# Build (only) tested build configs
#
include(${CMAKE_CURRENT_LIST_DIR}/configs_build.cmake)

#
# Build configs used only for testing purpses
#
include(${CMAKE_CURRENT_LIST_DIR}/configs_test.cmake)

XMOS_REGISTER_APP()
