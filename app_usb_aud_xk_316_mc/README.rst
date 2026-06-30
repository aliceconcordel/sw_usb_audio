XMOS xcore.ai USB Audio
=======================

:scope: Example
:description: USB Audio application for xcore.ai MC Audio
:keywords: USB, UAC
:boards: XK-AUDIO-316-MC

Overview
........

The firmware provides a high-speed USB Audio device designed to be compliant to version 2.0 of the
USB Audio Class Specification based on the xcore.ai device.

Key Features
............

The app_usb_aud_xk_316_mc application is designed to run on the xcore.ai Multichannel Audio Board.
It uses the XMOS USB Audio framework to implement a USB Audio device with the following key features:

- USB Audio Class 1.0/2.0 Compliant

- Fully Asynchronous operation

- 8 channels analogue input and 8 channels analogue output (Via I²S to 4 x Stereo DACs and 2 x Quad-channel ADCs)

- S/PDIF output (via COAX connector)

- Supports for the following sample frequencies: 44.1, 48, 88.2, 96, 176.4, 192kHz

- MIDI input and output

PDM Microphone (T5838) — build, run and record on Linux
.......................................................

This fork adds single PDM-microphone support (TDK T5838 on the board's 1.8 V GPIO pins
X1D12/X1D23, ports 1E/1H — no level shifter needed). The known-good config is
``2AMi1o8xxxxxx_mictest`` (mic-only, mono, 48 kHz).

Set up the XTC Tools environment. ``SetEnv`` derives its paths from ``$PWD``, so it must be
sourced from inside the tools directory::

    cd /path/to/XMOS/XTC/15.3.1 && source ./SetEnv

Build and run::

    cd app_usb_aud_xk_316_mc
    cmake -G "Unix Makefiles" -B build          # first time only; fetches dependencies
    xmake -C build 2AMi1o8xxxxxx_mictest
    xrun bin/2AMi1o8xxxxxx_mictest/app_usb_aud_xk_316_mc_2AMi1o8xxxxxx_mictest.xe

``xrun`` loads into RAM (lost on power-cycle); use ``xflash`` with the same ``.xe`` for a
persistent image. On Linux the device enumerates as an ALSA UAC2.0 capture device,
**XMOS xCORE.ai MC (UAC2.0)** — confirm with ``arecord -l``.

One-time USB permission setup (if ``xrun`` reports a ``0x20b1`` permissions error) — install the
udev rules shipped with the tools, then replug the XTAG DEBUG cable::

    cd /path/to/XMOS/XTC/15.3.1/scripts && sudo ./setup_xmos_devices.sh

Record with Audacity: set the audio host (ALSA / PulseAudio / PipeWire), select
**XMOS xCORE.ai MC (UAC2.0)** as the input, set channels to **1 (Mono)** and the project rate
to **48000 Hz**, then Record. Quick command-line check (``hw:N`` from ``arecord -l``)::

    arecord -D hw:3,0 -c 1 -f S24_3LE -r 48000 -d 3 test.wav && aplay test.wav

Known Issues
............

- None

See README in sw_usb_audio for general issues.

Support
.......

For all support issues please visit http://www.xmos.com/support


