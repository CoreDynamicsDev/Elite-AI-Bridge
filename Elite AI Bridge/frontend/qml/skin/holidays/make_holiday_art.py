"""Makes the holiday decoration art (original line art, SVG) in holidays/art/.
Run it again after changing a shape or colour: python make_holiday_art.py
Every piece is drawn in a 64 x 64 box centred on (32, 32) unless noted."""
import math
from pathlib import Path

OUT = Path(__file__).with_name("art")
OUT.mkdir(exist_ok=True)
INK = "#1a0d04"


def svg(name, body, w=64, h=64):
    (OUT / f"{name}.svg").write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>\n')


# ---------------------------------------------------------------- Thanksgiving
MAPLE = "M0,-10 L2,-5 L6,-7 L5,-2 L10,-1 L6,2 L7,6 L2,4 L1,9 L-1,9 L-2,4 L-7,6 L-6,2 L-10,-1 L-5,-2 L-6,-7 L-2,-5 Z"
OAK = ("M0,-11 C3,-11 3,-8 2,-7 C5,-8 6,-5 3,-3 C6,-3 6,0 3,1 C6,2 5,5 2,4 C3,7 1,9 0,11 C-1,9 -3,7 -2,4 "
       "C-5,5 -6,2 -3,1 C-6,0 -6,-3 -3,-3 C-6,-5 -5,-8 -2,-7 C-3,-8 -3,-11 0,-11 Z")
for name, c in [("maple_red", "#9b2a14"), ("maple_orange", "#d9701f"), ("maple_gold", "#e0a12a"), ("maple_brown", "#6b3a1c")]:
    svg(name, f'<g transform="translate(32,32) scale(2.7)"><path d="{MAPLE}" fill="{c}" stroke="{INK}" stroke-width="0.7" stroke-linejoin="round"/>'
              f'<path d="M0,9 L0,-6 M0,1 L5,-1 M0,1 L-5,-1" stroke="{INK}" stroke-width="0.55" fill="none" opacity="0.8"/></g>')
for name, c in [("oak_brown", "#7a4a20"), ("oak_rust", "#a8441c")]:
    svg(name, f'<g transform="translate(32,32) scale(2.5)"><path d="{OAK}" fill="{c}" stroke="{INK}" stroke-width="0.7"/>'
              f'<path d="M0,11 L0,-8" stroke="{INK}" stroke-width="0.55" opacity="0.8"/></g>')
svg("acorn", f'<g transform="translate(32,34) scale(3)"><ellipse cy="3" rx="4" ry="5" fill="#8a5a2b" stroke="{INK}" stroke-width="0.6"/>'
             f'<path d="M-5,0 Q0,-5 5,0 Z" fill="#5a3a1a" stroke="{INK}" stroke-width="0.6"/><path d="M0,-3 L1,-6" stroke="{INK}" stroke-width="1"/></g>')
# pumpkin: origin at the bottom centre (32, 60)
svg("pumpkin", f'<g transform="translate(32,60) scale(2.3)">'
               f'<ellipse cx="-7" cy="-11" rx="8" ry="11" fill="#c8601c" stroke="{INK}" stroke-width="0.9"/>'
               f'<ellipse cx="7" cy="-11" rx="8" ry="11" fill="#c8601c" stroke="{INK}" stroke-width="0.9"/>'
               f'<ellipse cx="0" cy="-11" rx="8" ry="11.5" fill="#e07a24" stroke="{INK}" stroke-width="0.9"/>'
               f'<ellipse cx="-2" cy="-15" rx="2" ry="4" fill="#fff" opacity=".18"/>'
               f'<path d="M0,-21 C0,-24 2,-25 3.5,-25.5" stroke="#4d3a18" stroke-width="2.6" fill="none" stroke-linecap="round"/>'
               f'<path d="M2,-22 C7,-26 11,-23 9,-20 C7,-22 5,-22 2,-22 Z" fill="#4d6b1f"/></g>')
# turkey in three parts so the fan and head can move. 96 x 96 boxes, hip at (48, 72).
fan = []
cols = ["#7a2412", "#c8601c", "#e0a12a", "#a8611f", "#e0a12a", "#c8601c", "#7a2412"]
for i, c in enumerate(cols):
    a = math.radians(-150 + i * 20); r = 34
    a1, a2 = a - math.radians(9), a + math.radians(9)
    fan.append(f'<path d="M0,0 L{math.cos(a1)*r:.1f},{math.sin(a1)*r:.1f} Q{math.cos(a)*(r+8):.1f},{math.sin(a)*(r+8):.1f} '
               f'{math.cos(a2)*r:.1f},{math.sin(a2)*r:.1f} Z" fill="{c}" stroke="{INK}" stroke-width="1"/>')
    fan.append(f'<path d="M{math.cos(a)*r*0.55:.1f},{math.sin(a)*r*0.55:.1f} L{math.cos(a)*r*0.85:.1f},{math.sin(a)*r*0.85:.1f}" '
               f'stroke="#f0d08a" stroke-width="1.8" opacity=".6"/>')
svg("turkey_fan", f'<g transform="translate(48,66)">{"".join(fan)}</g>', 96, 96)
svg("turkey_body", f'<g transform="translate(48,66)">'
                   f'<ellipse cx="0" cy="-6" rx="15" ry="12.5" fill="#6b3a1c" stroke="{INK}" stroke-width="1.1"/>'
                   f'<path d="M-10,-6 Q0,3 10,-6" stroke="#4a2810" stroke-width="1.2" fill="none"/>'
                   f'<path d="M-5,5 L-6,12 M5,5 L6,12 M-9,12 L-3,12 M3,12 L9,12" stroke="#e0a12a" stroke-width="2" stroke-linecap="round"/></g>', 96, 96)
# head: neck base at (48, 66) of its own 96 box, so it rotates around the neck
svg("turkey_head", f'<g transform="translate(48,66)">'
                   f'<path d="M0,6 C1,-1 2,-6 2,-12" stroke="#6b3a1c" stroke-width="6" fill="none" stroke-linecap="round"/>'
                   f'<circle cx="2.8" cy="-14" r="5.4" fill="#b8aa96" stroke="{INK}" stroke-width="0.9"/>'
                   f'<circle cx="4.2" cy="-15.2" r="1.2" fill="#111"/>'
                   f'<path d="M7.6,-14.6 L11.6,-13.4 L7.6,-12.2 Z" fill="#e0a12a"/>'
                   f'<path d="M7,-12 C8,-8 7,-6 6,-4.5" stroke="#a8311c" stroke-width="2.3" fill="none" stroke-linecap="round"/></g>', 96, 96)

# ---------------------------------------------------------------- Christmas
for name, c in [("bulb_gold", "#ffd257"), ("bulb_white", "#f4f1e6"), ("bulb_green", "#45e07a"), ("bulb_blue", "#5aa8ff"), ("bulb_red", "#b5473c")]:
    # socket at the top centre (32, 4)
    svg(name, f'<rect x="27" y="2" width="10" height="9" rx="2" fill="#2b2f27" stroke="{INK}" stroke-width="0.8"/>'
              f'<ellipse cx="32" cy="30" rx="11" ry="18" fill="{c}" stroke="{INK}" stroke-width="0.8"/>'
              f'<ellipse cx="28" cy="24" rx="3" ry="7" fill="#fff" opacity="0.5"/>')
flake = []
for k in range(6):
    a = k * 60
    flake.append(f'<g transform="rotate({a})"><path d="M0,0 L0,-24 M0,-9 L-6,-15 M0,-9 L6,-15 M0,-17 L-4,-21 M0,-17 L4,-21" '
                 f'stroke="#f4f8ff" stroke-width="2.6" stroke-linecap="round" fill="none"/></g>')
svg("flake_a", f'<g transform="translate(32,32)">{"".join(flake)}</g>')
svg("flake_b", f'<g transform="translate(32,32)"><circle r="9" fill="#f4f8ff"/><circle r="15" fill="#f4f8ff" opacity="0.25"/></g>')
for name, body, rib in [("present_green", "#2f6b3c", "#ffd257"), ("present_blue", "#29467a", "#f4f1e6"),
                        ("present_red", "#7a2e2a", "#ffd257"), ("present_gold", "#d9b44a", "#2f6b3c")]:
    # sits on its bottom edge (y 62)
    svg(name, f'<rect x="10" y="26" width="44" height="36" rx="2" fill="{body}" stroke="{INK}" stroke-width="1.2"/>'
              f'<rect x="10" y="26" width="44" height="6" fill="#000" opacity="0.18"/>'
              f'<rect x="28.5" y="26" width="7" height="36" fill="{rib}"/>'
              f'<path d="M32,26 C20,12 14,24 32,26 C50,12 56,24 32,26" fill="none" stroke="{rib}" stroke-width="3.5"/>')
# ---------------------------------------------------------------- secret: LOST CARGO
for name, body, band in [("canister_a", "#8a8f86", "#e0b62a"), ("canister_b", "#6f7a84", "#d9701f")]:
    svg(name, f'<g transform="translate(32,32) rotate(-20)">'
              f'<rect x="-11" y="-22" width="22" height="44" rx="5" fill="{body}" stroke="{INK}" stroke-width="1.4"/>'
              f'<rect x="-11" y="-6" width="22" height="12" fill="{band}" stroke="{INK}" stroke-width="1"/>'
              f'<path d="M-11,-6 L-3,6 M-3,-6 L5,6 M5,-6 L11,3" stroke="{INK}" stroke-width="2" opacity=".55"/>'
              f'<rect x="-6" y="-26" width="12" height="5" rx="1.5" fill="#4a4f48" stroke="{INK}" stroke-width="1"/>'
              f'<rect x="-6" y="21" width="12" height="5" rx="1.5" fill="#4a4f48" stroke="{INK}" stroke-width="1"/>'
              f'<rect x="-8" y="-19" width="3" height="10" rx="1.5" fill="#fff" opacity=".25"/></g>')

# ---------------------------------------------------------------- New Year
for name, c in [("confetti_gold", "#ffd257"), ("confetti_white", "#f4f1e6"), ("confetti_blue", "#5aa8ff"),
                ("confetti_green", "#45e07a"), ("confetti_pink", "#f08bb4")]:
    svg(name, f'<rect x="24" y="14" width="16" height="36" rx="2" fill="{c}" stroke="{INK}" stroke-width="1.2"/>')
def star(cx, cy, r1, r2, n=5):
    pts = []
    for i in range(n * 2):
        a = math.pi / n * i - math.pi / 2; r = r1 if i % 2 == 0 else r2
        pts.append(f"{cx + math.cos(a) * r:.1f},{cy + math.sin(a) * r:.1f}")
    return "M" + " L".join(pts) + " Z"
svg("star_gold", f'<path d="{star(32, 33, 24, 10)}" fill="#ffd257" stroke="{INK}" stroke-width="1.4" stroke-linejoin="round"/>'
                 f'<path d="{star(32, 33, 10, 4)}" fill="#fff" opacity=".35"/>')
svg("star_silver", f'<path d="{star(32, 33, 24, 10)}" fill="#d9dde2" stroke="{INK}" stroke-width="1.4" stroke-linejoin="round"/>')
for name, c, band in [("party_hat_blue", "#3a6fc4", "#ffd257"), ("party_hat_gold", "#d9a62a", "#f4f1e6")]:
    # stands on its bottom edge (y 62)
    svg(name, f'<path d="M32,6 L50,60 L14,60 Z" fill="{c}" stroke="{INK}" stroke-width="1.4" stroke-linejoin="round"/>'
              f'<path d="M27,22 L37,22 M22,38 L42,38 M18,50 L46,50" stroke="{band}" stroke-width="3.2"/>'
              f'<circle cx="32" cy="6" r="5" fill="{band}" stroke="{INK}" stroke-width="1.2"/>'
              f'<ellipse cx="32" cy="60" rx="18" ry="3" fill="{c}" stroke="{INK}" stroke-width="1.2"/>')
svg("popper", f'<g transform="rotate(-25 32 40)"><path d="M24,62 L28,30 L36,30 L40,62 Z" fill="#c23a6b" stroke="{INK}" stroke-width="1.3"/>'
              f'<path d="M26,46 L38,46" stroke="#ffd257" stroke-width="3"/>'
              f'<path d="M32,30 C30,22 22,20 20,12 M32,30 C34,20 40,16 44,8 M32,30 C32,22 32,16 30,8" stroke="#ffd257" stroke-width="2.4" fill="none" stroke-linecap="round"/></g>')

# ---------------------------------------------------------------- Valentine's Day (pinks, not alarm red)
HEART = "M32,56 C10,40 6,28 10,20 C14,11 26,10 32,20 C38,10 50,11 54,20 C58,28 54,40 32,56 Z"
for name, c in [("heart_pink", "#f08bb4"), ("heart_rose", "#d9577f"), ("heart_light", "#f7c1d4"), ("heart_white", "#f4f1e6")]:
    svg(name, f'<path d="{HEART}" fill="{c}" stroke="{INK}" stroke-width="1.6" stroke-linejoin="round"/>'
              f'<ellipse cx="20" cy="22" rx="4" ry="6" fill="#fff" opacity=".35" transform="rotate(-30 20 22)"/>')
svg("heart_box", f'<path d="M32,60 C8,44 4,30 8,21 C12,11 26,10 32,21 C38,10 52,11 56,21 C60,30 56,44 32,60 Z" fill="#c23a6b" stroke="{INK}" stroke-width="1.6"/>'
                 f'<path d="M32,52 C14,40 12,30 15,24 C18,17 28,17 32,25 C36,17 46,17 49,24 C52,30 50,40 32,52 Z" fill="#e86a9a" stroke="{INK}" stroke-width="1"/>'
                 f'<path d="M32,25 C26,14 18,12 20,8 C24,4 30,12 32,18 C34,12 40,4 44,8 C46,12 38,14 32,25" fill="#f4f1e6" stroke="{INK}" stroke-width="1"/>')
svg("rose", f'<path d="M32,62 C33,48 31,38 32,30" stroke="#3f6b2a" stroke-width="3" fill="none"/>'
            f'<path d="M32,46 C24,40 20,44 22,48 C26,50 30,48 32,46 Z" fill="#4d7f2f" stroke="{INK}" stroke-width="1"/>'
            f'<path d="M20,20 C18,8 30,4 32,10 C34,4 46,8 44,20 C42,30 22,30 20,20 Z" fill="#d9577f" stroke="{INK}" stroke-width="1.4"/>'
            f'<path d="M26,16 C28,10 36,10 38,16 C36,22 28,22 26,16 Z" fill="#f08bb4" stroke="{INK}" stroke-width="1"/>')

# ---------------------------------------------------------------- St. Patrick's Day
def shamrock(c):
    leaf = "M0,0 C-10,-6 -12,-18 -4,-20 C0,-21 2,-17 0,-12 C-2,-17 0,-21 4,-20 C12,-18 10,-6 0,0 Z"
    leaves = "".join(f'<path d="{leaf}" transform="rotate({a})" fill="{c}" stroke="{INK}" stroke-width="1.2"/>' for a in (0, 120, 240))
    return f'<g transform="translate(32,30)"><path d="M0,2 C2,12 6,20 12,26" stroke="#2f5a1f" stroke-width="3" fill="none" stroke-linecap="round"/>{leaves}<circle r="2.4" fill="#2f5a1f"/></g>'
svg("shamrock", shamrock("#3fa34d"))
svg("shamrock_light", shamrock("#7ccf5a"))
svg("gold_coin", f'<circle cx="32" cy="32" r="18" fill="#e0b62a" stroke="{INK}" stroke-width="1.6"/>'
                 f'<circle cx="32" cy="32" r="12" fill="none" stroke="#a87c14" stroke-width="2"/><ellipse cx="25" cy="25" rx="4" ry="6" fill="#fff" opacity=".35"/>')
svg("pot_of_gold", f'<ellipse cx="32" cy="26" rx="22" ry="7" fill="#ffd257" stroke="{INK}" stroke-width="1.2"/>'
                   f'<circle cx="24" cy="22" r="5" fill="#e0b62a" stroke="{INK}" stroke-width="1"/><circle cx="34" cy="19" r="5" fill="#ffd257" stroke="{INK}" stroke-width="1"/>'
                   f'<circle cx="42" cy="23" r="5" fill="#e0b62a" stroke="{INK}" stroke-width="1"/>'
                   f'<path d="M10,28 C8,44 14,60 32,60 C50,60 56,44 54,28 Z" fill="#26292a" stroke="{INK}" stroke-width="1.4"/>'
                   f'<path d="M10,28 C18,34 46,34 54,28" stroke="#4a4f52" stroke-width="3" fill="none"/>')
svg("green_hat", f'<ellipse cx="32" cy="54" rx="28" ry="7" fill="#2f7a3a" stroke="{INK}" stroke-width="1.4"/>'
                 f'<path d="M16,54 L19,14 L45,14 L48,54 Z" fill="#3fa34d" stroke="{INK}" stroke-width="1.4"/>'
                 f'<rect x="18" y="40" width="28" height="7" fill="#1d2a1a"/><rect x="28" y="39" width="8" height="9" rx="1" fill="none" stroke="#ffd257" stroke-width="2"/>')

# ---------------------------------------------------------------- Easter (pastels)
EGG = "M32,6 C46,6 54,30 54,42 C54,54 44,60 32,60 C20,60 10,54 10,42 C10,30 18,6 32,6 Z"
for name, c, d in [("egg_blue", "#8cc4f0", "#f4f1e6"), ("egg_pink", "#f4a7c8", "#ffd257"), ("egg_yellow", "#f4dc6a", "#8cc4f0"), ("egg_green", "#a6dc8c", "#f4a7c8")]:
    svg(name, f'<path d="{EGG}" fill="{c}" stroke="{INK}" stroke-width="1.6"/>'
              f'<path d="M12,34 Q22,28 32,34 T52,34" stroke="{d}" stroke-width="4" fill="none"/>'
              f'<circle cx="22" cy="46" r="3" fill="{d}"/><circle cx="32" cy="48" r="3" fill="{d}"/><circle cx="42" cy="46" r="3" fill="{d}"/>'
              f'<ellipse cx="24" cy="20" rx="3" ry="6" fill="#fff" opacity=".4"/>')
def blossom(c):
    pet = "".join(f'<ellipse cx="0" cy="-12" rx="8" ry="12" transform="rotate({a})" fill="{c}" stroke="{INK}" stroke-width="1"/>' for a in range(0, 360, 72))
    return f'<g transform="translate(32,32)">{pet}<circle r="5" fill="#ffd257" stroke="{INK}" stroke-width="1"/></g>'
svg("blossom_pink", blossom("#f7c1d4"))
svg("blossom_white", blossom("#f4f1e6"))
svg("chick", f'<ellipse cx="32" cy="44" rx="18" ry="16" fill="#f4dc6a" stroke="{INK}" stroke-width="1.4"/>'
             f'<circle cx="32" cy="24" r="12" fill="#f4dc6a" stroke="{INK}" stroke-width="1.4"/>'
             f'<circle cx="36" cy="22" r="2" fill="#111"/><path d="M42,25 L50,27 L42,29 Z" fill="#e08a2a" stroke="{INK}" stroke-width=".8"/>'
             f'<path d="M20,42 C14,38 14,48 22,48" fill="#e8c84a" stroke="{INK}" stroke-width="1"/>'
             f'<path d="M26,60 L26,63 M38,60 L38,63" stroke="#e08a2a" stroke-width="2.4" stroke-linecap="round"/>')

# ---------------------------------------------------------------- Halloween
svg("bat", f'<path d="M32,26 C28,20 22,16 4,18 C10,22 10,28 8,32 C14,28 18,32 20,36 C24,30 28,32 32,36 '
           f'C36,32 40,30 44,36 C46,32 50,28 56,32 C54,28 54,22 60,18 C42,16 36,20 32,26 Z" fill="#2a2030" stroke="{INK}" stroke-width="1.2" stroke-linejoin="round"/>'
           f'<circle cx="32" cy="27" r="5.5" fill="#2a2030" stroke="{INK}" stroke-width="1"/><path d="M28,23 L29,18 L31,22 M33,22 L35,18 L36,23" fill="#2a2030" stroke="{INK}" stroke-width="1"/>'
           f'<circle cx="30" cy="27" r="1.1" fill="#ffd257"/><circle cx="34" cy="27" r="1.1" fill="#ffd257"/>')
svg("jack_o_lantern", f'<g transform="translate(32,60) scale(2.3)">'
                      f'<ellipse cx="-7" cy="-11" rx="8" ry="11" fill="#c8601c" stroke="{INK}" stroke-width="0.9"/>'
                      f'<ellipse cx="7" cy="-11" rx="8" ry="11" fill="#c8601c" stroke="{INK}" stroke-width="0.9"/>'
                      f'<ellipse cx="0" cy="-11" rx="8" ry="11.5" fill="#e07a24" stroke="{INK}" stroke-width="0.9"/>'
                      f'<path d="M-7,-15 L-4,-11 L-10,-11 Z M7,-15 L10,-11 L4,-11 Z M-1,-10 L1,-10 L0,-8 Z" fill="#ffd257" stroke="{INK}" stroke-width="0.4"/>'
                      f'<path d="M-9,-6 L-6,-4 L-3,-6 L0,-4 L3,-6 L6,-4 L9,-6 L7,-2 L-7,-2 Z" fill="#ffd257" stroke="{INK}" stroke-width="0.4"/>'
                      f'<path d="M0,-21 C0,-24 2,-25 3.5,-25.5" stroke="#4d3a18" stroke-width="2.6" fill="none" stroke-linecap="round"/></g>')
svg("ghost", f'<path d="M14,58 L14,28 C14,14 22,6 32,6 C42,6 50,14 50,28 L50,58 L44,52 L38,58 L32,52 L26,58 L20,52 Z" '
             f'fill="#f4f6f8" stroke="{INK}" stroke-width="1.6" stroke-linejoin="round"/>'
             f'<ellipse cx="26" cy="26" rx="3" ry="4.5" fill="#1a1a1a"/><ellipse cx="38" cy="26" rx="3" ry="4.5" fill="#1a1a1a"/>'
             f'<ellipse cx="32" cy="38" rx="4" ry="5" fill="#1a1a1a"/>')
svg("candy_corn", f'<path d="M32,8 L48,56 C40,60 24,60 16,56 Z" fill="#f4f1e6" stroke="{INK}" stroke-width="1.4" stroke-linejoin="round"/>'
                  f'<path d="M21.5,40 L42.5,40 L48,56 C40,60 24,60 16,56 Z" fill="#ffd257"/>'
                  f'<path d="M27,24 L37,24 L42.5,40 L21.5,40 Z" fill="#e07a24"/>'
                  f'<path d="M32,8 L48,56 C40,60 24,60 16,56 Z" fill="none" stroke="{INK}" stroke-width="1.4" stroke-linejoin="round"/>')

# ---------------------------------------------------------------- Lunar New Year
# Lanterns and envelopes in a deep crimson with gold, darker than the alarm red the Bridge
# uses for danger, so they read as decoration.
for name, c in [("lantern", "#a8322c"), ("lantern_gold", "#d9a62a")]:
    # hangs from the top centre (32, 2) like a bulb
    svg(name, f'<path d="M32,0 L32,8" stroke="#2b2f27" stroke-width="2"/>'
              f'<rect x="24" y="7" width="16" height="5" rx="1.5" fill="#e0b62a" stroke="{INK}" stroke-width="1"/>'
              f'<ellipse cx="32" cy="30" rx="20" ry="18" fill="{c}" stroke="{INK}" stroke-width="1.4"/>'
              f'<path d="M32,12 C22,18 22,42 32,48 M32,12 C42,18 42,42 32,48 M14,30 L50,30" stroke="#e0b62a" stroke-width="1.3" fill="none" opacity=".8"/>'
              f'<rect x="24" y="47" width="16" height="5" rx="1.5" fill="#e0b62a" stroke="{INK}" stroke-width="1"/>'
              f'<path d="M28,52 L27,62 M32,52 L32,63 M36,52 L37,62" stroke="#e0b62a" stroke-width="1.8"/>'
              f'<ellipse cx="25" cy="24" rx="4" ry="7" fill="#fff" opacity=".18"/>')
svg("red_envelope", f'<rect x="14" y="8" width="36" height="52" rx="3" fill="#a8322c" stroke="{INK}" stroke-width="1.4"/>'
                    f'<path d="M14,22 C24,30 40,30 50,22" stroke="{INK}" stroke-width="1" fill="#8e2a25"/>'
                    f'<circle cx="32" cy="30" r="6" fill="#e0b62a" stroke="{INK}" stroke-width="1"/>'
                    f'<rect x="20" y="42" width="24" height="3" fill="#e0b62a"/><rect x="20" y="49" width="24" height="3" fill="#e0b62a"/>')
svg("mandarin", f'<circle cx="32" cy="38" r="20" fill="#e88a1f" stroke="{INK}" stroke-width="1.4"/>'
                f'<ellipse cx="24" cy="30" rx="4" ry="6" fill="#fff" opacity=".3"/>'
                f'<path d="M32,18 C30,12 34,10 34,10" stroke="#4d3a18" stroke-width="2.4" fill="none"/>'
                f'<path d="M34,14 C42,6 50,10 48,16 C44,14 38,14 34,14 Z" fill="#4d7f2f" stroke="{INK}" stroke-width="1"/>')
svg("plum_blossom", blossom("#f08bb4"))

print("holiday art written to", OUT)
