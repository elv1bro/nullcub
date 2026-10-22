#!/usr/bin/env python3
"""Капсулы страницы Steam из арта codex (docs/plan-demo/CODEX_ART.md): кадр + надпись NULL GRAVITY (BRAND.md: Oswald,
NULL — белый, GRAVITY — оранжевый #ff8c33) + знак N0.

    python3 godot/tools/codex_art/steam_capsules.py        # → docs/steam/capsules/*.jpg (+ logo.png на прозрачности)

Размеры — правила Steam 2024 (header 920×430, small 462×174, main 1232×706, vertical 748×896, library 600×900,
hero 3840×1240 без надписи, logo 1280×720). Исходник keyart_wide 1672×941: для hero он растянут — перед подачей
нужен рендер крупнее.
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
    "library_hero_3840x1240": ((3840, 1240), "keyart_wide.jpg", None, (0.5, 0.45)),
}


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


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (size, src, where, centering) in CAPSULES.items():
        capsule(size, src, where, centering).save(os.path.join(OUT, name + ".jpg"), quality=90, optimize=True)
        print("ok", name)
    logo = Image.new("RGBA", (1280, 720), (0, 0, 0, 0))
    mark = wordmark(250, stacked=True)
    mark.thumbnail((1200, 680), Image.LANCZOS)
    logo.paste(mark, ((1280 - mark.width) // 2, (720 - mark.height) // 2), mark)
    logo.save(os.path.join(OUT, "library_logo_1280x720.png"), optimize=True)
    print("ok library_logo_1280x720")


if __name__ == "__main__":
    main()
