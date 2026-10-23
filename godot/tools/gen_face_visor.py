"""Лица бойцов — «визор» (взрослый вид бойцов, docs/plan-demo/grownup_art/README.md). Pillow, без Blender и Godot. Запуск из корня:
    python3 godot/tools/gen_face_visor.py [--sheet out.png]
затем godot --headless --path godot --import.

Вместо мультяшной «фотокарточки» (глаза с бликом, румянец, улыбка — старые gen_kit_face.face / gen_face_atlas.py): плашка FacePlate
головы кита — дымчатое стекло визора в рамке, глаза — светодиодные полосы (тёплый янтарь, мягкое свечение), под ними решётка динамика
и мелкая трафаретная маркировка. Рта нет, румянца нет: выражение читается формой полос (как шлем пилота / дисплей робота).
Деревянный манекен — тот же рисунок трафаретом по дереву (тёмная краска) и метка краш-теста на лбу.

Пишет:
  godot/assets/materials/kit/face_default.png       — 256² RGB, «нейтральное» (Face.tres, плашка головы кита; эмиссия той же картой);
  godot/assets/textures/faces/face_expr_atlas.png   — RGB 4 × 3 ячейки по 256² (FaceExpr, uv1_offset = ячейка);
  godot/assets/textures/faces/face_expr_ink.png     — RGBA тот же рисунок без стекла (наклейка манекена).
Порядок ячеек = EXPRESSIONS = FaceExpr.EXPRESSIONS (scripts/look/face_expr.gd). Координаты — доли ячейки, y вниз. Рисуется в SS × размере
и сжимается LANCZOS. --sheet — лист для глаз (обе версии с подписями, не для игры)."""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # godot/
OUT_FACES = os.path.join(ROOT, "assets", "textures", "faces")
OUT_KIT = os.path.join(ROOT, "assets", "materials", "kit")
CELL = 256
SS = 4
COLS, ROWS = 4, 3
EXPRESSIONS = ["neutral", "blink", "wince", "hurt", "crit", "ko", "charge", "victory", "fear", "smug", "stun", "sad"]

GLASS_TOP = (9, 11, 14)
GLASS_BOT = (20, 23, 27)
BEZEL = (38, 41, 45)
BEZEL_HI = (78, 82, 88)
LED = (255, 184, 104)          # тёплый янтарь табло зала
LED_HOT = (255, 120, 64)       # Заряд
LED_DIM = (120, 92, 66)        # KO — дисплей гаснет
MARK = (74, 79, 86)            # трафарет на стекле
STENCIL = (26, 25, 24)         # трафарет по дереву
CAL_Y = (226, 176, 38)         # метка краш-теста
CLEAR = (0, 0, 0, 0)

EX = (0.315, 0.685)            # центры глаз по x
EY = 0.45                      # по y
BW, BH = 0.17, 0.052           # полоса глаза


class Pen:
    """Рисует в RGBA-слой SS-размера; k — масштаб рисунка вокруг центра ячейки (манекен — крупнее)."""

    def __init__(self, img, k=1.0):
        self.img = img
        self.d = ImageDraw.Draw(img)
        self.n = img.size[0]
        self.k = k

    def p(self, x, y):
        c = 0.5
        return ((c + (x - c) * self.k) * self.n, (c + (y - c) * self.k) * self.n)

    def s(self, v):
        return v * self.k * self.n

    def bar(self, cx, cy, w, h, col, ang=0.0):
        """Полоса со скруглёнными концами, повёрнутая на ang (град, + по часовой)."""
        a = math.radians(ang)
        dx, dy = math.cos(a) * w * 0.5, math.sin(a) * w * 0.5
        self.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], h, col)

    def line(self, pts, w, col):
        q = [self.p(x, y) for x, y in pts]
        ww = max(1, round(self.s(w)))
        self.d.line(q, fill=col, width=ww, joint="curve")
        r = ww / 2.0
        for x, y in (q[0], q[-1]):
            self.d.ellipse([x - r, y - r, x + r, y + r], fill=col)

    def ring(self, cx, cy, r, w, col):
        x, y = self.p(cx, cy)
        rr = self.s(r)
        self.d.ellipse([x - rr, y - rr, x + rr, y + rr], outline=col, width=max(1, round(self.s(w))))

    def dot(self, cx, cy, r, col):
        x, y = self.p(cx, cy)
        rr = self.s(r)
        self.d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=col)

    def arc(self, cx, cy, r, a0, a1, w, col, steps=24):
        pts = [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / steps)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / steps)))
               for i in range(steps + 1)]
        self.line(pts, w, col)


def glyph(name, pen, col):
    """Глаза-полосы выражения name цветом col (на стекле — светодиод, на дереве — трафарет)."""
    l, r = EX
    y = EY
    if name == "neutral":
        pen.bar(l, y, BW, BH, col)
        pen.bar(r, y, BW, BH, col)
    elif name == "blink":
        pen.bar(l, y + 0.012, BW, 0.016, col)
        pen.bar(r, y + 0.012, BW, 0.016, col)
    elif name == "wince":
        pen.bar(l, y, BW * 0.9, BH, col, -6.0)
        pen.line([(r - 0.07, y - 0.03), (r + 0.06, y + 0.005), (r - 0.07, y + 0.035)], 0.03, col)
    elif name == "hurt":
        pen.line([(l - 0.06, y - 0.05), (l + 0.06, y), (l - 0.06, y + 0.05)], 0.036, col)
        pen.line([(r + 0.06, y - 0.05), (r - 0.06, y), (r + 0.06, y + 0.05)], 0.036, col)
    elif name == "crit":
        for x in (l, r):
            pen.line([(x - 0.058, y - 0.058), (x + 0.058, y + 0.058)], 0.04, col)
            pen.line([(x - 0.058, y + 0.058), (x + 0.058, y - 0.058)], 0.04, col)
    elif name == "ko":
        for x in (l, r):
            for i in range(3):
                pen.bar(x - 0.06 + i * 0.06, y + 0.01, 0.03, 0.022, col)
    elif name == "charge":
        pen.bar(l, y, BW, BH * 1.05, col, 17.0)
        pen.bar(r, y, BW, BH * 1.05, col, -17.0)
    elif name == "victory":
        pen.arc(l, y + 0.035, 0.07, 200.0, 340.0, 0.04, col)
        pen.arc(r, y + 0.035, 0.07, 200.0, 340.0, 0.04, col)
    elif name == "fear":
        pen.ring(l, y, 0.05, 0.022, col)
        pen.ring(r, y, 0.05, 0.022, col)
        pen.dot(l, y, 0.014, col)
        pen.dot(r, y, 0.014, col)
    elif name == "smug":
        pen.bar(l, y + 0.01, BW, BH * 0.7, col)
        pen.bar(r, y - 0.005, BW, BH * 0.7, col, -12.0)
    elif name == "stun":
        for x in (l, r):
            pts = [(x - 0.075 + 0.15 * i / 16, y + 0.022 * math.sin(i / 16 * math.tau * 1.5)) for i in range(17)]
            pen.line(pts, 0.026, col)
    elif name == "sad":
        pen.bar(l, y + 0.01, BW, BH * 0.8, col, -15.0)
        pen.bar(r, y + 0.01, BW, BH * 0.8, col, 15.0)


def led_colour(name):
    return LED_HOT if name == "charge" else (LED_DIM if name == "ko" else LED)


def glass(n):
    """Стекло визора в рамке: градиент, косой блик, решётка динамика, маркировка."""
    img = Image.new("RGBA", (n, n))
    d = ImageDraw.Draw(img)
    for j in range(n):
        t = j / (n - 1)
        c = tuple(round(GLASS_TOP[i] + (GLASS_BOT[i] - GLASS_TOP[i]) * t) for i in range(3))
        d.line([(0, j), (n, j)], fill=c + (255,))
    hi = Image.new("RGBA", (n, n), CLEAR)
    hd = ImageDraw.Draw(hi)
    hd.polygon([(0.08 * n, n), (0.30 * n, n), (0.92 * n, 0), (0.70 * n, 0)], fill=(150, 165, 185, 14))
    hd.polygon([(0.34 * n, n), (0.38 * n, n), (0.98 * n, 0), (0.94 * n, 0)], fill=(150, 165, 185, 10))
    img.alpha_composite(hi)
    b = round(0.045 * n)
    d.rectangle([0, 0, n - 1, n - 1], outline=BEZEL + (255,), width=b)
    d.rectangle([b, b, n - 1 - b, n - 1 - b], outline=BEZEL_HI + (255,), width=max(1, round(0.006 * n)))
    pen = Pen(img)
    for i in range(7):   # решётка динамика
        pen.dot(0.38 + i * 0.04, 0.72, 0.008, (40, 44, 49, 255))
    for i in range(9):   # риски калибровки сверху
        x = 0.30 + i * 0.05
        pen.line([(x, 0.115), (x, 0.135 if i % 4 else 0.15)], 0.006, MARK + (255,))
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/DIN Condensed Bold.ttf", round(0.075 * n))
    except OSError:
        font = ImageFont.load_default()
    d.text((0.11 * n, 0.80 * n), "NG-07", fill=MARK + (255,), font=font)
    d.text((0.73 * n, 0.80 * n), "R2", fill=MARK + (255,), font=font)
    return img


def cell(name, ink_only):
    n = CELL * SS
    if ink_only:
        out = Image.new("RGBA", (n, n), CLEAR)
        pen = Pen(out, 1.12)
        # метка краш-теста на лбу: круг на четверти, жёлтый / чёрный
        cx, cy = pen.p(0.5, 0.2)
        rr = pen.s(0.06)
        box = [cx - rr, cy - rr, cx + rr, cy + rr]
        for k, col in enumerate([CAL_Y, STENCIL, CAL_Y, STENCIL]):
            pen.d.pieslice(box, k * 90, (k + 1) * 90, fill=col + (235,))
        glyph(name, pen, STENCIL + (235,))
    else:
        out = glass(n)
        lay = Image.new("RGBA", (n, n), CLEAR)
        glyph(name, Pen(lay), led_colour(name) + (255,))
        halo = lay.filter(ImageFilter.GaussianBlur(0.03 * n))
        halo.putalpha(halo.getchannel("A").point(lambda a: a * 0.55))
        out.alpha_composite(halo)
        out.alpha_composite(lay)
    out = out.resize((CELL, CELL), Image.LANCZOS)
    return out if ink_only else out.convert("RGB")


def atlas(ink_only):
    img = Image.new("RGBA" if ink_only else "RGB", (CELL * COLS, CELL * ROWS), CLEAR if ink_only else BEZEL)
    for i, name in enumerate(EXPRESSIONS):
        img.paste(cell(name, ink_only), ((i % COLS) * CELL, (i // COLS) * CELL))
    return img


def stub(path):
    if os.path.exists(path + ".import"):
        return
    with open(path + ".import", "w") as f:
        f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=2\ncompress/high_quality=false\n'
                'mipmaps/generate=true\ndetect_3d/compress_to=1\n')


def sheet(path, card, ink):
    pad = 20
    wood = Image.new("RGBA", (CELL, CELL), (176, 140, 98, 255))
    img = Image.new("RGB", (COLS * (CELL * 2 + pad * 2) + pad, ROWS * (CELL + 40) + pad), (22, 22, 24))
    d = ImageDraw.Draw(img)
    for i, name in enumerate(EXPRESSIONS):
        x = pad + (i % COLS) * (CELL * 2 + pad * 2)
        y = pad + (i // COLS) * (CELL + 40)
        box = ((i % COLS) * CELL, (i // COLS) * CELL, (i % COLS + 1) * CELL, (i // COLS + 1) * CELL)
        img.paste(card.crop(box), (x, y))
        w = wood.copy()
        w.alpha_composite(ink.crop(box))
        img.paste(w.convert("RGB"), (x + CELL + pad // 2, y))
        d.text((x, y + CELL + 6), "%d %s" % (i, name), fill=(220, 214, 200))
    img.save(path, optimize=True)


def main():
    os.makedirs(OUT_FACES, exist_ok=True)
    card = atlas(False)
    ink = atlas(True)
    p_card = os.path.join(OUT_FACES, "face_expr_atlas.png")
    p_ink = os.path.join(OUT_FACES, "face_expr_ink.png")
    p_def = os.path.join(OUT_KIT, "face_default.png")
    card.save(p_card, optimize=True)
    ink.save(p_ink, optimize=True)
    card.crop((0, 0, CELL, CELL)).save(p_def, optimize=True)
    for p in (p_card, p_ink, p_def):
        stub(p)
    print("gen_face_visor: %s, %s, %s" % tuple(os.path.relpath(p, ROOT) for p in (p_def, p_card, p_ink)))
    if "--sheet" in sys.argv:
        out = sys.argv[sys.argv.index("--sheet") + 1]
        sheet(out, card, ink)
        print("  sheet " + out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
