# Session notes — 2026-07-29

Two unrelated threads: a quick check of the coworker's XMOS fork, then a long
session on **gccphat-realtime** (the C#/Avalonia beamforming UI, a *different*
repo from this one) — getting it to run on Linux, enabling YAMNet
classification, and fixing three bugs in the audio feeding the classifier.

XMOS firmware itself was **not** touched today. See [HANDOFF.md](HANDOFF.md) for
that project's state.

---

## 1. Coworker's XMOS fork — nothing new

Fetched `pmarmaroli`'s fork of `sw_usb_audio`. **No new commits.** All three of
his branches were already merged or behind:

| Branch | At | |
| --- | --- | --- |
| `pmarmaroli/pm-ultrasonic-tests` | `6646fc8` | his CIC-7 work — already merged |
| `pmarmaroli/my-changes` | `6637440` | your old HANDOFF — behind you |
| `pmarmaroli/develop` | `9dbec00` | XMOS upstream, unchanged |

Local `my-changes` is at `13f8b7a`, **2 commits ahead** of him (`d8120db`
CIC-7 integration + `13f8b7a` gitignore). Nothing to pull.

## 2. Git over SSH does not work on this machine — use HTTPS

`git@github.com: Permission denied (publickey)` happens because **there is no
SSH key**: `~/.ssh/` contains only `known_hosts` and an empty `authorized_keys`,
and `ssh-add -l` reports no identities.

Nothing needs fixing — every remote here is already HTTPS and works:

```
origin      https://github.com/aliceconcordel/sw_usb_audio.git
pmarmaroli  https://github.com/pmarmaroli/sw_usb_audio.git
upstream    https://github.com/xmos/sw_usb_audio.git
```

If you clone something new, take the **HTTPS** URL from GitHub's green *Code*
button, not the SSH one. (Or generate a key with `ssh-keygen -t ed25519` and add
the `.pub` to GitHub, if you'd rather use SSH.)

## 3. ⚠️ Recordings moved off the system disk

The root partition is only **39 GB** and was repeatedly hitting 100% full, which
broke installs mid-flight. The WAV files were moved (**not deleted**):

| Was | Now |
| --- | --- |
| `xKozxMOS/Recordings/` (986 MB) | `/media/alice/New Volume/XMOS_Recordings_Backup/Recordings/` |
| `xKozxMOS/Test recordings/` (142 MB) | `/media/alice/New Volume/XMOS_Recordings_Backup/Test recordings/` |

Everything named in HANDOFF.md — `test_us_cic7.wav`, `test_us_ma7.wav`,
`test_us_filt1-2` — is under that folder. The external drive has ~920 GB free.

Other space reclaimed, all safe/regenerable: `~/.cache/vscode-cpptools` (1.9 GB),
`~/.cache/gnome-software`, `~/.cache/arduino`, unused-platform NuGet packages
(`skiasharp.nativeassets.win32|webassembly|macos` — ~1.5 GB of Windows/Mac/WASM
binaries pulled into a Linux build), and `journalctl --vacuum-size=100M`
(426 MB). LibreOffice was also purged.

**Watch this.** Disk sat at ~700 MB free at the end of the session.

## 4. gccphat-realtime on Linux — two silent traps

Full write-up committed to that repo as `LINUX_SETUP.md`. Summary:

**a) Ubuntu's .NET SDK is too old to build the Avalonia UI.**
`dotnet-sdk-8.0` bundles Roslyn 4.8; Avalonia 12.1's source generator needs
4.14. It doesn't fail cleanly — the generator is silently skipped and you get
~60 `CS0103` errors about `InitializeComponent`, `LevelPlot`, `MapCanvas` etc.
The real cause is a single `CS9057` warning higher up. Fixed by installing
**.NET 10.0.302** to `~/.dotnet` via Microsoft's `dotnet-install.sh` (user-local,
no sudo).

**b) `DOTNET_ROOT` breaks launching, which is why the GUI never appeared.**
This one cost most of the session. Setting `DOTNET_ROOT=$HOME/.dotnet` fixes the
*build* but breaks the *run*: the built `net8.0` app then looks for its runtime
only under `~/.dotnet`, finds just .NET 10, and exits immediately with
`You must install or update .NET`. Because `start.sh` launches with
`>/dev/null 2>&1`, that error is invisible — the script prints "Done. You can
close this window." and nothing opens.

`~/.bashrc` now has **`PATH` only, deliberately no `DOTNET_ROOT`**, with a
comment explaining why. Don't re-add it.

> Debugging lesson: when `start.sh` reports success but no window appears, run
> the binary directly to see its output —
> `./src/GccPhat.RealTime.Avalonia/bin/Release/net8.0/GccPhat.RealTime.Avalonia`.
> The ALSA/JACK noise it prints is normal PortAudio backend probing.

## 5. YAMNet classification — now working

`start.sh`'s auto-setup can't work on Ubuntu (pip refuses to install outside a
venv — PEP 668). Built manually instead:

- venv at **`~/.venvs/gccphat-yamnet`** — tensorflow 2.21.0, tensorflow-hub
  0.16.1, tf2onnx 1.17.0, **setuptools pinned to 80.10.2** (81+ removed
  `pkg_resources`, which `tensorflow_hub` still imports).
- Model converted from TFHub to ONNX opset 13 →
  `src/GccPhat.RealTime.Avalonia/Assets/yamnet.onnx` (16,109,956 bytes,
  md5 `09c8e272d1d9ccf5523ff8dd7d1e4217`) plus `yamnet_class_map.csv`.

**Gotcha worth remembering:** TensorFlow's install died twice on `ENOSPC` and
left a package that *looked* installed — `pip list` showed `tensorflow 2.21.0`
while `import tensorflow` failed with `No module named 'tensorflow.python'`.
A truncated pip install is not self-correcting; uninstall and reinstall.

## 6. Three bugs in the signal feeding YAMNet

Audited after you suspected the classifier input was wrong. It was.

**a) `CopyLatest` could return temporally scrambled audio at 96 kHz.**
The classifier asks for 1 s (`sampleRate` samples) but `ChannelRingBuffer` held
only 65536/channel. At 96 kHz that's 96000 > 65536, and `CopyLatest` checked
only `_written < n`, never the ring capacity — so it returned **`true`** and
copied 96000 samples out of a 65536-slot ring, wrapping ~1.5× and re-reading the
same slots. YAMNet was classifying a discontinuous window. `CopyRange` already
had the guard; `CopyLatest` didn't. Fixed both ways: added the guard **and**
raised `RingCapacity` `1<<16 → 1<<18`.

**b) Anti-alias filter too soft** — fixed 64/128-tap Hann sinc at 7 kHz, only
~20–30 dB down at YAMNet's 8 kHz Nyquist, so 8–9 kHz folded back while the
passband already rolled off from ~5.8 kHz. Replaced with a Kaiser design sized
from spec (passband 7.2 kHz, stop 8 kHz, 70 dB): 261 taps @48 k, 521 @96 k.

**c) Zero-padded window edges** — every 1 s block was convolved against zeros at
both ends. Now reads window + filter context each side (2.75 ms) and emits only
the centre.

Verified by compiling the real `AudioResampler`/`ChannelRingBuffer` sources into
a test harness:

| | before | after |
| --- | --- | --- |
| Passband flatness (≤7 kHz) | rolled off from ~5.8 kHz | **0.001 dB** |
| Alias rejection (≥8 kHz) | ~20–30 dB | **83.6 dB** worst case |
| Window-edge error | 1.28e-1 | **0.0** |
| `CopyLatest(96000)` on 65536 ring | `true` + scrambled | **`false`** |

Core test suite: **31/31 pass**.

Deliberately **not** changed: classification still runs on one raw mic channel
rather than the beamformed output — your call, since per-mic classification is
what you want.

## 7. Where it all ended up

**PR: https://github.com/pmarmaroli/gccphat-realtime/pull/1** (open, mergeable)

You have no push access to pmarmaroli's repo (`"push": false`), so it went via a
fork: `aliceconcordel/gccphat-realtime`, branch `fix/classification-signal-chain`,
two commits — `af11f0b` (the fixes) and `d253916` (LINUX_SETUP.md).

⚠️ **A 16 MB `yamnet.onnx` was accidentally committed** in the original local
commit. It was kept out of the PR (a binary that size is permanent in git
history, and the csproj says model files aren't committed), `.gitignore` rules
were added, and local `main` was moved to the clean commit. The model file is
still on disk and the app runs fine.

CI hasn't run yet: GitHub requires a maintainer to approve workflows for a
first-time contributor from a fork. pmarmaroli must approve → review → merge.
Note CI only builds the **WPF** app on Windows, so it never exercises the
Avalonia project anyway.

## 8. Open items

- **141.12 kHz ultrasonic capture cannot be classified.** The resampler only
  supports integer multiples of 16 kHz (16/32/48/96). At 141120 Hz it throws
  `NotSupportedException`, swallowed by the classification loop's catch-all — so
  the UI says "YAMNet ready" and silently produces nothing forever. Fixing it
  means rational resampling (141120→16000 is exactly ×50/441) or pre-decimating
  to 48 kHz. Explicitly deferred.
- Surface that swallowed exception to the UI instead of discarding it.
- Disk still tight (~700 MB free).
