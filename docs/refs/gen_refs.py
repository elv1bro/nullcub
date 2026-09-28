#!/usr/bin/env python3
"""Vector reference sheets for the Ragdoll Master demo. Writes SVG + PNG into docs/refs/."""
import math, os, subprocess, sys

OUT = os.path.dirname(os.path.abspath(__file__))
os.makedirs(OUT, exist_ok=True)

FONT = "Helvetica Neue, Helvetica, Arial, sans-serif"
HEAD_FONT = "Impact, Arial Black, Helvetica, sans-serif"
INK = "#2b2118"
PAPER = "#f3efe6"
WOOD = "#d9a86c"
WOOD_D = "#a9713a"
OUTL = "#4a2e15"
JOINT = "#3b2a1a"
PLATE = "#f1d9c0"
P = {"P1": "#2f6fde", "P2": "#d9342b", "P3": "#2e9e4f", "P4": "#e8b820"}

# ---------- svg helpers ----------
def svg(w, h, body, bg=PAPER):
    bgrect = f'<rect width="{w}" height="{h}" fill="{bg}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}">{bgrect}{body}</svg>')

def text(x, y, s, size=28, anchor="start", color=INK, weight="bold", family=FONT, rot=0, op=1):
    tr = f' transform="rotate({rot} {x} {y})"' if rot else ""
    s = s.replace("&", "&amp;").replace("<", "&lt;")
    return (f'<text x="{x}" y="{y}" font-size="{size}" text-anchor="{anchor}" fill="{color}" '
            f'font-weight="{weight}" font-family="{family}" opacity="{op}"{tr}>{s}</text>')

def line(x1, y1, x2, y2, color=INK, w=2, cap="round", dash=None, op=1):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return (f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{color}" '
            f'stroke-width="{w}" stroke-linecap="{cap}" opacity="{op}"{d}/>')

def circle(cx, cy, r, fill, stroke=None, sw=0, op=1):
    st = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    return f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="{fill}" opacity="{op}"{st}/>'

def ellipse(cx, cy, rx, ry, fill, stroke=None, sw=0, rot=0, op=1):
    st = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    tr = f' transform="rotate({rot} {cx} {cy})"' if rot else ""
    return f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="{fill}" opacity="{op}"{st}{tr}/>'

def rect(x, y, w, h, fill, stroke=None, sw=0, rx=0, rot=0, op=1):
    st = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    tr = f' transform="rotate({rot} {x + w / 2} {y + h / 2})"' if rot else ""
    return f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{rx}" fill="{fill}" opacity="{op}"{st}{tr}/>'

def poly(pts, fill, stroke=None, sw=0, op=1, close=True):
    st = f' stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round"' if stroke else ""
    d = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    tag = "polygon" if close else "polyline"
    f = fill if close else "none"
    return f'<{tag} points="{d}" fill="{f}" opacity="{op}"{st}/>'

def path(d, fill="none", stroke=INK, sw=2, op=1):
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round" opacity="{op}"/>'

def grad(gid, stops, x1=0, y1=0, x2=0, y2=1):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return f'<defs><linearGradient id="{gid}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{s}</linearGradient></defs>'

def rgrad(gid, stops, cx=0.35, cy=0.3):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return f'<defs><radialGradient id="{gid}" cx="{cx}" cy="{cy}" r="0.75">{s}</radialGradient></defs>'

def title(w, s, sub=None):
    out = text(60, 80, s, 54, family=HEAD_FONT)
    if sub:
        out += text(60, 120, sub, 24, weight="normal", color="#6b5a4a")
    out += line(60, 140, w - 60, 140, "#c9b9a2", 3)
    return out

def dim_h(x1, x2, y, label, size=20):
    return (line(x1, y, x2, y, INK, 2) + line(x1, y - 8, x1, y + 8) + line(x2, y - 8, x2, y + 8)
            + text((x1 + x2) / 2, y - 10, label, size, "middle", weight="normal"))

def dim_v(x, y1, y2, label, size=20):
    return (line(x, y1, x, y2, INK, 2) + line(x - 8, y1, x + 8, y1) + line(x - 8, y2, x + 8, y2)
            + text(x + 12, (y1 + y2) / 2 + 7, label, size, "start", weight="normal"))

def dirv(a):
    r = math.radians(a)
    return math.sin(r), math.cos(r)  # angle from "down", positive toward +X

def capsule(x, y, a, L, w, fill=WOOD, outline=OUTL):
    dx, dy = dirv(a)
    x2, y2 = x + dx * L, y + dy * L
    return (line(x, y, x2, y2, outline, w + 5) + line(x, y, x2, y2, fill, w)
            + line(x + (-dy) * w * 0.22, y + dx * w * 0.22, x2 + (-dy) * w * 0.22, y2 + dx * w * 0.22, "#ffffff", w * 0.18, op=0.35)), (x2, y2)

def joint(x, y, r):
    return circle(x, y, r + 2, OUTL) + circle(x, y, r, JOINT) + circle(x - r * 0.3, y - r * 0.3, r * 0.3, "#8a6a4a", op=0.8)

# ---------- doll ----------
M = dict(head_r=0.225, torso_h=0.50, torso_w=0.36, torso_d=0.22, ua=0.32, la=0.30, ul=0.42, ll=0.40,
         foot=0.26, foot_h=0.09, arm_w=0.11, leg_w=0.14, jr=0.05, neck=0.03)
ROOT_H = M["ul"] + M["ll"] + M["foot_h"]  # hip height when standing

def doll(cx, ground, s, view="front", pose=None, shirt=None, face=True, joints=True, root=None, label_parts=False):
    p = dict(torso=0, head=0, ua_l=-8, la_l=-8, ua_r=8, la_r=8, ul_l=-4, ll_l=-4, ul_r=4, ll_r=4)
    if pose:
        p.update(pose)
    rx, ry = root if root else (cx, ground - ROOT_H * s)
    out = []
    jr = M["jr"] * s
    arm_w, leg_w = M["arm_w"] * s, M["leg_w"] * s
    # torso frame
    ux, uy = dirv(180 + p["torso"])
    top = (rx + ux * M["torso_h"] * s, ry + uy * M["torso_h"] * s)
    px, py = -uy, ux  # perpendicular (toward +X when upright)
    if view == "side":
        tw = M["torso_d"] * s
        sh = [(top[0] - px * 0.02 * s, top[1] - py * 0.02 * s)] * 2
        hp = [(rx, ry)] * 2
    elif view == "quarter":
        tw = M["torso_w"] * s * 0.78
        sh = [(top[0] - px * 0.12 * s, top[1] - py * 0.12 * s), (top[0] + px * 0.16 * s, top[1] + py * 0.16 * s)]
        hp = [(rx - px * 0.07 * s, ry - py * 0.07 * s), (rx + px * 0.11 * s, ry + py * 0.11 * s)]
    else:
        tw = M["torso_w"] * s
        sh = [(top[0] - px * 0.18 * s, top[1] - py * 0.18 * s), (top[0] + px * 0.18 * s, top[1] + py * 0.18 * s)]
        hp = [(rx - px * 0.10 * s, ry - py * 0.10 * s), (rx + px * 0.10 * s, ry + py * 0.10 * s)]
    neck = (top[0] + ux * M["neck"] * s, top[1] + uy * M["neck"] * s)
    hx, hy = dirv(180 + p["torso"] + p["head"])
    hc = (neck[0] + hx * M["head_r"] * s, neck[1] + hy * M["head_r"] * s)
    ends = {}

    def limb(name, start, a1, L1, a2, L2, w, foot=False):
        seg, e1 = capsule(start[0], start[1], a1, L1 * s, w)
        seg2, e2 = capsule(e1[0], e1[1], a2, L2 * s, w)
        o = seg + seg2
        if foot:
            if view == "side":
                fs, fe = capsule(e2[0], e2[1] + M["foot_h"] * s * 0.3, 90, M["foot"] * s * 0.85, M["foot_h"] * s)
                o += fs
            else:
                o += rect(e2[0] - M["foot"] * s * 0.32, e2[1], M["foot"] * s * 0.64, M["foot_h"] * s, WOOD_D, OUTL, 3, 6)
        if joints:
            o += joint(start[0], start[1], jr) + joint(e1[0], e1[1], jr * 0.9) + joint(e2[0], e2[1], jr * 0.8)
        ends[name] = (start, e1, e2)
        return o

    legs = limb("leg_l", hp[0], p["ul_l"], M["ul"], p["ll_l"], M["ll"], leg_w, True) + \
           limb("leg_r", hp[1], p["ul_r"], M["ul"], p["ll_r"], M["ll"], leg_w, True)
    arms = limb("arm_l", sh[0], p["ua_l"], M["ua"], p["la_l"], M["la"], arm_w) + \
           limb("arm_r", sh[1], p["ua_r"], M["ua"], p["la_r"], M["la"], arm_w)
    # torso block
    ang = -p["torso"]
    tcx, tcy = (rx + top[0]) / 2, (ry + top[1]) / 2
    fill = shirt if shirt else WOOD
    torso = (f'<g transform="rotate({ang} {tcx:.1f} {tcy:.1f})">'
             + rect(tcx - tw / 2, tcy - M["torso_h"] * s / 2, tw, M["torso_h"] * s, fill, OUTL, 4, tw * 0.22)
             + (rect(tcx - tw / 2, tcy - M["torso_h"] * s / 2 - 2, tw, M["torso_h"] * s * 0.12, WOOD, OUTL, 3, tw * 0.15) if shirt else "")
             + "</g>")
    head = circle(hc[0], hc[1], M["head_r"] * s + 2, OUTL) + circle(hc[0], hc[1], M["head_r"] * s, WOOD) \
           + circle(hc[0] - M["head_r"] * s * 0.35, hc[1] - M["head_r"] * s * 0.35, M["head_r"] * s * 0.25, "#fff", op=0.25)
    if face and view != "back":
        hr = M["head_r"] * s
        if view == "front":
            head += ellipse(hc[0], hc[1] + hr * 0.05, hr * 0.72, hr * 0.8, PLATE, "#8a5a3a", 4)
            head += circle(hc[0] - hr * 0.28, hc[1] - hr * 0.1, hr * 0.07, INK) + circle(hc[0] + hr * 0.28, hc[1] - hr * 0.1, hr * 0.07, INK)
            head += path(f"M{hc[0] - hr * 0.3:.1f},{hc[1] + hr * 0.32:.1f} Q{hc[0]:.1f},{hc[1] + hr * 0.6:.1f} {hc[0] + hr * 0.3:.1f},{hc[1] + hr * 0.32:.1f}", sw=4)
        elif view == "quarter":
            head += ellipse(hc[0] + hr * 0.3, hc[1] + hr * 0.05, hr * 0.55, hr * 0.8, PLATE, "#8a5a3a", 4)
            head += circle(hc[0] + hr * 0.1, hc[1] - hr * 0.1, hr * 0.07, INK) + circle(hc[0] + hr * 0.55, hc[1] - hr * 0.1, hr * 0.06, INK)
        else:  # side: plate as a lens bump toward +X (rotated with head)
            fx, fy = dirv(90 + p["torso"] + p["head"])
            head += ellipse(hc[0] + fx * hr * 0.82, hc[1] + fy * hr * 0.82, hr * 0.2, hr * 0.78, PLATE, "#8a5a3a", 4, rot=-(p["torso"] + p["head"]))
    if joints:
        head += joint(neck[0], neck[1], jr * 0.9)
    if view == "side":
        # far limbs drawn first, slightly darker
        out = [f'<g opacity="0.75">{legs}{arms}</g>', torso, legs, arms, head]
        out = [f'<g opacity="0.75">' + limb("leg_r", hp[1], p["ul_r"], M["ul"], p["ll_r"], M["ll"], leg_w, True)
               + limb("arm_r", sh[1], p["ua_r"], M["ua"], p["la_r"], M["la"], arm_w) + "</g>",
               torso,
               limb("leg_l", hp[0], p["ul_l"], M["ul"], p["ll_l"], M["ll"], leg_w, True),
               limb("arm_l", sh[0], p["ua_l"], M["ua"], p["la_l"], M["la"], arm_w), head]
    else:
        out = [legs, torso, arms, head]
    return "".join(out), dict(root=(rx, ry), top=top, neck=neck, head=hc, sh=sh, hp=hp, ends=ends)

# ---------- sheets ----------
def r01():
    W, H = 1920, 1080
    b = title(W, "R1  WOODEN RAGDOLL — CHARACTER SHEET", "T-поза, 12 частей, шарниры-шарики. Рост 1.80 м, голова Ø0.45 м. Масштаб одинаковый на всех видах.")
    s = 380
    ground = 900
    b += line(120, ground, 1400, ground, "#9c8a72", 3)
    views = [("front", "FRONT", dict(ua_l=-90, la_l=-90, ua_r=90, la_r=90, ul_l=-6, ul_r=6, ll_l=-6, ll_r=6)),
             ("side", "SIDE", dict(ua_l=6, la_l=10, ua_r=2, la_r=6)),
             ("back", "BACK", dict(ua_l=-90, la_l=-90, ua_r=90, la_r=90, ul_l=-6, ul_r=6, ll_l=-6, ll_r=6)),
             ("quarter", "3/4 (схематично)", dict(ua_l=-70, la_l=-70, ua_r=55, la_r=55, ul_l=-5, ul_r=5))]
    xs = [330, 640, 950, 1220]
    for (v, lab, pose), x in zip(views, xs):
        d, g = doll(x, ground, s, v, pose)
        b += d + text(x, ground + 40, lab, 26, "middle")
    # dimensions on front view
    d, g = doll(xs[0], ground, s, "front", views[0][2])
    top_y = g["head"][1] - M["head_r"] * s
    b += dim_v(150, top_y, ground, "1.80 m")
    b += dim_h(g["head"][0] - M["head_r"] * s, g["head"][0] + M["head_r"] * s, top_y - 18, "Ø0.45")
    # parts legend
    x0, y0 = 1540, 190
    b += text(x0, y0, "12 ЧАСТЕЙ (имена узлов glb)", 24)
    parts = ["Head", "Torso", "UpperArm_L / R", "LowerArm_L / R", "UpperLeg_L / R", "LowerLeg_L / R", "Foot_L / R", "FacePlate (плашка на голове)"]
    for i, pn in enumerate(parts):
        b += text(x0, y0 + 36 + i * 30, f"• {pn}", 21, weight="normal")
    y1 = y0 + 36 + len(parts) * 30 + 20
    b += text(x0, y1, "РАЗМЕРЫ (м)", 24)
    dims = [("голова Ø", 0.45), ("торс В×Ш×Г", "0.50×0.36×0.22"), ("плечо", 0.32), ("предплечье", 0.30), ("бедро", 0.42), ("голень", 0.40), ("стопа Д×В", "0.26×0.09"), ("толщина руки / ноги", "0.11 / 0.14"), ("шарнир Ø", 0.10)]
    for i, (k, vv) in enumerate(dims):
        b += text(x0, y1 + 36 + i * 28, f"{k}: {vv}", 20, weight="normal")
    y2 = y1 + 36 + len(dims) * 28 + 20
    b += text(x0, y2, "ШАРНИРЫ (Z-ось, лимиты °)", 24)
    lims = ["шея ±40", "плечо −90…170", "локоть 0…140", "бедро −30…120", "колено 0…140", "лодыжка ±25"]
    for i, l in enumerate(lims):
        b += text(x0, y2 + 36 + i * 28, f"• {l}", 20, weight="normal")
    b += text(60, H - 40, "Pivot каждой части — в суставе, который крепит её к родителю. Смотрит в +X. Ось Y вверх.", 20, weight="normal", color="#6b5a4a")
    return svg(W, H, b)

def head_study(cx, cy, hr, mode, variant):
    """mode: front|quarter|side. variant a: flat plate, b: wrapped cap."""
    o = circle(cx, cy, hr + 3, OUTL) + circle(cx, cy, hr, WOOD)
    o += circle(cx - hr * 0.35, cy - hr * 0.35, hr * 0.22, "#fff", op=0.25)
    rim = "#7a4a22"
    if variant == "a":
        if mode == "front":
            o += ellipse(cx, cy + hr * 0.05, hr * 0.74, hr * 0.82, rim) + ellipse(cx, cy + hr * 0.05, hr * 0.66, hr * 0.74, PLATE)
        elif mode == "quarter":
            o += ellipse(cx + hr * 0.3, cy + hr * 0.05, hr * 0.56, hr * 0.82, rim) + ellipse(cx + hr * 0.3, cy + hr * 0.05, hr * 0.49, hr * 0.74, PLATE)
        else:
            o += ellipse(cx + hr * 0.86, cy + hr * 0.05, hr * 0.22, hr * 0.82, rim) + ellipse(cx + hr * 0.86, cy + hr * 0.05, hr * 0.15, hr * 0.74, PLATE)
    else:
        if mode == "front":
            o += circle(cx, cy, hr * 0.9, rim) + circle(cx, cy, hr * 0.82, PLATE)
        elif mode == "quarter":
            o += path(f"M{cx - hr * 0.35:.1f},{cy - hr * 0.86:.1f} A{hr * 0.9:.1f},{hr * 0.9:.1f} 0 0 1 {cx - hr * 0.35:.1f},{cy + hr * 0.86:.1f} A{hr * 0.5:.1f},{hr * 0.9:.1f} 0 0 0 {cx - hr * 0.35:.1f},{cy - hr * 0.86:.1f} Z", PLATE, rim, 5)
        else:
            o += path(f"M{cx:.1f},{cy - hr * 0.95:.1f} A{hr * 0.95:.1f},{hr * 0.95:.1f} 0 0 1 {cx:.1f},{cy + hr * 0.95:.1f} L{cx:.1f},{cy - hr * 0.95:.1f} Z", PLATE, rim, 5)
    if mode != "side":
        ex = cx + (hr * 0.3 if mode == "quarter" else 0)
        o += circle(ex - hr * 0.26, cy - hr * 0.12, hr * 0.06, INK) + circle(ex + hr * 0.26, cy - hr * 0.12, hr * 0.06, INK)
        o += path(f"M{ex - hr * 0.28:.1f},{cy + hr * 0.3:.1f} Q{ex:.1f},{cy + hr * 0.58:.1f} {ex + hr * 0.28:.1f},{cy + hr * 0.3:.1f}", sw=4)
    o += joint(cx, cy + hr + 14, 16)
    return o

def r02():
    W, H = 1920, 1080
    b = title(W, "R2  HEAD & FACE PLATE", "Как фото лица сидит на деревянной голове. Вариант a: плоская плашка на шаре. Вариант b: лицо вписано в шар (сферическая крышка).")
    hr = 150
    for row, (var, name, desc) in enumerate([("a", "ВАРИАНТ a — плашка", "выпуклая плашка Ø0.36 м, обод 0.02 м прячет край фото, глубина 0.03 м"),
                                            ("b", "ВАРИАНТ b — вписанное", "передняя полусфера под фото, обод по экватору, UV-проекция сложнее")]):
        y = 330 + row * 450
        b += text(80, y - 190, name, 30) + text(80, y - 158, desc, 20, weight="normal", color="#6b5a4a")
        for col, (mode, lab) in enumerate([("front", "FRONT"), ("quarter", "3/4"), ("side", "PROFILE")]):
            x = 380 + col * 420
            b += head_study(x, y, hr, mode, var) + text(x, y + 215, lab, 22, "middle")
        # rim callout on side
        x = 380 + 2 * 420
        b += line(x + hr * 1.05, y - hr * 0.5, x + hr * 1.6, y - hr * 1.1, INK, 2) + text(x + hr * 1.65, y - hr * 1.15, "обод", 20, weight="normal")
    b += rect(1620, 200, 250, 640, "#fff", "#c9b9a2", 3, 12)
    b += text(1645, 240, "ФОТО → ПЛАШКА", 22)
    for i, s in enumerate(["1. кроп лица 512×512", "2. овальная маска", "3. виньетка по краю", "4. текстура FacePlate", "5. обод скрывает шов", "", "Мимика без вебки:", "4 слоя поверх фото", "(нейтрально / удар /", " победа / KO)"]):
        b += text(1645, 280 + i * 30, s, 19, weight="normal")
    return svg(W, H, b)

def r03():
    W, H = 1920, 1080
    b = title(W, "R3  PLAYER COLORS P1–P4", "Одна и та же кукла, меняется только материал Shirt. Цвета должны различаться на расстоянии камеры боя.")
    s = 380
    ground = 920
    b += line(100, ground, W - 100, ground, "#9c8a72", 3)
    for i, (pid, col) in enumerate(P.items()):
        x = 330 + i * 420
        d, g = doll(x, ground, s, "front", dict(ua_l=-20, la_l=-30, ua_r=20, la_r=30), shirt=col)
        b += d
        b += rect(x - 40, 170, 80, 44, col, OUTL, 3, 10) + text(x, 202, pid, 28, "middle", "#fff")
        b += text(x, ground + 44, col, 22, "middle", weight="normal")
    return svg(W, H, b)

def hat(kind, cx, top, hr, view):
    """draw a hat sitting on head whose top point is (cx, top); hr = head radius."""
    w = hr * 1.25
    o = ""
    if kind == "crown":
        pts = [(cx - w * 0.75, top + 6), (cx - w * 0.75, top - w * 0.55), (cx - w * 0.38, top - w * 0.2), (cx, top - w * 0.7), (cx + w * 0.38, top - w * 0.2), (cx + w * 0.75, top - w * 0.55), (cx + w * 0.75, top + 6)]
        o += poly(pts, "#e8b820", OUTL, 4) + circle(cx, top - w * 0.7, 7, "#d9342b")
    elif kind == "cowboy":
        o += ellipse(cx, top + 4, w * 1.35, w * 0.28, "#8b5a2b", OUTL, 4)
        o += path(f"M{cx - w * 0.6:.1f},{top + 4:.1f} Q{cx - w * 0.62:.1f},{top - w * 0.75:.1f} {cx:.1f},{top - w * 0.8:.1f} Q{cx + w * 0.62:.1f},{top - w * 0.75:.1f} {cx + w * 0.6:.1f},{top + 4:.1f} Z", "#a9713a", OUTL, 4)
        o += rect(cx - w * 0.6, top - w * 0.25, w * 1.2, w * 0.14, "#4a2e15")
    elif kind == "helmet":
        o += path(f"M{cx - w * 0.95:.1f},{top + w * 0.5:.1f} L{cx - w * 0.95:.1f},{top - w * 0.1:.1f} A{w * 0.95:.1f},{w * 0.95:.1f} 0 0 1 {cx + w * 0.95:.1f},{top - w * 0.1:.1f} L{cx + w * 0.95:.1f},{top + w * 0.5:.1f} Z", "#9aa3ad", OUTL, 4)
        o += rect(cx - w * 0.7, top + w * 0.12, w * 1.4, w * 0.1, "#2b2118")
        o += rect(cx - w * 0.06, top - w * 1.0, w * 0.12, w * 0.9, "#d9342b", OUTL, 3, 4)
    elif kind == "viking":
        o += path(f"M{cx - w * 0.9:.1f},{top + w * 0.25:.1f} A{w * 0.9:.1f},{w * 0.9:.1f} 0 0 1 {cx + w * 0.9:.1f},{top + w * 0.25:.1f} Z", "#8f9aa5", OUTL, 4)
        o += rect(cx - w * 0.9, top + w * 0.2, w * 1.8, w * 0.14, "#6b5a4a", OUTL, 3)
        for sgn in (-1, 1):
            o += path(f"M{cx + sgn * w * 0.75:.1f},{top + w * 0.2:.1f} Q{cx + sgn * w * 1.35:.1f},{top - w * 0.1:.1f} {cx + sgn * w * 1.2:.1f},{top - w * 0.9:.1f} Q{cx + sgn * w * 1.0:.1f},{top - w * 0.2:.1f} {cx + sgn * w * 0.55:.1f},{top - w * 0.05:.1f} Z", "#f1e6cf", OUTL, 4)
    elif kind == "chicken":
        o += ellipse(cx, top - w * 0.2, w * 0.9, w * 0.45, "#f2c200", OUTL, 4)
        o += circle(cx + w * 0.7, top - w * 0.5, w * 0.3, "#f2c200", OUTL, 4)
        o += poly([(cx + w * 0.95, top - w * 0.5), (cx + w * 1.3, top - w * 0.42), (cx + w * 0.95, top - w * 0.36)], "#f28c28", OUTL, 3)
        o += path(f"M{cx + w * 0.55:.1f},{top - w * 0.8:.1f} q10,-20 20,0 q10,-20 20,0 q10,-20 20,0", "#d9342b", OUTL, 3)
        o += circle(cx + w * 0.78, top - w * 0.56, 4, INK)
    elif kind == "pot":
        o += rect(cx - w * 0.8, top - w * 0.55, w * 1.6, w * 0.7, "#4b5563", OUTL, 4, 8)
        o += rect(cx - w * 0.85, top - w * 0.62, w * 1.7, w * 0.12, "#6b7280", OUTL, 3, 4)
        for sgn in (-1, 1):
            o += rect(cx + sgn * w * 0.8 - (w * 0.12 if sgn < 0 else 0), top - w * 0.3, w * 0.12, w * 0.3, "#374151", OUTL, 3, 4)
    elif kind == "cap":
        o += path(f"M{cx - w * 0.85:.1f},{top + w * 0.1:.1f} A{w * 0.85:.1f},{w * 0.85:.1f} 0 0 1 {cx + w * 0.85:.1f},{top + w * 0.1:.1f} Z", "#2f6fde", OUTL, 4)
        o += path(f"M{cx + w * 0.4:.1f},{top + w * 0.1:.1f} Q{cx + w * 1.4:.1f},{top + w * 0.05:.1f} {cx + w * 1.45:.1f},{top + w * 0.3:.1f} L{cx + w * 0.4:.1f},{top + w * 0.3:.1f} Z", "#1e4fa8", OUTL, 4)
        o += circle(cx, top - w * 0.85, 6, INK)
    elif kind == "bucket":
        o += poly([(cx - w * 0.9, top - w * 0.9), (cx + w * 0.9, top - w * 0.9), (cx + w * 0.75, top + w * 0.35), (cx - w * 0.75, top + w * 0.35)], "#8f9aa5", OUTL, 4)
        o += rect(cx - w * 0.95, top - w * 0.98, w * 1.9, w * 0.12, "#6b7280", OUTL, 3, 4)
        o += path(f"M{cx - w * 0.9:.1f},{top - w * 0.9:.1f} Q{cx:.1f},{top - w * 1.6:.1f} {cx + w * 0.9:.1f},{top - w * 0.9:.1f}", stroke="#374151", sw=6)
    return o

def r04():
    W, H = 1920, 1080
    b = title(W, "R4  HATS ×8", "Каждая шляпа на голове куклы (профиль и 3/4). Pivot = точка посадки на макушку (красный крест). Масса задаётся в Godot.")
    hats = [("crown", "Корона", 0.3), ("cowboy", "Ковбойская", 0.5), ("helmet", "Шлем рыцаря", 1.5), ("viking", "Викинг", 1.5),
            ("chicken", "Курица", 0.4), ("pot", "Кастрюля", 2.0), ("cap", "Кепка", 0.3), ("bucket", "Ведро", 1.2)]
    hr = 62
    for i, (k, name, mass) in enumerate(hats):
        col, row = i % 4, i // 4
        x0, y0 = 90 + col * 455, 190 + row * 430
        b += rect(x0, y0, 420, 400, "#fff", "#c9b9a2", 3, 14)
        for j, mode in enumerate(["side", "quarter"]):
            cx, cy = x0 + 120 + j * 190, y0 + 250
            b += head_study(cx, cy, hr, mode, "a")
            b += hat(k, cx, cy - hr, hr, mode)
            b += line(cx - 12, cy - hr, cx + 12, cy - hr, "#d9342b", 3) + line(cx, cy - hr - 12, cx, cy - hr + 12, "#d9342b", 3)
        b += text(x0 + 20, y0 + 40, name, 26) + text(x0 + 20, y0 + 72, f"масса ≈ {mass} кг", 20, weight="normal", color="#6b5a4a")
        b += text(x0 + 120, y0 + 370, "профиль", 18, "middle", weight="normal") + text(x0 + 310, y0 + 370, "3/4", 18, "middle", weight="normal")
    return svg(W, H, b)

def weapon(kind, x, y, s):
    """side view, grip at (x,y), extends along +X. s = px per metre. returns svg, length_m"""
    o = ""
    if kind == "hammer":
        L = 1.1
        o += rect(x - 0.15 * s, y - 0.035 * s, L * s, 0.07 * s, WOOD_D, OUTL, 4, 8)
        o += rect(x + (L - 0.15 - 0.12) * s, y - 0.22 * s, 0.24 * s, 0.44 * s, "#8f9aa5", OUTL, 4, 10)
        o += rect(x + (L - 0.15 - 0.12) * s, y - 0.22 * s, 0.24 * s, 0.05 * s, "#c7ced6")
    elif kind == "mace":
        L = 1.2
        o += rect(x - 0.12 * s, y - 0.03 * s, 0.55 * s, 0.06 * s, WOOD_D, OUTL, 4, 8)
        cx = x + 0.43 * s
        for i in range(4):
            o += ellipse(cx + i * 0.12 * s, y, 0.075 * s, 0.045 * s, "none", "#4b5563", 7)
        bx = cx + 4 * 0.12 * s + 0.1 * s
        for k in range(8):
            a = k * math.pi / 4
            o += line(bx, y, bx + math.cos(a) * 0.19 * s, y + math.sin(a) * 0.19 * s, "#6b7280", 8)
        o += circle(bx, y, 0.13 * s, "#8f9aa5", OUTL, 4)
    elif kind == "plank":
        L = 0.9
        o += rect(x - 0.1 * s, y - 0.05 * s, L * s, 0.1 * s, WOOD, OUTL, 4, 4)
        o += line(x + 0.1 * s, y - 0.045 * s, x + (L - 0.15) * s, y - 0.045 * s, WOOD_D, 3)
        o += line(x + (L - 0.2) * s, y - 0.05 * s, x + (L - 0.2) * s, y - 0.2 * s, "#6b7280", 6) + circle(x + (L - 0.2) * s, y - 0.2 * s, 6, "#6b7280")
    elif kind == "pan":
        L = 0.7
        o += rect(x - 0.1 * s, y - 0.03 * s, 0.4 * s, 0.06 * s, "#2b2118", OUTL, 4, 8)
        o += ellipse(x + 0.5 * s, y, 0.22 * s, 0.11 * s, "#4b5563", OUTL, 4)
        o += ellipse(x + 0.5 * s, y - 0.02 * s, 0.17 * s, 0.07 * s, "#6b7280")
    elif kind == "torch":
        L = 0.6
        o += rect(x - 0.1 * s, y - 0.03 * s, 0.45 * s, 0.06 * s, WOOD_D, OUTL, 4, 8)
        o += rect(x + 0.3 * s, y - 0.05 * s, 0.1 * s, 0.1 * s, "#6b5a4a", OUTL, 3, 4)
        o += path(f"M{x + 0.4 * s:.1f},{y - 0.05 * s:.1f} q{0.12 * s},{-0.12 * s} {0.2 * s},0 q{0.02 * s},{0.06 * s} {-0.2 * s},{0.1 * s} Z", "#f28c28", "#d9342b", 4)
        o += path(f"M{x + 0.42 * s:.1f},{y - 0.02 * s:.1f} q{0.06 * s},{-0.06 * s} {0.11 * s},0 q{0.01 * s},{0.03 * s} {-0.11 * s},{0.05 * s} Z", "#f2c200")
    return o, L

def hand(x, y, s):
    o = circle(x, y, 0.06 * s, WOOD, OUTL, 4)
    for a in (-40, 0, 40):
        dx, dy = dirv(a)
        o += line(x, y, x + dx * 0.07 * s, y + dy * 0.07 * s, OUTL, 6) + line(x, y, x + dx * 0.07 * s, y + dy * 0.07 * s, WOOD, 3)
    return o

def r05():
    W, H = 1920, 1080
    b = title(W, "R5  WEAPONS ×5", "Вид сбоку, один масштаб (1 м = 300 px). Красный крест — точка хвата (pivot glb). Рука куклы показана для масштаба.")
    s = 300
    items = [("hammer", "Молот двуручный", "6 кг · урон ×2.2 · медленный"), ("mace", "Булава на цепи", "3 кг + 4 звена · верёвочный сустав"),
             ("plank", "Доска с гвоздём", "1.5 кг · ×1.3 · быстрая"), ("pan", "Сковородка", "2 кг · ×1.6 · звонкая"), ("torch", "Факел", "1 кг · ×1.0 · поджиг 3 с")]
    for i, (k, name, spec) in enumerate(items):
        y = 250 + i * 160
        x = 260
        o, L = weapon(k, x, y, s)
        b += hand(x, y, s) + o
        b += line(x - 14, y, x + 14, y, "#d9342b", 3) + line(x, y - 14, x, y + 14, "#d9342b", 3)
        b += text(760 if k != "mace" else 760, y + 8, name, 26) + text(1060, y + 8, spec, 20, weight="normal", color="#6b5a4a")
        b += text(1500, y + 8, f"длина {L:.2f} м", 20, weight="normal")
    b += dim_h(260, 260 + s, 1040, "1 м") + line(260, 990, 260 + s, 990, "#c9b9a2", 1)
    return svg(W, H, b)

# ---------- arena ----------
def arena(mode):
    W, H = 2520, 1080
    s = 92.0
    ox, oy = 60, 1000  # world origin (0,0) at px; y up

    def X(m): return ox + m * s
    def Y(m): return oy - m * s
    col = mode == "concept"
    b = ""
    if col:
        b += grad("sky", [(0, "#8fc3e6"), (0.6, "#dbe8ef"), (1, "#f5e7c8")]) + rect(0, 0, W, H, "url(#sky)")
        # sea
        b += grad("sea", [(0, "#4c8fb8"), (1, "#245a82")]) + rect(0, Y(4.3), W, 1080 - Y(4.3), "url(#sea)")
        for i in range(20):
            b += line(80 + i * 130, Y(4.0) + (i % 3) * 30, 150 + i * 130, Y(4.0) + (i % 3) * 30, "#dbe8ef", 3, op=0.5)
        # far ruins
        for i, (xm, wm, hm) in enumerate([(1, 1.2, 2.2), (2.6, 0.8, 3.0), (5, 2.0, 1.6), (14, 1.0, 2.6), (16, 2.5, 1.2), (21, 1.2, 2.0)]):
            b += rect(X(xm), Y(4.3 + hm), wm * s, hm * s, "#8a9bb0", op=0.55)
        # ship
        b += path(f"M{X(1.2):.0f},{Y(4.5):.0f} L{X(3.2):.0f},{Y(4.5):.0f} L{X(2.9):.0f},{Y(4.15):.0f} L{X(1.5):.0f},{Y(4.15):.0f} Z", "#3b2a1a") + line(X(2.2), Y(4.5), X(2.2), Y(5.6), "#3b2a1a", 5) + poly([(X(2.25), Y(5.55)), (X(2.95), Y(4.7)), (X(2.25), Y(4.7))], "#f1e6cf")
        # blimp
        b += ellipse(X(19.5), Y(9.6), 1.4 * s, 0.45 * s, "#e9dfc9", OUTL, 3) + rect(X(19.2), Y(9.1), 0.6 * s, 0.2 * s, "#6b5a4a") + text(X(19.5), Y(9.55), "RAGDOLL MASTER", 22, "middle", "#8b5a2b")
        # cliff under platforms
        b += poly([(X(4), Y(1)), (X(4.4), Y(-0.5)), (X(13.2), Y(-0.5)), (X(13), Y(1))], "#7a6a58") + poly([(X(15), Y(1)), (X(15.1), Y(-0.5)), (X(26), Y(-0.5)), (X(26), Y(1))], "#7a6a58")
        b += poly([(X(4), Y(1)), (X(2.5), Y(-0.5)), (X(4.4), Y(-0.5))], "#5f5044")
    else:
        b += rect(0, 0, W, H, "#ffffff")
        for m in range(0, 27):
            b += line(X(m), Y(0) + 40, X(m), Y(10.5), "#e5e7eb", 1) + (text(X(m), Y(0) + 62, str(m), 16, "middle", "#9ca3af", "normal") if m % 2 == 0 else "")
        for m in range(0, 11):
            b += line(X(0), Y(m), X(26), Y(m), "#e5e7eb", 1) + text(X(0) - 10, Y(m) + 6, str(m), 16, "end", "#9ca3af", "normal")
    stone = "#b8ab96" if col else "#f28c28"
    stone_d = "#8f836f" if col else "#f28c28"
    wood = WOOD if col else "#f28c28"
    deco = "#9a8b76" if col else "#bfbfbf"
    destr = None if col else "#3b82f6"
    outl = OUTL if col else "#111"

    def platform(x0, x1, y0, y1, kind="stone"):
        f = stone if kind == "stone" else wood
        o = rect(X(x0), Y(y1), (x1 - x0) * s, (y1 - y0) * s, f, outl, 4, 6)
        if col and kind == "stone":
            for k in range(int((x1 - x0) * 2)):
                o += line(X(x0 + k * 0.5 + 0.25), Y(y1) + 4, X(x0 + k * 0.5 + 0.25), Y(y0) - 4, stone_d, 2, op=0.5)
        if col and kind == "wood":
            for k in range(int((x1 - x0) * 3)):
                o += line(X(x0 + k / 3), Y(y1) + 3, X(x0 + k / 3), Y(y0) - 3, WOOD_D, 2, op=0.6)
        return o

    # tier 0
    b += platform(4, 13, 0, 1) + platform(15, 26, 0, 1)
    # rope bridge over 13-15 (walkable, static)
    if col:
        b += path(f"M{X(13):.0f},{Y(1):.0f} Q{X(14):.0f},{Y(0.7):.0f} {X(15):.0f},{Y(1):.0f}", stroke="#5a3a1e", sw=6)
        for k in range(1, 8):
            xm = 13 + k * 0.25
            ym = 1 - 0.3 * (1 - ((xm - 14) / 1) ** 2)
            b += rect(X(xm) - 10, Y(ym) - 4, 20, 8, WOOD, OUTL, 2)
    else:
        b += path(f"M{X(13):.0f},{Y(1):.0f} Q{X(14):.0f},{Y(0.7):.0f} {X(15):.0f},{Y(1):.0f}", stroke="#f28c28", sw=10)
    # tier 1
    b += platform(6, 10, 2.9, 3.2, "wood") + platform(16, 20, 2.9, 3.4)
    # supports
    if col:
        for xm in (6.3, 9.7):
            b += line(X(xm), Y(2.9), X(xm - 0.6), Y(1), WOOD_D, 8)
        for xm in (16.5, 19.5):
            b += rect(X(xm) - 12, Y(2.9), 24, 1.9 * s, stone_d, outl, 3)
    # tier 2
    b += platform(9, 14, 5.4, 5.8) + platform(19, 22, 5.4, 5.7, "wood")
    if col:
        # stone wall with two arched openings under tier 2 (decor, no collision: ground stays passable)
        b += rect(X(9.2), Y(5.4), 4.6 * s, 4.4 * s, stone_d, outl, 3)
        for k in range(4):
            b += line(X(9.2), Y(2.0 + k), X(13.8), Y(2.0 + k), "#6f6455", 2, op=0.5)
        for (x0m, x1m) in ((9.6, 11.0), (12.0, 13.4)):
            r = (x1m - x0m) / 2 * s
            b += path(f"M{X(x0m):.0f},{Y(1):.0f} L{X(x0m):.0f},{Y(3.4):.0f} A{r:.0f},{r:.0f} 0 0 1 {X(x1m):.0f},{Y(3.4):.0f} L{X(x1m):.0f},{Y(1):.0f} Z", "#c9dfe9", outl, 3)
        for xm in (19.4, 21.6):
            b += line(X(xm), Y(5.4), X(xm), Y(3.4 if xm < 20.5 else 1), WOOD_D, 8)
    # collapsed tower right (x 22-26)
    tower = [(X(22.5), Y(1)), (X(22.5), Y(7.2)), (X(23.3), Y(7.6)), (X(23.8), Y(6.9)), (X(24.6), Y(8.3)), (X(25.4), Y(7.4)), (X(26), Y(7.8)), (X(26), Y(1))]
    b += poly(tower, stone, outl, 4)
    if col:
        for k in range(6):
            b += line(X(22.5), Y(1.8 + k), X(26), Y(1.8 + k), stone_d, 2, op=0.5)
        b += rect(X(23.3), Y(4.2), 0.9 * s, 1.4 * s, "#3b2a1a", outl, 3, 30)
    # walkable ledge on tower
    b += platform(22.5, 24, 6.7, 7.0)
    # left pit marker
    if col:
        b += text(X(2), Y(0.5), "ПРОПАСТЬ", 30, "middle", "#e9dfc9", family=HEAD_FONT, op=0.9)
        b += text(X(2), Y(0.1), "падение = KO", 20, "middle", "#e9dfc9", "normal")
    else:
        b += rect(X(0), Y(-0.5), 26 * s, 0.5 * s, "#ef4444", op=0.35) + text(X(13), Y(-0.75), "DEATH ZONE y < −0.5", 22, "middle", "#b91c1c")
        b += line(X(0), Y(-0.5), X(0), Y(10.5), "#111", 5, dash="14,10") + line(X(26), Y(-0.5), X(26), Y(10.5), "#111", 5, dash="14,10") + line(X(0), Y(10.5), X(26), Y(10.5), "#111", 5, dash="14,10")
        b += text(X(13), Y(10.5) - 12, "невидимые стены: x=0, x=26, y=10.5", 22, "middle", "#111")
    # props
    def barrel(xm, ym):
        f = "#8b5a2b" if col else destr
        o = rect(X(xm) - 0.3 * s, Y(ym + 0.8), 0.6 * s, 0.8 * s, f, outl, 4, 16)
        if col:
            o += rect(X(xm) - 0.32 * s, Y(ym + 0.62), 0.64 * s, 0.06 * s, "#4b5563") + rect(X(xm) - 0.32 * s, Y(ym + 0.25), 0.64 * s, 0.06 * s, "#4b5563")
        return o

    def crate(xm, ym):
        f = WOOD if col else destr
        o = rect(X(xm) - 0.35 * s, Y(ym + 0.7), 0.7 * s, 0.7 * s, f, outl, 4, 4)
        if col:
            o += line(X(xm) - 0.35 * s, Y(ym + 0.7), X(xm) + 0.35 * s, Y(ym), WOOD_D, 3) + line(X(xm) + 0.35 * s, Y(ym + 0.7), X(xm) - 0.35 * s, Y(ym), WOOD_D, 3)
        return o
    b += barrel(5, 1) + barrel(17, 3.4) + barrel(23, 7.0) + crate(11.5, 5.8) + crate(20.5, 1) + crate(8, 3.2) + crate(21.3, 1)
    # banner
    b += line(X(12.6), Y(5.8), X(12.6), Y(8.6), "#5a3a1e" if col else deco, 8) + poly([(X(12.6), Y(8.5)), (X(13.8), Y(8.5)), (X(13.5), Y(7.6)), (X(13.8), Y(6.7)), (X(12.6), Y(6.7))], "#d9342b" if col else deco, outl, 3)
    if col:
        b += text(X(13.1), Y(7.45), "♛", 40, "middle", "#e8b820")
    # winch on tower
    b += rect(X(24.3), Y(8.3), 0.5 * s, 0.5 * s, "#6b5a4a" if col else deco, outl, 3) + line(X(24.55), Y(8.0), X(24.55), Y(6.9), "#2b2118" if col else deco, 4) + rect(X(24.35), Y(6.9), 0.4 * s, 0.4 * s, "#7a6a58" if col else deco, outl, 3)
    # scale doll
    d, _ = doll(X(7.2), Y(1), s, "side", dict(ua_l=10, la_l=20), shirt=P["P1"])
    b += d + text(X(7.2), Y(1) + 26, "1.8 м", 18, "middle", INK if not col else "#f3efe6", "normal")
    # legend / title
    if col:
        b += rect(50, 40, 900, 100, "#fff", "#c9b9a2", 3, 12, op=0.9) + text(75, 82, "R6  ARENA «RUINS» — LAYOUT", 40, family=HEAD_FONT) + text(75, 118, "26 × 10.5 м, 3 яруса, пропасть слева, обрушенная башня справа, 1 м = 92 px; кукла 1.8 м для масштаба", 20, weight="normal", color="#6b5a4a")
        b += dim_h(X(15), X(17), Y(9.3) - 30, "2 м", 22)
    else:
        b += rect(50, 40, 1100, 100, "#fff", "#c9b9a2", 3, 12) + text(75, 82, "R7  ARENA «RUINS» — COLLISION DIAGRAM", 40, family=HEAD_FONT)
        b += rect(75, 96, 30, 24, "#f28c28") + text(115, 115, "твёрдое (платформы, стены)", 20, weight="normal")
        b += rect(420, 96, 30, 24, "#3b82f6") + text(460, 115, "разрушаемое (бочки, ящики)", 20, weight="normal")
        b += rect(760, 96, 30, 24, "#bfbfbf") + text(800, 115, "декор без коллизии", 20, weight="normal")
        # tier annotations
        for (xm, ym, lab) in [(10.5, 1, "ярус 0  y=1.0"), (6.1, 3.2, "ярус 1  y≈3.0–3.4"), (9.1, 5.8, "ярус 2  y≈5.4–5.8"), (22.6, 6.4, "уступ башни y=7.0")]:
            b += text(X(xm), Y(ym) - 10, lab, 20, "start", "#111")
    return svg(W, H, b, None)

def r06(): return arena("concept")
def r07(): return arena("collision")

def r08():
    W, H = 1920, 1080
    b = title(W, "R8  ARENA PROPS", "Один масштаб (1 м = 260 px). Обломки собираются обратно в целый объект. Имена мешей: Debris_1..N.")
    s = 260
    # barrel intact
    x, y = 140, 300
    b += text(x, y - 60, "prop_barrel — бочка 0.6 × 0.8 м, 4 обломка", 24)
    b += rect(x, y, 0.6 * s, 0.8 * s, "#8b5a2b", OUTL, 4, 30) + rect(x - 6, y + 0.15 * s, 0.6 * s + 12, 0.06 * s, "#4b5563") + rect(x - 6, y + 0.6 * s, 0.6 * s + 12, 0.06 * s, "#4b5563")
    for k in range(4):
        b += line(x + (k + 1) * 0.12 * s, y + 8, x + (k + 1) * 0.12 * s, y + 0.8 * s - 8, WOOD_D, 2, op=0.6)
    # barrel debris: 4 curved staves groups
    for k in range(4):
        bx = x + 0.9 * s + k * 0.45 * s
        rot = [-25, 15, -10, 30][k]
        b += rect(bx, y + 0.1 * s + k % 2 * 40, 0.16 * s, 0.7 * s, "#8b5a2b", OUTL, 3, 10, rot) + text(bx + 20, y + 0.95 * s, f"Debris_{k + 1}", 16, weight="normal")
    b += rect(x + 0.9 * s + 0.2 * s, y + 0.3 * s, 0.4 * s, 0.05 * s, "#4b5563", OUTL, 2, 3, -20)
    # crate
    x, y = 140, 640
    b += text(x, y - 60, "prop_crate — ящик 0.7 × 0.7 м, 6 обломков", 24)
    b += rect(x, y, 0.7 * s, 0.7 * s, WOOD, OUTL, 4, 4) + line(x, y, x + 0.7 * s, y + 0.7 * s, WOOD_D, 4) + line(x + 0.7 * s, y, x, y + 0.7 * s, WOOD_D, 4) + rect(x, y, 0.7 * s, 0.7 * s, "none", WOOD_D, 8)
    for k in range(6):
        bx = x + 0.9 * s + (k % 3) * 0.42 * s
        by = y + (k // 3) * 0.4 * s
        pts = [(bx, by), (bx + 0.3 * s, by + 0.05 * s), (bx + 0.25 * s, by + 0.3 * s), (bx + 0.04 * s, by + 0.27 * s)]
        b += poly([(px + (k * 7) % 20, py) for px, py in pts], WOOD, OUTL, 3) + text(bx, by + 0.36 * s + 10, f"Debris_{k + 1}", 16, weight="normal")
    # bridge segment
    x, y = 1180, 260
    b += text(x, y - 60, "prop_bridge — сегмент моста 2 м", 24)
    b += path(f"M{x},{y} Q{x + 1.0 * s},{y + 0.3 * s} {x + 2.0 * s},{y}", stroke="#5a3a1e", sw=6)
    for k in range(9):
        xm = x + k * 0.25 * s
        t = (xm - x) / (2.0 * s)
        ym = y + 0.3 * s * 4 * t * (1 - t) * 0.5
        b += rect(xm - 14, ym - 6, 28, 12, WOOD, OUTL, 2)
    # banner
    x, y = 1180, 420
    b += text(x, y - 40, "prop_banner — флаг 1.2 × 1.8 м, шест 3 м", 24)
    b += line(x, y, x, y + 1.6 * s * 0.6, "#5a3a1e", 8) + poly([(x, y), (x + 0.7 * s, y), (x + 0.55 * s, y + 0.5 * s), (x + 0.7 * s, y + 1.0 * s), (x, y + 1.0 * s)], "#d9342b", OUTL, 3) + text(x + 0.3 * s, y + 0.62 * s, "♛", 44, "middle", "#e8b820")
    # winch
    x, y = 1560, 620
    b += text(x - 60, y - 40, "prop_winch — ворот с грузом", 24)
    b += rect(x, y, 0.5 * s, 0.5 * s, "#6b5a4a", OUTL, 3) + circle(x + 0.25 * s, y + 0.25 * s, 0.12 * s, "#2b2118") + line(x + 0.25 * s, y + 0.5 * s, x + 0.25 * s, y + 1.2 * s, "#2b2118", 4) + rect(x + 0.05 * s, y + 1.2 * s, 0.4 * s, 0.4 * s, "#7a6a58", OUTL, 3)
    b += dim_h(1180, 1180 + s, 1030, "1 м")
    return svg(W, H, b)

def r09(kind):
    W, H = 4096, 1024
    b = ""
    if kind == "a":
        b += grad("sky", [(0, "#6fb0dd"), (0.55, "#c9dfe9"), (1, "#f5e7c8")]) + rect(0, 0, W, H, "url(#sky)")
        import random
        random.seed(3)
        for i in range(18):
            cx, cy = random.randint(0, W), random.randint(80, 520)
            for k in range(5):
                b += ellipse(cx + k * 70 - 140, cy + (k % 2) * 18, 120 + (k * 37) % 80, 60 + (k * 23) % 40, "#ffffff", op=0.85)
        b += text(40, 60, "R9-a  SKY (4096×1024, seamless по X)", 30, color="#365d7a")
        return svg(W, H, b, None)
    if kind == "b":
        hz = 340
        b += grad("sea", [(0, "#5aa0c8"), (1, "#1f4d70")]) + rect(0, hz, W, H - hz, "url(#sea)")
        for i in range(60):
            b += line(60 + i * 68, hz + 60 + (i % 5) * 90, 110 + i * 68, hz + 60 + (i % 5) * 90, "#dbe8ef", 4, op=0.45)
        # ship
        sx, sy = 900, hz
        b += path(f"M{sx},{sy} L{sx + 260},{sy} L{sx + 220},{sy + 60} L{sx + 40},{sy + 60} Z", "#3b2a1a") + line(sx + 130, sy, sx + 130, sy - 160, "#3b2a1a", 8) + poly([(sx + 138, sy - 155), (sx + 240, sy - 20), (sx + 138, sy - 20)], "#f1e6cf")
        # blimp
        b += ellipse(3000, 150, 260, 85, "#e9dfc9", OUTL, 4) + rect(2950, 225, 100, 34, "#6b5a4a") + text(3000, 160, "RAGDOLL MASTER", 34, "middle", "#8b5a2b")
        b += text(40, 60, "R9-b  SEA + SHIP + BLIMP (верх прозрачный, горизонт y=340)", 30, color="#365d7a")
        return svg(W, H, b, None)
    if kind == "c":
        import random
        random.seed(7)
        b += rect(0, 620, W, H - 620, "#8a9bb0", op=0.9)
        x = 0
        while x < W:
            w = random.randint(90, 260)
            h = random.randint(80, 420)
            b += rect(x, 620 - h, w, h + 10, "#7f90a6", op=0.9)
            if random.random() < 0.3:
                b += path(f"M{x + 10},{620 - h + 10} A{w / 2 - 10},{w / 2 - 10} 0 0 1 {x + w - 10},{620 - h + 10}", "#a9b6c6", "none", 0, 0.7)
            x += w + random.randint(20, 160)
        b += text(40, 60, "R9-c  FAR RUINS (силуэты, дымка; верх прозрачный)", 30, color="#365d7a")
        return svg(W, H, b, None)
    # d foreground
    import random
    random.seed(11)
    x = -50
    while x < W:
        w = random.randint(120, 320)
        h = random.randint(60, 220)
        b += poly([(x, H), (x + 15, H - h), (x + w * 0.5, H - h - random.randint(0, 50)), (x + w, H - h + 20), (x + w + 20, H)], "#2f261d", "#1b1510", 6)
        x += w - 30
    for i in range(7):
        bx = 200 + i * 560
        b += rect(bx, H - 330, 36, 330, "#3b2a1a", "#1b1510", 4, 4, [-20, 12, -6, 25, -14, 8, -30][i])
    b += text(40, 60, "R9-d  FOREGROUND (обломки и балки по нижнему краю; верх прозрачный)", 30, color="#365d7a")
    return svg(W, H, b, None)

# ---------- UI ----------
UI_BG, UI_PANEL, UI_TXT, UI_ACC = "#1a1512", "#2a2320", "#f3efe6", "#d9342b"

def portrait(cx, cy, r, col, initial):
    return circle(cx, cy, r + 5, col) + circle(cx, cy, r, PLATE) + text(cx, cy + r * 0.35, initial, r, "middle", INK, family=HEAD_FONT)

def r10(kind):
    W, H = 1920, 1080
    b = rect(0, 0, W, H, UI_BG)
    if kind == "a":
        b += text(90, 170, "RAGDOLL", 120, color=UI_TXT, family=HEAD_FONT) + text(90, 290, "MASTER", 120, color=UI_ACC, family=HEAD_FONT)
        items = ["PLAY", "CHARACTERS", "SETTINGS", "REPLAYS", "STATS", "EXIT"]
        for i, it in enumerate(items):
            y = 420 + i * 78
            if i == 0:
                b += rect(70, y - 46, 420, 62, UI_ACC, rx=6)
            b += text(100, y, it, 44, color=UI_TXT if i == 0 else "#bdb2a4", family=HEAD_FONT)
        b += text(90, 980, "SILLY FIGHTS. REAL EMOTIONS.", 36, color="#8a7a6a", family=HEAD_FONT, rot=-4)
        # doll on crate right
        b += rect(1100, 250, 760, 700, UI_PANEL, rx=24)
        b += rect(1350, 760, 300, 180, WOOD_D, OUTL, 4, 6)
        d, _ = doll(1500, 760, 330, "quarter", dict(ul_l=-70, ll_l=10, ul_r=-60, ll_r=20, ua_l=-40, la_l=-100, ua_r=40, la_r=-20), shirt=P["P2"], root=(1500, 760 - 0.05 * 330))
        b += d + text(1750, 320, "GOOD RAGDOLLS", 30, "end", "#8a7a6a", family=HEAD_FONT) + text(1750, 360, "BETTER PEOPLE", 30, "end", "#8a7a6a", family=HEAD_FONT)
        b += text(60, 60, "R10-a  MAIN MENU (макет)", 24, color="#6b5a4a")
    elif kind == "b":
        b += rect(0, 0, W, H, "#5b6b7a") + text(960, 560, "[ арена, размыто ]", 40, "middle", "#9fb0bf", "normal")
        pos = [(60, 40, "P1"), (500, 40, "P2"), (1130, 40, "P3"), (1560, 40, "P4")]
        hp = [72, 18, 56, 91]
        for (x, y, pid), h in zip(pos, hp):
            b += rect(x, y, 330, 90, UI_BG, rx=14, op=0.85) + portrait(x + 45, y + 45, 32, P[pid], pid[1])
            b += text(x + 95, y + 35, pid, 22, color=P[pid], family=HEAD_FONT)
            b += rect(x + 95, y + 48, 190, 24, "#3a3330", rx=6) + rect(x + 95, y + 48, 190 * h / 100, 24, P[pid], rx=6) + text(x + 300, y + 68, f"{h}%", 24, "middle", UI_TXT, family=HEAD_FONT)
        b += rect(860, 30, 200, 80, UI_BG, rx=14, op=0.9) + text(960, 88, "00:43", 52, "middle", UI_TXT, family=HEAD_FONT)
        b += rect(1700, 160, 190, 100, UI_BG, "#8a7a6a", 2, 12, op=0.85) + text(1795, 190, "minimap", 18, "middle", "#8a7a6a", "normal")
        for (mx, my, c) in [(1740, 230, "P1"), (1790, 210, "P2"), (1830, 240, "P3"), (1860, 205, "P4")]:
            b += circle(mx, my, 6, P[c])
        b += text(1200, 640, "+48", 54, "middle", "#f2c200", family=HEAD_FONT, rot=-8) + text(700, 720, "SUDDEN DEATH", 40, "middle", UI_ACC, family=HEAD_FONT)
        b += text(60, 1040, "R10-b  HUD (макет): портрет + бар + % в углах, таймер по центру, всплывающий урон", 24, color=UI_TXT, op=0.7)
    elif kind == "c":
        b += rect(0, 0, W, H, "#3a2a20") + rgrad("vig", [(0, "#000000"), (0.6, "#00000000"), (1, "#000000")], 0.5, 0.5) + rect(0, 0, W, H, "url(#vig)", op=0.9)
        for k in range(30):
            a = k * 12
            dx, dy = dirv(a)
            b += line(960 + dx * 300, 520 + dy * 300, 960 + dx * 900, 520 + dy * 900, "#f2c200", 6 if k % 3 == 0 else 3, op=0.35)
        d1, _ = doll(600, 960, 360, "side", dict(torso=-15, ua_l=140, la_l=170, ua_r=120, la_r=150, ul_l=25, ll_l=-25, ul_r=-20, ll_r=20), shirt=P["P1"])
        d2, _ = doll(1320, 960, 360, "side", dict(torso=60, head=30, ua_l=50, la_l=90, ua_r=70, la_r=110, ul_l=80, ll_l=120, ul_r=60, ll_r=100), shirt=P["P2"], root=(1300, 700))
        b += d1 + d2
        for k in range(24):
            import random
            random.seed(k)
            b += rect(1000 + random.randint(-250, 250), 520 + random.randint(-200, 200), 26, 8, "#d9a86c", rot=random.randint(0, 180))
        b += text(946, 276, "KO!", 260, "middle", "#7a1c14", family=HEAD_FONT, rot=-6, op=0.6) + text(940, 270, "KO!", 260, "middle", UI_ACC, family=HEAD_FONT, rot=-6)
        b += text(80, 1000, "SLOW MOTION", 30, color=UI_TXT, family=HEAD_FONT) + rect(80, 1020, 600, 10, "#3a3330", rx=5) + rect(80, 1020, 220, 10, UI_ACC, rx=5)
        b += text(60, 60, "R10-c  KO CARD (макет)", 24, color=UI_TXT, op=0.7)
    else:
        b += text(90, 130, "MATCH RESULTS", 80, color=UI_TXT, family=HEAD_FONT)
        cols = [("P1", 1, "MASTER OF CHAOS", "3 KO · 612 урона · 45 с в воздухе", "#e8b820"), ("P3", 2, "THE ACROBAT", "2 KO · 488 · 38 с", "#c0c0c0"),
                ("P4", 3, "LUCKY ONE", "1 KO · 300 · 22 с", "#cd7f32"), ("P2", 4, "BETTER LUCK NEXT TIME", "0 KO · 280 · 19 с", "#6b5a4a")]
        for i, (pid, place, ttl, st, rim) in enumerate(cols):
            x = 300 + i * 430
            y = 480
            b += circle(x, y, 110, rim) + portrait(x, y, 95, P[pid], pid[1])
            if place == 1:
                b += text(x, y - 130, "♛", 70, "middle", "#e8b820")
            b += text(x, y + 170, f"{place}", 60, "middle", rim, family=HEAD_FONT) + text(x, y + 215, pid, 30, "middle", P[pid], family=HEAD_FONT)
            b += text(x, y + 260, ttl, 26, "middle", UI_TXT, family=HEAD_FONT) + text(x, y + 300, st, 20, "middle", "#bdb2a4", "normal")
        for i, lab in enumerate(["PLAY AGAIN", "SAVE REPLAY", "MAIN MENU"]):
            x = 330 + i * 460
            b += rect(x, 900, 400, 90, UI_ACC if i == 0 else UI_PANEL, "#8a7a6a" if i else None, 3, 12) + text(x + 200, 960, lab, 36, "middle", UI_TXT, family=HEAD_FONT)
        b += text(60, 60, "R10-d  RESULTS (макет)", 24, color=UI_TXT, op=0.7)
    return svg(W, H, b, None)

def r11():
    W, H = 1920, 1080
    b = rect(0, 0, W, H, "#000")
    b += text(60, 70, "R11  VFX SPRITE SHEET — 5 эффектов × 4 кадра", 40, color="#fff", family=HEAD_FONT)
    rows = ["щепки при ударе", "пыль при падении", "вспышка KO", "виньетка slow-mo", "искра удара"]
    for r, name in enumerate(rows):
        y = 200 + r * 175
        b += text(60, y + 10, name, 24, color="#bdb2a4")
        for f in range(4):
            x = 480 + f * 340
            b += rect(x - 140, y - 75, 280, 150, "none", "#333", 2)
            t = (f + 1) / 4
            if r == 0:
                for k in range(10):
                    a = k * 36 + 10
                    dx, dy = dirv(a)
                    b += rect(x + dx * 90 * t - 12, y + dy * 60 * t - 4, 24, 8, "#d9a86c", rot=a, op=1 - 0.6 * t)
                b += circle(x, y, 12 * (1 - t), "#fff")
            elif r == 1:
                for k in range(5):
                    b += circle(x - 60 + k * 30, y + 20 - (k % 2) * 10 - 40 * t, 18 + 30 * t, "#c9b9a2", op=0.6 * (1 - t) + 0.1)
            elif r == 2:
                for k in range(12):
                    a = k * 30
                    dx, dy = dirv(a)
                    b += poly([(x, y), (x + dx * 120 * t + dy * 12, y + dy * 70 * t - dx * 12), (x + dx * 120 * t - dy * 12, y + dy * 70 * t + dx * 12)], "#f2c200", op=1 - 0.7 * t)
                b += circle(x, y, 40 * (1 - t) + 6, "#fff")
            elif r == 3:
                b += rgrad(f"vg{f}", [(0, "#00000000"), (0.5 + 0.3 * (1 - t), "#00000000"), (1, "#000000ff")], 0.5, 0.5)
                b += rect(x - 140, y - 75, 280, 150, "#4b5563") + rect(x - 140, y - 75, 280, 150, f"url(#vg{f})")
            else:
                for k in range(6):
                    a = k * 60 + 15 * f
                    dx, dy = dirv(a)
                    b += line(x, y, x + dx * 40 * t, y + dy * 40 * t, "#fff", 4 - 2 * t, op=1 - 0.5 * t)
                b += circle(x, y, 8 * (1 - t) + 2, "#f2c200")
            b += text(x, y + 100, f"кадр {f + 1}", 16, "middle", "#666", "normal")
    return svg(W, H, b, None)

def r12():
    W, H = 1920, 1080
    b = title(W, "R12  POSES FOR PHYSICS CHECK", "Как должны вести себя суставы: локти/колени не гнутся назад, обмякшая кукла складывается в суставах.")
    s = 240
    # (name, pose, root offset from panel centre in metres: dx, height above ground)
    panels = [("1  ЛЕТИТ НАЗАД ПОСЛЕ УДАРА", dict(torso=45, head=20, ua_l=70, la_l=110, ua_r=90, la_r=130, ul_l=70, ll_l=120, ul_r=95, ll_r=140), (0.05, 1.35)),
              ("2  ПАДАЕТ ПЛАШМЯ", dict(torso=85, head=-40, ua_l=-160, la_l=-110, ua_r=150, la_r=110, ul_l=95, ll_l=85, ul_r=80, ll_r=100), (0.05, 0.14)),
              ("3  СТОЙКА (brace)", dict(torso=-8, head=5, ua_l=140, la_l=175, ua_r=125, la_r=165, ul_l=25, ll_l=-28, ul_r=-22, ll_r=22), (0.0, ROOT_H - 0.1)),
              ("4  KO: ОБМЯК У СТЕНЫ", dict(torso=-40, head=30, ua_l=15, la_l=35, ua_r=-10, la_r=20, ul_l=-80, ll_l=-95, ul_r=-65, ll_r=-90), (0.1, 0.3))]
    for i, (name, pose, (dx, dy)) in enumerate(panels):
        x0 = 80 + i * 455
        b += rect(x0, 170, 430, 830, "#fff", "#c9b9a2", 3, 14)
        ground = 940
        b += line(x0 + 20, ground, x0 + 410, ground, "#9c8a72", 4)
        if i == 3:
            b += rect(x0 + 372, 200, 38, 740, "#b8ab96", OUTL, 3)
        cx = x0 + 200 + dx * s
        root = (cx, ground - dy * s)
        d, _ = doll(cx, ground, s, "side", pose, shirt=P["P1"], root=root)
        b += d + text(x0 + 215, 215, name, 22, "middle")
        if i == 0:
            b += line(x0 + 380, 480, x0 + 260, 400, "#d9342b", 6) + poly([(x0 + 250, 392), (x0 + 285, 388), (x0 + 270, 418)], "#d9342b")
    return svg(W, H, b)

def r13():
    W, H = 1920, 1080
    b = title(W, "R13  MATERIAL PALETTE", "Сфера + куб на каждый материал. Цвета краски совпадают с R3. Все материалы матовые, кроме железа.")
    mats = [("raw wood", "#d9a86c", "#a9713a"), ("painted blue", "#2f6fde", "#1e4fa8"), ("painted red", "#d9342b", "#9c1f19"), ("painted green", "#2e9e4f", "#1f6f37"),
            ("painted yellow", "#e8b820", "#b58a10"), ("dark iron", "#6b7280", "#374151"), ("rough cloth", "#c9b9a2", "#8f836f"), ("rope", "#b08a5a", "#7a5a34"), ("weathered stone", "#b8ab96", "#7a6a58")]
    for i, (name, c, d) in enumerate(mats):
        col, row = i % 5, i // 5
        x, y = 180 + col * 360, 330 + row * 380
        b += rgrad(f"m{i}", [(0, "#ffffff"), (0.15, c), (1, d)]) + circle(x, y, 78, f"url(#m{i})", OUTL, 3)
        # cube
        cx, cy = x + 175, y
        b += poly([(cx - 52, cy - 18), (cx, cy - 48), (cx + 52, cy - 18), (cx, cy + 12)], c, OUTL, 3)
        b += poly([(cx - 52, cy - 18), (cx, cy + 12), (cx, cy + 72), (cx - 52, cy + 42)], d, OUTL, 3)
        b += poly([(cx + 52, cy - 18), (cx, cy + 12), (cx, cy + 72), (cx + 52, cy + 42)], c, OUTL, 3, op=0.8)
        if "wood" in name:
            for k in range(3):
                b += line(x - 60 + k * 36, y - 52, x - 44 + k * 36, y + 60, d, 3, op=0.4)
        b += text(x + 88, y + 140, name, 24, "middle") + text(x + 88, y + 170, f"{c} / {d}", 18, "middle", "#6b5a4a", "normal")
    return svg(W, H, b)

# ---------- render ----------
SHEETS = {
    "R01-a-doll-sheet": r01, "R02-a-face": r02, "R03-a-colors": r03, "R04-a-hats": r04, "R05-a-weapons": r05,
    "R06-a-ruins": r06, "R07-a-ruins-collision": r07, "R08-a-props": r08,
    "R09-a-sky": lambda: r09("a"), "R09-b-sea": lambda: r09("b"), "R09-c-far-ruins": lambda: r09("c"), "R09-d-foreground": lambda: r09("d"),
    "R10-a-menu": lambda: r10("a"), "R10-b-hud": lambda: r10("b"), "R10-c-ko": lambda: r10("c"), "R10-d-results": lambda: r10("d"),
    "R11-a-vfx": r11, "R12-a-poses": r12, "R13-a-materials": r13,
}

if __name__ == "__main__":
    only = sys.argv[1:] or list(SHEETS)
    for name in only:
        content = SHEETS[name]()
        svg_path = os.path.join(OUT, name + ".svg")
        png_path = os.path.join(OUT, name + ".png")
        with open(svg_path, "w") as f:
            f.write(content)
        r = subprocess.run(["rsvg-convert", "-o", png_path, svg_path], capture_output=True, text=True)
        print(name, "ok" if r.returncode == 0 else r.stderr[:300])
