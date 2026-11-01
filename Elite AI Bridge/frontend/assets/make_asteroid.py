"""Original asteroid sprite atlas for the Mining page (Elite AI Bridge).

Ray-marches a lumpy rock (noise-displaced ellipsoid with a few flat fracture cuts) and bakes
one loop of rotation into an atlas. Channels are data, not colour; the QML shader colours them:
  R = diffuse shading, G = etched contour lines + facet edges, B = crack line, A = coverage.
Usage: python make_asteroid.py asteroid_rock.png   (v3: one still frame, craters, edge-line style)
"""
import sys
import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "asteroid_atlas.png"
PX = int(sys.argv[2]) if len(sys.argv) > 2 else 224
FRAMES = int(sys.argv[3]) if len(sys.argv) > 3 else 64
SS = 2
COLS = 16
import os as _os
FDIR = _os.environ.get("FDIR", "frames")
RNG = np.random.default_rng(4242)
PERM = RNG.permutation(256)
PERM = np.concatenate([PERM, PERM]).astype(np.int64)
GRAD = RNG.random(256).astype(np.float64)


def vnoise(p):
    """Value noise in [-1, 1], p (..., 3)."""
    i = np.floor(p).astype(np.int64)
    f = p - i
    u = f * f * (3 - 2 * f)
    def h(dx, dy, dz):
        x = (i[..., 0] + dx) & 255
        y = (i[..., 1] + dy) & 255
        z = (i[..., 2] + dz) & 255
        return GRAD[PERM[PERM[x] + y] + z & 511 & 255]
    c000, c100, c010, c110 = h(0, 0, 0), h(1, 0, 0), h(0, 1, 0), h(1, 1, 0)
    c001, c101, c011, c111 = h(0, 0, 1), h(1, 0, 1), h(0, 1, 1), h(1, 1, 1)
    ux, uy, uz = u[..., 0], u[..., 1], u[..., 2]
    x00 = c000 + (c100 - c000) * ux
    x10 = c010 + (c110 - c010) * ux
    x01 = c001 + (c101 - c001) * ux
    x11 = c011 + (c111 - c011) * ux
    y0 = x00 + (x10 - x00) * uy
    y1 = x01 + (x11 - x01) * uy
    return (y0 + (y1 - y0) * uz) * 2 - 1


def ridged(p):
    # sharp creases (1 - |noise|) for crevices
    return (1.0 - np.abs(vnoise(p))) ** 4 + 0.5 * (1.0 - np.abs(vnoise(p * 2.1 + 5.0))) ** 4


def fbm(p, octaves=4):
    a, s, out = 0.5, 1.0, 0.0
    for _ in range(octaves):
        out = out + a * vnoise(p * s + 13.1 * s)
        a *= 0.5
        s *= 2.03
    return out


AXES = np.array([1.0, 0.88, 0.78])
CUTS = []
for k in range(5):
    n = RNG.normal(size=3)
    n /= np.linalg.norm(n)
    CUTS.append((n, 0.78 + 0.12 * RNG.random()))


CRATERS = []
for _k in range(14):
    c = RNG.normal(size=3); c /= np.linalg.norm(c)
    CRATERS.append((c * (0.95 + 0.1 * RNG.random()) * AXES, 0.12 + 0.22 * RNG.random()))


def sdf(p):
    q = p / AXES
    d = (np.linalg.norm(q, axis=-1) - 1.0) * AXES.min()
    d = d - 0.20 * fbm(p * 1.4, 4) - 0.05 * fbm(p * 4.5, 2) + 0.035 * ridged(p * 3.2)
    for n, off in CUTS:
        d = np.maximum(d, p @ n - off)
    for c, r in CRATERS:
        d1 = np.linalg.norm(p - c, axis=-1) - r
        # smooth subtraction (a crater with a soft rim)
        h = np.clip(0.5 - 0.5 * (d + d1) / 0.05, 0, 1)
        d = d * (1 - h) + (-d1) * h + 0.05 * h * (1 - h)
    d = d - 0.012 * fbm(p * 14.0, 2)
    return d


def normal(p):
    e = 0.004
    g = np.stack([sdf(p + np.array([e, 0, 0])) - sdf(p - np.array([e, 0, 0])),
                  sdf(p + np.array([0, e, 0])) - sdf(p - np.array([0, e, 0])),
                  sdf(p + np.array([0, 0, e])) - sdf(p - np.array([0, 0, e]))], axis=-1)
    return g / (np.linalg.norm(g, axis=-1, keepdims=True) + 1e-9)


def rot(axis, ang):
    axis = axis / np.linalg.norm(axis)
    x, y, z = axis
    c, s = np.cos(ang), np.sin(ang)
    C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


TILT = rot(np.array([1.0, 0.0, 0.25]), 0.42)
SPIN_AXIS = np.array([0.15, 1.0, 0.1])
# the crack: a plane through the rock; the line is where the surface meets it
CRACK_N = np.array([0.82, 0.18, -0.54]); CRACK_N /= np.linalg.norm(CRACK_N)


def render(t):
    n = PX * SS
    span = 2.55
    xs = (np.arange(n) + 0.5) / n * span - span / 2
    X, Y = np.meshgrid(xs, -xs)
    origin = np.stack([X, Y, np.full_like(X, 3.0)], axis=-1).reshape(-1, 3)
    dirv = np.array([0.0, 0.0, -1.0])
    R = rot(SPIN_AXIS, t * 2 * np.pi) @ TILT
    Rinv = R.T
    o = origin @ Rinv.T
    d = dirv @ Rinv.T
    # start on a bounding sphere; rays that miss it are background
    Rb = 1.32
    b = o @ d
    c = (o * o).sum(-1) - Rb * Rb
    disc = b * b - c
    dist = np.maximum(0.0, -b - np.sqrt(np.maximum(disc, 0)))
    hit = np.zeros(len(o), bool)
    alive = disc > 0
    for _ in range(96):
        idx = np.nonzero(alive)[0]
        if len(idx) == 0:
            break
        p = o[idx] + d * dist[idx, None]
        s = sdf(p)
        dist[idx] += s * 0.8
        done = s < 0.0015
        hit[idx[done]] = True
        gone = dist[idx] > 6.0
        alive[idx[done | gone]] = False
    P = o + d * dist[:, None]
    body = np.zeros(len(o)); lines = np.zeros(len(o)); crack = np.zeros(len(o))
    nrm = np.zeros((len(o), 3))
    hi = np.nonzero(hit)[0]
    p = P[hi]
    nn = normal(p)
    nrm[hi] = nn @ R.T
    light = np.array([-0.5, 0.6, 0.65]); light /= np.linalg.norm(light)
    lw = light @ R  # light fixed in view space
    dif = np.clip(nn @ lw, 0, 1)
    body[hi] = 0.12 + 0.88 * dif
    # etched contours: iso-lines of a second noise field, thin and bright
    f = fbm(p * 2.0 + 7.0, 3) * 6.0 + fbm(p * 5.0, 2) * 1.5
    fr = np.abs(f - np.round(f))
    contour = np.clip(1.0 - fr / 0.10, 0, 1) ** 1.6
    crease = np.clip((1.0 - np.abs(vnoise(p * 3.2)) - 0.93) * 14.0, 0, 1) + np.clip((1.0 - np.abs(vnoise(p * 6.7 + 5.0)) - 0.95) * 14.0, 0, 1) * 0.6
    lines[hi] = crease * 0.35 * (0.45 + 0.55 * dif)
    cd = np.abs(p @ CRACK_N + 0.05 * fbm(p * 4.0, 2))
    crack[hi] = np.clip(1.0 - cd / 0.035, 0, 1)
    img_n = nrm.reshape(n, n, 3)
    # facet edges: where the screen-space normal jumps
    gx = np.linalg.norm(np.diff(img_n, axis=1, append=img_n[:, -1:]), axis=-1)
    gy = np.linalg.norm(np.diff(img_n, axis=0, append=img_n[-1:]), axis=-1)
    edge = np.clip((gx + gy) * 2.2 - 0.18, 0, 1) ** 0.8
    a = hit.reshape(n, n).astype(np.float64)
    edge *= a
    L = np.maximum(lines.reshape(n, n), edge)
    rgba = np.stack([body.reshape(n, n), L, crack.reshape(n, n), a], axis=-1)
    # downsample (box) for antialiasing
    rgba = rgba.reshape(PX, SS, PX, SS, 4).mean(axis=(1, 3))
    # store straight colour (un-premultiplied where partially covered)
    cov = rgba[..., 3:4]
    rgba[..., :3] = np.where(cov > 1e-3, rgba[..., :3] / np.maximum(cov, 1e-3), 0)
    return np.clip(rgba, 0, 1)


def main():
    """One still frame at 512 px (the Bridge moves it live). Writes OUT."""
    global PX
    PX = 512
    fr = render(0.13)
    Image.fromarray((fr * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT, optimize=True)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
