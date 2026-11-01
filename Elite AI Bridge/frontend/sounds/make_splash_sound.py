"""Startup sound for the Elite AI Bridge boot splash (all synthesized, no samples).
2026-10-25 rework: real hardware instead of cartoon beeps. Mechanical key clicks are
synced to every typed character on screen; the power-up is a thump, mains hum, CRT
whine, relays and static. No pitch sweeps, pings or chimes.

2026-10-28: the shipped sound is variant ABED (A plus a low bed built from the sting's own chord
from 0.6 to 8.2 s, handing off into the sting).

Timed to boot_splash.py's 15 s story. Writes:
  splash_boot.wav  0.0 .. 14.2 s   (plays when the story clock starts)
  splash_off.wav   CRT power-off   (plays when the splash powers off into the app)

  python make_splash_sound.py OUT_DIR [A|B|C]
    A  terminal: keys, relays, hum, CRT. No tones at all.
    B  A plus a few quiet equipment tones (signal lock, target lock, docking).
    C  A plus a low ship ambience bed and a filtered engine pass for the flyby.
"""
import sys, wave
import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
BED_GAIN = 0.07
rng = np.random.default_rng(11)


def t_of(n):
    return np.arange(n) / SR


def noise(n):
    return rng.standard_normal(n)


def band(x, lo=None, hi=None, order=2):
    if lo and hi:
        sos = butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    elif lo:
        sos = butter(order, lo, btype="high", fs=SR, output="sos")
    else:
        sos = butter(order, hi, btype="low", fs=SR, output="sos")
    return sosfilt(sos, x)


def add(buf, start, sig, gain=1.0):
    i = int(start * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i] * gain


# ------------------------------------------------------------------ hardware sounds
def key_click(strength=1.0, space=False):
    """Mechanical keyboard key: the switch click, the keycap bottoming out on the plate (the
    'clack', a short low-mid knock), then the lighter clack of the key coming back up."""
    n = int(0.11 * SR)
    t = t_of(n)
    v = strength * rng.uniform(0.82, 1.12)
    tone = rng.uniform(0.9, 1.12) * (0.82 if space else 1.0)
    click = (np.sin(2 * np.pi * 3400 * tone * t) * 0.6 + band(noise(n), 2500, 7000) * 0.4) * np.exp(-t / 0.0011)
    knock = (np.sin(2 * np.pi * 240 * tone * t) * 0.9 + np.sin(2 * np.pi * 610 * tone * t + 0.7) * 0.6
             + np.sin(2 * np.pi * 1350 * tone * t + 1.9) * 0.35) * np.exp(-t / 0.009)
    knock += band(noise(n), 400, 2500) * np.exp(-t / 0.0035) * 0.35
    rel_at = rng.uniform(0.050, 0.075)
    tr = np.maximum(0, t - rel_at)
    up = (np.sin(2 * np.pi * 900 * tone * t) * 0.5 + band(noise(n), 1200, 5000) * 0.3) * np.exp(-tr / 0.004) * (t > rel_at) * 0.35
    s = (click * 0.5 + knock * (1.25 if space else 1.0) + up) * np.minimum(1, t / 0.0002)
    return s * v


KEY_MIN_GAP = 0.058          # real typing pace: at most about 17 clicks a second


def type_line(buf, text, t0, cps, gain):
    """Clicks follow the characters on screen (char k at t0 + k/cps, as boot_splash.typed()),
    but never faster than KEY_MIN_GAP apart, so fast lines sound like quick typing, not a buzz."""
    last = -1.0
    for k, ch in enumerate(text):
        at = t0 + k / cps
        if at - last < KEY_MIN_GAP and k != len(text) - 1:
            continue
        last = at
        at += rng.uniform(-0.006, 0.006)
        add(buf, max(0.0, at), key_click(1.0, space=(ch == " ")), gain)


def thump(dur=0.7, f_hi=95, f_lo=36):
    """Power contactor closing and the transformer taking the load."""
    n = int(dur * SR)
    t = t_of(n)
    f = f_lo + (f_hi - f_lo) * np.exp(-t / 0.06)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.20)
    s += band(noise(n), 60, 500) * np.exp(-t / 0.025) * 0.9
    return s


def mains_hum(dur, level=1.0, rise=0.25, fall=0.6):
    """60 Hz transformer hum with its harmonics and a little mechanical buzz."""
    n = int(dur * SR)
    t = t_of(n)
    s = (np.sin(2 * np.pi * 60 * t) * 0.6 + np.sin(2 * np.pi * 120 * t) * 0.9
         + np.sin(2 * np.pi * 180 * t) * 0.35 + np.sin(2 * np.pi * 240 * t) * 0.2)
    s += band(noise(n), 100, 400) * 0.15
    wob = 1 + 0.04 * np.sin(2 * np.pi * 0.7 * t)
    e = np.minimum(1, t / rise) * np.clip((dur - t) / fall, 0, 1)
    return s * wob * e * level


def crt_whine(dur, f=15734.0):
    """The flyback whine of a CRT, faint and steady, settling in as it warms."""
    n = int(dur * SR)
    t = t_of(n)
    drift = f - 120 * np.exp(-t / 0.5)
    s = np.sin(2 * np.pi * np.cumsum(drift) / SR)
    e = np.minimum(1, t / 0.4) * (0.55 + 0.45 * np.exp(-t / 1.2)) * np.clip((dur - t) / 0.8, 0, 1)
    return s * e


def degauss(dur=0.9):
    """CRT degauss: a loud 60 Hz buzz with a rattle that dies away fast."""
    n = int(dur * SR)
    t = t_of(n)
    s = np.sign(np.sin(2 * np.pi * 60 * t)) * 0.4 + np.sin(2 * np.pi * 120 * t) * 0.6
    s = band(s, 50, 1800)
    s += band(noise(n), 200, 2500) * 0.25
    return s * np.exp(-t / 0.22) * np.minimum(1, t / 0.01)


def relay(bright=1.0):
    """Relay: armature hits, then bounces once."""
    n = int(0.05 * SR)
    t = t_of(n)
    hit = band(noise(n), 1200, 8000) * np.exp(-t / 0.0035)
    bounce_at = rng.uniform(0.008, 0.014)
    tb = np.maximum(0, t - bounce_at)
    bounce = band(noise(n), 900, 6000) * np.exp(-tb / 0.004) * (t > bounce_at) * 0.45
    body = np.sin(2 * np.pi * rng.uniform(900, 1300) * t) * np.exp(-t / 0.006) * 0.2
    return (hit + bounce + body) * bright


def static(dur, lo=800, hi=7000):
    n = int(dur * SR)
    t = t_of(n)
    crackle = (rng.random(n) < 0.004) * rng.standard_normal(n) * 4
    s = band(noise(n) * 0.6 + crackle, lo, hi)
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.6
    return s * e


def fan_bed(dur, level=1.0):
    """Cooling fan and air: broadband, low, steady."""
    n = int(dur * SR)
    t = t_of(n)
    s = band(noise(n), 80, 900) * 0.8 + band(noise(n), 900, 4000) * 0.12
    s *= 1 + 0.05 * np.sin(2 * np.pi * 3.1 * t)
    e = np.minimum(1, t / 1.5) * np.clip((dur - t) / 1.0, 0, 1)
    return s * e * level


def clamp_hit():
    """Docking clamp: heavy metal latch through the hull."""
    n = int(0.6 * SR)
    t = t_of(n)
    s = np.sin(2 * np.pi * 58 * t) * np.exp(-t / 0.12)
    s += band(noise(n), 80, 900) * np.exp(-t / 0.03) * 0.9
    for f, dcy in ((233, 0.18), (367, 0.12), (512, 0.08)):
        s += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * np.exp(-t / dcy) * 0.12
    return s


def hiss(dur=0.8):
    """Pneumatic hiss as the clamps seal."""
    n = int(dur * SR)
    t = t_of(n)
    return band(noise(n), 2500, 9000) * np.exp(-t / 0.25) * np.minimum(1, t / 0.02)


def soft_tone(freq, dur=0.14):
    """A plain equipment tone: sine, soft edges, no pitch movement."""
    n = int(dur * SR)
    t = t_of(n)
    e = np.minimum(1, t / 0.006) * np.clip((dur - t) / 0.03, 0, 1)
    return np.sin(2 * np.pi * freq * t) * e


def engine_pass(dur=2.2):
    """Distant engines going by: low rumble that swells and fades (filtered, no sweep)."""
    n = int(dur * SR)
    t = t_of(n)
    e = np.exp(-((t / dur - 0.45) ** 2) / 0.05)
    s = band(noise(n), 40, 260, order=3) * 1.0 + band(noise(n), 260, 900) * 0.25
    s += np.sin(2 * np.pi * 47 * t) * 0.35
    return s * e


def reverb(x, secs=2.6, mix=0.35):
    """Plain hall: convolve with decaying stereo-ish noise (mono out)."""
    from scipy.signal import fftconvolve
    n = int(secs * SR)
    t = t_of(n)
    ir = band(noise(n), 120, 6000) * np.exp(-t / (secs / 5.5))
    ir[0] = 0
    ir /= np.sqrt((ir ** 2).sum()) + 1e-9
    wet = fftconvolve(x, ir)
    out = np.zeros(len(wet))
    out[: len(x)] += x * (1 - mix)
    out += wet * mix * 3.0
    return out


def saw_voice(freq, dur, detune=0.0035, voices=5):
    """Brassy stack: detuned band-limited saws (no pitch movement)."""
    n = int(dur * SR)
    t = t_of(n)
    out = np.zeros(n)
    for k in range(voices):
        f = freq * (1 + detune * (k - (voices - 1) / 2))
        ph = rng.uniform(0, 2 * np.pi)
        harm = int(min(30, 9000 // max(f, 1)))
        for h in range(1, harm + 1):
            out += np.sin(2 * np.pi * f * h * t + ph * h) / h
    return out / voices


def epic_sting(swell=1.5, hold=3.2):
    """Original logo sting for the title reveal: a dark cluster that grows louder and brighter
    (volume and tone open up, no pitch slides), then a big D major hit with a sub boom and a
    hall tail. Not modelled on any existing logo sound."""
    total = swell + hold
    n = int(total * SR)
    t = t_of(n)
    out = np.zeros(n)
    hit = int(swell * SR)
    # swell: close cluster around A, low and soft, getting louder and brighter
    cluster = sum(saw_voice(f, swell + 0.05, 0.004, 3) for f in (110.0, 116.5, 123.5, 146.8))
    ramp = (t_of(len(cluster)) / swell) ** 2.2
    cl = band(cluster, 40, 600, 2) * (1 - ramp) + band(cluster, 40, 4000, 2) * ramp
    out[: len(cl)] += cl * ramp * 0.35 * np.clip((swell + 0.05 - t_of(len(cl))) / 0.05, 0, 1)
    rumble = band(noise(hit), 25, 140, 3) * (t_of(hit) / swell) ** 1.6
    out[:hit] += rumble * 1.2
    # the hit: D major spread wide, brassy, fading over the hold
    th = t_of(n - hit)
    chord = sum(saw_voice(f, hold, 0.003, 5) * g for f, g in
                ((73.42, 1.0), (110.0, 0.8), (146.83, 0.8), (185.0, 0.55), (220.0, 0.55), (293.66, 0.45), (369.99, 0.3)))
    env = np.minimum(1, th / 0.012) * (0.55 + 0.45 * np.exp(-th / 0.35)) * np.clip((hold - th) / (hold * 0.85), 0, 1) ** 1.4
    out[hit:] += band(chord, 35, 5000, 2) * env * 0.45
    boom = np.sin(2 * np.pi * 41.2 * th) * np.exp(-th / 0.9) * 1.6 + band(noise(len(th)), 30, 400) * np.exp(-th / 0.08) * 1.2
    out[hit:] += boom * np.minimum(1, th / 0.004)
    crash = band(noise(len(th)), 3000, 9000) * np.exp(-th / 0.25) * 0.07
    out[hit:] += crash
    return reverb(out, 2.8, 0.38)


def sting_bed(L, start=0.6, hand_off=8.2, lock=5.75, cut=2.7):
    """2026-10-27 bed under the boot: the sting's own dark A cluster, low and muffled at cold start,
    opening up a little at the cut to space, one soft swell on target lock, then building into the
    sting's swell at 8.2 s and fading under it. Plus a slow sub pulse from the cut to space."""
    n = int(L * SR)
    t = t_of(n)
    out = np.zeros(n)
    cl = sum(saw_voice(f, L, 0.004, 3) for f in (110.0, 116.5, 123.5, 146.8))
    dark = band(cl, 40, 260, 2)
    open_ = band(cl, 40, 900, 2)
    # brightness: dark until the cut to space, then opens over 1.5 s, more on the build
    mixb = np.clip((t - cut) / 1.5, 0, 1) * 0.55 + np.clip((t - (hand_off - 1.4)) / 1.4, 0, 1) * 0.45
    tone = dark * (1 - mixb) + open_ * mixb
    env = np.clip((t - start) / 1.6, 0, 1) * 0.55                       # fade in under the cold start
    env += np.clip((t - cut) / 0.8, 0, 1) * 0.25                          # a step up at the cut to space
    env += 0.35 * np.exp(-((t - (lock + 0.35)) / 0.45) ** 2)              # one soft swell on target lock
    env += np.clip((t - (hand_off - 1.6)) / 1.6, 0, 1) ** 2 * 0.6          # build into the sting
    env *= np.clip((hand_off + 0.5 - t) / 0.5, 0, 1)                      # hand off: gone 0.5 s after the swell starts
    out += tone * env
    # sub pulse, about one a second, from the cut to space to the hand-off
    k = int(0.55 * SR)
    tk = t_of(k)
    thump = np.sin(2 * np.pi * 52 * tk) * np.exp(-tk / 0.16) * np.minimum(1, tk / 0.006)
    beat = cut + 0.3
    while beat < hand_off - 0.2:
        add(out, beat, thump, 0.55 * min(1.0, (beat - cut) / 2.0 + 0.4))
        beat += 1.0
    return reverb(out, 2.2, 0.30)[:n]


# ------------------------------------------------------------------ the story
TYPING = [  # (text, start, chars per second) from boot_splash.py
    ("CORE DYNAMICS DEV  //  BRIDGE SYSTEMS  //  UNIT 2.0.5", 0.62, 70),
    ("COLD START SEQUENCE", 1.15, 50),
    ("SIGNAL  100%", 1.95, 40),
    ("TARGET LOCK // ORBITAL RELAY K-7", 5.75, 50),
    ("BRIDGE SYSTEMS ONLINE", 10.2, 34),
    ("DOCKING GRANTED  //  WELCOME ABOARD, COMMANDER", 12.9, 40),
]
BOOT_LOG = ["PHOSPHOR WARM-UP", "FLIGHT COMPUTER LINK", "VOICE SYNTH CORE", "STAR CATALOGUE",
            "THREAT MATRIX", "COMMS ARRAY", "DOCKING COMPUTER", "BRIDGE AI"]


def boot(variant="A"):
    L = 14.2
    buf = np.zeros(int(L * SR) + SR)
    # power on
    add(buf, 0.00, thump(), 0.50)
    add(buf, 0.02, degauss(), 0.10)
    add(buf, 0.05, mains_hum(L - 0.1, 1.0, 0.3, 1.0), 0.030)
    add(buf, 0.10, crt_whine(L - 0.2), 0.006)
    add(buf, 0.05, static(0.30), 0.05)
    # self-test relays
    for k, tt in enumerate((0.42, 0.50, 0.78, 1.36, 1.44, 2.05)):
        add(buf, tt, relay(1.0 if k % 2 == 0 else 0.7), 0.20)
    # disk / memory seek chatter under COLD START (dull ticks, not beeps)
    for i in range(14):
        add(buf, 1.22 + i * 0.05 + rng.uniform(0, 0.015), band(noise(int(0.01 * SR)), 300, 2500) * np.exp(-t_of(int(0.01 * SR)) / 0.002), 0.05)
    add(buf, 2.20, static(0.45, 600, 5000), 0.07)       # vertical hold slips
    # typing
    for text, t0, cps in TYPING:
        type_line(buf, text, t0, cps, 0.11)
    for i, name in enumerate(BOOT_LOG):
        t0 = 3.0 + i * 0.72
        type_line(buf, name, t0, 44, 0.09)
        done = t0 + len(name) / 44.0 + 0.25          # dots finish, status prints
        add(buf, done, relay(0.6), 0.10)
    # title: the logo sting swells under the end of the boot log and hits on the title flash (9.7 s)
    add(buf, 9.70 - 1.5, epic_sting(1.5, 3.4), 0.30)
    add(buf, 9.02, static(0.12, 1500, 8000), 0.05)
    add(buf, 9.0, mains_hum(3.4, 1.0, 0.5, 1.5), 0.014)  # extra load as systems come online
    # docking clamps
    add(buf, 12.80, clamp_hit(), 0.42)
    add(buf, 13.12, clamp_hit(), 0.34)
    add(buf, 13.20, hiss(0.9), 0.05)

    if "BED" in variant:
        add(buf, 0.0, sting_bed(L), BED_GAIN)
    if variant.startswith("B") and variant != "BED":
        add(buf, 2.15, soft_tone(880, 0.10), 0.035)        # signal lock
        add(buf, 5.05, soft_tone(988, 0.08), 0.035)        # target lock: two short, same pitch
        add(buf, 5.17, soft_tone(988, 0.08), 0.035)
        add(buf, 10.15, soft_tone(660, 0.18), 0.030)       # systems online
        add(buf, 13.55, soft_tone(784, 0.12), 0.030)       # docking granted
        add(buf, 13.70, soft_tone(1047, 0.16), 0.026)
    if variant.startswith("C"):
        add(buf, 0.6, fan_bed(L - 0.6), 0.05)
        add(buf, 6.1, engine_pass(2.4), 0.22)
        add(buf, 10.4, engine_pass(2.6), 0.10)             # approach to the station
    return buf


def off():
    n = int(0.9 * SR)
    buf = np.zeros(n)
    add(buf, 0.0, relay(1.0), 0.25)
    t = t_of(int(0.5 * SR))
    collapse = np.sin(2 * np.pi * 60 * t) * np.exp(-t / 0.12) * 0.6 + band(noise(len(t)), 300, 5000) * np.exp(-t / 0.05) * 0.4
    add(buf, 0.01, collapse, 0.25)
    add(buf, 0.02, static(0.18, 1500, 8000), 0.06)
    return buf


def write(path, x, peak=0.70):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = int(0.02 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    variant = (sys.argv[2] if len(sys.argv) > 2 else "ABED").upper()   # 2026-10-28: A + the sting bed is the shipped sound
    write(f"{out}/splash_boot.wav", boot(variant))
    write(f"{out}/splash_off.wav", off(), 0.5)
    print("ok", variant)
