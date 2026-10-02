#!/usr/bin/env python3
"""Перевод 3D-текстур проекта на VRAM-сжатие (docs/plan-demo/PERF_PASS.md §4). Правит ТОЛЬКО *.import текстур в каталогах для 3D:
assets/textures/pbr, assets/models (кроме _texture_test*), assets/materials/kit. compress/mode=2 (VRAM), high_quality=false (S3TC: DXT1 4 бита/пиксель, у нормалей RGTC;
BPTC / BC7 тут не годится — кодирует ~8 текстур в минуту, импорт 1600 штук идёт часами), mipmaps/generate=true, у нормалей (имя содержит normal) compress/normal_map=1.
Не трогает: paint_stencils / fx / kit / workshop / ui / crowd / parallax (2D, данные для скриптов, жёсткий альфа-край) — их читают как
картинки (KitImages, WorkshopPaint._avg_colour) или рисуют в 2D.
Заходит один раз после появления новых текстур:  python3 godot/tools/texture_compress_pass.py [--check]
--check — ничего не пишет, печатает список 3D-текстур, оставшихся в Lossless (exit 1, если такие есть) — для гейта производительности.
После правки: godot --headless --path godot --import (минуты: BPTC считается на CPU)."""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DIRS = ["assets/textures/pbr", "assets/models", "assets/materials/kit"]
SKIP_PREFIX = "_texture_test"
EXT = (".png.import", ".webp.import", ".jpg.import", ".jpeg.import")


def want(path: str) -> bool:
    base = os.path.basename(path)
    return path.endswith(EXT) and not base.startswith(SKIP_PREFIX)


def patch(text: str, normal: bool) -> tuple[str, bool]:
    if 'importer="texture"' not in text:
        return text, False
    new = text
    sets = {"compress/mode": "2", "compress/high_quality": "false", "mipmaps/generate": "true"}
    if normal:
        sets["compress/normal_map"] = "1"
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
                new, diff = patch(text, "normal" in f.lower())
                if diff:
                    changed += 1
                    lossless.append(os.path.relpath(p, ROOT))
                    if not check:
                        open(p, "w", encoding="utf-8").write(new)
    if check:
        for l in lossless[:40]:
            print("LOSSLESS", l)
        print("3D-текстур не на VRAM-сжатии: %d" % len(lossless))
        return 1 if lossless else 0
    print("правлено .import: %d" % changed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
