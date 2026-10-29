#!/usr/bin/env python3
"""Exact frequency response of the filter chain used by mic4_882 (88.2 kHz).

Reads the REAL coefficient arrays out of the patched lib_xua mic_array.cpp, undoes
lib_mic_array's bit-interleaved stage-1 packing, and evaluates the response at the
rates the hardware actually runs at:

    PDM 5.6448 MHz --[stage 1: 256-tap FIR, /32]--> 176.4 kHz
                   --[stage 2:  96-tap FIR,  /2]--> 88.2 kHz

The unpacking is validated by round-tripping through the library's own packer
(Stage1Filter.ToXCoreCoefArray) before anything is trusted.
"""
import re, sys
import numpy as np

sys.path.insert(0, "/home/alice/XMOS/lib_mic_array/python")
from mic_array import util                      # noqa: E402
from mic_array.filters import Stage1Filter       # noqa: E402

SRC = "/home/alice/XMOS/lib_xua/lib_xua/src/core/pdm_mics/mic_array.cpp"
FS0 = 5_644_800            # PDM clock, measured 5,644,514 Hz on X1D12
D1, D2 = 32, 2
FS1 = FS0 / D1             # 176_400
FS2 = FS1 / D2             # 88_200

text = open(SRC).read()


def array_body(name):
    m = re.search(name + r"\s*\[[^\]]*\]\s*=\s*\{(.*?)\};", text, re.S)
    if not m:
        sys.exit(f"could not find {name} in {SRC}")
    body = re.sub(r"//.*", "", m.group(1))
    return [int(t, 0) for t in re.findall(r"-?0x[0-9a-fA-F]+|-?\d+", body)]


s1_words = np.array(array_body("stage1_48k_coefs"), dtype=np.uint32)
s2_coefs = np.array(array_body("stage2_48k_coefs"), dtype=np.int64)
print(f"stage 1: {len(s1_words)} packed words (expect 128)")
print(f"stage 2: {len(s2_coefs)} taps          (expect 96)")


def unpack_stage1(words):
    """Inverse of Stage1Filter.ToXCoreCoefArray."""
    words = np.asarray(words, dtype=np.uint32)
    bits = ((words[:, None] >> np.arange(31, -1, -1, dtype=np.uint32)) & 1)   # col 0 = MSB
    bits = bits.reshape((words.size * 32 // 256, 8, 32))
    bits = np.flip(bits, axis=2)
    bits = np.flip(bits, axis=1)
    binary = bits.reshape(-1, 256).astype(np.int64)        # CoefBinary, shape (16, N)
    bipolar = 1 - 2 * binary                               # CoefBinary = (1 - bipolar.T)//2
    n = binary.shape[1]
    dual = util.int16_dual.astype(np.int64)
    return (bipolar.T @ dual) // 2, n                      # (bipolar @ dual) / 2 == x


# ---- validate the inverse against the library's own forward packer ----------
rng = np.random.default_rng(1)
probe = rng.integers(-32000, 32000, 256).astype(np.int16)
repacked = Stage1Filter(probe).ToXCoreCoefArray()
back, _ = unpack_stage1(repacked)
# The dual-vector decomposition quantises to the nearest representable value, so
# compare against what the library itself reads back rather than the raw input.
ref = util.int16_vect_to_bipolar_matrix(probe, util.int16_dual).astype(np.int64) @ util.int16_dual.astype(np.int64) // 2
assert np.array_equal(back, ref), "UNPACK DOES NOT MATCH THE LIBRARY'S PACKER"
print("unpack validated: round-trips through Stage1Filter.ToXCoreCoefArray exactly")

h1, n_taps = unpack_stage1(s1_words)
h1 = h1.astype(np.float64)
print(f"stage 1 taps recovered: {n_taps}, DC gain {h1.sum():.1f}, "
      f"symmetric: {np.allclose(h1, h1[::-1], atol=2)}")

h2 = s2_coefs.astype(np.float64)
print(f"stage 2 taps: {len(h2)}, DC gain {h2.sum():.4g}, symmetric: {np.allclose(h2, h2[::-1], rtol=1e-6)}")


def response(h, fs, freqs):
    n = np.arange(len(h))
    return np.array([np.abs(np.sum(h * np.exp(-2j * np.pi * f / fs * n))) for f in freqs])


# ---- combined response, in-band (0 .. Nyquist of the 88.2 kHz output) --------
f = np.linspace(0.0, FS2 / 2, 22051)                       # 2 Hz steps
H1 = response(h1, FS0, f)
H2 = response(h2, FS1, f)
H = H1 * H2
H /= H[0]                                                   # normalise to DC
Hdb = 20 * np.log10(np.maximum(H, 1e-300))



def crossing(level_db):
    """First frequency where the response falls below level_db (linear interp)."""
    idx = np.where(Hdb < level_db)[0]
    idx = idx[idx > 0]
    if idx.size == 0:
        return None
    i = idx[0]
    f0, f1, y0, y1 = f[i - 1], f[i], Hdb[i - 1], Hdb[i]
    return f0 + (level_db - y0) * (f1 - f0) / (y1 - y0)


print()
print(f"rates: PDM {FS0/1e6:.4f} MHz  ->  {FS1/1e3:.1f} kHz  ->  {FS2/1e3:.1f} kHz output")
print()
print("Combined low-pass, normalised to DC:")
pb = f <= 30_000
print(f"  passband ripple (0-30 kHz):   {Hdb[pb].max():+.3f} .. {Hdb[pb].min():+.3f} dB")
for lvl in (-0.1, -1, -3, -6, -20, -40, -60, -80, -100):
    c = crossing(lvl)
    print(f"  {lvl:>5} dB at   " + (f"{c/1000:8.3f} kHz" if c else "   (not reached below Nyquist)"))
print(f"  at Nyquist {FS2/2/1000:.1f} kHz:        {Hdb[-1]:.1f} dB")

c3 = crossing(-3.0)
print()
print(f"==>  -3 dB cutoff = {c3:.1f} Hz   ({c3/FS2:.4f} x fs,  {c3/(FS2/2):.3f} x Nyquist)")
