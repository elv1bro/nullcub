#!/usr/bin/env python3
"""Перевод 3D-текстур проекта на VRAM-сжатие (docs/plan-demo/PERF_PASS.md §4). Правит ТОЛЬКО *.import текстур в каталогах для 3D:
assets/textures/pbr, assets/models (кроме _texture_test*), assets/materials/kit. compress/mode=2 (VRAM), high_quality=false (S3TC: DXT1 4 бита/пиксель, у нормалей RGTC;
BPTC / BC7 тут не годится — кодирует ~8 текстур в минуту, импорт 1600 штук идёт часами), mipmaps/generate=true, у нормалей (имя содержит normal) compress/normal_map=1.
Не трогает: paint_stencils / fx / kit / workshop / ui / crowd / parallax (2D, данные для скриптов, жёсткий альфа-край) — их читают как
картинки (KitImages, WorkshopPaint._avg_colour) или рисуют в 2D.
Второй проход — размеры (PERF_PASS.md §8, process/size_limit): текстуры кукол (models/heroes/mannequin_v3/light|dark) — не больше 512 px
(кукла в кадре 100–250 px на деталь; были 1024² × 28 деталей × 3 карты = 67 МБ в КАЖДОЙ арене); normal / roughness / metallic пропсов, мастерской
и Свалки — не больше 512 px (альбедо остаётся как есть: в нём видна детализация, в нормалях и шероховатости на этих расстояниях — нет).
Атлас толпы (textures/crowd) — VRAM-сжатие без мипмапов (границы ячеек атласа на мипах текли бы).
Заходит один раз после появления новых текстур:  python3 godot/tools/texture_compress_pass.py [--check]
--check — ничего не пишет, печатает список 3D-текстур, оставшихся в Lossless или крупнее лимита (exit 1, если такие есть) — для гейта.
После правки: godot --headless --path godot --import (минуты: BPTC считается на CPU)."""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DIRS = ["assets/textures/pbr", "assets/models", "assets/materials/kit"]
SKIP_PREFIX = "_texture_test"
EXT = (".png.import", ".webp.import", ".jpg.import", ".jpeg.import")


# (подстрока пути, регулярка имени файла или None для всех, лимит стороны в пикселях)
SIZE_RULES = [
    ("assets/models/heroes/mannequin_v3/light/", None, 512),
    ("assets/models/heroes/mannequin_v3/dark/", None, 512),
    ("assets/models/props/", r"(normal|roughness|metallic)", 512),
    ("assets/models/workshop/", r"(normal|roughness|metallic)", 512),
    ("assets/models/scrap/", r"(normal|roughness|metallic)", 512),
]
# VRAM-сжатие без мипмапов: каталог -> файл
NO_MIPS = ["assets/textures/crowd/crowd_atlas.png"]


def size_limit_for(rel: str, name: str) -> int:
    for sub, rx, lim in SIZE_RULES:
        if sub in rel and (rx is None or re.search(rx, name, re.I)):
            return lim
    return 0


def want(path: str) -> bool:
    base = os.path.basename(path)
    return path.endswith(EXT) and not base.startswith(SKIP_PREFIX)


def patch(text: str, normal: bool, limit: int = 0, mips: bool = True) -> tuple[str, bool]:
    if 'importer="texture"' not in text:
        return text, False
    new = text
    sets = {"compress/mode": "2", "compress/high_quality": "false", "mipmaps/generate": "true" if mips else "false"}
    if normal:
        sets["compress/normal_map"] = "1"
    if limit:
        sets["process/size_limit"] = str(limit)
    for k, v in sets.items():
        new = re.sub(r"^%s=.*$" % re.escape(k), "%s=%s" % (k, v), new, flags=re.M)
    return new, new != text


def main() -> int:
    check = "--check" in sys.argv
    changed = 0
    lossless = []
    for d in DIRS:
        for root, _, files in os.walk(os.path.join(ROOT, d)):
            for f in files:
                p = os.path.join(root, f)
                if not want(p):
                    continue
                text = open(p, encoding="utf-8").read()
                rel = os.path.relpath(p, ROOT).replace(os.sep, "/")
                new, diff = patch(text, "normal" in f.lower(), size_limit_for(rel, f))
                if diff:
                    changed += 1
                    lossless.append(os.path.relpath(p, ROOT))
                    if not check:
                        open(p, "w", encoding="utf-8").write(new)
    # атлас толпы: сжатие без мипмапов
    for rel in NO_MIPS:
        p = os.path.join(ROOT, rel + ".import")
        if os.path.exists(p):
            text = open(p, encoding="utf-8").read()
            new, diff = patch(text, False, 0, False)
            if diff:
                changed += 1
                lossless.append(rel + ".import")
                if not check:
                    open(p, "w", encoding="utf-8").write(new)
    if check:
        for l in lossless[:40]:
            print("LOSSLESS", l)
        print("3D-текстур не по правилам (сжатие / лимит размера): %d" % len(lossless))
        return 1 if lossless else 0
    print("правлено .import: %d" % changed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
