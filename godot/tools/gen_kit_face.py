"""Картинки материалов кита тела v2 (docs/plan-demo/BODY_KIT.md §2) — Pillow, без Blender и Godot. Запуск из корня репозитория:
    python3 godot/tools/gen_kit_face.py
затем godot --headless --path godot --import и tools/build_body_kit.gd (builder ссылается на эти файлы из Face.tres и Base_*.tres).

Пишет в godot/assets/materials/kit/:
  face_default.png — 256² мультяшное лицо на «фотокарточке» (как face_material() в tools/blender/kit_common.py: тёплая
      фотобумага, белая кайма, глаза с бликом, румянец, улыбка-дуга). В игре сюда потом ляжет фото игрока (этап 10).
  tex/<папка>/<карта>.webp — копии assets/textures/pbr/<папка>/{albedo,roughness,normal,metallic}.png, уменьшенные до 512²
      (как CRAFT_TEX_SIZE деталей крафта в glb), с мип-мапами (.import-заготовка ниже). Исходники 2048² импортированы без мип-мапов
      и без сжатия: ~16 МБ видеопамяти на карту, ~0.5 ГБ на кит — и мерцание мелких деталей. albedo/roughness/metallic — WebP
      с потерями (q 92), normal — WebP без потерь (подвыборка цвета портит X/Y нормали).
Идемпотентно: копия пересоздаётся, если исходник новее; .import-заготовка пишется, только если файла ещё нет (Godot дописывает его сам).
Список папок = папки таблицы MATS в tools/build_body_kit.gd (там же запасной путь на исходник, если копии нет)."""
import math
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # godot/
PBR = os.path.join(ROOT, "assets", "textures", "pbr")
OUT = os.path.join(ROOT, "assets", "materials", "kit")
TEX_SIZE = 512
FOLDERS = ["wood", "maple_light", "wood_dark", "wood_plank", "walnut_dark", "paint_marks", "rust_painted_red", "iron", "rust_metal",
           "brass_worn", "rope"]
MAPS = ["albedo", "roughness", "normal", "metallic"]
IMPORT_STUB = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
mipmaps/generate=true
"""


def face(path, n=256):
    """Порт face_material(): v — снизу вверх (как пиксели Blender), в PNG строка 0 — верх, поэтому y = n − 1 − j.
    Значения — байты картинки ×255 (у байтовой картинки Blender pixels = sRGB как есть; так лицо и выглядит на кадре стиля)."""
    img = Image.new("RGB", (n, n))
    px = img.load()
    for j in range(n):
        v = j / (n - 1)
        for i in range(n):
            u = i / (n - 1)
            r, g, b = 0.80, 0.62, 0.42          # фотобумага, тёплая
            if min(u, v, 1 - u, 1 - v) < 0.035:
                r, g, b = 0.93, 0.88, 0.78      # белая кайма карточки
            for ex in (0.32, 0.68):             # глаза с бликом
                du, dv = (u - ex) / 0.075, (v - 0.58) / 0.11
                if du * du + dv * dv < 1.0:
                    r, g, b = 0.02, 0.02, 0.025
                    hu, hv = (u - ex + 0.022) / 0.024, (v - 0.625) / 0.03
                    if hu * hu + hv * hv < 1.0:
                        r, g, b = 0.9, 0.9, 0.9
            for cx in (0.2, 0.8):               # румянец
                du, dv = (u - cx) / 0.08, (v - 0.4) / 0.05
                if du * du + dv * dv < 1.0:
                    r, g, b = r * 0.9 + 0.08, g * 0.7, b * 0.7
            d = math.hypot(u - 0.5, v - 0.47)   # улыбка: дуга окружности
            if abs(d - 0.2) < 0.018 and v < 0.36:
                r, g, b = 0.12, 0.03, 0.02
            px[i, n - 1 - j] = (round(r * 255), round(g * 255), round(b * 255))
    img.save(path, optimize=True)


def stub(path):
    if not os.path.exists(path + ".import"):
        with open(path + ".import", "w") as f:
            f.write(IMPORT_STUB)


def textures():
    made, kept, missing = 0, 0, []
    for folder in FOLDERS:
        for m in MAPS:
            src = os.path.join(PBR, folder, m + ".png")
            dst = os.path.join(OUT, "tex", folder, m + ".webp")
            if not os.path.exists(src):
                if m != "metallic" and not (m == "normal" and folder == "paint_marks"):
                    missing.append(os.path.relpath(src, ROOT))
                continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
                kept += 1
            else:
                # альфа отбрасывается: материалы кита непрозрачные, Blender берёт Color без альфы. У paint_marks альфа почти
                # везде 0 — WebP под нулевой альфой обнуляет RGB, и краска выходила чёрной
                im = Image.open(src).convert("RGB")
                if im.size != (TEX_SIZE, TEX_SIZE):
                    im = im.resize((TEX_SIZE, TEX_SIZE), Image.LANCZOS)
                if m == "normal":
                    im.save(dst, lossless=True, method=6)
                else:
                    im.save(dst, quality=92, method=6)
                made += 1
            stub(dst)
    return made, kept, missing


def main():
    os.makedirs(OUT, exist_ok=True)
    face_path = os.path.join(OUT, "face_default.png")
    face(face_path)
    stub(face_path)
    made, kept, missing = textures()
    print("gen_kit_face: face %s, textures %d new / %d up to date%s" % (
        os.path.relpath(face_path, ROOT), made, kept, (", MISSING " + ", ".join(missing)) if missing else ""))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
