#!/usr/bin/env python3
"""Капсулы страницы Steam из арта codex (docs/plan-demo/CODEX_ART.md): кадр + надпись NULL GRAVITY (BRAND.md: Oswald,
NULL — белый, GRAVITY — оранжевый #ff8c33) + знак N0.

    python3 godot/tools/codex_art/steam_capsules.py        # → docs/steam/capsules/*.jpg (+ logo.png на прозрачности)

Размеры — правила Steam 2024 (header 920×430, small 462×174, main 1232×706, vertical 748×896, library 600×900,
hero 3840×1240 без надписи, logo 1280×720).

Hero (23.10): если есть docs/steam/hero_wide.jpg (codex, задание hero_wide в tools/codex_art/jobs_arena_ads.json;
кладёт tools/codex_art/arena_ads.py --codex DIR) — он, вписанный в 3840×1240. Иначе — без растяжения кадра:
keyart_wide 1672×941 по высоте 1240 (×1.32, раньше обрезка тянула его ×2.3) в центре, а бока — зеркальное продолжение
того же кадра, размытое и притемнённое, с мягким швом. Перед подачей в Steam всё равно лучше настоящий широкий арт.
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
STEAM = os.path.abspath(os.path.join(GODOT, "..", "docs", "steam"))
OUT = os.path.join(STEAM, "capsules")
FONT = os.path.join(GODOT, "assets", "fonts", "Oswald.ttf")
BADGE = os.path.join(GODOT, "assets", "ui", "brand", "null_gravity_badge_512.png")
WHITE = (255, 255, 255)
ORANGE = (255, 140, 51)

# имя → (размер, исходник, где надпись: "left" | "bottom" | None, centering кадра)
CAPSULES = {
    "header_920x430": ((920, 430), "keyart_wide.jpg", "left", (0.6, 0.5)),
    "small_462x174": ((462, 174), "keyart_wide.jpg", "left", (0.6, 0.5)),
    "main_1232x706": ((1232, 706), "keyart_wide.jpg", "left", (0.6, 0.5)),
    "vertical_748x896": ((748, 896), "capsule_tall.jpg", "bottom", (0.5, 0.4)),
    "library_600x900": ((600, 900), "capsule_tall.jpg", "bottom", (0.5, 0.4)),
}
HERO = ("library_hero_3840x1240", (3840, 1240))
HERO_WIDE = os.path.join(STEAM, "hero_wide.jpg")   # широкий арт codex (hero_wide), если сгенерирован


def font(px):
    f = ImageFont.truetype(FONT, px)
    try:
        f.set_variation_by_axes([700])     # Oswald — переменный шрифт, жирное начертание
    except Exception:
        pass
    return f


def shade(im, where):
    """Тёмная шторка под надписью, чтобы читалась на любом кадре."""
    w, h = im.size
    g = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(g)
    if where == "left":
        for x in range(w):
            a = max(0.0, 1.0 - x / (w * 0.62))
            d.line([(x, 0), (x, h)], fill=int(215 * a))
    else:
        for y in range(h):
            a = max(0.0, (y - h * 0.5) / (h * 0.5))
            d.line([(0, y), (w, y)], fill=int(225 * a))
    dark = Image.new("RGB", (w, h), (8, 10, 18))
    return Image.composite(dark, im, g)


def wordmark(size_px, stacked):
    """Надпись NULL GRAVITY на прозрачности: в строку или в два ряда."""
    f = font(size_px)
    parts = [("NULL", WHITE), ("GRAVITY", ORANGE)]
    boxes = [f.getbbox(t) for t, _ in parts]
    gap = int(size_px * 0.22)
    if stacked:
        w = max(b[2] - b[0] for b in boxes)
        h = sum(b[3] - b[1] for b in boxes) + gap
    else:
        w = sum(b[2] - b[0] for b in boxes) + gap
        h = max(b[3] - b[1] for b in boxes)
    pad = int(size_px * 0.12)
    im = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x, y = pad, pad
    for (t, col), b in zip(parts, boxes):
        d.text((x - b[0], y - b[1]), t, font=f, fill=col + (255,))
        if stacked:
            y += b[3] - b[1] + gap
        else:
            x += b[2] - b[0] + gap
    shadow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    shadow.putalpha(im.split()[3].filter(ImageFilter.GaussianBlur(size_px * 0.06)).point(lambda v: int(v * 0.8)))
    return Image.alpha_composite(shadow, im)


def capsule(size, src, where, centering):
    w, h = size
    im = ImageOps.fit(Image.open(os.path.join(STEAM, src)).convert("RGB"), size, Image.LANCZOS, centering=centering)
    if where is None:
        return im
    im = shade(im, where)
    badge = Image.open(BADGE).convert("RGBA")
    if where == "left":
        mark = wordmark(int(h * 0.2), stacked=True)
        bw = int(h * 0.3)
        b = badge.resize((bw, bw), Image.LANCZOS)
        x = int(w * 0.05)
        top = (h - (bw + mark.height)) // 2
        im.paste(b, (x, top), b)
        im.paste(mark, (x - int(h * 0.02), top + bw), mark)
    else:
        mark = wordmark(int(w * 0.17), stacked=False)
        if mark.width > w * 0.9:
            mark = mark.resize((int(w * 0.9), int(mark.height * w * 0.9 / mark.width)), Image.LANCZOS)
        bw = int(w * 0.22)
        b = badge.resize((bw, bw), Image.LANCZOS)
        y = h - mark.height - int(h * 0.05)
        im.paste(b, ((w - bw) // 2, y - bw), b)
        im.paste(mark, ((w - mark.width) // 2, y), mark)
    return im


def hero(size):
    """Library hero без надписи (Steam сам кладёт логотип): широкий арт codex или кадр с продолжением по бокам."""
    w, h = size
    if os.path.exists(HERO_WIDE):
        return ImageOps.fit(Image.open(HERO_WIDE).convert("RGB"), size, Image.LANCZOS, centering=(0.5, 0.45)), "hero_wide.jpg"
    src = Image.open(os.path.join(STEAM, "keyart_wide.jpg")).convert("RGB")
    cw = round(src.width * h / src.height)
    mid = src.resize((cw, h), Image.LANCZOS)
    # бока: тот же кадр зеркально по обе стороны, сильно размытый и притемнённый — цвет и свет купола продолжаются
    flip = ImageOps.mirror(mid)
    strip = Image.new("RGB", (cw * 3, h))
    strip.paste(flip, (0, 0))
    strip.paste(mid, (cw, 0))
    strip.paste(flip, (cw * 2, 0))
    x0 = (cw * 3 - w) // 2
    bg = strip.crop((x0, 0, x0 + w, h)).filter(ImageFilter.GaussianBlur(h * 0.03))
    bg = Image.blend(bg, Image.new("RGB", size, (8, 10, 18)), 0.45)
    # мягкий шов: центр плотный, к краям кадра (на ширину ~18 %) уходит в фон
    feather = int(cw * 0.18)
    m = Image.new("L", (cw, h), 255)
    d = ImageDraw.Draw(m)
    for x in range(feather):
        a = int(255 * (x / feather) ** 1.5)
        d.line([(x, 0), (x, h)], fill=a)
        d.line([(cw - 1 - x, 0), (cw - 1 - x, h)], fill=a)
    bg.paste(mid, ((w - cw) // 2, 0), m)
    return bg, "keyart_wide.jpg + бока"


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (size, src, where, centering) in CAPSULES.items():
        capsule(size, src, where, centering).save(os.path.join(OUT, name + ".jpg"), quality=90, optimize=True)
        print("ok", name)
    im, how = hero(HERO[1])
    im.save(os.path.join(OUT, HERO[0] + ".jpg"), quality=90, optimize=True)
    print("ok", HERO[0], "—", how)
    logo = Image.new("RGBA", (1280, 720), (0, 0, 0, 0))
    mark = wordmark(250, stacked=True)
    mark.thumbnail((1200, 680), Image.LANCZOS)
    logo.paste(mark, ((1280 - mark.width) // 2, (720 - mark.height) // 2), mark)
    logo.save(os.path.join(OUT, "library_logo_1280x720.png"), optimize=True)
    print("ok library_logo_1280x720")


if __name__ == "__main__":
    main()
