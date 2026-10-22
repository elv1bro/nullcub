#!/usr/bin/env python3
"""Раскладывает картинки codex (tools/codex_art/codex_gen.py) по игре (docs/plan-demo/CODEX_ART.md).

    python3 godot/tools/codex_art/apply_art.py <папка с png из codex>

Плакаты и фото гаража — в assets/textures/garage/ под размеры и имена прежних заглушек (UV моделей рассчитаны на эти
пропорции, роли материалов Poster_*/Photo_*/BannerCloth в scripts/menu/garage_materials.gd); фото — в бумажной рамке,
как раньше. Ключевой арт — фон лоадера (assets/ui/brand/keyart.jpg) и исходники для магазина в docs/steam/.
Нет файла — пропуск (можно перегенерировать одну картинку).
"""
import os
import sys

from PIL import Image, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAR = os.path.join(GODOT, "assets", "textures", "garage")
BRAND = os.path.join(GODOT, "assets", "ui", "brand")
STEAM = os.path.abspath(os.path.join(GODOT, "..", "docs", "steam"))

sys.path.insert(0, os.path.join(GODOT, "tools"))
from gen_garage_textures import _paper_frame  # noqa: E402

# id → (папка, имя, размер, рамка)
GARAGE = {
    "poster_a": (GAR, "poster_a.png", (408, 620), 0),
    "poster_b": (GAR, "poster_b.png", (408, 620), 0),
    "poster_c": (GAR, "poster_c.png", (408, 620), 0),
    "photo_a": (GAR, "photo_a.png", (340, 290), 10),
    "photo_b": (GAR, "photo_b.png", (340, 290), 10),
    "photo_c": (GAR, "photo_c.png", (340, 290), 10),
    "photo_d": (GAR, "photo_d.png", (340, 290), 10),
    "photo_e": (GAR, "photo_e.png", (340, 290), 10),
    "photo_f": (GAR, "photo_f.png", (340, 290), 10),
    "banner": (GAR, "banner.png", (512, 832), 0),
    "keyart_wide": (BRAND, "keyart.jpg", (1920, 1080), 0),
}
# исходники для магазина / пресс-кита: полный размер, jpg 92
STORE = {"keyart_wide": "keyart_wide.jpg", "capsule_tall": "capsule_tall.jpg", "emblem": "league_emblem.jpg",
         "poster_a": "poster_null_league.jpg", "poster_b": "poster_live.jpg", "poster_c": "poster_zero_g.jpg"}


def fit(im, size, border):
    inner = (size[0] - 2 * border, size[1] - 5 * border)   # _paper_frame: рамка border, снизу ещё 3×border
    im = ImageOps.fit(im.convert("RGB"), inner, Image.LANCZOS, centering=(0.5, 0.45))
    return _paper_frame(im, border) if border else im


def main():
    src = sys.argv[1]
    os.makedirs(STEAM, exist_ok=True)
    for jid, (folder, name, size, border) in GARAGE.items():
        p = os.path.join(src, jid + ".png")
        if not os.path.exists(p):
            print("skip", jid)
            continue
        out = fit(Image.open(p), size, border)
        dst = os.path.join(folder, name)
        if name.endswith(".jpg"):
            out.save(dst, quality=86, optimize=True, progressive=False)
        else:
            out.save(dst, optimize=True)
        print("ok", jid, "→", os.path.relpath(dst, GODOT), out.size)
    for jid, name in STORE.items():
        p = os.path.join(src, jid + ".png")
        if os.path.exists(p):
            Image.open(p).convert("RGB").save(os.path.join(STEAM, name), quality=92, optimize=True)
            print("store", name)


if __name__ == "__main__":
    main()
