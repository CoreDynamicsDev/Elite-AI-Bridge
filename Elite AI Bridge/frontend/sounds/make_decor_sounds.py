"""Makes the holiday easter egg sounds (all synthesized here, no samples):
gobble.wav (turkey), pop.wav (present), secret.wav (hidden pack found), and one click
sound per holiday: noisemaker, harp, coins, chirp, gong, spooky, knock, jingle.
Run again after changing a sound: python make_decor_sounds.py"""
import math, random, wave, array
from pathlib import Path

SR = 44100
HERE = Path(__file__).parent


def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    data = array.array("h", (int(max(-1, min(1, s / peak * 0.85)) * 32767) for s in samples))
    with wave.open(str(HERE / name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())


def env(t, a, d):
    return min(1.0, t / a) * math.exp(-t / d) if t >= 0 else 0.0


# gobble: a run of throaty warbles that fall in pitch, like "gobble-obble-obble"
def gobble():
    out = [0.0] * int(SR * 0.95)
    random.seed(3)
    starts = [0.00, 0.11, 0.21, 0.31, 0.40, 0.49, 0.58, 0.66]
    for k, t0 in enumerate(starts):
        f0 = 620 - k * 38
        n0 = int(t0 * SR); ph = 0.0
        for i in range(int(0.12 * SR)):
            t = i / SR
            f = f0 * (1 + 0.18 * math.sin(2 * math.pi * 38 * t)) * (1 - 0.35 * t / 0.12)
            ph += 2 * math.pi * f / SR
            v = (math.sin(ph) + 0.55 * math.sin(2 * ph + 0.4) + 0.35 * math.sin(3 * ph) + 0.18 * math.sin(5 * ph))
            v = math.tanh(1.8 * v) + 0.05 * (random.random() - 0.5)
            a = env(t, 0.008, 0.045) * (1 - 0.06 * k)
            if n0 + i < len(out):
                out[n0 + i] += v * a
    return out


# pop: a soft cork pop and a little two-note chime
def pop():
    out = [0.0] * int(SR * 0.7)
    random.seed(5)
    ph = 0.0
    for i in range(int(0.08 * SR)):
        t = i / SR
        f = 900 * math.exp(-t * 30) + 180
        ph += 2 * math.pi * f / SR
        out[i] += (0.8 * math.sin(ph) + 0.5 * (random.random() - 0.5)) * env(t, 0.001, 0.018)
    for f, t0 in [(1318.5, 0.07), (1975.5, 0.16)]:
        n0 = int(t0 * SR)
        for i in range(int(0.5 * SR)):
            t = i / SR
            if n0 + i < len(out):
                out[n0 + i] += 0.35 * (math.sin(2 * math.pi * f * t) + 0.3 * math.sin(4 * math.pi * f * t)) * env(t, 0.002, 0.16)
    return out


# secret: a quick rising arpeggio with a shimmer on top
def secret():
    out = [0.0] * int(SR * 1.3)
    notes = [523.25, 659.25, 783.99, 1046.5, 1318.5]
    for k, f in enumerate(notes):
        n0 = int(k * 0.085 * SR)
        for i in range(int(0.9 * SR)):
            t = i / SR
            if n0 + i < len(out):
                out[n0 + i] += 0.3 * (math.sin(2 * math.pi * f * t) + 0.25 * math.sin(2 * math.pi * 2 * f * t)
                                      + 0.1 * math.sin(2 * math.pi * 3.01 * f * t)) * env(t, 0.003, 0.28)
    return out


write("gobble.wav", gobble())
write("pop.wav", pop())
write("secret.wav", secret())

def tone(out, t0, f, dur, amp, dec, harm=(1.0,), vib=0.0, vibf=5.0, glide=0.0):
    n0 = int(t0 * SR); ph = 0.0
    for i in range(int(dur * SR)):
        t = i / SR
        ff = f * (1 + glide * t / dur) * (1 + vib * math.sin(2 * math.pi * vibf * t))
        ph += 2 * math.pi * ff / SR
        v = sum(h * math.sin((k + 1) * ph) for k, h in enumerate(harm))
        if n0 + i < len(out):
            out[n0 + i] += amp * v * env(t, 0.004, dec)


def blank(sec):
    return [0.0] * int(SR * sec)


# New Year: a short party noisemaker (buzzy, rising, then a wobble)
def noisemaker():
    out = blank(0.75); ph = 0.0
    for i in range(int(0.7 * SR)):
        t = i / SR
        f = 380 + 260 * min(1, t / 0.18) + 18 * math.sin(2 * math.pi * 14 * t)
        ph += 2 * math.pi * f / SR
        v = math.tanh(3 * (math.sin(ph) + 0.6 * math.sin(2 * ph) + 0.4 * math.sin(3 * ph)))
        out[i] += 0.5 * v * min(1, t / 0.02) * (1 if t < 0.55 else max(0, 1 - (t - 0.55) / 0.15))
    return out


# Valentine's: a soft harp run upwards
def harp():
    out = blank(1.3)
    for k, f in enumerate([523.25, 659.25, 783.99, 987.77, 1174.66]):
        tone(out, k * 0.07, f, 1.1, 0.3, 0.35, harm=(1.0, 0.35, 0.12))
    return out


# St. Patrick's: a little jingle of coins
def coins():
    out = blank(0.8)
    random.seed(9)
    for k in range(7):
        t0 = 0.03 + k * 0.06 + random.random() * 0.03
        f = random.choice([2637, 3136, 3520, 2794, 3951])
        tone(out, t0, f, 0.4, 0.22, 0.07, harm=(1.0, 0.5, 0.0, 0.25))
    return out


# Easter: two chick peeps
def chirp():
    out = blank(0.55)
    for t0 in (0.0, 0.2):
        n0 = int(t0 * SR); ph = 0.0
        for i in range(int(0.13 * SR)):
            t = i / SR
            f = 3100 - 1400 * (t / 0.13) + 120 * math.sin(2 * math.pi * 60 * t)
            ph += 2 * math.pi * f / SR
            out[n0 + i] += 0.4 * math.sin(ph) * env(t, 0.006, 0.05)
    return out


# Lunar New Year: a small soft gong
def gong():
    out = blank(1.8)
    for f, a, d in [(196, 0.35, 0.9), (311, 0.2, 0.6), (467, 0.14, 0.45), (623, 0.08, 0.3)]:
        tone(out, 0.0, f, 1.75, a, d, harm=(1.0,), vib=0.004, vibf=3.0)
    return out


# Halloween: a spooky wobbling "ooo"
def spooky():
    out = blank(1.2); ph = 0.0
    for i in range(int(1.15 * SR)):
        t = i / SR
        f = 330 * (1 + 0.5 * min(1, t / 0.3)) * (1 - 0.25 * max(0, t - 0.6)) * (1 + 0.03 * math.sin(2 * math.pi * 6 * t))
        ph += 2 * math.pi * f / SR
        a = min(1, t / 0.15) * (1 if t < 0.85 else max(0, 1 - (t - 0.85) / 0.3))
        out[i] += 0.4 * (math.sin(ph) + 0.15 * math.sin(2 * ph)) * a
    return out


# Autumn: a hollow wooden knock-knock (pumpkins, acorns)
def knock():
    out = blank(0.5)
    random.seed(4)
    for t0 in (0.0, 0.14):
        n0 = int(t0 * SR)
        for i in range(int(0.12 * SR)):
            t = i / SR
            v = 0.7 * math.sin(2 * math.pi * 220 * t) + 0.4 * math.sin(2 * math.pi * 540 * t) + 0.25 * (random.random() - 0.5)
            out[n0 + i] += 0.5 * v * env(t, 0.001, 0.025)
    return out


# Christmas: sleigh bells
def jingle():
    out = blank(0.9)
    random.seed(12)
    for k in range(10):
        t0 = k * 0.055 + random.random() * 0.02
        for f in (4186, 5274, 6272):
            tone(out, t0, f * (0.97 + random.random() * 0.06), 0.25, 0.1, 0.05, harm=(1.0, 0.0, 0.3))
    return out


for name, fn in [("noisemaker", noisemaker), ("harp", harp), ("coins", coins), ("chirp", chirp),
                 ("gong", gong), ("spooky", spooky), ("knock", knock), ("jingle", jingle)]:
    write(name + ".wav", fn())

print("decor sounds written")
