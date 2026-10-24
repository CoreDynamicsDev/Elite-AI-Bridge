"""Original startup sound for the Elite AI Bridge boot splash (all synthesized, no samples).
Timed to boot_splash.py's 15 s story (see claude/boot-splash.md). Two files:
  splash_boot.wav  0.0 .. 14.2 s   (plays when the story clock starts)
  splash_off.wav   power-off zap   (plays when the splash powers off into the app)
"""
import numpy as np, wave, sys
SR = 44100
rng = np.random.default_rng(7)

def t_of(n): return np.arange(n) / SR
def env_ad(n, a, d):
    t = t_of(n); e = np.minimum(1, t / max(a, 1e-4)) * np.exp(-np.maximum(0, t - a) / max(d, 1e-4)); return e
def lp(x, fc):
    # one-pole low-pass, run twice
    a = np.exp(-2 * np.pi * fc / SR); y = np.empty_like(x); s = 0.0
    for _ in range(2):
        for i in range(len(x)):
            s = (1 - a) * x[i] + a * s; y[i] = s
        x = y.copy()
    return y
def hp(x, fc): return x - lp(x, fc)
def noise(n): return rng.standard_normal(n)
def add(buf, start, sig, gain=1.0):
    i = int(start * SR); j = min(len(buf), i + len(sig)); buf[i:j] += sig[: j - i] * gain
def tone(freq, dur, a=0.005, d=0.1, shape="sine"):
    n = int(dur * SR); t = t_of(n)
    f = freq if np.isscalar(freq) else freq
    ph = 2 * np.pi * np.cumsum(np.full(n, f) if np.isscalar(f) else f) / SR
    s = np.sin(ph) if shape == "sine" else np.sign(np.sin(ph)) * 0.5 + 0.5 * np.sin(ph)
    return s * env_ad(n, a, d)

def thump(dur=0.6):
    n = int(dur * SR); t = t_of(n)
    f = 38 + 60 * np.exp(-t / 0.05)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.18)
    s += lp(noise(n), 400) * np.exp(-t / 0.03) * 0.8
    return s
def whine(dur, f0=7200):
    n = int(dur * SR); t = t_of(n)
    f = f0 + 400 * (1 - np.exp(-t / 0.4))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.minimum(1, t / 0.3) * np.exp(-t / 1.6) * 0.06
def relay(bright=1.0):
    n = int(0.05 * SR); t = t_of(n)
    s = hp(noise(n), 1500) * np.exp(-t / 0.004) + hp(noise(n), 800) * np.exp(-np.maximum(0, t - 0.012) / 0.006) * (t > 0.012) * 0.6
    return s * bright
def static(dur, fc=3000):
    n = int(dur * SR); t = t_of(n)
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.7
    return lp(noise(n), fc) * e
def sweep(f0, f1, dur, a=0.05, d=None):
    n = int(dur * SR); t = t_of(n)
    f = f0 * (f1 / f0) ** (t / dur)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR)
    e = np.minimum(1, t / a) * np.minimum(1, (dur - t) / 0.08)
    return s * np.clip(e, 0, 1)
def ping(freq=1320, dur=0.9):
    n = int(dur * SR); t = t_of(n)
    s = np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.18) + 0.35 * np.sin(2 * np.pi * freq * 2.01 * t) * np.exp(-t / 0.08)
    return s * np.minimum(1, t / 0.002)
def whoosh(dur=1.6, f_lo=300, f_hi=3200):
    n = int(dur * SR); t = t_of(n); x = noise(n)
    # moving band: crude by mixing two low-passes with a crossfading cutoff
    peak = 0.45
    e = np.exp(-((t / dur - peak) ** 2) / 0.04)
    hi = lp(x, f_hi); lo = lp(x, f_lo)
    pan = np.clip(t / dur, 0, 1)
    return (hi * (1 - pan) + lo * pan) * e
def pad(chord, dur, a=0.6, r=1.2):
    n = int(dur * SR); t = t_of(n); s = np.zeros(n)
    for k, f in enumerate(chord):
        for det in (-0.6, 0.0, 0.6):
            s += np.sin(2 * np.pi * (f + det) * t + k) / (len(chord) * 3)
    e = np.minimum(1, t / a) * np.clip((dur - t) / r, 0, 1)
    return lp(s * e, 2500)
def clunk():
    n = int(0.45 * SR); t = t_of(n)
    s = np.sin(2 * np.pi * 70 * t) * np.exp(-t / 0.09) * 0.9
    s += lp(noise(n), 1200) * np.exp(-t / 0.02) * 0.7
    for f, dcy in ((410, 0.12), (623, 0.09), (1170, 0.05)):
        s += np.sin(2 * np.pi * f * t) * np.exp(-t / dcy) * 0.18
    return s
def chime(notes=(880.0, 1318.5), gap=0.16):
    out = np.zeros(int((gap * len(notes) + 1.4) * SR))
    for i, f in enumerate(notes):
        add(out, i * gap, ping(f, 1.3) * 0.7)
    return out

def boot():
    L = 14.2; buf = np.zeros(int(L * SR) + SR)
    add(buf, 0.00, thump(), 0.55)                      # power on
    add(buf, 0.05, whine(2.4), 1.0)                    # CRT whine settling
    add(buf, 0.05, static(0.35, 4000), 0.10)           # flash + static
    for k, tt in enumerate((0.70, 0.86, 1.02, 1.30, 1.38, 1.66, 1.95, 2.08)):   # self-test relays
        add(buf, tt, relay(0.8 if k % 3 else 1.0), 0.22)
    for i in range(12):                                # memory count ticks
        add(buf, 0.75 + i * 0.11, tone(2400, 0.03, 0.001, 0.008), 0.05)
    add(buf, 2.15, tone(1046.5, 0.12, 0.003, 0.05), 0.12)   # SIGNAL 100%
    add(buf, 2.20, static(0.5, 2500), 0.16)            # vertical hold slips
    add(buf, 2.70, sweep(140, 900, 2.2) * 0.06, 1.0)   # scan plane rising
    add(buf, 3.20, ping(1320, 0.9), 0.10)              # radar sweep pings
    add(buf, 4.40, ping(1320, 0.9), 0.07)
    add(buf, 5.00, tone(1568, 0.08, 0.002, 0.03), 0.12)     # target lock: two-tone
    add(buf, 5.10, tone(2093, 0.12, 0.002, 0.05), 0.12)
    for i in range(10):                                # range counting down
        add(buf, 5.4 + i * 0.25, tone(3000, 0.02, 0.001, 0.006), 0.035)
    add(buf, 5.0, pad((55.0, 82.4, 110.0), 3.8, 1.5, 1.2), 0.30)   # approach drone
    add(buf, 6.3, whoosh(1.7), 0.10)                   # ship flyby
    add(buf, 8.60, thump(0.8), 0.35)                   # title lands
    add(buf, 8.62, static(0.18, 6000), 0.10)           # glitch slices
    add(buf, 8.85, static(0.10, 6000), 0.07)
    add(buf, 8.6, pad((110.0, 164.8, 220.0, 277.2), 3.6, 0.35, 1.6), 0.28)   # title swell
    add(buf, 10.5, pad((55.0, 82.4), 2.6, 0.6, 0.8), 0.18)                 # docking hum
    add(buf, 12.85, clunk(), 0.45)                     # clamps
    add(buf, 13.15, clunk(), 0.38)
    add(buf, 13.45, chime(), 0.20)                     # DOCKING GRANTED
    return buf
def off():
    n = int(0.9 * SR); buf = np.zeros(n)
    add(buf, 0.0, sweep(1800, 90, 0.55) * 0.18, 1.0)
    add(buf, 0.0, static(0.25, 5000), 0.06)
    add(buf, 0.5, thump(0.4), 0.12)
    return buf

def write(path, x, peak=0.70):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = int(0.02 * SR); x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    write(f"{out}/splash_boot.wav", boot())
    write(f"{out}/splash_off.wav", off(), 0.5)
    print("ok")
