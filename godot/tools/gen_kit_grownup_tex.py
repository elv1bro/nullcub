"""Текстуры «взрослого вида» кита (docs/plan-demo/grownup_art/, направление «Лига-про» + износ Свалки) — numpy + Pillow, без
исходников 2048² и без Blender. Запуск из корня репозитория:
    python3 godot/tools/gen_kit_grownup_tex.py            # пишет godot/assets/materials/kit/tex/<папка>/*.webp
    python3 godot/tools/gen_kit_grownup_tex.py --sheet P  # ещё и лист образцов (albedo / roughness / normal) в P
затем godot --headless --path godot --import, tools/build_body_kit.gd и tools/build_league.gd.

Все карты процедурные и бесшовные: шум — через спектр (FFT белого шума с затуханием 1/f^β — тайлится сам), царапины рисуются на
3×3 плитках и складываются по модулю. 512² как у прежних карт (CRAFT_TEX_SIZE): albedo / roughness / metallic — WebP q 92,
normal — WebP без потерь, OpenGL (Y+), как ждёт Godot. Нормаль — из карты высот (Собель с заворотом).

Папки (роли — MATS в tools/build_body_kit.gd и build_league.gd):
  worn_paint   — заводская краска / керамика со сколами до тёмного грунта, царапинами и копотью; почти белая, цвет даёт tint
                 (Base_Paint*, Base_Bone, Bone, Shirt_Kit — цвет игрока ложится на неё и тоже выходит потёртым).
  gunmetal     — тёмный воронёный металл, шлифовка вдоль, царапины по кромке (Iron, Steel, Base_Iron, Joint, Pin).
  oxide        — ржавая сталь: бурая окись пятнами, потёки, голый металл в промежутках (Rust, RustDark, Base_Rust).
  oxide_paint  — красный сурик поверх стали, сколы до ржавчины (RustRed, Base_RustRed).
  aged_wood / aged_wood_dark / aged_planks — выветренное дерево без мультяшных сучков: тонкое волокно, серый налёт, пятна масла.
  aged_brass   — латунь с патиной и светлыми царапинами (Brass, Base_Brass).
  rubber       — матовая резина с пылью; серая, тёмной её делает tint (Rubber, Base_Pink = «Резина»).
  carbon       — саржа углеволокна 2×2 под лаком (Pro_Carbon в build_league.gd).
Печатает средний линейный albedo каждой папки — по нему swatch (плашка материала в мастерской) в MATS."""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # godot/
OUT = os.path.join(ROOT, "assets", "materials", "kit", "tex")
N = 512
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/normal_map=%d
mipmaps/generate=true
detect_3d/compress_to=1
"""


# --- примитивы ---

def fbm(seed, beta=1.8, aniso=(1.0, 1.0), lo=1.0):
    """Бесшовный шум 0..1: белый шум через спектр 1/f^β. aniso — растяжение частот по (x, y): (1, 10) — полосы вдоль y.
    lo — нижняя частота (в периодах на тайл): ниже неё спектр срезан, чтобы не было одного пятна на весь тайл."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((N, N))
    fx = np.fft.fftfreq(N)[None, :] * N * aniso[0]
    fy = np.fft.fftfreq(N)[:, None] * N * aniso[1]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    amp = 1.0 / np.power(np.maximum(f, lo), beta)
    amp[0, 0] = 0.0
    r = np.real(np.fft.ifft2(np.fft.fft2(w) * amp))
    a, b = np.percentile(r, 0.5), np.percentile(r, 99.5)
    return np.clip((r - a) / (b - a), 0.0, 1.0)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def grow(mask, r):
    """Дилатация маски квадратом r (с заворотом) — кромка скола."""
    out = mask.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx or dy:
                out = np.maximum(out, np.roll(np.roll(mask, dy, 0), dx, 1))
    return out


def scratches(seed, count, length, width=1, angle=None, spread=180.0, strength=(0.4, 1.0)):
    """Маска царапин 0..1: отрезки на холсте 3N×3N, свёрнутые в тайл (бесшовно)."""
    rng = np.random.default_rng(seed)
    img = Image.new("L", (3 * N, 3 * N), 0)
    dr = ImageDraw.Draw(img)
    for _ in range(count):
        x, y = rng.uniform(N, 2 * N, 2)
        a = np.radians((angle if angle is not None else 0.0) + rng.uniform(-spread / 2, spread / 2))
        ln = rng.uniform(*length)
        v = int(255 * rng.uniform(*strength))
        # слегка изогнутая: два звена
        mx, my = x + np.cos(a) * ln / 2, y + np.sin(a) * ln / 2
        a2 = a + rng.uniform(-0.25, 0.25)
        ex, ey = mx + np.cos(a2) * ln / 2, my + np.sin(a2) * ln / 2
        dr.line([(x, y), (mx, my), (ex, ey)], fill=v, width=width)
    big = np.asarray(img, dtype=np.float32) / 255.0
    m = np.zeros((N, N), np.float32)
    for i in range(3):
        for j in range(3):
            m = np.maximum(m, big[i * N:(i + 1) * N, j * N:(j + 1) * N])
    return m


def lerp(a, b, t):
    t = t[..., None] if np.ndim(t) == 2 else t
    return np.asarray(a, np.float32) * (1.0 - t) + np.asarray(b, np.float32) * t


def col(rgb):
    return np.asarray(rgb, np.float32) / 255.0


def normal_from(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx, ny, nz = -dx * strength, dy * strength, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5


# --- материалы: каждый возвращает dict карт (albedo RGB 0..1 sRGB, roughness, metallic 0..1, height 0..1) ---

def chips_mask(seed, cover, scale=1.0):
    """Сколы краски: крупные пятна по низкой частоте × рваная кромка по высокой. cover — доля площади."""
    low = fbm(seed, 1.5, lo=5.0 * scale)
    high = fbm(seed + 1, 0.8, lo=12.0)
    v = low * 0.55 + high * 0.45
    t = np.percentile(v, 100.0 * (1.0 - cover))
    return (v > t).astype(np.float32)


def worn_paint(seed=11, base=(226, 223, 216), primer=(92, 94, 98), cover=0.018, grime=0.09, tiny_cover=0.003):
    mott = fbm(seed, 1.4, lo=4.0)
    fine = fbm(seed + 2, 0.6, lo=32.0)
    dirt = fbm(seed + 3, 2.0, lo=4.0)
    chip = chips_mask(seed + 5, cover)
    tiny = chips_mask(seed + 7, tiny_cover, 3.0)   # мелкие сколы: больше — и белое читалось «далматином» (кадр after 23.10)
    chip = np.maximum(chip, tiny)
    rim = np.clip(grow(chip, 2) - chip, 0, 1)
    scr = scratches(seed + 9, 70, (20, 140), 1, None, 180.0, (0.25, 0.8))
    scr_fine = scratches(seed + 10, 220, (6, 40), 1, None, 180.0, (0.1, 0.4))
    a = col(base)[None, None, :] * (0.95 + 0.05 * mott[..., None]) * (0.985 + 0.015 * fine[..., None])
    a = a * (1.0 - grime * smooth(0.35, 1.0, dirt))[..., None]
    a = lerp(a, a * 0.82, scr_fine * 0.6)
    a = lerp(a, col((150, 150, 152)), scr * 0.55)
    a = lerp(a, a * 0.85, rim * 0.5)                    # тёмная кромка скола (краска приподнята, под ней грязь)
    a = lerp(a, col(primer) * (0.85 + 0.3 * fine[..., None]), chip)
    rough = 0.6 + 0.08 * (mott - 0.5) + 0.12 * smooth(0.4, 1.0, dirt)
    rough = rough * (1.0 - 0.25 * scr) * (1.0 - 0.2 * chip)
    metal = chip * 0.55 + scr * 0.25
    h = 0.6 + 0.03 * fine - 0.35 * chip - 0.08 * scr - 0.03 * scr_fine
    return {"albedo": a, "roughness": rough, "metallic": metal, "height": h, "nstr": 5.0}


def gunmetal(seed=21):
    brush = fbm(seed, 1.0, aniso=(12.0, 1.0), lo=4.0)
    mott = fbm(seed + 1, 1.8, lo=3.0)
    dirt = fbm(seed + 2, 1.9, lo=5.0)
    pits = (fbm(seed + 3, 0.5, lo=64.0) > 0.93).astype(np.float32)
    scr = scratches(seed + 4, 90, (15, 120), 1, 0.0, 50.0, (0.3, 0.9))
    scr2 = scratches(seed + 5, 40, (10, 60), 1, None, 180.0, (0.3, 0.8))
    s = np.maximum(scr, scr2)
    base = col((104, 107, 113))
    a = base[None, None, :] * (0.88 + 0.16 * brush[..., None]) * (0.92 + 0.1 * mott[..., None])
    a = a * (1.0 - 0.16 * smooth(0.5, 1.0, dirt))[..., None]
    a = lerp(a, col((40, 38, 36)), pits * 0.7)
    a = lerp(a, col((178, 180, 184)), s * 0.75)
    rough = 0.42 + 0.1 * (brush - 0.5) + 0.18 * smooth(0.5, 1.0, dirt) + 0.2 * pits - 0.15 * s
    metal = np.clip(0.85 - 0.25 * smooth(0.5, 1.0, dirt) - 0.5 * pits, 0, 1)
    h = 0.5 + 0.04 * brush - 0.25 * pits - 0.12 * s
    return {"albedo": a, "roughness": rough, "metallic": metal, "height": h, "nstr": 4.0}


def oxide(seed=31):
    r = fbm(seed, 1.8, lo=3.0)
    s = fbm(seed + 1, 1.0, lo=12.0)
    s2 = fbm(seed + 2, 1.4, lo=6.0)
    streak = fbm(seed + 3, 1.2, aniso=(1.0, 14.0), lo=6.0)
    fleck = fbm(seed + 4, 0.4, lo=96.0)
    amt = smooth(0.38, 0.62, r * 0.68 + s * 0.32)
    steel = col((76, 74, 72)) * (0.9 + 0.2 * s2[..., None])
    rust = lerp(col((62, 37, 25)), col((112, 64, 36)), smooth(0.3, 0.8, s2))
    a = lerp(steel, rust, amt)
    a = lerp(a, col((138, 86, 50)), (fleck > 0.86).astype(np.float32) * amt * 0.7)
    a = a * (0.82 + 0.18 * streak[..., None])
    rough = 0.55 + 0.38 * amt + 0.05 * (fleck - 0.5)
    metal = (1.0 - amt) * 0.75
    h = 0.5 + 0.22 * amt * s + 0.06 * fleck - 0.1 * (fleck < 0.08)
    return {"albedo": a, "roughness": rough, "metallic": metal, "height": h, "nstr": 6.0}


def oxide_paint(seed=41):
    p = worn_paint(seed, base=(116, 38, 30), primer=(70, 42, 28), cover=0.16, grime=0.22, tiny_cover=0.012)
    ox = oxide(seed + 3)
    chip = chips_mask(seed + 5, 0.16)
    p["albedo"] = lerp(p["albedo"], ox["albedo"], chip)
    p["metallic"] = np.maximum(p["metallic"] * 0.3, chip * ox["metallic"])
    p["roughness"] = lerp(p["roughness"][..., None], ox["roughness"][..., None], chip)[..., 0]
    return p


def wood(seed=51, light=(132, 110, 88), dark=(84, 66, 52), planks=0, rings=34):
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32) / N
    warp = fbm(seed, 2.0, aniso=(1.0, 3.0), lo=1.0)
    warp2 = fbm(seed + 1, 1.6, aniso=(1.0, 4.0), lo=3.0)
    phase = np.zeros_like(xx)
    tone = np.zeros_like(xx)
    if planks:
        idx = np.floor(xx * planks)
        rng = np.random.default_rng(seed + 9)
        off = rng.uniform(0, 1, planks)
        sh = rng.uniform(-0.07, 0.07, planks)
        phase = off[idx.astype(int)]
        tone = sh[idx.astype(int)]
    g = np.sin(2 * np.pi * (rings * xx + 1.6 * warp + 0.35 * warp2 + phase * 7.0))
    ring = smooth(0.35, 1.0, g * 0.5 + 0.5) ** 2.0 * (0.55 + 0.45 * warp2)
    fib = fbm(seed + 2, 0.8, aniso=(1.0, 20.0), lo=40.0)
    fib2 = fbm(seed + 5, 1.1, aniso=(1.0, 8.0), lo=10.0)
    stain = fbm(seed + 3, 1.9, lo=4.0)
    a = lerp(col(light), col(dark), np.clip(ring * 0.42 + 0.33 * (1 - fib) + 0.25 * fib2, 0, 1))
    a = a * (1.0 + tone[..., None])
    grey = a.mean(-1, keepdims=True)
    a = a * 0.72 + grey * 0.28                                     # выветренный серый налёт
    a = a * (1.0 - 0.16 * smooth(0.6, 1.0, stain))[..., None]      # пятна масла
    h = 0.55 - 0.08 * ring - 0.1 * (1 - fib)
    if planks:
        u = (xx * planks) % 1.0
        seam = ((u < 0.012) | (u > 0.988)).astype(np.float32)
        a = lerp(a, col((30, 24, 20)), seam)
        h = h - 0.4 * seam
    scr = scratches(seed + 4, 30, (20, 90), 1, 90.0, 40.0, (0.2, 0.6))
    a = lerp(a, a * 1.25, scr * 0.4)
    rough = 0.72 + 0.12 * ring + 0.08 * smooth(0.55, 1.0, stain)
    return {"albedo": a, "roughness": rough, "metallic": None, "height": h, "nstr": 7.0}


def aged_brass(seed=61):
    brush = fbm(seed, 1.0, aniso=(10.0, 1.0), lo=4.0)
    pat = fbm(seed + 1, 1.5, lo=6.0)
    ver = fbm(seed + 2, 1.2, lo=8.0)
    scr = scratches(seed + 3, 70, (12, 110), 1, 0.0, 70.0, (0.3, 0.9))
    a = col((156, 122, 66))[None, None, :] * (0.9 + 0.14 * brush[..., None])
    pm = smooth(0.5, 0.95, pat)
    a = lerp(a, col((96, 80, 50)), pm * 0.55)
    a = lerp(a, col((82, 94, 74)), smooth(0.7, 0.95, pat * 0.6 + ver * 0.4) * 0.6)   # зелень в низинах
    a = lerp(a, col((214, 182, 118)), scr * 0.7)
    rough = 0.38 + 0.28 * pm - 0.15 * scr
    metal = np.clip(0.9 - 0.35 * pm, 0, 1)
    h = 0.5 + 0.05 * brush - 0.1 * scr + 0.05 * pm
    return {"albedo": a, "roughness": rough, "metallic": metal, "height": h, "nstr": 4.0}


def rubber(seed=71):
    fine = fbm(seed, 0.5, lo=48.0)
    mott = fbm(seed + 1, 1.6, lo=4.0)
    dust = fbm(seed + 2, 2.0, lo=3.0)
    a = col((132, 132, 132))[None, None, :] * (0.92 + 0.08 * fine[..., None]) * (0.95 + 0.06 * mott[..., None])
    a = lerp(a, col((190, 184, 172)), smooth(0.6, 1.0, dust) * 0.22)
    scr = scratches(seed + 3, 40, (8, 50), 1, None, 180.0, (0.2, 0.6))
    a = lerp(a, a * 1.3, scr * 0.5)
    rough = 0.82 + 0.1 * smooth(0.6, 1.0, dust) - 0.05 * fine
    h = 0.5 + 0.12 * fine - 0.1 * scr
    return {"albedo": a, "roughness": rough, "metallic": None, "height": h, "nstr": 3.0}


def carbon(seed=81, cell=16):
    yy, xx = np.mgrid[0:N, 0:N]
    i, j = xx // cell, yy // cell
    over = ((i - j) % 4) < 2                                       # саржа 2×2
    u = (xx % cell + 0.5) / cell
    v = (yy % cell + 0.5) / cell
    across = np.where(over, v, u)
    bulge = np.sin(np.pi * across) ** 0.6
    fib_h = fbm(seed, 0.5, aniso=(30.0, 1.0), lo=64.0)
    fib_v = fbm(seed + 1, 0.5, aniso=(1.0, 30.0), lo=64.0)
    fib = np.where(over, fib_h, fib_v)
    sheen = np.where(over, 1.0, 0.72)                              # «нити» поперёк ловят свет по-разному
    val = (0.07 + 0.11 * bulge * sheen) * (0.85 + 0.3 * fib)
    a = np.stack([val, val * 1.03, val * 1.08], -1)
    dirt = fbm(seed + 2, 2.0, lo=2.0)
    scr = scratches(seed + 3, 40, (10, 80), 1, None, 180.0, (0.2, 0.6))
    a = lerp(a, col((120, 122, 126)), scr * 0.35)
    rough = 0.28 + 0.2 * smooth(0.5, 1.0, dirt) + 0.25 * scr
    h = 0.5 + 0.25 * bulge
    return {"albedo": a, "roughness": rough, "metallic": None, "height": h.astype(np.float32), "nstr": 3.0}


FOLDERS = {
    "worn_paint": worn_paint,
    "gunmetal": gunmetal,
    "oxide": oxide,
    "oxide_paint": oxide_paint,
    "aged_wood": lambda: wood(51, (134, 110, 86), (86, 67, 52)),
    "aged_wood_dark": lambda: wood(55, (88, 68, 54), (46, 34, 27), rings=40),
    "aged_planks": lambda: wood(57, (128, 106, 84), (80, 63, 50), planks=4, rings=30),
    "aged_brass": aged_brass,
    "rubber": rubber,
    "carbon": carbon,
}


def to8(x):
    return (np.clip(x, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def write(folder, maps):
    d = os.path.join(OUT, folder)
    os.makedirs(d, exist_ok=True)
    out = {"albedo": to8(maps["albedo"]), "roughness": to8(maps["roughness"])}
    if maps.get("metallic") is not None:
        out["metallic"] = to8(maps["metallic"])
    out["normal"] = to8(normal_from(maps["height"].astype(np.float32), maps["nstr"]))
    for name, arr in out.items():
        p = os.path.join(d, name + ".webp")
        im = Image.fromarray(arr if arr.ndim == 3 else np.stack([arr] * 3, -1), "RGB")
        if name == "normal":
            im.save(p, lossless=True, method=6)
        else:
            im.save(p, quality=92, method=6)
        if not os.path.exists(p + ".import"):
            with open(p + ".import", "w") as f:
                f.write(IMPORT % (1 if name == "normal" else 0))
    lin = np.power(np.clip(maps["albedo"], 0, 1), 2.2).reshape(-1, 3).mean(0)
    return out, lin


def main(argv):
    sheet_path = argv[argv.index("--sheet") + 1] if "--sheet" in argv else None
    tiles = []
    for folder, fn in FOLDERS.items():
        maps = fn()
        out, lin = write(folder, maps)
        print("%-15s mean linear albedo [%.3f, %.3f, %.3f]" % (folder, lin[0], lin[1], lin[2]))
        tiles.append(out)
    if sheet_path:
        t = 256
        sheet = Image.new("RGB", (t * len(tiles), t * 3), (20, 20, 20))
        for i, out in enumerate(tiles):
            for r, key in enumerate(["albedo", "roughness", "normal"]):
                arr = out[key]
                im = Image.fromarray(arr if arr.ndim == 3 else np.stack([arr] * 3, -1), "RGB").resize((t, t), Image.LANCZOS)
                sheet.paste(im, (i * t, r * t))
        sheet.save(sheet_path)
        print("sheet", sheet_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
