#!/usr/bin/env python3
"""Synthesizes Paddle & Pine's sound effects and ambience (original, CC0).

Run:  python3 tools/gen_audio.py      (needs numpy)
Writes 16-bit mono 22.05 kHz WAV files to assets/audio/.
"""
import wave
from pathlib import Path

import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"
OUT.mkdir(parents=True, exist_ok=True)
SR = 22050
rng = np.random.default_rng(7)


def t(dur):
    return np.arange(int(SR * dur)) / SR


def env(n, attack=0.005, release=0.1, curve=2.0):
    e = np.ones(n)
    a = max(1, int(SR * attack))
    r = max(1, int(SR * release))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r) ** curve
    return e


def decay(n, rate):
    return np.exp(-np.arange(n) / SR * rate)


def noise(n):
    return rng.uniform(-1, 1, n)


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = a * acc + (1 - a) * v
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, lo, hi):
    return highpass(lowpass(x, hi), lo)


def tone(freq, dur, shape="sine"):
    x = t(dur)
    ph = 2 * np.pi * np.cumsum(np.broadcast_to(freq, x.shape)) / SR
    if shape == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if shape == "square":
        return np.sign(np.sin(ph)) * 0.6
    return np.sin(ph)


def save(name, x, gain=0.8):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * gain
    data = (x * 32767).astype("<i2")
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data.tobytes())


def loopable(x, fade=0.5):
    """Cross-fades the tail into the head so the clip loops without a click."""
    n = int(SR * fade)
    head, tail = x[:n], x[-n:]
    ramp = np.linspace(0, 1, n)
    out = x[:-n].copy()
    out[:n] = head * ramp + tail * (1 - ramp)
    return out


def splash(seed, dur=0.35, lo=500, hi=3500):
    n = int(SR * dur)
    x = bandpass(noise(n), lo, hi) * decay(n, 9) * env(n, 0.01, 0.15)
    x += 0.4 * tone(np.linspace(520, 180, n), dur) * decay(n, 14)
    return x


def chirp(f0, f1, dur, rate=12, shape="sine"):
    n = int(SR * dur)
    return tone(np.linspace(f0, f1, n), dur, shape) * decay(n, rate) * env(n, 0.004, 0.03)


def seq(parts, gap=0.0):
    out = []
    for p in parts:
        out.append(p)
        if gap:
            out.append(np.zeros(int(SR * gap)))
    return np.concatenate(out)


def main():
    # --- effects -------------------------------------------------------
    for i in range(3):
        save(f"splash{i}", splash(i, 0.3 + i * 0.05, 400 + i * 150, 3000 + i * 400), 0.5)
    save("splash", splash(9, 0.6, 300, 4000), 0.7)
    for i in range(2):
        n = int(SR * 0.09)
        save(f"step{i}", lowpass(noise(n), 900 + i * 300) * decay(n, 40), 0.35)
    n = int(SR * 0.16)
    save("chop", (lowpass(noise(n), 1400) * decay(n, 30) + 0.8 * tone(150, 0.16) * decay(n, 25)), 0.8)
    n = int(SR * 0.9)
    crack = bandpass(noise(n), 300, 2500) * decay(n, 3) * (0.5 + 0.5 * (rng.random(n) > 0.97))
    thud = np.zeros(n)
    k = int(SR * 0.55)
    thud[k:] = (tone(70, 0.9)[: n - k] * decay(n - k, 9) + lowpass(noise(n - k), 500) * decay(n - k, 14))
    save("treefall", crack * 0.6 + thud, 0.85)
    n = int(SR * 0.22)
    save("dig", lowpass(noise(n), 700) * env(n, 0.03, 0.12) * decay(n, 8), 0.6)
    save("pickup", seq([chirp(660, 990, 0.07, 18), chirp(990, 1320, 0.09, 16)]), 0.45)
    save("coin", seq([chirp(1320, 1320, 0.06, 20, "tri"), chirp(1760, 1760, 0.22, 10, "tri")]), 0.45)
    n = int(SR * 0.25)
    save("bow", tone(np.linspace(240, 150, n), 0.25, "tri") * decay(n, 16) + 0.3 * highpass(noise(n), 2000) * decay(n, 40), 0.6)
    n = int(SR * 0.1)
    save("hit", lowpass(noise(n), 1800) * decay(n, 35) + tone(110, 0.1) * decay(n, 30), 0.8)
    n = int(SR * 0.18)
    save("swing", bandpass(noise(n), 600, 5000) * np.sin(np.linspace(0, np.pi, n)) ** 2, 0.4)
    save("hurt", chirp(330, 150, 0.25, 9, "square") + 0.3 * lowpass(noise(int(SR * 0.25)), 900) * decay(int(SR * 0.25), 20), 0.55)
    save("alert", seq([chirp(880, 880, 0.08, 6, "square"), chirp(1175, 1175, 0.14, 8, "square")], 0.02), 0.4)
    notes = [523, 659, 784, 1047]
    save("chime", seq([chirp(f, f, 0.16, 7, "tri") for f in notes]) , 0.5)
    save("rare", seq([chirp(f, f, 0.12, 6, "tri") for f in [784, 988, 1175, 1568, 1976]]), 0.5)
    save("quest", seq([chirp(f, f, d, 5, "tri") for f, d in [(523, 0.12), (659, 0.12), (784, 0.12), (1047, 0.4)]]), 0.55)
    save("click", chirp(900, 700, 0.04, 40), 0.3)
    save("bite", seq([chirp(1200, 1500, 0.06, 20), chirp(1200, 1500, 0.06, 20)], 0.03), 0.5)
    n = int(SR * 0.5)
    save("fire", bandpass(noise(n), 800, 6000) * (rng.random(n) > 0.985) * 3 * env(n, 0.01, 0.2) + 0.2 * lowpass(noise(n), 400) * env(n, 0.05, 0.2), 0.5)
    save("growl", (tone(np.linspace(95, 70, int(SR * 0.5)), 0.5, "square") * (0.6 + 0.4 * np.sin(2 * np.pi * 28 * t(0.5))))
         * env(int(SR * 0.5), 0.05, 0.2), 0.5)

    # --- ambience loops ------------------------------------------------
    dur = 6.0
    n = int(SR * dur)
    x = t(dur)
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * x / 3.0) * np.sin(2 * np.pi * x / 2.0 + 1.0)
    save("amb_water", loopable(bandpass(noise(n), 200, 1800) * swell), 0.35)
    birds = np.zeros(n)
    for _ in range(14):
        start = rng.integers(0, n - int(SR * 0.4))
        f = rng.uniform(2200, 4200)
        for k in range(rng.integers(2, 5)):
            c = chirp(f, f * rng.uniform(0.8, 1.3), 0.07, 14)
            s = start + k * int(SR * 0.09)
            birds[s:s + len(c)] += c[: max(0, min(len(c), n - s))] * rng.uniform(0.3, 1.0)
    save("amb_birds", loopable(birds + 0.02 * bandpass(noise(n), 300, 2000)), 0.3)
    crick = np.zeros(n)
    pulse = (np.sin(2 * np.pi * 16 * x) > 0.2).astype(float)
    for f, ph in ((4300, 0.0), (4700, 0.7), (5100, 1.9)):
        gate = (np.sin(2 * np.pi * x / 1.5 + ph) > -0.2).astype(float)
        crick += np.sin(2 * np.pi * f * x) * pulse * gate
    save("amb_crickets", loopable(crick * 0.5 + 0.05 * lowpass(noise(n), 500)), 0.22)
    save("amb_falls", loopable(bandpass(noise(n), 120, 5000) * (0.85 + 0.15 * np.sin(2 * np.pi * x * 0.7))), 0.5)
    print("audio written to", OUT)


if __name__ == "__main__":
    main()
