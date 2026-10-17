from __future__ import annotations

"""Elite AI Bridge boot splash: "COLD START" (retro redesign).

A 15 second cinematic on one big CRT set in the worn housing: power on, self-test,
vertical-hold roll, a hidden-line vector space station scanned in, target lock, the
Commander's ship flying in to dock, the title, docking granted, then the picture
squeezes to a dot and the splash fades away to reveal the Bridge.

Everything is drawn live with QPainter (no video file), into an internal image at up to
1920x1080 that is scaled to the screen, so the cost is the same on 1080p, 1440p and 4K.

Public API is unchanged from v1.0.1 (main.py uses it as before):
    BootSplash(screen, background_path)    # background_path is no longer used
    set_ready_probe(fn), set_main_window(window), finish(), showFullScreen(), raise_()

Timing: the 15 s story starts once the Qt event loop is running (main.py loads the
backend and the QML scene first, while the housing sits dark with the POWER lamp on),
so the heavy start-up work never makes the animation stutter. If the Bridge is not
ready at 14.2 s the docked frame holds (station keeps turning) until it is, or until
30 s have passed in total.
"""

import math
import random
import time
from pathlib import Path

from PySide6.QtCore import QPointF, QRectF, QTimer, Qt, QLineF
from PySide6.QtGui import (QBrush, QColor, QFont, QFontDatabase, QImage, QLinearGradient, QPainter,
                           QPen, QPixmap, QPolygonF, QRadialGradient)
from PySide6.QtWidgets import QWidget

try:
    import numpy as np
except Exception:  # pragma: no cover - numpy ships with the runtime (Supertonic needs it)
    np = None

HERE = Path(__file__).resolve().parent
SKIN = HERE / "qml" / "skin"

# design canvas
FW, FH = 1920, 1080
SX, SY, SW, SH = 44, 40, 1832, 962          # the CRT glass inside the housing
STORY_END = 14.2                            # power-off starts here (when the Bridge is ready)
OFF_LEN = 0.65                              # line, dot
FADE_LEN = 0.35                             # then the splash window fades away
START_DELAY = 0.35                          # dark housing after the event loop starts
STEADY_GAP = 0.055                          # a tick counts as steady when it comes within 55 ms
STEADY_TICKS = 8                            # this many steady ticks in a row start the story
STEADY_MAX_WAIT = 3.0                       # never wait longer than this for steady frames
Q = 0.75                                    # internal resolution of the picture (scaled up to the glass)
CW, CH = int(SW * Q), int(SH * Q)

G = (125, 255, 160)
A = (255, 180, 70)
WH = (235, 255, 240)
RD = (255, 90, 72)


def clamp(x, a=0.0, b=1.0):
    return a if x < a else (b if x > b else x)


def ease(x):
    x = clamp(x)
    return x * x * (3 - 2 * x)


def ease_out(x):
    x = clamp(x)
    return 1 - (1 - x) ** 3


def seg(t, a, b):
    return clamp((t - a) / (b - a))


def col(c, v):
    return QColor(c[0], c[1], c[2], int(255 * clamp(v)))


def typed(s, t, t0, cps=38.0):
    n = int(max(0.0, (t - t0) * cps))
    return s[:n], n < len(s)


# ============================================================================ geometry
def _P(r, a, y):
    return (r * math.cos(a), y, r * math.sin(a))


class Mesh:
    """Hidden-line station: faces are filled dark, then chosen edges are stroked."""

    def __init__(self):
        self.V = {"S": [], "A": [], "B": []}
        self.E = []

    def v(self, g, p):
        self.V[g].append(tuple(float(x) for x in p))
        return len(self.V[g]) - 1

    def face(self, g, idx, stroke, fill=True, base=1.0, dots=None, extra=None, inside=None):
        # inside: a point inside the solid this face belongs to (lets faces turned away be skipped)
        self.E.append(dict(g=g, idx=idx, stroke=stroke, fill=fill, base=base, dots=dots or [], extra=extra or [], inside=inside))

    def seg(self, g, a, b, base=1.0):
        self.E.append(dict(g=g, idx=[self.v(g, a), self.v(g, b)], stroke=[(0, 1)], fill=False, base=base, dots=[], extra=[], inside=None))


def _torus_box(m, g, R0, R1, y0, y1, n, rib, windows=False):
    sect = [(R0, y0), (R1, y0), (R1, y1), (R0, y1)]
    ids = [[m.v(g, _P(r, 2 * math.pi * i / n, y)) for (r, y) in sect] for i in range(n)]
    for i in range(n):
        j = (i + 1) % n
        for s in range(4):
            s2 = (s + 1) % 4
            dots = []
            if windows and s == 1 and i % 2 == 0:
                a = 2 * math.pi * (i + 0.5) / n
                dots = [(_P(R1, a, (y0 + y1) / 2 - 1.6), i), (_P(R1, a, (y0 + y1) / 2 + 1.6), i + 97)]
            m.face(g, [ids[i][s], ids[j][s], ids[j][s2], ids[i][s2]],
                   [(0, 1), (2, 3)] + ([(3, 0)] if i % rib == 0 else []), dots=dots,
                   inside=_P((R0 + R1) / 2, 2 * math.pi * (i + 0.5) / n, (y0 + y1) / 2))


def _cylinder(m, g, r, ys, n, every):
    ids = [[m.v(g, _P(r, 2 * math.pi * i / n, y)) for i in range(n)] for y in ys]
    for k in range(len(ys) - 1):
        for i in range(n):
            j = (i + 1) % n
            m.face(g, [ids[k][i], ids[k][j], ids[k + 1][j], ids[k + 1][i]],
                   [(0, 1), (2, 3)] + ([(3, 0)] if i % every == 0 else []), inside=(0, (ys[k] + ys[k + 1]) / 2, 0))
    for k in (0, len(ys) - 1):
        m.face(g, ids[k], [], inside=(0, (ys[0] + ys[-1]) / 2, 0))


def _cone(m, g, r, y0, ytip, n, every=2):
    ring = [m.v(g, _P(r, 2 * math.pi * i / n, y0)) for i in range(n)]
    tip = m.v(g, (0, ytip, 0))
    for i in range(n):
        m.face(g, [ring[i], ring[(i + 1) % n], tip], [(0, 1)] + ([(2, 0)] if i % every == 0 else []),
               inside=(0, y0 + (ytip - y0) * 0.25, 0))


def _box(m, g, c, h, open_face=None, base=1.0):
    cx, cy, cz = c
    hx, hy, hz = h
    C = [m.v(g, (cx + sx * hx, cy + sy * hy, cz + sz * hz)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    faces = {"-x": [0, 1, 3, 2], "+x": [4, 6, 7, 5], "-y": [0, 4, 5, 1], "+y": [2, 3, 7, 6], "-z": [0, 2, 6, 4], "+z": [1, 5, 7, 3]}
    for k, f in faces.items():
        if k != open_face:
            m.face(g, [C[i] for i in f], [(0, 1), (1, 2), (2, 3), (3, 0)], base=base,
                   inside=None if open_face else (cx, cy, cz))


def _beam(m, g, a, b, w):
    ax, ay, az = a
    bx, by, bz = b
    d = (bx - ax, by - ay, bz - az)
    ln = math.sqrt(sum(x * x for x in d))
    d = tuple(x / ln for x in d)
    up = (0.0, 1.0, 0.0) if abs(d[1]) < 0.9 else (1.0, 0.0, 0.0)
    u = (d[1] * up[2] - d[2] * up[1], d[2] * up[0] - d[0] * up[2], d[0] * up[1] - d[1] * up[0])
    lu = math.sqrt(sum(x * x for x in u))
    u = tuple(x / lu for x in u)
    v = (d[1] * u[2] - d[2] * u[1], d[2] * u[0] - d[0] * u[2], d[0] * u[1] - d[1] * u[0])
    offs = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    Aa = [m.v(g, tuple(a[k] + w * (ox * u[k] + oy * v[k]) for k in range(3))) for ox, oy in offs]
    Bb = [m.v(g, tuple(b[k] + w * (ox * u[k] + oy * v[k]) for k in range(3))) for ox, oy in offs]
    for i in range(4):
        j = (i + 1) % 4
        m.face(g, [Aa[i], Aa[j], Bb[j], Bb[i]], [(0, 3), (1, 2)],
               inside=tuple((a[k] + b[k]) / 2 for k in range(3)))


def build_station():
    """Original design (not a Frontier station): spindle with collars, two counter-rotating
    rings, solar arrays, radiators, dish and beacon mast, truss arm to an open docking bay."""
    m = Mesh()
    _cylinder(m, "S", 8, [-50, -40, -30, -20, -10, 0, 10, 20, 30, 40, 50], 20, 4)
    _cylinder(m, "S", 15, [-18, -15, -9, -6], 24, 3)
    _cylinder(m, "S", 11, [36, 39, 44], 20, 4)
    _cone(m, "S", 8, 50, 64, 20)
    _cone(m, "S", 8, -50, -66, 20)
    m.seg("S", (0, 64, 0), (0, 86, 0), base=0.9)
    ring = [m.v("S", _P(9, 2 * math.pi * i / 18, 72)) for i in range(18)]
    hub = m.v("S", (0, 66, 0))
    for i in range(18):
        m.face("S", [ring[i], ring[(i + 1) % 18], hub], [(0, 1)] + ([(2, 0)] if i % 3 == 0 else []))
    _torus_box(m, "A", 60, 70, -5, 5, 72, 4, windows=True)
    for k in range(6):
        a = k * math.pi / 3
        _beam(m, "A", _P(8, a, 0), _P(60, a, 0), 1.6)
    _torus_box(m, "B", 33, 39, 24, 30, 48, 4, windows=True)
    for k in range(4):
        a = k * math.pi / 2 + 0.3
        _beam(m, "B", _P(8, a, 27), _P(33, a, 27), 1.2)
    for side in (-1, 1):
        m.seg("S", (side * 8, -34, 0), (side * 22, -34, 0))
        x0, x1 = side * 22, side * 64
        q = [m.v("S", (x0, -34, -11)), m.v("S", (x1, -34, -11)), m.v("S", (x1, -34, 11)), m.v("S", (x0, -34, 11))]
        extra = [((x0 + (x1 - x0) * k / 8, -34, -11), (x0 + (x1 - x0) * k / 8, -34, 11)) for k in range(1, 8)]
        extra.append(((x0, -34, 0), (x1, -34, 0)))
        m.face("S", q, [(0, 1), (1, 2), (2, 3), (3, 0)], extra=extra)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        q = [m.v("S", _P(8, a, -42)), m.v("S", _P(26, a, -46)), m.v("S", _P(26, a, -58)), m.v("S", _P(8, a, -56))]
        m.face("S", q, [(0, 1), (1, 2), (2, 3)], extra=[(_P(14, a, -43.5), _P(14, a, -56.5)), (_P(20, a, -45), _P(20, a, -57.5))])
    by = -16
    for (yy, zz) in [(-3, -3), (3, -3), (3, 3), (-3, 3)]:
        m.seg("S", (14, by + yy, zz), (91, by + yy, zz), base=0.9)
    for k in range(14):
        x = 14 + 77 * k / 13
        m.seg("S", (x, by - 3, -3), (x, by + 3, -3), base=0.6)
        if k < 13:
            x2 = 14 + 77 * (k + 1) / 13
            m.seg("S", (x, by - 3, -3), (x2, by + 3, -3), base=0.5)
            m.seg("S", (x, by + 3, 3), (x2, by - 3, 3), base=0.5)
    _box(m, "S", (104, by, 0), (13, 9, 14), open_face="-z")
    _box(m, "S", (104, by, 6), (9, 6, 6), base=0.7)
    return m


BAY = (104.0, -16.0, -14.0)
SHIP_EDGES = None


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


# camera keyframes (smooth monotone cubic between keys)
KT = [2.6, 5.0, 6.2, 8.4, 9.4, 12.8, 14.4]
KEYS = {
    "dist": [600, 360, 300, 178, 300, 282, 270],
    "yaw": [-0.95, -0.50, -0.28, 0.18, 0.30, 0.40, 0.44],
    "pitch": [0.50, 0.44, 0.38, 0.20, 0.40, 0.38, 0.38],
    "cx": [0.55, 0.56, 0.54, 0.47, 0.50, 0.50, 0.50],
    "cy": [0.55, 0.57, 0.58, 0.55, 0.73, 0.74, 0.74],
}
F_LEN = 1250.0


def _pchip_slopes(x, y):
    n = len(x)
    h = [x[i + 1] - x[i] for i in range(n - 1)]
    d = [(y[i + 1] - y[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0:
            m[i] = 0.0
        else:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    def end(h0, h1, d0, d1):
        s = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
        if s * d0 <= 0:
            return 0.0
        if d0 * d1 <= 0 and abs(s) > abs(3 * d0):
            return 3 * d0
        return s
    m[0] = end(h[0], h[1], d[0], d[1])
    m[-1] = end(h[-1], h[-2], d[-1], d[-2])
    return m


_SLOPES = {k: _pchip_slopes(KT, v) for k, v in KEYS.items()}


def _pchip(k, t):
    x, y, m = KT, KEYS[k], _SLOPES[k]
    t = clamp(t, x[0], x[-1])
    i = 0
    while i < len(x) - 2 and t > x[i + 1]:
        i += 1
    h = x[i + 1] - x[i]
    s = (t - x[i]) / h
    h00 = 2 * s ** 3 - 3 * s ** 2 + 1
    h10 = s ** 3 - 2 * s ** 2 + s
    h01 = -2 * s ** 3 + 3 * s ** 2
    h11 = s ** 3 - s ** 2
    return h00 * y[i] + h10 * h * m[i] + h01 * y[i + 1] + h11 * h * m[i + 1]


def cam_state(t):
    return _pchip("dist", t), _pchip("yaw", t), _pchip("pitch", t), SW * _pchip("cx", t), SH * _pchip("cy", t)


# ============================================================================ splash
class BootSplash(QWidget):
    def __init__(self, screen, background_path: Path | None = None):
        super().__init__(None)
        self.setWindowTitle("Elite AI Bridge")
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool)
        self.setAttribute(Qt.WA_DeleteOnClose, True)
        self.setAttribute(Qt.WA_OpaquePaintEvent, True)
        self.setStyleSheet("background:#0b0b09;")

        self._ready_probe = None
        self._main_window = None
        self._created_at = time.monotonic()
        self._seq_start = None          # set once the event loop is running
        self._off_start = None          # power-off start (wall clock)
        self._max_total = 30.0
        self._t = 0.0                   # story time
        self._tw = 0.0                  # free-running animation time
        self._closing = False

        self._load_fonts()
        self._ok = np is not None
        if self._ok:
            self._build_geometry()
        self._content = QImage(CW, CH, QImage.Format_RGB32)
        self._housing_img = self._build_housing()
        self._overlay = self._build_overlay()
        self._scan = self._build_scanlines()
        self._noise = self._build_noise()
        self._title_g, self._title_w, self._title_shadow, self._title_cols = self._build_title()
        self._housing_px = QPixmap()
        rnd = random.Random(7)
        self._stars = [(rnd.uniform(-3000, 3000), rnd.uniform(-1800, 1800), rnd.uniform(800, 4200),
                        rnd.uniform(0.15, 0.7), rnd.uniform(0, 6.28)) for _ in range(520)]

        if screen is not None:
            try:
                self.setGeometry(screen.geometry())
            except Exception:
                pass

        self._timer = QTimer(self)
        self._timer.setTimerType(Qt.PreciseTimer)
        self._timer.setInterval(33)       # about 30 fps, like the v1.0.1 splash, so start-up work keeps flowing
        self._timer.timeout.connect(self._tick)
        self._timer.start()
        self._ready_timer = QTimer(self)
        self._ready_timer.setInterval(100)
        self._ready_timer.timeout.connect(self._probe_ready)
        self._ready_timer.start()
        # The first timer tick only happens once app.exec() runs, i.e. after main.py
        # has started the backend and loaded the QML scene. The story starts then.

    # ------------------------------------------------------------------ public API
    def set_ready_probe(self, probe):
        self._ready_probe = probe

    def set_main_window(self, window):
        self._main_window = window

    def finish(self):
        """Start the power-off now (used when the Bridge is ready, or as a manual skip)."""
        if self._off_start is None:
            self._off_start = time.monotonic()

    # ------------------------------------------------------------------ timing
    def showEvent(self, event):
        super().showEvent(event)
        self.raise_()
        self.activateWindow()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._housing_px = QPixmap()

    def _ready(self):
        try:
            return bool(self._ready_probe and self._ready_probe())
        except Exception:
            return False

    def _probe_ready(self):
        if self._off_start is not None or self._seq_start is None:
            return
        story = time.monotonic() - self._seq_start
        total = time.monotonic() - self._created_at
        if story >= STORY_END and (self._ready() or total >= self._max_total):
            self.finish()

    def _tick(self):
        now = time.monotonic()
        if self._seq_start is None:
            # Hold the warm-up frame until the timer ticks steadily (start-up work in
            # the same process makes the first frames uneven), at most STEADY_MAX_WAIT.
            first = getattr(self, "_first_tick", None)
            if first is None:
                self._first_tick = first = now
                self._last_tick = now
                self._steady = 0
            else:
                gap = now - self._last_tick
                self._last_tick = now
                self._steady = self._steady + 1 if gap < STEADY_GAP else 0
            if self._steady >= STEADY_TICKS or now - first >= STEADY_MAX_WAIT:
                self._seq_start = now + START_DELAY
            else:
                self.update()
                return
        self._tw = max(0.0, now - self._seq_start)
        self._t = min(self._tw, STORY_END) if self._off_start is None else STORY_END
        if self._off_start is not None:
            k = now - self._off_start
            if k > OFF_LEN:
                fade = clamp((k - OFF_LEN) / FADE_LEN)
                self.setWindowOpacity(1.0 - fade)
                if fade >= 1.0 and not self._closing:
                    self._closing = True
                    self._timer.stop()
                    self._ready_timer.stop()
                    self.close()
                    return
        self.update()

    # ------------------------------------------------------------------ assets
    def _load_fonts(self):
        fams = {}
        for key, fn in (("vt", "VT323-Regular.ttf"), ("st", "SairaStencilOne-Regular.ttf"), ("osw", "Oswald.ttf")):
            fam = None
            try:
                fid = QFontDatabase.addApplicationFont(str(SKIN / "fonts" / fn))
                fl = QFontDatabase.applicationFontFamilies(fid) if fid >= 0 else []
                fam = fl[0] if fl else None
            except Exception:
                fam = None
            fams[key] = fam or "Consolas"
        self._fam = fams

    def _font(self, key, px):
        f = QFont(self._fam[key])
        f.setPixelSize(int(px))
        f.setHintingPreference(QFont.PreferNoHinting)
        return f

    def _build_geometry(self):
        m = build_station()
        self._mesh = m
        self._GV = {g: np.array(v, float) if v else np.zeros((0, 3)) for g, v in m.V.items()}
        # flatten everything once so each frame is a few numpy calls plus one drawing loop
        groups = ["S", "A", "B"]
        off = {}
        n = 0
        for g in groups:
            off[g] = n
            n += len(m.V[g])
        self._goff = off
        E = m.E
        M = max(len(e["idx"]) for e in E)
        idx = np.zeros((len(E), M), np.int64)
        cnt = np.zeros(len(E), np.int64)
        gid = np.zeros(len(E), np.int64)
        nloc = np.zeros((len(E), 3))
        cloc = np.zeros((len(E), 3))
        cull = np.zeros(len(E), bool)
        self._el_idx, self._el_strokes = [], []
        for k, e in enumerate(E):
            gi = [off[e["g"]] + i for i in e["idx"]]
            idx[k, :len(gi)] = gi
            idx[k, len(gi):] = gi[-1]
            cnt[k] = len(gi)
            gid[k] = groups.index(e["g"])
            self._el_idx.append(gi)
            self._el_strokes.append([(gi[a], gi[b]) for (a, b) in e["stroke"]])
            V = np.array([m.V[e["g"]][i] for i in e["idx"]])
            c = V.mean(0)
            cloc[k] = c
            if e["inside"] is not None and len(V) >= 3:
                nn = np.cross(V[1] - V[0], V[2] - V[0])
                ln = np.linalg.norm(nn)
                if ln > 1e-9:
                    nn /= ln
                    if np.dot(nn, c - np.array(e["inside"])) < 0:
                        nn = -nn
                    nloc[k] = nn
                    cull[k] = True
        self._el_I, self._el_cnt, self._el_gid = idx, cnt, gid
        self._el_mask = (np.arange(M)[None, :] < cnt[:, None]).astype(float)   # ignore the padding columns
        self._el_n, self._el_c, self._el_cull = nloc, cloc, cull
        self._el_fill = np.array([e["fill"] and len(e["idx"]) >= 3 for e in E])
        self._el_base = np.array([e["base"] for e in E])
        self._el_has_extra = [bool(e["extra"] or e["dots"]) for e in E]
        # extra lines and window dots, flattened: local points + their group, per element ranges
        xp, xg, dp, dg, dseed = [], [], [], [], []
        self._el_xr, self._el_dr = [], []
        for k, e in enumerate(E):
            g = groups.index(e["g"])
            a0 = len(xp)
            for (a, b) in e["extra"]:
                xp += [a, b]
                xg += [g, g]
            self._el_xr.append((a0, len(xp)))
            d0 = len(dp)
            for (pt, seed) in e["dots"]:
                dp.append(pt)
                dg.append(g)
                dseed.append(seed)
            self._el_dr.append((d0, len(dp)))
        self._xp = np.array(xp, float) if xp else np.zeros((0, 3))
        self._xg = np.array(xg, np.int64)
        self._dp = np.array(dp, float) if dp else np.zeros((0, 3))
        self._dg = np.array(dg, np.int64)
        self._dseed = np.array(dseed, float)
        self._dwarm = [(int(sd) * 7919) % 5 == 0 for sd in dseed]
        self._V_all = np.concatenate([self._GV[g] for g in groups])
        self._v_gid = np.concatenate([np.full(len(m.V[g]), i) for i, g in enumerate(groups)])
        self._pens = {}
        tri = [((0, 0, 9), (-6.5, -0.5, -5), (0, 2.2, -4)), ((0, 0, 9), (6.5, -0.5, -5), (0, 2.2, -4)),
               ((0, 0, 9), (-6.5, -0.5, -5), (0, -1.2, -5)), ((0, 0, 9), (6.5, -0.5, -5), (0, -1.2, -5)),
               ((-6.5, -0.5, -5), (6.5, -0.5, -5), (0, 2.2, -4))]
        self._ship_tri = [np.array(t, float) for t in tri]
        P = {"n": (0, 0, 9), "l": (-6.5, -0.5, -5), "r": (6.5, -0.5, -5), "t": (0, 2.2, -4), "b": (0, -1.2, -5),
             "el": (-2.5, 0.3, -6), "er": (2.5, 0.3, -6)}
        E = [("n", "l"), ("n", "r"), ("n", "t"), ("l", "t"), ("r", "t"), ("l", "b"), ("r", "b"), ("n", "b"), ("l", "r"),
             ("el", "er"), ("el", "t"), ("er", "t")]
        self._ship_edges = [(np.array(P[a], float), np.array(P[b], float)) for a, b in E]
        # ship path control points (fixed in station space)
        t0 = 5.7
        d0, y0, p0, _, _ = cam_state(t0)
        R0 = rot_x(p0) @ rot_y(y0)
        bay = np.array(BAY)
        self._ship_ctrl = (R0.T @ np.array([26.0, -12.0, 70.0 - d0]), R0.T @ np.array([22.0, -4.0, 150.0 - d0]),
                           bay + np.array([0, 0, -170.0]), bay + np.array([0, 0, 8.0]))

    def _build_housing(self):
        img = QImage(FW, FH, QImage.Format_RGB32)
        p = QPainter(img)
        tex = QImage(str(SKIN / "textures" / "tex_housing.jpg"))
        if not tex.isNull():
            p.fillRect(0, 0, FW, FH, QBrush(tex))
            p.fillRect(0, 0, FW, FH, QColor(0, 0, 0, 56))
        else:
            p.fillRect(0, 0, FW, FH, QColor("#2e302a"))
        p.setRenderHint(QPainter.Antialiasing, True)
        # moulded bezel around the glass
        bez = QRectF(SX - 26, SY - 26, SW + 52, SH + 52)
        p.setPen(Qt.NoPen)
        for k in range(10, 0, -1):
            p.setBrush(QColor(0, 0, 0, 14))
            p.drawRoundedRect(bez.adjusted(-k, -k + 4, k, k + 4), 18 + k, 18 + k)
        grad = QLinearGradient(0, bez.top(), 0, bez.bottom())
        grad.setColorAt(0, QColor(48, 48, 44))
        grad.setColorAt(0.4, QColor(30, 30, 27))
        grad.setColorAt(1, QColor(20, 20, 18))
        p.setBrush(grad)
        p.drawRoundedRect(bez, 18, 18)
        p.setPen(QPen(QColor(255, 250, 230, 40), 1.5))
        p.setBrush(Qt.NoBrush)
        p.drawRoundedRect(bez.adjusted(1, 1, -1, -1), 17, 17)
        for (x, y) in [(18, 16), (FW - 18, 16), (18, FH - 18), (FW - 18, FH - 18)]:
            g = QRadialGradient(x - 3, y - 3, 10)
            g.setColorAt(0, QColor(190, 186, 170))
            g.setColorAt(1, QColor(60, 58, 52))
            p.setBrush(g)
            p.setPen(QPen(QColor(25, 24, 20), 1))
            p.drawEllipse(QPointF(x, y), 9, 9)
            p.setPen(QPen(QColor(30, 29, 25), 2))
            p.drawLine(QPointF(x - 6, y - 3), QPointF(x + 6, y + 3))
        # Dymo tape under the glass
        label = "CORE DYNAMICS DEV  //  BRIDGE SYSTEMS  //  COLD START"
        f = self._font("osw", 17)
        f.setLetterSpacing(QFont.AbsoluteSpacing, 2.5)
        p.setFont(f)
        tw = p.fontMetrics().horizontalAdvance(label)
        lx, ly = SX + 30, SY + SH + 24
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(0, 0, 0))
        p.drawRect(QRectF(lx, ly + 2, tw + 36, 26))
        tape = QImage(str(SKIN / "textures" / "tex_tape.png"))
        p.setBrush(QBrush(tape) if not tape.isNull() else QColor(22, 22, 22))
        p.drawRect(QRectF(lx, ly, tw + 36, 26))
        p.setPen(QColor(232, 228, 214))
        p.drawText(QRectF(lx + 18, ly, tw + 4, 26), Qt.AlignVCenter | Qt.AlignLeft, label)
        # lamp labels
        f2 = self._font("osw", 17)
        f2.setLetterSpacing(QFont.AbsoluteSpacing, 2.5)
        p.setFont(f2)
        p.setPen(QColor(229, 224, 209))
        for i, name in enumerate(["LINK", "DRIVE", "POWER"]):
            cx = SX + SW - 40 - i * 120
            p.drawText(QRectF(cx + 22, SY + SH + 26, 90, 26), Qt.AlignVCenter | Qt.AlignLeft, name)
        p.end()
        return img

    def _build_overlay(self):
        """Vignette, rounded glass edge and a faint reflection, as one image drawn over the picture."""
        img = QImage(CW, CH, QImage.Format_ARGB32_Premultiplied)
        img.fill(Qt.transparent)
        if np is None:
            return img
        yy, xx = np.mgrid[0:CH, 0:CW].astype(np.float32)
        nx = (xx - CW / 2) / (CW / 2)
        ny = (yy - CH / 2) / (CH / 2)
        r2 = nx * nx + ny * ny
        vign = np.clip(1.08 - 0.42 * r2 ** 1.4, 0, 1)
        ex = np.minimum(xx, CW - 1 - xx)
        ey = np.minimum(yy, CH - 1 - yy)
        edge = np.clip(np.minimum(ex, ey) / (26.0 * Q), 0, 1)
        dark = 1 - vign * edge            # how much black to lay over
        refl = np.clip(-ny - 0.35, 0, 1) ** 2 * 0.05
        a = np.clip(dark + refl, 0, 1)
        # colour: black for the darkening, pale green for the reflection
        rgb_w = np.where(a > 0, refl / np.maximum(a, 1e-6), 0)
        out = np.zeros((CH, CW, 4), np.uint8)
        out[..., 3] = (a * 255).astype(np.uint8)
        out[..., 2] = (rgb_w * 0.8 * a * 255).astype(np.uint8)      # premultiplied, BGRA order
        out[..., 1] = (rgb_w * 1.0 * a * 255).astype(np.uint8)
        out[..., 0] = (rgb_w * 0.9 * a * 255).astype(np.uint8)
        self._overlay_buf = out
        return QImage(out.data, CW, CH, CW * 4, QImage.Format_ARGB32_Premultiplied).copy()

    def _build_scanlines(self):
        img = QImage(CW, 2, QImage.Format_ARGB32_Premultiplied)
        img.fill(Qt.transparent)
        p = QPainter(img)
        p.fillRect(0, 1, CW, 1, QColor(0, 0, 0, 72))
        p.end()
        return img

    def _build_noise(self):
        tiles = []
        rnd = random.Random(3)
        for k in range(6):
            if np is not None:
                r = np.random.default_rng(k).random((128, 128)).astype(np.float32)
                a = (r * 255).astype(np.uint8)
                buf = np.zeros((128, 128, 4), np.uint8)
                buf[..., 3] = a
                buf[..., 2] = (a * 0.55).astype(np.uint8)
                buf[..., 1] = a
                buf[..., 0] = (a * 0.7).astype(np.uint8)
                img = QImage(buf.data, 128, 128, 512, QImage.Format_ARGB32_Premultiplied).copy()
            else:
                img = QImage(128, 128, QImage.Format_ARGB32_Premultiplied)
                img.fill(Qt.transparent)
            tiles.append(img.scaled(256, 256))
        return tiles

    def _build_title(self):
        f = self._font("st", 156)
        img_g = QImage(SW, 260, QImage.Format_ARGB32_Premultiplied)
        img_g.fill(Qt.transparent)
        p = QPainter(img_g)
        p.setRenderHint(QPainter.TextAntialiasing, True)
        p.setFont(f)
        p.setPen(QColor(*G))
        p.drawText(QRectF(0, 0, SW, 260), Qt.AlignCenter, "ELITE AI BRIDGE")
        fm = p.fontMetrics()
        w = fm.horizontalAdvance("ELITE AI BRIDGE")
        p.end()
        img_w = QImage(img_g)
        p = QPainter(img_w)
        p.setCompositionMode(QPainter.CompositionMode_SourceIn)
        p.fillRect(img_w.rect(), QColor(*WH))
        p.end()
        sh = QImage(img_g)
        p = QPainter(sh)
        p.setCompositionMode(QPainter.CompositionMode_SourceIn)
        p.fillRect(sh.rect(), QColor(0, 0, 0))
        p.end()
        sh = sh.scaled(SW // 12, 260 // 12, Qt.IgnoreAspectRatio, Qt.SmoothTransformation).scaled(SW, 260, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
        sh2 = QImage(sh)
        p = QPainter(sh2)
        p.drawImage(0, 0, sh)
        p.end()
        tw_, th_ = int(SW * Q), int(260 * Q)
        def q(im):
            return im.scaled(tw_, th_, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
        xa = (SW - w) / 2
        return q(img_g), q(img_w), q(sh2), (xa, xa + w)

    # ------------------------------------------------------------------ drawing helpers
    @staticmethod
    def _line(p, a, b, c, v, w=1.0):
        if v <= 0.004:
            return
        p.setPen(QPen(col(c, v), w, Qt.SolidLine, Qt.RoundCap))
        p.drawLine(QLineF(a[0], a[1], b[0], b[1]))

    @staticmethod
    def _circle(p, c, r, colr, v, w=1.0, fill=False):
        if v <= 0.004 or r <= 0:
            return
        if fill:
            p.setPen(Qt.NoPen)
            p.setBrush(col(colr, v))
        else:
            p.setPen(QPen(col(colr, v), w))
            p.setBrush(Qt.NoBrush)
        p.drawEllipse(QPointF(c[0], c[1]), r, r)

    def _text(self, p, xy, s, key, px, colr, v, align="l"):
        if not s or v <= 0.004:
            return
        p.setFont(self._font(key, px))
        p.setPen(col(colr, v))
        x, y = xy
        if align == "l":
            p.drawText(QRectF(x, y, 2000, px * 1.4), Qt.AlignLeft | Qt.AlignTop, s)
        elif align == "c":
            p.drawText(QRectF(x - 1000, y, 2000, px * 1.4), Qt.AlignHCenter | Qt.AlignTop, s)
        else:
            p.drawText(QRectF(x - 2000, y, 2000, px * 1.4), Qt.AlignRight | Qt.AlignTop, s)

    @staticmethod
    def _project(P, dist, cx, cy):
        z = np.maximum(P[..., 2] + dist, 1.0)
        return np.stack([cx + F_LEN * P[..., 0] / z, cy - F_LEN * P[..., 1] / z], -1), z

    # ------------------------------------------------------------------ scenes
    def _draw_selftest(self, p, t):
        s, _ = typed("CORE DYNAMICS DEV  //  BRIDGE SYSTEMS  //  UNIT 2.0.3", t, 0.62, 70)
        self._text(p, (46, 46), s, "vt", 32, G, 0.95)
        s2, _ = typed("COLD START SEQUENCE", t, 1.15, 50)
        self._text(p, (46, 86), s2, "vt", 32, G, 0.7)
        if t > 1.2:
            mem = int(524288 * ease(seg(t, 1.2, 1.95)))
            self._text(p, (46, 126), "MEMORY CHECK  %06dK" % mem + ("  OK" if t > 1.95 else ""), "vt", 32, G, 0.85)
        # The convergence target here looked jumpy; the self-test is text on black now.
        if t > 1.95:
            s3, _ = typed("SIGNAL  100%", t, 1.95, 40)
            self._text(p, (46, 166), s3, "vt", 32, G, 0.85)

    def _draw_stars(self, p, t, dist, yaw):
        push = 720 - dist
        c, s_ = math.cos(yaw * 0.15), math.sin(yaw * 0.15)
        buckets = {}
        for (x, y, z, b, ph) in self._stars:
            X = c * x + s_ * z
            Z = -s_ * x + c * z - push * 0.6
            sx = SW * 0.5 + 900 * X / Z
            sy = SH * 0.5 - 900 * y / Z
            if 0 <= sx < SW and 0 <= sy < SH:
                v = b * (0.75 + 0.25 * math.sin(t * 2.2 + ph)) * (1.4 if Z < 1500 else 1.0)
                big = b > 0.62
                key = (big, min(7, int(v * (0.8 if big else 1.0) * 8)))
                buckets.setdefault(key, []).append(QPointF(sx, sy))
        for (big, lv), pts in buckets.items():
            p.setPen(QPen(col(WH if big else G, (lv + 0.5) / 8), 2.6 if big else 1.8, Qt.SolidLine, Qt.RoundCap))
            p.drawPoints(pts)

    def _draw_planet(self, p, t, vis):
        if vis <= 0:
            return
        n = getattr(self, "_planet_n", 0)
        self._planet_n = n + 1
        cache = getattr(self, "_planet_img", None)
        if cache is None or n % 4 == 0 or abs(getattr(self, "_planet_vis", -1) - vis) > 0.02:
            img = QImage(int(SW * 0.62 * Q) + 2, int(SH * 0.70 * Q) + 2, QImage.Format_ARGB32_Premultiplied)
            img.fill(Qt.transparent)
            pp = QPainter(img)
            pp.setRenderHint(QPainter.Antialiasing, True)
            pp.scale(Q, Q)
            pp.translate(0, -SH * 0.30)
            self._draw_planet_lines(pp, t, vis)
            pp.end()
            self._planet_img, self._planet_vis = img, vis
        p.save()
        p.scale(1 / Q, 1 / Q)
        p.drawImage(QPointF(0, SH * 0.30 * Q), self._planet_img)
        p.restore()

    def _draw_planet_lines(self, p, t, vis):
        c = (SW * 0.10, SH * 1.22)
        R = 620
        tilt = 0.32
        ct, st = math.cos(tilt), math.sin(tilt)
        p.setBrush(Qt.NoBrush)
        for k in range(1, 9):
            lat = -math.pi / 2 + k * math.pi / 9
            y, r = math.sin(lat), math.cos(lat)
            pts = []
            for j in range(0, 181, 4):
                lon = math.radians(j)
                px, py, pz = r * math.cos(lon), y, r * math.sin(lon)
                py, pz = py * ct - pz * st, py * st + pz * ct
                pts.append(QPointF(c[0] + R * px, c[1] - R * py))
            p.setPen(QPen(col(G, 0.22 * vis), 1))
            p.drawPolyline(QPolygonF(pts))
        rot = t * 0.08
        for k in range(18):
            lon = rot + k * math.pi / 9
            sl = math.sin(lon)
            if sl < 0:
                continue
            pts = []
            for j in range(0, 181, 5):
                lat = math.radians(j - 90)
                px, py, pz = math.cos(lat) * math.cos(lon), math.sin(lat), math.cos(lat) * sl
                py, pz = py * ct - pz * st, py * st + pz * ct
                pts.append(QPointF(c[0] + R * px, c[1] - R * py))
            p.setPen(QPen(col(G, 0.18 * vis * sl), 1))
            p.drawPolyline(QPolygonF(pts))
        self._circle(p, c, R, G, 0.75 * vis, 2)
        self._circle(p, c, R + 10, G, 0.18 * vis, 6)

    def _pen(self, c, v, w):
        key = (c, int(v * 40), w)
        pen = self._pens.get(key)
        if pen is None:
            pen = QPen(col(c, key[1] / 40.0), w, Qt.SolidLine, Qt.FlatCap)
            self._pens[key] = pen
        return pen

    def _draw_station(self, p, t, tw, dist, yaw, pitch, cx, cy, dim):
        R = rot_x(pitch) @ rot_y(yaw)
        rots = [R, R @ rot_y(tw * 0.20), R @ rot_y(-tw * 0.34)]
        reveal = seg(t, 2.75, 5.0)
        ry = None if reveal >= 1 else -70 + 165 * ease_out(reveal)
        V = self._V_all
        W = np.empty_like(V)
        for gi in range(3):
            msk = self._v_gid == gi
            W[msk] = V[msk] @ rots[gi].T
        z = W[:, 2] + dist
        zz = np.maximum(z, 1.0)
        P2 = np.stack([cx + F_LEN * W[:, 0] / zz, cy - F_LEN * W[:, 1] / zz], 1)
        I = self._el_I
        ze = z[I]
        depth = (ze * self._el_mask).sum(1) / self._el_cnt
        zmin = ze.min(1)
        ok = zmin >= 12
        if ry is not None:
            ok &= V[:, 1][I].max(1) <= ry
        # skip faces turned away from the camera
        nw = np.empty_like(self._el_n)
        cw = np.empty_like(self._el_c)
        for gi in range(3):
            msk = self._el_gid == gi
            nw[msk] = self._el_n[msk] @ rots[gi].T
            cw[msk] = self._el_c[msk] @ rots[gi].T
        cw[:, 2] += dist
        facing = (nw * cw).sum(1) < 0
        ok &= (~self._el_cull) | facing
        order = np.nonzero(ok)[0]
        order = order[np.argsort(-depth[order], kind="stable")]
        near = np.clip(1.35 - (depth - dist) / 140.0, 0.30, 1.0)
        vals = np.minimum(1.0, near * self._el_base * dim)
        yv = V[:, 1][I].max(1) if ry is not None else None
        pl = P2.tolist()
        def proj_group(Pl, gl):
            Wq = np.empty_like(Pl)
            for gi in range(3):
                msk = gl == gi
                if msk.any():
                    Wq[msk] = Pl[msk] @ rots[gi].T
            zq = np.maximum(Wq[:, 2] + dist, 1.0)
            return np.stack([cx + F_LEN * Wq[:, 0] / zq, cy - F_LEN * Wq[:, 1] / zq], 1).tolist()
        xl = proj_group(self._xp, self._xg) if len(self._xp) else []
        dl = proj_group(self._dp, self._dg) if len(self._dp) else []
        dflick = (0.55 + 0.45 * np.sin(tw * 1.3 + self._dseed * 1.7)).tolist() if len(self._dp) else []
        fill = QColor(4, 11, 7)
        nofill_pen = Qt.NoPen
        el_idx, el_str, el_fill = self._el_idx, self._el_strokes, self._el_fill
        mesh_E = self._mesh.E
        drawn = set()
        for k in order.tolist():
            nk = float(near[k])
            th = 3.4 if (nk > 0.92 and dist < 230) else (2.4 if nk > 0.6 else 1.5)
            if el_fill[k]:
                p.setPen(nofill_pen)
                p.setBrush(fill)
                p.drawPolygon(QPolygonF([QPointF(*pl[i]) for i in el_idx[k]]))
            st = el_str[k]
            if st:
                p.setPen(self._pen(G, float(vals[k]), th))
                for (a, b) in st:
                    key = (a, b) if a < b else (b, a)
                    if key in drawn:
                        continue
                    drawn.add(key)
                    pa, pb = pl[a], pl[b]
                    p.drawLine(QLineF(pa[0], pa[1], pb[0], pb[1]))
                if ry is not None:
                    fy = ry - float(yv[k])
                    if fy < 8:
                        p.setPen(self._pen(WH, (1 - fy / 8) * dim, th + 1))
                        for (a, b) in st:
                            pa, pb = pl[a], pl[b]
                            p.drawLine(QLineF(pa[0], pa[1], pb[0], pb[1]))
            if self._el_has_extra[k]:
                x0, x1 = self._el_xr[k]
                if x1 > x0:
                    p.setPen(self._pen(G, float(vals[k]) * 0.6, 1.0))
                    for j in range(x0, x1, 2):
                        pa, pb = xl[j], xl[j + 1]
                        p.drawLine(QLineF(pa[0], pa[1], pb[0], pb[1]))
                d0, d1 = self._el_dr[k]
                if d1 > d0:
                    p.setPen(Qt.NoPen)
                    r = max(1.0, 2.2 * nk * (300.0 / max(dist, 1)))
                    for j in range(d0, d1):
                        p.setBrush(col(A if self._dwarm[j] else WH, dflick[j] * nk * dim * 0.85))
                        pp = dl[j]
                        p.drawEllipse(QPointF(pp[0], pp[1]), r, r)
        if ry is not None:
            ang = [2 * math.pi * i / 72 for i in range(73)]
            ring = np.array([[92 * math.cos(a), ry, 92 * math.sin(a)] for a in ang]) @ R.T
            pp, _ = self._project(ring, dist, cx, cy)
            p.setPen(QPen(col(WH, 0.5 * dim), 2))
            p.setBrush(Qt.NoBrush)
            p.drawPolyline(QPolygonF([QPointF(float(x), float(y)) for x, y in pp]))
        else:
            rA = rots[1]
            p.setPen(Qt.NoPen)
            for k in range(8):
                a = k * math.pi / 4
                Pw = rA @ np.array([70.5 * math.cos(a), 0, 70.5 * math.sin(a)])
                pp, zq = self._project(Pw, dist, cx, cy)
                if (0.5 + 0.5 * math.sin(tw * 4.0 + k * 0.9)) > 0.6 and zq < dist + 30:
                    p.setBrush(col(A, dim))
                    p.drawEllipse(QPointF(float(pp[0]), float(pp[1])), 3.0, 3.0)
            if (tw * 1.25) % 1.0 < 0.18:
                pp, _ = self._project(R @ np.array([0, 86, 0]), dist, cx, cy)
                p.setBrush(col(RD, dim))
                p.drawEllipse(QPointF(float(pp[0]), float(pp[1])), 3.6, 3.6)
        return R, P2

    def _has_extra(self, k):
        return self._el_has_extra[k]

    def _ship_pos(self, t):
        P0, P1, P2, P3 = self._ship_ctrl
        s_ = seg(t, 5.7, 12.8)
        u = 1 - (1 - s_) ** 2.4
        def bez(u):
            return (1 - u) ** 3 * P0 + 3 * (1 - u) ** 2 * u * P1 + 3 * (1 - u) * u ** 2 * P2 + u ** 3 * P3
        q = bez(u)
        d = bez(min(1.0, u + 0.004)) - q
        n = float(np.linalg.norm(d))
        d = d / n if n > 1e-6 else np.array([0, 0, 1.0])
        return q, d, u

    def _draw_dock(self, p, t, tw, dist, R, cx, cy, docked):
        bay = np.array(BAY)
        p.setBrush(Qt.NoBrush)
        for k in range(8):
            c = bay + np.array([0, 0, -10 - k * 18.0])
            corners = [c + np.array(o) for o in [(-12, -9, 0), (12, -9, 0), (12, 9, 0), (-12, 9, 0)]]
            pp = [self._project(q @ R.T, dist, cx, cy)[0] for q in corners]
            if docked:
                v = 0.55 + 0.45 * ((((tw * 3) - k * 0.35) % 1.0) < 0.3)
                cc = G
            else:
                chase = ((tw * 1.6) - (7 - k) / 8.0) % 1.0
                v = 0.25 + 0.75 * max(0.0, 1 - chase * 4)
                cc = A
            v *= (1.0 - k * 0.09) * seg(t, 5.2 + k * 0.08, 5.6 + k * 0.08)
            if v > 0.004:
                p.setPen(QPen(col(cc, v), 1.2))
                p.drawPolygon(QPolygonF([QPointF(float(x[0]), float(x[1])) for x in pp]))
        p.setPen(Qt.NoPen)
        for k, o in enumerate([(-12, -8), (0, -8), (12, -8), (-12, 8), (0, 8), (12, 8)]):
            pp, _ = self._project(np.array([bay[0] + o[0], bay[1] + o[1], bay[2]]) @ R.T, dist, cx, cy)
            if docked:
                p.setBrush(col(G, 1.0))
                p.drawEllipse(QPointF(float(pp[0]), float(pp[1])), 3.0, 3.0)
            elif ((tw * 2) + k * 0.15) % 1 < 0.5:
                p.setBrush(col(A, 0.9))
                p.drawEllipse(QPointF(float(pp[0]), float(pp[1])), 2.6, 2.6)

    def _draw_ship(self, p, t, dist, R, cx, cy):
        if t < 5.7:
            return None
        q, d, u = self._ship_pos(t)
        up = np.array([0, 1.0, 0])
        x = np.cross(up, d)
        x /= np.linalg.norm(x)
        y = np.cross(d, x)
        M = np.stack([x, y, d], 1)
        sc = 1.8
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(4, 11, 7))
        for tri in self._ship_tri:
            pp = [self._project((M @ (v * sc) + q) @ R.T, dist, cx, cy)[0] for v in tri]
            p.drawPolygon(QPolygonF([QPointF(float(a[0]), float(a[1])) for a in pp]))
        pts = []
        for a, b in self._ship_edges:
            Aw = (M @ (a * sc) + q) @ R.T
            Bw = (M @ (b * sc) + q) @ R.T
            pa, za = self._project(Aw, dist, cx, cy)
            pb, zb = self._project(Bw, dist, cx, cy)
            self._line(p, pa, pb, WH, 0.95, 3.0 if (za + zb) / 2 < 90 else 2.0)
            pts += [pa, pb]
        fl0 = 0.75 + 0.25 * math.sin(t * 40)
        for e in ((-2.5, 0.3, -6.5), (2.5, 0.3, -6.5)):
            pe, z = self._project((M @ (np.array(e) * sc) + q) @ R.T, dist, cx, cy)
            self._circle(p, pe, min(16.0, max(2.0, 2200.0 / z)) * fl0 * (1 - 0.6 * u), A, 1.0, fill=True)
        prev, _ = self._project((q - d * 6 * sc) @ R.T, dist, cx, cy)
        for k in range(1, 16):
            tk = t - k * 0.045
            if tk < 5.7:
                break
            qk, dk, _ = self._ship_pos(tk)
            pk, _ = self._project((qk - dk * 6 * sc) @ R.T, dist, cx, cy)
            self._line(p, prev, pk, A, (1 - k / 15.0) * 0.8 * (1 - 0.5 * u), 2.0)
            prev = pk
        P = np.array(pts)
        return float(P[:, 0].min()), float(P[:, 1].min()), float(P[:, 0].max()), float(P[:, 1].max())

    def _brackets(self, p, x0, y0, x1, y1, c, v, arm=26, th=2.0):
        for (x, y, dx, dy) in [(x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)]:
            self._line(p, (x, y), (x + dx * arm, y), c, v, th)
            self._line(p, (x, y), (x, y + dy * arm), c, v, th)

    BOOT_LOG = [("PHOSPHOR WARM-UP", "OK", G), ("FLIGHT COMPUTER LINK", "OK", G), ("VOICE SYNTH CORE", "OK", G),
                ("STAR CATALOGUE", "LOADED", G), ("THREAT MATRIX", "ARMED", A), ("COMMS ARRAY", "ONLINE", G),
                ("DOCKING COMPUTER", "STANDBY", A), ("BRIDGE AI", "AWAKE", G)]

    def _draw_hud(self, p, t, tw, box, shipbox):
        vis = seg(t, 2.7, 3.1)
        if vis <= 0:
            return
        side = vis * (1 - seg(t, 8.6, 9.3))
        x0, y0 = 46, 46
        if side > 0:
            self._text(p, (x0, y0), "BOOT LOG", "vt", 32, G, 0.9 * side)
            self._line(p, (x0, y0 + 40), (x0 + 470, y0 + 40), G, 0.5 * side)
            for i, (name, st, cc) in enumerate(self.BOOT_LOG):
                t0 = 3.0 + i * 0.72
                if t < t0:
                    break
                s, typing = typed(name, t, t0, 44)
                y = y0 + 54 + i * 38
                self._text(p, (x0, y), "> " + s, "vt", 28, G, 0.78 * side)
                if not typing:
                    dots = int(clamp((t - t0 - len(name) / 44.0) / 0.25) * 12)
                    self._text(p, (x0 + 300, y), "." * dots, "vt", 28, G, 0.5 * side)
                    if dots >= 12:
                        self._text(p, (x0 + 400, y), st, "vt", 28, cc, side)
            rc = (SW - 170, 170)
            rr = 112
            self._circle(p, rc, rr, G, 0.55 * side, 2)
            self._circle(p, rc, rr * 0.66, G, 0.3 * side)
            self._circle(p, rc, rr * 0.33, G, 0.3 * side)
            self._line(p, (rc[0] - rr, rc[1]), (rc[0] + rr, rc[1]), G, 0.25 * side)
            self._line(p, (rc[0], rc[1] - rr), (rc[0], rc[1] + rr), G, 0.25 * side)
            sweep = (tw / 2.5) * 2 * math.pi
            for k in range(14):
                a = sweep - k * 0.045
                self._line(p, rc, (rc[0] + rr * math.cos(a), rc[1] + rr * math.sin(a)), G, (0.9 - k * 0.06) * side, 2)
            for (bx, by, ph) in [(0.4, -0.3, 0.2), (-0.55, 0.2, 1.4), (0.15, 0.6, 3.1), (-0.2, -0.65, 4.4)]:
                a = math.atan2(by, bx) % (2 * math.pi)
                age = ((sweep % (2 * math.pi)) - a) % (2 * math.pi)
                self._circle(p, (rc[0] + rr * bx, rc[1] + rr * by), 3.2, A if ph > 4 else G, max(0.0, 1 - age / 4.0) * side, fill=True)
            self._text(p, (rc[0] - rr, rc[1] + rr + 14), "LOCAL SPACE // 25 KM", "vt", 24, G, 0.55 * side)
            ox, oy, ow, oh = SW - 290, 340, 240, 80
            p.setPen(QPen(col(G, 0.35 * side), 1))
            p.setBrush(Qt.NoBrush)
            p.drawRect(QRectF(ox, oy, ow, oh))
            ph = tw * 2 * math.pi / 2.0
            pts = []
            for i in range(61):
                x = i / 60
                yv = 0.45 * math.sin(x * 14 + ph * 2) * (0.6 + 0.4 * math.sin(x * 3 - ph)) + 0.2 * math.sin(x * 37 - ph * 3)
                pts.append(QPointF(ox + x * ow, oy + oh / 2 - yv * oh * 0.8))
            p.setPen(QPen(col(G, 0.85 * side), 2))
            p.drawPolyline(QPolygonF(pts))
            self._text(p, (ox, oy + oh + 8), "VOICE CARRIER", "vt", 24, G, 0.55 * side)
        lockv = 1 - seg(t, 8.6, 9.3)
        if box is not None and t > 4.9 and lockv > 0:
            k = ease_out(seg(t, 4.9, 5.7))
            bx0, by0, bx1, by1 = box[0] - 26, max(96, box[1] - 26), box[2] + 26, box[3] + 26
            fx0, fy0, fx1, fy1 = 40, 40, SW - 40, SH - 40
            xa = fx0 + (bx0 - fx0) * k
            ya = fy0 + (by0 - fy0) * k
            xb = fx1 + (bx1 - fx1) * k
            yb = fy1 + (by1 - fy1) * k
            self._brackets(p, xa, ya, xb, yb, G, 0.9 * lockv, 34, 2)
            if 5.7 < t < 5.95 and int(t * 16) % 2 == 0:
                self._brackets(p, xa, ya, xb, yb, WH, 1.0, 34, 3)
            if k >= 1:
                s, _ = typed("TARGET LOCK // ORBITAL RELAY K-7", t, 5.75, 50)
                self._text(p, (xa, ya - 36), s, "vt", 28, G, 0.95 * lockv)
                km = 4.2 * (1 - ease(seg(t, 5.7, 13.0))) + 0.1
                self._text(p, (xb, ya - 36), "RNG %.2f KM" % km, "vt", 28, G, 0.8 * lockv, "r")
        if shipbox is not None and t > 6.3:
            x0s, y0s, x1s, y1s = shipbox
            v = 0.9 * seg(t, 6.3, 6.6) * (1 - seg(t, 8.6, 9.3))
            if v > 0:
                self._brackets(p, x0s - 14, y0s - 14, x1s + 14, y1s + 14, A, v, 12, 2)
                self._text(p, (x1s + 22, y0s - 18), "INBOUND // CMDR", "vt", 24, A, v)
                self._text(p, (x1s + 22, y0s + 6), "VECTOR NOMINAL", "vt", 24, A, v * 0.7)
        prog = ease(seg(t, 2.9, 13.0))
        bx, by = 46, SH - 64
        self._text(p, (bx, by - 4), "SYSTEMS", "vt", 28, G, 0.7 * vis)
        p.setPen(Qt.NoPen)
        for i in range(40):
            lit = (i + 0.5) / 40 <= prog
            p.setBrush(col(G, (0.9 if lit else 0.14) * vis))
            p.drawRect(QRectF(bx + 120 + i * 14, by, 10, 20))
        self._text(p, (bx + 120 + 40 * 14 + 12, by - 4), "%3d%%" % int(round(prog * 100)), "vt", 28, G, 0.9 * vis)

    TITLE_Y = 40

    def _draw_title(self, p, t, tw):
        if t < 9.0:
            return
        y0 = self.TITLE_Y
        k = seg(t, 9.0, 9.7)
        xa, xb = self._title_cols
        edge = xa + (xb - xa + 60) * k
        p.save()
        p.resetTransform()                    # title images are already at the internal size
        yq, eq, hq = y0 * Q, edge * Q, 260 * Q
        p.setOpacity(min(1.0, 0.85 * clamp(k * 3)))
        p.drawImage(QPointF(0, yq), self._title_shadow)
        p.setOpacity(1.0)
        p.setClipRect(QRectF(0, yq, eq, hq))
        if t < 9.95:
            rnd = random.Random(int(t * 60))
            p.drawImage(QPointF(0, yq), self._title_g)
            iw = self._title_g.width()
            for _ in range(6):
                sy = rnd.randrange(0, int(248 * Q))
                sh = rnd.randrange(3, 12)
                dx = rnd.randrange(-22, 22)
                p.fillRect(QRectF(0, yq + sy, iw, sh), QColor(3, 8, 5))
                p.drawImage(QRectF(dx, yq + sy, iw, sh), self._title_g, QRectF(0, sy, iw, sh))
        else:
            p.drawImage(QPointF(0, yq), self._title_g)
        flash = 1 - seg(t, 9.7, 10.5)
        if flash > 0:
            p.setOpacity(0.9 * flash)
            p.drawImage(QPointF(0, yq), self._title_w)
        p.setOpacity(1.0)
        if k < 1:   # bright leading edge
            p.setClipRect(QRectF(eq - 20, yq, 20, hq))
            p.drawImage(QPointF(0, yq), self._title_w)
        p.restore()
        if t > 9.8:
            w = 700 * ease_out(seg(t, 9.8, 10.3))
            self._line(p, (SW / 2 - w, y0 + 236), (SW / 2 + w, y0 + 236), G, 0.7, 2)
            s, _ = typed("BRIDGE SYSTEMS ONLINE", t, 10.2, 34)
            self._text(p, (SW / 2, y0 + 250), s, "vt", 48, G, 0.95, "c")
        if t > 12.9:
            s, typing = typed("DOCKING GRANTED  //  WELCOME ABOARD, COMMANDER", t, 12.9, 40)
            cur = "_" if (typing or int(tw * 2.5) % 2 == 0) else ""
            self._text(p, (SW / 2, y0 + 304), s + cur, "vt", 40, G, 1.0, "c")

    # ------------------------------------------------------------------ frame
    def _render_content(self, t, tw):
        img = self._content
        img.fill(QColor(3, 8, 5))
        p = QPainter(img)
        p.setRenderHint(QPainter.Antialiasing, True)
        p.setRenderHint(QPainter.TextAntialiasing, True)
        p.setRenderHint(QPainter.SmoothPixmapTransform, True)
        p.scale(Q, Q)
        noise = 0.05
        if t < 2.62 or not self._ok:
            self._draw_selftest(p, t)
            p.end()
            if t > 2.2:
                k = seg(t, 2.2, 2.62)
                off = int((k ** 2) * CH * 1.3) % CH
                src = img.copy()
                p = QPainter(img)
                p.drawImage(0, -off, src)
                p.drawImage(0, CH - off, src)
                band = int(CH * 0.08)
                yb = (CH - off) % CH
                p.fillRect(0, max(0, yb - band), CW, band, QColor(0, 0, 0, 240))
                p.fillRect(img.rect(), QColor(0, 0, 0, int(255 * 0.5 * k)))
                p.end()
                noise = 0.30
            return noise
        dist, yaw, pitch, cx, cy = cam_state(t)
        self._draw_stars(p, tw, dist, yaw)
        self._draw_planet(p, tw, seg(t, 2.7, 3.6) * (1 - 0.5 * seg(t, 9, 10)))
        dim = 1.0 - 0.25 * seg(t, 9.0, 9.8)
        R, spts = self._draw_station(p, t, tw, dist, yaw, pitch, cx, cy, dim)
        docked = t > 12.85
        if t > 5.0:
            self._draw_dock(p, t, tw, dist, R, cx, cy, docked)
        shipbox = self._draw_ship(p, t, dist, R, cx, cy)
        box = None
        if t > 4.9:
            box = (max(60.0, float(spts[:, 0].min())), max(60.0, float(spts[:, 1].min())),
                   min(SW - 60.0, float(spts[:, 0].max())), min(SH - 60.0, float(spts[:, 1].max())))
        self._draw_hud(p, t, tw, box, shipbox)
        if docked and t < 13.35:
            k = seg(t, 12.85, 13.35)
            bp, _ = self._project(np.array(BAY) @ R.T, dist, cx, cy)
            self._circle(p, bp, 20 + 160 * k, WH, 1 - k, 3)
        self._draw_title(p, t, tw)
        p.end()
        return 0.05 + 0.25 * (1 - seg(t, 2.62, 3.0))

    def _post(self, noise, tw):
        """CRT look in QPainter: bloom (downscale/upscale), scanlines, noise, rolling bar, vignette."""
        img = self._content
        self._frame_no = getattr(self, "_frame_no", 0) + 1
        if self._frame_no % 2 == 1 or getattr(self, "_bloom", None) is None:
            # bloom: shrink (blur), add a wider halo, grow back. Refreshed every other frame.
            half = img.scaled(CW // 2, CH // 2, Qt.IgnoreAspectRatio, Qt.FastTransformation)
            small = half.scaled(CW // 5, CH // 5, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
            tiny = small.scaled(CW // 20, CH // 20, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
            comb = QImage(small.size(), QImage.Format_RGB32)
            comb.fill(QColor(0, 0, 0))
            bp = QPainter(comb)
            bp.setRenderHint(QPainter.SmoothPixmapTransform, True)
            bp.setCompositionMode(QPainter.CompositionMode_Plus)
            bp.setOpacity(0.55)
            bp.drawImage(0, 0, small)
            bp.setOpacity(0.45)
            bp.drawImage(QRectF(0, 0, comb.width(), comb.height()), tiny)
            bp.end()
            self._bloom = comb.scaled(CW, CH, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
        p = QPainter(img)
        p.setCompositionMode(QPainter.CompositionMode_Plus)
        p.setOpacity(0.8)
        p.drawImage(0, 0, self._bloom)
        bar = ((tw / 4.0) % 1.0) * (CH + 220) - 110
        gr = QLinearGradient(0, bar - 52, 0, bar + 52)
        gr.setColorAt(0, QColor(0, 0, 0, 0))
        gr.setColorAt(0.5, QColor(10, 24, 14, 255))
        gr.setColorAt(1, QColor(0, 0, 0, 0))
        p.setOpacity(1.0)
        p.fillRect(QRectF(0, bar - 52, CW, 104), gr)
        p.setOpacity(clamp(noise * 1.1))
        tile = self._noise[int(tw * 30) % len(self._noise)]
        ox = random.randrange(0, 256)
        oy = random.randrange(0, 256)
        p.setBrushOrigin(-ox, -oy)
        p.fillRect(img.rect(), QBrush(tile))
        p.setCompositionMode(QPainter.CompositionMode_SourceOver)
        p.setOpacity(1.0)
        p.fillRect(img.rect(), QBrush(self._scan))
        p.drawImage(0, 0, self._overlay)
        p.end()

    def render_frame(self, story_t, wall_t, off_k=None):
        """Draws the whole design-size frame (housing + glass). Used by paintEvent and by tests."""
        frame = QImage(self._housing_img)
        p = QPainter(frame)
        p.setRenderHint(QPainter.Antialiasing, True)
        p.setRenderHint(QPainter.SmoothPixmapTransform, True)
        self._paint_glass(p, story_t, wall_t, off_k, QRectF(SX, SY, SW, SH))
        self._paint_lamps(p, story_t, wall_t, 1.0, QPointF(0, 0))
        p.end()
        return frame

    def _paint_glass(self, p, t, tw, off_k, rect):
        sx = rect.width() / SW
        sy = rect.height() / SH
        p.fillRect(rect, QColor(3, 8, 5))
        if self._seq_start is None and off_k is None and t <= 0 and tw <= 0:
            return
        if t < 0.12 and off_k is None:
            return
        noise = self._render_content(t, tw)
        self._post(noise, tw)
        cxr, cyr = rect.center().x(), rect.center().y()
        if off_k is None and t < 0.3:
            k = seg(t, 0.12, 0.3)
            w = rect.width() * ease_out(k) * 0.98
            p.fillRect(QRectF(cxr - w / 2, cyr - 3 * sy, w, 6 * sy), QColor(235, 255, 240))
            return
        if off_k is None and t < 0.55:
            k = ease_out(seg(t, 0.3, 0.55))
            h = max(4.0, rect.height() * k)
            p.drawImage(QRectF(rect.left(), cyr - h / 2, rect.width(), h), self._content)
            p.fillRect(QRectF(rect.left(), cyr - h / 2, rect.width(), h), QColor(235, 255, 240, int(140 * (1 - seg(t, 0.3, 0.5)))))
            return
        if off_k is not None:
            if off_k < 0.46:
                k = ease(off_k / 0.46)
                h = max(4.0, rect.height() * (1 - k))
                r2 = QRectF(rect.left(), cyr - h / 2, rect.width(), h)
                p.drawImage(r2, self._content)
                p.fillRect(r2, QColor(235, 255, 240, int(255 * min(1.0, k * 1.2))))
            else:
                k = ease(clamp((off_k - 0.46) / 0.46))
                w = max(2.0, rect.width() * (1 - k))
                p.fillRect(QRectF(cxr - w / 2, cyr - 2 * sy, w, 4 * sy), QColor(235, 255, 240))
                g = QRadialGradient(cxr, cyr, (24 + 20 * (1 - k)) * sx)
                a = int(255 * clamp(1 - clamp((off_k - 0.85) / 0.15)))
                g.setColorAt(0, QColor(235, 255, 240, a))
                g.setColorAt(1, QColor(235, 255, 240, 0))
                p.setPen(Qt.NoPen)
                p.setBrush(g)
                p.drawEllipse(QPointF(cxr, cyr), (24 + 20 * (1 - k)) * sx, (24 + 20 * (1 - k)) * sx)
            return
        tw_, th_ = int(round(rect.width())), int(round(rect.height()))
        if tw_ == self._content.width() and th_ == self._content.height():
            p.drawImage(rect.topLeft(), self._content)
        else:
            p.drawImage(rect.topLeft(), self._content.scaled(tw_, th_, Qt.IgnoreAspectRatio, Qt.SmoothTransformation))

    def _paint_lamps(self, p, t, tw, scale, origin):
        ready_link = t > 12.9
        states = {
            "POWER": (G, 1.0),
            "DRIVE": (A, 1.0 if (0.4 < t < 13.2 and (math.sin(tw * 23) + math.sin(tw * 7.3)) > 0.4) else 0.0),
            "LINK": (G, 1.0 if ready_link else 0.0),
        }
        for i, name in enumerate(["LINK", "DRIVE", "POWER"]):
            c, on = states[name]
            cx = origin.x() + (SX + SW - 40 - i * 120) * scale
            cy = origin.y() + (SY + SH + 38) * scale
            if on:
                g = QRadialGradient(cx, cy, 34 * scale)
                g.setColorAt(0, QColor(c[0], c[1], c[2], 150))
                g.setColorAt(1, QColor(c[0], c[1], c[2], 0))
                p.setPen(Qt.NoPen)
                p.setBrush(g)
                p.drawEllipse(QPointF(cx, cy), 34 * scale, 34 * scale)
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(20, 20, 18))
            p.drawEllipse(QPointF(cx, cy), 13 * scale, 13 * scale)
            lens = QRadialGradient(cx - 3 * scale, cy - 3 * scale, 11 * scale)
            if on:
                lens.setColorAt(0, QColor(255, 255, 255))
                lens.setColorAt(0.35, QColor(c[0], c[1], c[2]))
                lens.setColorAt(1, QColor(int(c[0] * 0.45), int(c[1] * 0.45), int(c[2] * 0.45)))
            else:
                lens.setColorAt(0, QColor(110, 115, 105))
                lens.setColorAt(0.4, QColor(40, 48, 42))
                lens.setColorAt(1, QColor(16, 18, 16))
            p.setBrush(lens)
            p.drawEllipse(QPointF(cx, cy), 10 * scale, 10 * scale)

    def _log_perf(self):
        """One line per run in %LOCALAPPDATA%\\EliteAIBridge\\splash_perf.log (frame rate check)."""
        try:
            import os
            from datetime import datetime
            ft = getattr(self, "_perf", [])
            if len(ft) < 10:
                return
            srt = sorted(ft)
            avg = sum(ft) / len(ft)
            p95 = srt[int(len(srt) * 0.95)]
            span = self._perf_last - self._perf_first if self._perf_last > self._perf_first else 1.0
            dpr = self.devicePixelRatioF()
            line = ("%s  frames %d  fps %.1f  paint avg %.1f ms  p95 %.1f ms  window %dx%d @ %.2fx\n"
                    % (datetime.now().strftime("%Y-%m-%d %H:%M:%S"), len(ft), len(ft) / span, avg * 1000, p95 * 1000,
                       self.width(), self.height(), dpr))
            base = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "EliteAIBridge"
            base.mkdir(parents=True, exist_ok=True)
            with open(base / "splash_perf.log", "a", encoding="utf-8") as f:
                f.write(line)
            print("[SPLASH] " + line.strip(), flush=True)
        except Exception:
            pass

    def closeEvent(self, event):
        if not getattr(self, "_perf_logged", False):
            self._perf_logged = True
            self._log_perf()
        super().closeEvent(event)

    def paintEvent(self, event):
        _t0 = time.perf_counter()
        try:
            self._paint(event)
        finally:
            if self._seq_start is not None and time.monotonic() >= self._seq_start and self._off_start is None:
                now = time.monotonic()
                if not hasattr(self, "_perf"):
                    self._perf, self._perf_first = [], now
                self._perf.append(time.perf_counter() - _t0)
                self._perf_last = now

    def _paint(self, event):
        p = QPainter(self)
        w, h = self.width(), self.height()
        k = min(w / FW, h / FH)
        fw, fh = FW * k, FH * k
        ox, oy = (w - fw) / 2, (h - fh) / 2
        if self._housing_px.isNull() or self._housing_px.size() != self.size():
            px = QPixmap(self.size())
            pp = QPainter(px)
            tex = QImage(str(SKIN / "textures" / "tex_housing.jpg"))
            if not tex.isNull():
                pp.fillRect(px.rect(), QBrush(tex))
                pp.fillRect(px.rect(), QColor(0, 0, 0, 90))
            else:
                pp.fillRect(px.rect(), QColor("#2e302a"))
            pp.setRenderHint(QPainter.SmoothPixmapTransform, True)
            pp.drawImage(QRectF(ox, oy, fw, fh), self._housing_img)
            pp.end()
            self._housing_px = px
        p.drawPixmap(0, 0, self._housing_px)
        p.setRenderHint(QPainter.Antialiasing, True)
        p.setRenderHint(QPainter.SmoothPixmapTransform, True)
        off_k = None
        if self._off_start is not None:
            off_k = clamp((time.monotonic() - self._off_start) / OFF_LEN)
            if off_k >= 1.0:
                p.fillRect(QRectF(ox + SX * k, oy + SY * k, SW * k, SH * k), QColor(3, 8, 5))
                self._paint_lamps(p, self._t, self._tw, k, QPointF(ox, oy))
                p.end()
                return
        started = self._seq_start is not None and time.monotonic() >= self._seq_start
        if started or off_k is not None:
            self._paint_glass(p, self._t, self._tw, off_k, QRectF(ox + SX * k, oy + SY * k, SW * k, SH * k))
        else:
            self._paint_standby(p, QRectF(ox + SX * k, oy + SY * k, SW * k, SH * k), k)
        self._paint_lamps(p, self._t, self._tw, k, QPointF(ox, oy))
        p.end()

    def _paint_standby(self, p, rect, k):
        """Shown while the Bridge loads (the GUI thread is busy, so this frame is static):
        the tube warming up, a soft glow and STAND BY, so the wait never looks like nothing."""
        p.fillRect(rect, QColor(3, 8, 5))
        # The warm-up frame looked dead. Static + scan lines, in content space.
        # While the Bridge loads this frame is painted once and stays still; once the
        # event loop runs (waiting for steady frames) the static shimmers and a faint
        # bar rolls down, using the prebuilt noise / scanline images.
        now = time.monotonic()
        p.save()
        p.setClipRect(rect)
        p.translate(rect.topLeft())
        p.scale(rect.width() / CW, rect.height() / CH)
        full = QRectF(0, 0, CW, CH)
        if self._noise:
            p.setOpacity(0.16)
            tile = self._noise[int(now * 30) % len(self._noise)]
            p.setBrushOrigin(-random.randrange(0, 256), -random.randrange(0, 256))
            p.fillRect(full, QBrush(tile))
        bar = ((now / 3.2) % 1.0) * (CH + 220) - 110
        gr = QLinearGradient(0, bar - 60, 0, bar + 60)
        gr.setColorAt(0, QColor(0, 0, 0, 0))
        gr.setColorAt(0.5, QColor(40, 90, 55, 70))
        gr.setColorAt(1, QColor(0, 0, 0, 0))
        p.setOpacity(1.0)
        p.fillRect(QRectF(0, bar - 60, CW, 120), gr)
        p.setBrushOrigin(0, 0)
        p.fillRect(full, QBrush(self._scan))
        p.restore()
        c = rect.center()
        g = QRadialGradient(c, rect.width() * 0.42)
        g.setColorAt(0.0, QColor(60, 140, 90, 70))
        g.setColorAt(0.5, QColor(30, 80, 50, 28))
        g.setColorAt(1.0, QColor(0, 0, 0, 0))
        p.fillRect(rect, g)
        p.setFont(self._font("vt", 40 * k))
        p.setPen(QColor(125, 255, 160, 150))
        p.drawText(rect, Qt.AlignCenter, "STAND BY _")
        p.setFont(self._font("vt", 26 * k))
        p.setPen(QColor(125, 255, 160, 90))
        p.drawText(QRectF(rect.left(), c.y() + 34 * k, rect.width(), 40 * k), Qt.AlignHCenter | Qt.AlignTop, "TUBE WARMING")
