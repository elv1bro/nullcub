"""Атлас выражений лиц бойцов (docs/plan-demo/look/faces.md, проход по картинке LOOK_PASS.md, направление look-faces). Pillow, без
Blender и Godot. Запуск из корня репозитория:
    python3 godot/tools/gen_face_atlas.py [--sheet out.png]
затем godot --headless --path godot --import.

Стиль — как у лица кита по умолчанию (assets/materials/kit/face_default.png, tools/gen_kit_face.py): тёплая фотобумага, белая кайма
карточки, чёрные глаза с бликом, румянец, тёмно-коричневая линия рта. Нейтральное выражение повторяет face_default почти пиксель
в пиксель — включённый пункт «ВИД» не меняет лицо в покое.

Пишет в godot/assets/textures/faces/:
  face_expr_atlas.png — RGB 4 × 3 ячейки по 256² (1024 × 768): карточка целиком (плашка FacePlate голов кита, UV 0..1 на ячейку);
  face_expr_ink.png   — RGBA тот же рисунок без бумаги и каймы («маркером по дереву»): лицо-наклейка деревянного манекена.
Порядок ячеек = EXPRESSIONS (слева направо, сверху вниз) — тот же список в scripts/look/face_expr.gd (FaceExpr.EXPRESSIONS).
--sheet — ещё лист для глаз: обе версии крупно с подписями (не для игры).

Рисуется в SS × размере (суперсэмплинг) и сжимается LANCZOS — гладкие края без своего сглаживания. Координаты — доли ячейки,
y вниз (как у PNG)."""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # godot/
OUT = os.path.join(ROOT, "assets", "textures", "faces")
CELL = 256
SS = 4
COLS, ROWS = 4, 3
EXPRESSIONS = ["neutral", "blink", "wince", "hurt", "crit", "ko", "charge", "victory", "fear", "smug", "stun", "sad"]
LABELS = {"neutral": "нейтральное", "blink": "моргание", "wince": "лёгкий удар", "hurt": "удар >_<", "crit": "крит X X",
          "ko": "KO", "charge": "Заряд / злость", "victory": "победа ^^", "fear": "страх", "smug": "попал", "stun": "оглушён",
          "sad": "проиграл"}

# цвета face_default (gen_kit_face.face: байты = доли × 255)
PAPER = (204, 158, 107)
BORDER = (237, 224, 199)
BLUSH = (204, 111, 75)
EYE = (5, 5, 6)
INK = (31, 8, 5)
SHINE = (230, 230, 230)
WHITE = (246, 240, 228)
TONGUE = (214, 92, 92)
RED = (196, 38, 34)
SWEAT = (150, 205, 240)
STAR = (255, 214, 92)
CLEAR = (0, 0, 0, 0)

EX = (0.32, 0.68)        # центры глаз по x
EY = 0.42                # центр глаз по y (v = 0.58 у face_default)
ERX, ERY = 0.075, 0.11   # полуоси глаза
LW = 0.036               # толщина линии рта face_default
BOLD = 0.05              # толщина линий выражений (читаются мельче на игровом расстоянии)


class Pen:
    """Рисование в долях ячейки на слое RGBA размером CELL·SS."""

    def __init__(self, img, k=1.0, wk=1.0):
        """k — масштаб рисунка вокруг центра ячейки, wk — множитель толщины линий (версия «маркером» крупнее и жирнее)."""
        self.img = img
        self.d = ImageDraw.Draw(img)
        self.n = img.size[0]
        self.k = k
        self.wk = wk

    def p(self, x, y):
        return ((0.5 + (x - 0.5) * self.k) * self.n, (0.5 + (y - 0.5) * self.k) * self.n)

    def w(self, w, cap=99.0):
        """cap — потолок множителя толщины (спирали и кольца в жирной версии слиплись бы в кляксу)."""
        return max(1, round(w * min(self.wk, cap) * self.k * self.n))

    def ellipse(self, cx, cy, rx, ry, fill, outline=None, width=0.0, cap=99.0):
        self.d.ellipse([self.p(cx - rx, cy - ry), self.p(cx + rx, cy + ry)], fill=fill,
                       outline=outline, width=self.w(width, cap) if outline else 1)

    def dot(self, x, y, w, col, cap=99.0):
        r = w * min(self.wk, cap) / 2
        self.ellipse(x, y, r, r, col)

    def line(self, pts, w, col, cap=99.0):
        """Ломаная с круглыми концами и стыками."""
        # отрезки без стыков PIL (joint="curve" на частой дуге даёт бахрому) + круг в каждой вершине
        wpx = self.w(w, cap)
        for a, b in zip(pts, pts[1:]):
            self.d.line([self.p(*a), self.p(*b)], fill=col, width=wpx)
        for x, y in pts:
            self.dot(x, y, w, col, cap)

    def arc(self, cx, cy, rx, ry, a0, a1, w, col, steps=48):
        """Дуга эллипса: углы в градусах, по часовой (y вниз), круглые концы."""
        pts = []
        for i in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * i / steps)
            pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
        self.line(pts, w, col)

    def poly(self, pts, col):
        self.d.polygon([self.p(x, y) for x, y in pts], fill=col)

    def star(self, cx, cy, r, col, k=0.38, n=4, rot=0.0):
        pts = []
        for i in range(n * 2):
            a = math.radians(rot + i * 180.0 / n - 90.0)
            rr = r if i % 2 == 0 else r * k
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        self.poly(pts, col)


# --- детали ------------------------------------------------------------------------------------------------------------------

def eyes_open(pen, ry=ERY, dy=0.0, shine=True):
    for ex in EX:
        pen.ellipse(ex, EY + dy, ERX, ry, EYE)
        if shine:
            pen.ellipse(ex - 0.022, EY + dy - 0.045 * ry / ERY, 0.024, 0.03, SHINE)


def smile(pen, w=LW):
    # face_default: дуга окружности r 0.2 вокруг (0.5, 0.53), только ниже y 0.64
    a = math.degrees(math.asin((0.64 - 0.53) / 0.2))
    pen.arc(0.5, 0.53, 0.2, 0.2, a, 180.0 - a, w, INK)


def chevron(pen, ex, right, w=BOLD):
    s = 1.0 if right else -1.0     # right: «>» (вершина справа)
    pen.line([(ex - s * 0.07, EY - 0.075), (ex + s * 0.06, EY), (ex - s * 0.07, EY + 0.075)], w, EYE)


def cross(pen, ex, r=0.068, w=BOLD):
    pen.line([(ex - r, EY - r), (ex + r, EY + r)], w, EYE)
    pen.line([(ex + r, EY - r), (ex - r, EY + r)], w, EYE)


def spiral(pen, ex, r=0.105, turns=1.8, w=0.034, rot=0.0):
    pts = []
    steps = 120
    for i in range(steps + 1):
        t = i / steps
        a = math.radians(rot) + t * turns * 2.0 * math.pi
        pts.append((ex + r * t * math.cos(a), EY + r * t * math.sin(a)))
    pen.line(pts, w, EYE, cap=1.1)


def brows(pen, inner_dy, outer_dy, y=0.27, w=BOLD, half=0.085):
    """Брови: inner_dy / outer_dy — сдвиг внутреннего / внешнего конца по y (минус — выше)."""
    for ex, s in ((EX[0], 1.0), (EX[1], -1.0)):
        pen.line([(ex - s * half, y + outer_dy), (ex + s * half, y + inner_dy)], w, INK)


def open_mouth(pen, cx, cy, rx, ry, tongue=True):
    pen.ellipse(cx, cy, rx, ry, INK)
    if tongue:
        pen.ellipse(cx, cy + ry * 0.55, rx * 0.62, ry * 0.42, TONGUE)
        # верх языка срезан тенью рта — чтобы язык лежал внутри
        pen.ellipse(cx, cy + ry * 0.18, rx * 0.66, ry * 0.3, INK)


def wavy(pen, x0, x1, y, amp, waves, w=LW + 0.006):
    pts = []
    steps = 60
    for i in range(steps + 1):
        t = i / steps
        pts.append((x0 + (x1 - x0) * t, y + amp * math.sin(t * waves * 2.0 * math.pi)))
    pen.line(pts, w, INK)


def drop(pen, cx, cy, r, col):
    pen.ellipse(cx, cy, r, r, col)
    pen.poly([(cx - r * 0.92, cy - r * 0.35), (cx, cy - r * 2.3), (cx + r * 0.92, cy - r * 0.35)], col)
    pen.ellipse(cx - r * 0.35, cy - r * 0.2, r * 0.25, r * 0.3, (255, 255, 255, 230))


def vein(pen, cx, cy, r):
    """Знак злости 💢: четыре изогнутых уголка."""
    for k in range(4):
        a = k * 90.0 + 45.0
        c = (cx + r * 0.62 * math.cos(math.radians(a)), cy + r * 0.62 * math.sin(math.radians(a)))
        pen.arc(c[0], c[1], r * 0.45, r * 0.45, a + 90.0, a + 270.0, r * 0.32, RED, 16)


# --- выражения: ink — линии (слой без бумаги), blush — румянец (отдельный слой: в версии «маркером» он полупрозрачный) -----------

def draw(name, pen):
    """Возвращает (румянец: 0 нет / 1 как у face_default / 1.5 ярче)."""
    if name == "neutral":
        eyes_open(pen)
        smile(pen)
        return 1.0
    if name == "blink":
        for ex in EX:
            pen.arc(ex, EY - 0.01, ERX, 0.05, 15.0, 165.0, BOLD, EYE)
        smile(pen)
        return 1.0
    if name == "wince":
        pen.ellipse(EX[0], EY + 0.005, ERX, ERY * 0.82, EYE)
        pen.ellipse(EX[0] - 0.022, EY - 0.035, 0.022, 0.026, SHINE)
        chevron(pen, EX[1], False)
        brows(pen, -0.035, 0.0, y=0.25, w=0.04, half=0.07)
        pen.line([(0.40, 0.71), (0.47, 0.685), (0.53, 0.715), (0.60, 0.69)], LW + 0.006, INK)
        return 1.0
    if name == "hurt":
        chevron(pen, EX[0], True)
        chevron(pen, EX[1], False)
        pen.poly([(0.385, 0.755), (0.5, 0.63), (0.615, 0.755)], INK)
        pen.line([(0.385, 0.755), (0.5, 0.63), (0.615, 0.755), (0.385, 0.755)], 0.03, INK)
        pen.ellipse(0.5, 0.735, 0.06, 0.02, TONGUE)
        for x0, y0, x1, y1 in ((0.1, 0.16, 0.16, 0.22), (0.07, 0.27, 0.14, 0.28), (0.9, 0.16, 0.84, 0.22), (0.93, 0.27, 0.86, 0.28)):
            pen.line([(x0, y0), (x1, y1)], 0.024, INK)
        return 1.5
    if name == "crit":
        cross(pen, EX[0])
        cross(pen, EX[1])
        open_mouth(pen, 0.5, 0.71, 0.1, 0.1)
        pen.star(0.14, 0.17, 0.075, STAR, rot=12.0)
        pen.star(0.87, 0.15, 0.055, STAR, rot=-10.0)
        pen.star(0.88, 0.32, 0.035, STAR)
        return 1.5
    if name == "ko":
        spiral(pen, EX[0], rot=0.0)
        spiral(pen, EX[1], rot=180.0)
        wavy(pen, 0.37, 0.63, 0.68, 0.018, 2.0)
        pen.ellipse(0.565, 0.735, 0.045, 0.055, TONGUE)
        pen.line([(0.565, 0.70), (0.565, 0.76)], 0.012, (160, 60, 60))
        return 0.0
    if name == "charge":
        for ex, s in ((EX[0], 1.0), (EX[1], -1.0)):
            pen.ellipse(ex, EY + 0.02, ERX, ERY * 0.85, EYE)
            pen.ellipse(ex - 0.02, EY + 0.04, 0.02, 0.024, SHINE)
            # верх глаза срезан косой бровью: внутренний край ниже
            pen.poly([(ex - 0.12, EY - 0.13 - s * 0.03), (ex + 0.12, EY - 0.13 + s * 0.03), (ex + 0.12, EY - 0.04 + s * 0.045),
                      (ex - 0.12, EY - 0.04 - s * 0.045)], CLEAR)
        brows(pen, 0.05, -0.03, y=0.31, w=0.055, half=0.095)
        # стиснутые зубы
        x0, x1, y0, y1 = 0.37, 0.63, 0.645, 0.755
        pen.d.rounded_rectangle([pen.p(x0, y0), pen.p(x1, y1)], radius=0.03 * pen.n, fill=WHITE, outline=INK, width=pen.w(0.026))
        pen.line([(x0 + 0.01, (y0 + y1) / 2), (x1 - 0.01, (y0 + y1) / 2)], 0.016, INK)
        for x in (0.435, 0.5, 0.565):
            pen.line([(x, y0 + 0.01), (x, y1 - 0.01)], 0.014, INK)
        vein(pen, 0.84, 0.17, 0.085)
        return 1.5
    if name == "victory":
        for ex in EX:
            pen.arc(ex, EY + 0.03, ERX, 0.075, 195.0, 345.0, BOLD, EYE)
        pen.d.pieslice([pen.p(0.34, 0.47), pen.p(0.66, 0.81)], 0.0, 180.0, fill=INK)
        pen.d.chord([pen.p(0.40, 0.66), pen.p(0.60, 0.80)], 20.0, 160.0, fill=TONGUE)
        pen.star(0.13, 0.16, 0.06, STAR, rot=10.0)
        pen.star(0.88, 0.2, 0.045, STAR, rot=-8.0)
        return 1.5
    if name == "fear":
        for ex in EX:
            pen.ellipse(ex, EY, 0.092, 0.108, WHITE, outline=EYE, width=0.026, cap=1.2)
            pen.ellipse(ex, EY + 0.012, 0.03, 0.034, EYE)
        brows(pen, -0.05, 0.02, y=0.26, w=0.04, half=0.075)
        open_mouth(pen, 0.5, 0.70, 0.045, 0.06, tongue=False)
        drop(pen, 0.86, 0.33, 0.04, SWEAT)
        return 0.0
    if name == "smug":
        for ex in EX:
            pen.ellipse(ex, EY + 0.02, ERX, ERY * 0.9, EYE)
            pen.poly([(ex - 0.12, EY - 0.14), (ex + 0.12, EY - 0.14), (ex + 0.12, EY + 0.005), (ex - 0.12, EY + 0.005)], CLEAR)
            pen.line([(ex - ERX - 0.012, EY + 0.005), (ex + ERX + 0.012, EY + 0.005)], 0.034, EYE)
            pen.ellipse(ex - 0.018, EY + 0.04, 0.018, 0.02, SHINE)
        pen.arc(0.56, 0.52, 0.15, 0.17, 35.0, 118.0, LW + 0.008, INK)
        pen.line([(0.665, 0.615), (0.69, 0.59)], LW + 0.008, INK)
        return 1.0
    if name == "stun":
        pen.ellipse(EX[0], EY, 0.07, 0.085, None, outline=EYE, width=0.032, cap=1.15)
        pen.ellipse(EX[1], EY + 0.02, 0.042, 0.052, None, outline=EYE, width=0.026, cap=1.0)
        pen.line([(0.38, 0.70), (0.43, 0.665), (0.48, 0.70), (0.53, 0.665), (0.58, 0.70), (0.62, 0.68)], LW + 0.004, INK)
        for i, (x, y) in enumerate(((0.2, 0.14), (0.5, 0.1), (0.8, 0.14))):
            pen.star(x, y, 0.05 if i == 1 else 0.04, STAR, n=5, k=0.45, rot=i * 20.0)
        return 1.0
    if name == "sad":
        for ex in EX:
            pen.ellipse(ex, EY + 0.03, ERX * 0.9, ERY * 0.85, EYE)
            pen.ellipse(ex - 0.02, EY + 0.0, 0.02, 0.026, SHINE)
        brows(pen, -0.045, 0.02, y=0.27, w=0.04, half=0.075)
        pen.arc(0.5, 0.84, 0.15, 0.13, 215.0, 325.0, LW + 0.006, INK)
        drop(pen, EX[0] - 0.02, EY + 0.21, 0.028, SWEAT)
        return 0.6
    raise ValueError(name)


def blush_layer(n, amount, alpha, k=1.0):
    img = Image.new("RGBA", (n, n), CLEAR)
    if amount <= 0.0:
        return img
    pen = Pen(img, k)
    k = min(amount, 1.5)
    col = BLUSH if k <= 1.0 else (214, 96, 66)
    a = round(255 * alpha)
    for cx in (0.2, 0.8):
        pen.ellipse(cx, 0.6, 0.08 * (1.0 + (k - 1.0) * 0.3), 0.05 * (1.0 + (k - 1.0) * 0.3), col + (a,))
    return img


def card_base(n):
    img = Image.new("RGBA", (n, n), BORDER + (255,))
    b = round(0.035 * n)
    ImageDraw.Draw(img).rectangle([b, b, n - 1 - b, n - 1 - b], fill=PAPER + (255,))
    return img


## Толщина линий: карточка — как face_default в нейтральном, жирнее в остальных (читаются на игровом расстоянии: голова в кадре
## боя 35–60 px); «маркером» по дереву — рисунок крупнее (INK_K) и ещё жирнее.
CARD_WK = 1.25
INK_K = 1.12
INK_WK = 1.45


def cell(name, ink_only):
    n = CELL * SS
    lines = Image.new("RGBA", (n, n), CLEAR)
    if ink_only:
        pen = Pen(lines, INK_K, INK_WK)
    else:
        pen = Pen(lines, 1.0, 1.0 if name == "neutral" else CARD_WK)
    amount = draw(name, pen)
    if ink_only:
        out = blush_layer(n, amount, 0.55, INK_K)
    else:
        out = card_base(n)
        out.alpha_composite(blush_layer(n, amount, 1.0))
    out.alpha_composite(lines)
    out = out.resize((CELL, CELL), Image.LANCZOS)
    return out if ink_only else out.convert("RGB")


def atlas(ink_only):
    mode = "RGBA" if ink_only else "RGB"
    img = Image.new(mode, (CELL * COLS, CELL * ROWS), CLEAR if ink_only else BORDER)
    for i, name in enumerate(EXPRESSIONS):
        c = cell(name, ink_only)
        img.paste(c, ((i % COLS) * CELL, (i // COLS) * CELL))
    return img


def stub(path):
    if os.path.exists(path + ".import"):
        return
    with open(path + ".import", "w") as f:
        f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=2\ncompress/high_quality=false\n'
                'mipmaps/generate=true\ndetect_3d/compress_to=1\n')


def sheet(path, card, ink):
    """Лист для глаз: карточка и «маркер по дереву» рядом, подписи."""
    pad, lab = 24, 34
    cw = CELL * 2 + pad
    img = Image.new("RGB", (COLS * (cw + pad) + pad, ROWS * (CELL + lab + pad) + pad), (24, 20, 18))
    wood = Image.new("RGBA", (CELL, CELL), (196, 150, 98, 255))
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 22)
    except OSError:
        font = ImageFont.load_default()
    d = ImageDraw.Draw(img)
    for i, name in enumerate(EXPRESSIONS):
        x = pad + (i % COLS) * (cw + pad)
        y = pad + (i // COLS) * (CELL + lab + pad)
        box = ((i % COLS) * CELL, (i // COLS) * CELL, (i % COLS + 1) * CELL, (i // COLS + 1) * CELL)
        img.paste(card.crop(box), (x, y))
        w = wood.copy()
        w.alpha_composite(ink.crop(box))
        img.paste(w.convert("RGB"), (x + CELL + pad, y))
        d.text((x, y + CELL + 6), "%d  %s — %s" % (i, name, LABELS[name]), fill=(235, 225, 205), font=font)
    img.save(path, optimize=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    card = atlas(False)
    ink = atlas(True)
    p_card = os.path.join(OUT, "face_expr_atlas.png")
    p_ink = os.path.join(OUT, "face_expr_ink.png")
    card.save(p_card, optimize=True)
    ink.save(p_ink, optimize=True)
    stub(p_card)
    stub(p_ink)
    print("gen_face_atlas: %s, %s (%d выражений, %d × %d ячеек по %d px)" % (
        os.path.relpath(p_card, ROOT), os.path.relpath(p_ink, ROOT), len(EXPRESSIONS), COLS, ROWS, CELL))
    if "--sheet" in sys.argv:
        out = sys.argv[sys.argv.index("--sheet") + 1]
        sheet(out, card, ink)
        print("  sheet " + out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
