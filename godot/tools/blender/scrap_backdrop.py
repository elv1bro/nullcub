#!/usr/bin/env python3
"""THE SCRAP (биом 1 «Свалка») — фоновые конструкции среднего плана из 3D, запечённые в PNG с alpha для параллакса.

Зачем: хорошие отдельные элементы фона трудно добиться от генератора картинок (прозрачность, одинаковый свет, без подписей).
Здесь те же материалы, что у арены (scrap_kit.py: rust_metal, rust_painted_red, scrap_wood, флаги с короной), конструкции
строятся процедурно (фермы, краны, трубы, баки, мосты), каждая рендерится отдельно в орто-проекции спереди с прозрачным
фоном. В игре это плоские квады ParallaxScatter3D (docs/plan-demo/PARALLAX.md) — ни одного 3D-треугольника фона.

Свет — контражур заката: два солнца сзади-сверху (справа тёплое, слева розоватое) дают кайму с ОБЕИХ сторон силуэта,
слабый холодный заполняющий спереди — фасад тёмный, но читается; окна кабин светятся. Поэтому элементы можно зеркалить.

Запуск (headless):
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/scrap_backdrop.py -- out=/abs/dir
        [ppm=50] [ppm_fore=120] [sets=mid,fore] [only=Name,…]
        → <out>/mid/<Name>.png  — 19 конструкций среднего плана (фермы, краны, трубы, баки, мост, сараи, эстакада,
                                  бункер, цех, мачта, конвейер, ангар), основание (z = 0) у нижнего края, поля 1 м
        → <out>/fore/<Name>.png — 13 элементов переднего плана: подвешенные (цепи с крюком/магнитом/блоком, балка на
                                  цепях — верхнее поле 0, якорь top) и стоящие (шестерни, балки, кучи из моделей арены
                                  assets/models/scrap/{bodies,props}/*.glb)
    затем каждый файл → parallax_elements_cut.py --single --ppm <ppm> →
        godot/assets/textures/parallax/scrap_baked/{mid,fore}/ (+ manifest.json) — команды в docs/plan-demo/PARALLAX.md
Переменные окружения: SCRAP_BACKDROP_ENGINE=CYCLES (по умолчанию EEVEE), SCRAP_BACKDROP_SAMPLES.
Соглашения как у кита: метры, Blender Z вверх, лицо в −Y; seed конструкции — её номер.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402

# хелперы кита (Kit, материалы Свалки, g_box/g_prism/g_lathe, флаг, цепь, крюк) — модуль без вызова main() в конце
_KIT_PATH = os.path.join(HERE, "scrap_kit.py")
with open(_KIT_PATH) as _f:
    _src = _f.read()
_src = _src[:_src.rstrip().rfind("\nmain()")]
SK = {"__name__": "scrap_kit", "__file__": _KIT_PATH}
exec(compile(_src, _KIT_PATH, "exec"), SK)
Kit, g_box, g_prism, g_lathe, frame_x = SK["Kit"], SK["g_box"], SK["g_prism"], SK["g_lathe"], SK["frame_x"]
banner, chain, hook = SK["banner"], SK["chain"], SK["hook"]
RNG = SK["RNG"]
# тёмная красная краска: у фона на крупных площадях (труба, кабины) обычная RustRed читается игрушечно-розовой
SK["MAT_DEFS"]["RustRedDark"] = ("rust_painted_red", {"tint": (0.58, 0.46, 0.46, 1.0), "roughness_scale": 1.05},
                                 ((0.24, 0.05, 0.04, 1.0), 0.7, 0.1))



# ----------------------------------------------------------------------------------------------------------------------
# детали
# ----------------------------------------------------------------------------------------------------------------------
def member(K, p0, p1, s, mat="RustIron", d=None):
    """Брус сечением s × d (d — по глубине к камере) от p0 до p1."""
    p0, p1 = Vector(p0), Vector(p1)
    v = p1 - p0
    # крупная фаска: в орто спереди на ней ловится скользящий боковой свет — кайма по краям силуэта
    K.add(g_box(v.length, s, s if d is None else d, bevel=s * 0.2), mat, loc=(p0 + p1) / 2,
          rot=frame_x(v), along='X')


def truss_face(K, xl, xr, y, zs, girt=0.26, brace=0.15, mat="RustIron", pattern="X"):
    """Плоская ферма на глубине y: пояса на уровнях zs, раскосы X или N; xl/xr(z) — края."""
    for i, z in enumerate(zs):
        member(K, (xl(z), y, z), (xr(z), y, z), girt, mat)
        if i + 1 < len(zs):
            z2 = zs[i + 1]
            member(K, (xl(z), y, z), (xr(z2), y, z2), brace, mat)
            if pattern == "X":
                member(K, (xr(z), y, z), (xl(z2), y, z2), brace, mat)


def tower(K, cx, h, wb, wt, dep, bays, leg=0.42, legmat="RustIronDark"):
    """Ферменная башня-пирамида: 4 ноги, пояса и X-раскосы спереди и сзади, связи по глубине. Возвращает (xl, xr) верха."""
    def xl(z):
        return cx - (wb / 2 + (wt / 2 - wb / 2) * z / h)

    def xr(z):
        return cx + (wb / 2 + (wt / 2 - wb / 2) * z / h)
    # пролёты короче к верху — как у настоящих мачт
    w = [1.0 + 0.35 * (1.0 - i / max(bays - 1, 1)) for i in range(bays)]
    zs = [0.0]
    for k in w:
        zs.append(zs[-1] + h * k / sum(w))
    for y in (-dep / 2, dep / 2):
        member(K, (xl(0), y, 0), (xl(h), y, h), leg, legmat)
        member(K, (xr(0), y, 0), (xr(h), y, h), leg, legmat)
        truss_face(K, xl, xr, y, zs)
    for z in zs[1:]:
        for x in (xl(z), xr(z)):
            member(K, (x, -dep / 2, z), (x, dep / 2, z), 0.2)
    for x in (xl(0), xr(0)):   # башмаки
        K.add(g_box(leg * 2.2, dep + leg * 1.6, 0.35, bevel=0.04), "RustIronDark", loc=(x, 0, 0.175))
    for z in zs[1:-1]:          # косынки в узлах спереди
        for x, sg in ((xl(z), 1), (xr(z), -1)):
            K.add(g_prism([(0.0, -0.45), (0.0, 0.45), (sg * 0.55, 0.0)], 0.05, bevel=0.01), "RustIron",
                  loc=(x + sg * leg * 0.4, -dep / 2 - leg * 0.55, z))
    # труба вдоль правой ноги и фонари на части узлов
    pipe_x = lambda z: xr(z) - leg * 1.1
    member(K, (pipe_x(0), -dep / 2 - 0.5, 0.3), (pipe_x(h), -dep / 2 - 0.5, h * 0.96), 0.24, "RustRed")
    for k, z in enumerate(zs[1:-1]):
        if RNG.random() < 0.45:
            x = xl(z) if k % 2 else xr(z)
            K.add(g_box(0.28, 0.2, 0.36), "WindowGlow", loc=(x, -dep / 2 - leg * 0.9, z - 0.35), uv=False)
    # площадка с перилами на одном из поясов
    zp = zs[max(1, len(zs) // 2)]
    x0, x1 = xl(zp) - 1.2, xr(zp) + 1.2
    K.add(g_box(x1 - x0, dep + 0.6, 0.16, bevel=0.02), "ScrapWoodDark", loc=((x0 + x1) / 2, 0, zp + 0.08))
    member(K, (x0, -dep / 2 - 0.3, zp + 1.05), (x1, -dep / 2 - 0.3, zp + 1.05), 0.08, "RustIronDark")
    n = max(2, int((x1 - x0) / 0.9))
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i / n
        member(K, (x, -dep / 2 - 0.3, zp + 0.16), (x, -dep / 2 - 0.3, zp + 1.1), 0.07, "RustIronDark")
    return xl(h), xr(h)


def cabin(K, cx, z0, w, dep, hgt, wall="RustRedDark", roof=True, spire=True):
    K.add(g_box(w, dep, hgt, bevel=0.05), wall, loc=(cx, 0, z0 + hgt / 2))
    K.add(g_box(w + 0.5, dep + 0.5, 0.25, bevel=0.03), "RustIronDark", loc=(cx, 0, z0 + 0.12))
    n = max(2, int(w / 1.3))
    for i in range(n):
        x = cx - w / 2 + (i + 0.5) * w / n
        K.add(g_box(0.5, 0.08, hgt * 0.34), "WindowGlow", loc=(x, -dep / 2 - 0.03, z0 + hgt * 0.58), uv=False)
    top = z0 + hgt
    if roof:
        K.add(g_prism([(-w / 2 - 0.4, 0.0), (w / 2 + 0.4, 0.0), (0.0, hgt * 0.6)], dep + 0.5, bevel=0.03),
              "RustIronDark", loc=(cx, 0, top))
        top += hgt * 0.6
    if spire:
        member(K, (cx, 0, top - 0.2), (cx, 0, top + hgt * 0.9), 0.14, "RustIronDark")
        K.add(g_lathe([(0.0, -0.2), (0.22, 0.0), (0.0, 0.25)], 8), "Brass", loc=(cx, 0, top + hgt * 0.9))
    return top


def flag(K, cx, top, w, h, y):
    K.xf = Matrix.Translation((0, y, 0))
    banner(K, cx, top, w, h)
    K.xf = Matrix.Identity(4)


def bucket(K, top, r=1.1, mat="RustIronDark"):
    """Ковш на цепи: усечённый конус открытым верхом + ручка-дуга."""
    top = Vector(top)
    K.add(g_lathe([(r, 0.0), (r * 1.08, -0.08), (r * 0.72, -r * 1.2), (0.0, -r * 1.25)], 12), mat,
          loc=top + Vector((0, 0, -0.6)))
    member(K, top + Vector((-r, 0, -0.6)), top, 0.1, mat)
    member(K, top + Vector((r, 0, -0.6)), top, 0.1, mat)


def magnet(K, top, r=1.3):
    top = Vector(top)
    K.add(g_lathe([(0.0, 0.0), (r, 0.0), (r, -0.55), (r * 0.9, -0.7), (0.0, -0.7)], 16), "RustRed",
          loc=top + Vector((0, 0, -0.5)))
    for a in (-0.6, 0.6):
        member(K, top + Vector((a, 0, -0.5)), top, 0.09, "RustIronDark")


# ----------------------------------------------------------------------------------------------------------------------
# конструкции (origin — центр основания, z = 0 — низ)
# ----------------------------------------------------------------------------------------------------------------------
def lattice_tower(name, h, seed, flag_on=True):
    RNG.seed(seed)
    K = Kit(name)
    wb, wt = RNG.uniform(3.4, 4.2), RNG.uniform(2.2, 2.8)
    tower(K, 0, h, wb, wt, 2.6, int(h / 3.2))
    top = cabin(K, 0, h, wt * 1.45, 3.2, 2.4)
    if flag_on:
        flag(K, 0, h * 0.62, 1.6, 2.6, -1.9)
    # подвесная цепь с крюком сбоку
    x = wt / 2 + 0.3
    end = chain(K, [Vector((x, -1.4, h - 0.2)), Vector((x, -1.4, h - 4.5))], R=0.09, r=0.028)
    hook(K, end, scale=2.0)
    return K.finish()


def gantry_crane(name, h, seed):
    RNG.seed(seed)
    K = Kit(name)
    tower(K, 0, h, 3.0, 2.2, 2.4, int(h / 3.0))
    jr, jl = RNG.uniform(10.0, 13.0), RNG.uniform(4.5, 6.0)
    zb, zt = h + 0.3, h + 2.2
    y = -0.7
    member(K, (-jl, y, zb), (jr, y, zb), 0.34)
    member(K, (-jl, y, zt), (jr, y, zb + 0.5), 0.26)
    x = -jl
    step = 2.2
    while x < jr - 0.1:
        x2 = min(x + step, jr)
        zt1 = zt + (zb + 0.5 - zt) * (x + jl) / (jr + jl)
        zt2 = zt + (zb + 0.5 - zt) * (x2 + jl) / (jr + jl)
        member(K, (x, y, zb), (x, y, zt1), 0.16)
        member(K, (x, y, zb), (x2, y, zt2), 0.14)
        x = x2
    # оголовок и тяги
    peak = Vector((0, y, h + 6.0))
    member(K, (-1.1, y, zt), peak, 0.3, "RustIronDark")
    member(K, (1.1, y, zt), peak, 0.3, "RustIronDark")
    member(K, peak, (jr, y, zb + 0.5), 0.08, "RustIronDark")
    member(K, peak, (-jl, y, zt), 0.08, "RustIronDark")
    K.add(g_box(2.4, 2.0, 2.2, bevel=0.05), "RustIronDark", loc=(-jl + 1.3, y, zb - 1.1))  # противовес
    K.add(g_box(2.6, 2.4, 2.0, bevel=0.05), "RustRedDark", loc=(1.6, y, zb - 1.0))        # кабина крановщика
    K.add(g_box(0.5, 0.08, 0.6), "WindowGlow", loc=(1.6, y - 1.23, zb - 0.9), uv=False)
    flag(K, 0, h * 0.55, 1.5, 2.4, -1.8)
    # тележка и подвес
    tx = jr * RNG.uniform(0.55, 0.8)
    K.add(g_box(1.2, 1.4, 0.6, bevel=0.04), "RustIronDark", loc=(tx, y, zb - 0.45))
    drop = RNG.uniform(5.0, 8.0)
    member(K, (tx - 0.25, y, zb - 0.7), (tx - 0.25, y, zb - drop), 0.07, "RustIronDark")
    member(K, (tx + 0.25, y, zb - 0.7), (tx + 0.25, y, zb - drop), 0.07, "RustIronDark")
    if seed % 2:
        magnet(K, (tx, y, zb - drop))
    else:
        bucket(K, (tx, y, zb - drop))
    return K.finish()


def smokestack(name, h, seed):
    RNG.seed(seed)
    K = Kit(name)
    r0, r1 = RNG.uniform(1.5, 1.8), RNG.uniform(1.0, 1.2)
    K.add(g_lathe([(0.0, 0.0), (r0, 0.0), (r1, h), (r1 * 1.18, h), (r1 * 1.18, h + 0.6), (r1 * 0.95, h + 0.6),
                   (r1 * 0.95, h)], 28), "RustRedDark", along='Z')
    for k in range(1, int(h / 3.5)):
        z = k * 3.5
        r = r0 + (r1 - r0) * z / h
        K.add(g_lathe([(r + 0.06, -0.14), (r + 0.1, 0.0), (r + 0.06, 0.14), (r - 0.05, 0.14), (r - 0.05, -0.14)],
                      28), "RustIronDark", loc=(0, 0, z))
    zp = h * 0.62
    rp = r0 + (r1 - r0) * zp / h
    K.add(g_lathe([(rp, 0.0), (rp + 1.0, 0.0), (rp + 1.0, 0.12), (rp, 0.12)], 28), "RustIronDark", loc=(0, 0, zp))
    for a in range(9):            # стойки перил площадки спереди
        ang = math.pi * (1.1 + 0.8 * a / 8)
        p = Vector(((rp + 0.9) * math.cos(ang), (rp + 0.9) * math.sin(ang), zp))
        member(K, p, p + Vector((0, 0, 1.1)), 0.07, "RustIronDark")
    # лестница спереди
    lx = r0 * 0.45
    for s in (-0.3, 0.3):
        member(K, (lx + s, -r0 - 0.25, 0.0), (lx * 0.8 + s, -r1 - 0.25, h * 0.95), 0.08, "RustIronDark")
    z = 0.4
    while z < h * 0.93:
        t = z / h
        xc = lx + (lx * 0.8 - lx) * t
        yy = -(r0 + (r1 - r0) * t) - 0.25
        member(K, (xc - 0.3, yy, z), (xc + 0.3, yy, z), 0.05, "RustIronDark")
        z += 0.45
    K.add(g_box(r0 * 2.6, r0 * 2.6, 1.2, bevel=0.06), "RustIronDark", loc=(0, 0, 0.6))    # цоколь
    return K.finish()


def water_tank(name, h_legs, seed):
    RNG.seed(seed)
    K = Kit(name)
    R = RNG.uniform(3.0, 3.6)
    H = RNG.uniform(4.0, 5.0)
    tower(K, 0, h_legs, R * 2.1, R * 1.7, R * 1.5, max(3, int(h_legs / 3.2)))
    z0 = h_legs
    K.add(g_lathe([(0.0, 0.0), (R * 0.95, 0.0), (R, 0.3), (R, H), (R * 0.2, H + R * 0.55), (0.0, H + R * 0.6)],
                  32), "RustIron", loc=(0, 0, z0), along='Z')
    for k in (0.12, 0.45, 0.78):
        z = z0 + H * k
        K.add(g_lathe([(R + 0.08, -0.12), (R + 0.12, 0.0), (R + 0.08, 0.12), (R - 0.05, 0.12), (R - 0.05, -0.12)],
                      32), "RustIronDark", loc=(0, 0, z))
    K.add(g_box(0.9, 0.1, 0.7), "RustRed", loc=(-R * 0.3, -R - 0.05, z0 + H * 0.62))            # бирка-заплатка
    member(K, (0, 0, z0 + H + R * 0.6), (0, 0, z0 + H + R * 0.6 + 2.0), 0.12, "RustIronDark")
    flag(K, R * 0.35, z0 + H * 0.92, 1.4, 2.2, -R - 0.25)
    return K.finish()


def bridge_pair(name, span, h1, h2, seed):
    RNG.seed(seed)
    K = Kit(name)
    xa, xb = -span / 2 - 1.6, span / 2 + 1.6
    tower(K, xa, h1, 3.4, 2.4, 2.6, int(h1 / 3.2))
    cabin(K, xa, h1, 3.4, 3.0, 2.2)
    tower(K, xb, h2, 3.6, 2.6, 2.6, int(h2 / 3.2))
    cabin(K, xb, h2, 3.6, 3.0, 2.3, wall="ScrapWood")
    zb = min(h1, h2) * 0.72
    zt = zb + 2.4
    x0, x1 = xa + 1.2, xb - 1.2
    for y in (-1.0, 1.0):
        member(K, (x0, y, zb), (x1, y, zb), 0.3)
        member(K, (x0, y, zt), (x1, y, zt), 0.26)
        n = max(2, int((x1 - x0) / 2.4))
        for i in range(n + 1):
            x = x0 + (x1 - x0) * i / n
            member(K, (x, y, zb), (x, y, zt), 0.16)
            if i < n:
                xn = x0 + (x1 - x0) * (i + 1) / n
                member(K, (x, y, zb) if i % 2 == 0 else (x, y, zt), (xn, y, zt) if i % 2 == 0 else (xn, y, zb), 0.13)
    K.add(g_box(x1 - x0, 1.8, 0.3, bevel=0.03), "ScrapWoodDark", loc=((x0 + x1) / 2, 0, zt + 0.18))    # лента конвейера
    for k in range(3):                                   # ковши под мостом на цепях
        x = x0 + (x1 - x0) * (0.25 + 0.25 * k)
        end = chain(K, [Vector((x, -1.2, zb - 0.1)), Vector((x, -1.2, zb - RNG.uniform(1.8, 3.2)))], R=0.08, r=0.025)
        bucket(K, end, r=0.8)
    flag(K, xb, h2 * 0.5, 1.5, 2.4, -1.9)
    return K.finish()


def shed_on_stilts(name, h, seed):
    """Сарай на ферменной площадке: доски, крыша из листа, печная труба, лестница."""
    RNG.seed(seed)
    K = Kit(name)
    w = RNG.uniform(5.0, 6.5)
    tower(K, 0, h, w * 0.8, w * 0.7, 3.0, max(2, int(h / 3.0)))
    K.add(g_box(w + 1.4, 3.8, 0.25, bevel=0.03), "ScrapWoodDark", loc=(0, 0, h + 0.12))
    sh = RNG.uniform(3.0, 3.8)
    K.add(g_box(w, 3.0, sh, bevel=0.04), "ScrapWood", loc=(0, 0, h + 0.25 + sh / 2), along='Z')
    for k in range(int(w / 0.8)):                        # нащельники
        x = -w / 2 + 0.4 + k * 0.8
        K.add(g_box(0.12, 0.06, sh * 0.96), "ScrapWoodDark", loc=(x, -1.53, h + 0.25 + sh / 2), along='Z')
    for x in (-w * 0.28, w * 0.22):
        K.add(g_box(0.9, 0.08, 0.8), "WindowGlow", loc=(x, -1.58, h + 0.25 + sh * 0.55), uv=False)
    rz = h + 0.25 + sh
    K.add(g_prism([(-w / 2 - 0.7, 0.0), (w / 2 + 0.7, 0.0), (w * 0.15, 1.7)], 3.6, bevel=0.02), "RustIron",
          loc=(0, 0, rz))
    sx = w * 0.3
    member(K, (sx, 0.6, rz), (sx, 0.6, rz + 2.8), 0.3, "RustIronDark")
    K.add(g_lathe([(0.35, 0.0), (0.55, 0.25), (0.0, 0.35)], 8), "RustIronDark", loc=(sx, 0.6, rz + 2.8))
    lx = -w * 0.5 - 0.9                                  # лестница сбоку
    for s_ in (-0.28, 0.28):
        member(K, (lx + s_, -1.3, 0.0), (lx + s_, -1.3, h + 1.0), 0.07, "RustIronDark")
    z = 0.4
    while z < h + 0.8:
        member(K, (lx - 0.28, -1.3, z), (lx + 0.28, -1.3, z), 0.05, "RustIronDark")
        z += 0.45
    if seed % 2:
        flag(K, 0, h * 0.7, 1.4, 2.2, -1.8)
    return K.finish()


def pipe_rack(name, h, seed):
    """Эстакада трубопровода: П-рамы, 3–4 трубы с фланцами, стояк вверх с дефлектором, вентили."""
    RNG.seed(seed)
    K = Kit(name)
    L = RNG.uniform(16.0, 20.0)
    xs = [-L / 2 + L * k / 3 for k in range(4)]
    for x in xs:
        for y in (-1.2, 1.2):
            member(K, (x - 1.4, y, 0.0), (x - 1.4, y, h), 0.36, "RustIronDark")
            member(K, (x + 1.4, y, 0.0), (x + 1.4, y, h), 0.36, "RustIronDark")
            member(K, (x - 1.8, y, h), (x + 1.8, y, h), 0.34)
            member(K, (x - 1.4, y, h * 0.5), (x + 1.4, y, h * 0.5), 0.22)
            member(K, (x - 1.4, y, 0.0), (x + 1.4, y, h * 0.5), 0.14)
    pipes = [("RustRedDark", 0.55, -0.6), ("RustIron", 0.42, 0.4), ("RustIronDark", 0.32, 1.2)]
    for k, (mat, r, dz) in enumerate(pipes):
        z = h + 0.35 + r + (0.0 if k == 0 else dz)
        g = g_lathe([(0.0, 0.0), (r, 0.0), (r, L + 4.0), (0.0, L + 4.0)], 16)
        K.add(g, mat, loc=(-L / 2 - 2.0, -0.6 + 0.6 * k, z), rot=(0, math.pi / 2, 0))
        for f in range(int(L / 3.0)):
            fx = -L / 2 + f * 3.0
            K.add(g_lathe([(r + 0.1, -0.08), (r + 0.1, 0.08), (r, 0.08), (r, -0.08)], 16), "RustIronDark",
                  loc=(fx, -0.6 + 0.6 * k, z), rot=(0, math.pi / 2, 0))
    rx = L * RNG.uniform(0.1, 0.3)
    rz0 = h + 0.9
    K.add(g_lathe([(0.0, 0.0), (0.5, 0.0), (0.5, h * 0.9), (0.0, h * 0.9)], 16), "RustRedDark", loc=(rx, -0.6, rz0))
    K.add(g_lathe([(0.3, 0.0), (0.95, 0.35), (0.95, 0.55), (0.0, 0.7)], 12), "RustIronDark",
          loc=(rx, -0.6, rz0 + h * 0.9 + 0.3))
    for k in range(2):                                   # вентили-штурвалы
        vx = -L / 3 + k * L / 2.5
        K.add(SK["g_torus"](0.45, 0.06, 14, 4), "RustRed", loc=(vx, -1.5, h + 1.6), rot=(math.pi / 2, 0, 0))
        member(K, (vx, -1.5, h + 1.1), (vx, -1.5, h + 1.6), 0.1, "RustIronDark")
    return K.finish()


def hopper(name, h, seed):
    """Бункер: короб на ферме, воронка вниз, наклонный желоб, цепи."""
    RNG.seed(seed)
    K = Kit(name)
    w = RNG.uniform(6.0, 7.5)
    tower(K, 0, h, w * 0.85, w * 0.8, 4.0, max(2, int(h / 3.2)))
    bh = RNG.uniform(4.0, 5.0)
    K.add(g_box(w, 4.2, bh, bevel=0.06), "RustIron", loc=(0, 0, h + 1.2 + bh / 2), along='Z')
    for k in range(3):
        K.add(g_box(w + 0.2, 4.4, 0.25, bevel=0.03), "RustIronDark", loc=(0, 0, h + 1.2 + bh * (0.15 + 0.35 * k)))
    K.add(g_lathe([(w * 0.55, 0.0), (0.7, -2.6), (0.7, -3.2), (0.0, -3.2)], 4, phase=math.pi / 4), "RustIronDark",
          loc=(0, 0, h + 1.25))
    member(K, (0.4, -0.3, h - 2.0), (w * 0.9, -0.3, h * 0.35), 1.1, "RustRedDark", d=1.4)          # желоб
    K.add(g_box(1.8, 0.1, 1.0), "RustRed", loc=(-w * 0.2, -2.15, h + 1.2 + bh * 0.62))
    K.add(g_box(0.5, 0.08, 0.5), "WindowGlow", loc=(w * 0.3, -2.15, h + 1.2 + bh * 0.62), uv=False)
    return K.finish()


def factory_block(name, seed):
    """Цех: массивный корпус со светящимися окнами, пилообразная крыша, две трубы. Даёт массу за фермами."""
    RNG.seed(seed)
    K = Kit(name)
    W, H, D = RNG.uniform(13.0, 16.0), RNG.uniform(8.0, 9.5), 7.0
    K.add(g_box(W, D, H, bevel=0.08), "RustIronDark", loc=(0, 0, H / 2), along='Z')
    for k in range(int(W / 1.2)):                        # рёбра профнастила
        x = -W / 2 + 0.6 + k * 1.2
        K.add(g_box(0.14, 0.1, H * 0.98), "RustIron", loc=(x, -D / 2 - 0.04, H / 2), along='Z')
    for row in range(2):
        for k in range(int(W / 2.2)):
            if RNG.random() < 0.25:
                continue
            x = -W / 2 + 1.3 + k * 2.2
            K.add(g_box(1.2, 0.1, 1.4), "WindowGlow", loc=(x, -D / 2 - 0.1, H * (0.35 + 0.35 * row)), uv=False)
    n = 4
    for k in range(n):                                   # пилообразная крыша
        x0 = -W / 2 + W * k / n
        K.add(g_prism([(0.0, 0.0), (W / n, 0.0), (W / n, 2.2)], D, bevel=0.02), "RustIron", loc=(x0, 0, H))
    for k, (sx, sh) in enumerate(((-W * 0.3, RNG.uniform(9, 12)), (W * 0.2, RNG.uniform(6, 8)))):
        r = 0.9 - 0.2 * k
        K.add(g_lathe([(0.0, 0.0), (r * 1.2, 0.0), (r, sh), (r * 1.15, sh), (r * 1.15, sh + 0.4), (r * 0.9, sh + 0.4),
                       (r * 0.9, sh)], 20), "RustRedDark", loc=(sx, 0.8, H + 1.0), along='Z')
    K.add(g_box(3.4, 0.2, 4.2), "RustIronDark", loc=(W * 0.32, -D / 2 - 0.12, 2.1))                 # ворота
    flag(K, -W * 0.08, H * 0.92, 1.6, 2.6, -D / 2 - 0.25)
    return K.finish()


def signal_mast(name, h, seed):
    """Высокая тонкая мачта с фонарями, площадками и растяжками."""
    RNG.seed(seed)
    K = Kit(name)
    tower(K, 0, h, 2.0, 0.9, 1.6, int(h / 2.6), leg=0.3)
    for z in (h * 0.45, h * 0.8):
        K.add(g_box(3.0, 2.4, 0.15), "RustIronDark", loc=(0, 0, z))
        K.add(g_box(0.35, 0.2, 0.35), "WindowGlow", loc=(1.3, -1.25, z + 0.3), uv=False)
    K.add(g_lathe([(0.0, 0.0), (0.45, 0.0), (0.5, 0.6), (0.0, 1.0)], 10), "WindowGlow", loc=(0, 0, h + 0.1), uv=False)
    for sgn in (-1, 1):                                  # растяжки
        member(K, (sgn * 0.5, -0.2, h * 0.85), (sgn * h * 0.32, -0.2, 0.2), 0.05, "RustIronDark")
    return K.finish()


def incline_conveyor(name, seed):
    """Наклонный конвейер от земли к верху башни на опорах, ковши на ленте."""
    RNG.seed(seed)
    K = Kit(name)
    th = RNG.uniform(13.0, 16.0)
    tower(K, 6.0, th, 3.4, 2.6, 2.8, int(th / 3.2))
    cabin(K, 6.0, th, 3.6, 3.2, 2.4)
    p0, p1 = Vector((-10.0, 0.0, 1.2)), Vector((5.0, 0.0, th - 0.8))
    d = (p1 - p0).normalized()
    up = Vector((-d.z, 0, d.x))
    for y in (-0.9, 0.9):
        member(K, p0 + Vector((0, y, 0)), p1 + Vector((0, y, 0)), 0.3)
        member(K, p0 + up * 1.6 + Vector((0, y, 0)), p1 + up * 1.6 + Vector((0, y, 0)), 0.22)
        n = int((p1 - p0).length / 2.2)
        for k in range(n + 1):
            q = p0 + (p1 - p0) * k / n
            member(K, q + Vector((0, y, 0)), q + up * 1.6 + Vector((0, y, 0)), 0.13)
            if k < n:
                q2 = p0 + (p1 - p0) * (k + 1) / n
                member(K, q + Vector((0, y, 0)), q2 + up * 1.6 + Vector((0, y, 0)), 0.11)
    for k in range(1, 4):                                # опоры
        q = p0 + (p1 - p0) * k / 4
        member(K, (q.x - 0.8, -0.9, 0.0), (q.x, -0.9, q.z), 0.28, "RustIronDark")
        member(K, (q.x + 0.8, -0.9, 0.0), (q.x, -0.9, q.z), 0.28, "RustIronDark")
    for k in range(6):
        q = p0 + (p1 - p0) * (0.1 + 0.15 * k) + up * 1.9
        K.add(g_box(0.8, 1.2, 0.6, bevel=0.03), "RustIronDark", loc=q, rot=frame_x(d))
    return K.finish()


def hangar(name, seed):
    """Ангар с арочной крышей: сплошная арка-призма, рёбра, большие ворота. Масса у земли."""
    RNG.seed(seed)
    K = Kit(name)
    R = RNG.uniform(6.0, 7.5)
    D = 8.0
    n = 16
    arc = [(R * math.cos(math.pi * k / n), R * 0.8 * math.sin(math.pi * k / n) + 3.0) for k in range(n + 1)]
    K.add(g_prism([(R, 0.0)] + arc + [(-R, 0.0)], D, bevel=0.03), "RustIron", loc=(0, 0, 0))
    for k in range(n):                                   # рёбра арки спереди
        (xa, za), (xb, zb) = arc[k], arc[k + 1]
        member(K, (xa, -D / 2 - 0.1, za), (xb, -D / 2 - 0.1, zb), 0.3, "RustIronDark")
    for k in range(int(2 * R / 1.4)):
        x = -R + 0.7 + k * 1.4
        top = 3.0 + R * 0.8 * math.sqrt(max(0.0, 1.0 - (x / R) ** 2))
        K.add(g_box(0.1, 0.1, top - 0.2), "RustIronDark", loc=(x, -D / 2 - 0.05, (top - 0.2) / 2), along='Z')
    K.add(g_box(R * 0.9, 0.2, 5.0), "RustRedDark", loc=(0, -D / 2 - 0.15, 2.5))                       # ворота
    K.add(g_box(R * 0.9 + 0.4, 0.3, 0.3), "RustIronDark", loc=(0, -D / 2 - 0.25, 5.1))
    for x in (-R * 0.65, R * 0.65):
        K.add(g_box(1.0, 0.1, 0.8), "WindowGlow", loc=(x, -D / 2 - 0.1, 3.4), uv=False)
    flag(K, -R * 0.62, 7.0, 1.5, 2.4, -D / 2 - 0.3)
    return K.finish()


def stack_pair(name, seed):
    RNG.seed(seed)
    K = Kit(name)
    for k, (x, h) in enumerate(((-2.4, RNG.uniform(17, 20)), (2.6, RNG.uniform(13, 15)))):
        r0, r1 = 1.4 - 0.2 * k, 0.95 - 0.1 * k
        K.add(g_lathe([(0.0, 0.0), (r0, 0.0), (r1, h), (r1 * 1.18, h), (r1 * 1.18, h + 0.5), (r1 * 0.95, h + 0.5),
                       (r1 * 0.95, h)], 24), "RustIronDark" if k else "RustRedDark", loc=(x, 0, 0), along='Z')
        for z in range(3, int(h), 3):
            r = r0 + (r1 - r0) * z / h
            K.add(g_lathe([(r + 0.06, -0.12), (r + 0.09, 0.0), (r + 0.06, 0.12), (r - 0.05, 0.12), (r - 0.05, -0.12)],
                          24), "RustIron", loc=(x, 0, z))
    zb = 9.5
    member(K, (-2.4, -1.4, zb), (2.6, -1.4, zb), 0.26)
    member(K, (-2.4, -1.4, zb + 1.1), (2.6, -1.4, zb + 1.1), 0.1, "RustIronDark")
    for k in range(6):
        x = -2.4 + 5.0 * k / 5
        member(K, (x, -1.4, zb), (x, -1.4, zb + 1.1), 0.08, "RustIronDark")
    K.add(g_box(9.0, 5.0, 2.2, bevel=0.05), "RustIronDark", loc=(0.1, 0, 1.1))
    return K.finish()


# ----------------------------------------------------------------------------------------------------------------------
# передний план: почти чёрные силуэты (в игре ещё и затемнены шейдером), крупно — 180 пкс/м
# ----------------------------------------------------------------------------------------------------------------------
GLB_DIR = os.path.join(SK["GODOT"], "assets", "models", "scrap")


def import_glb(sub, name, loc=(0, 0, 0), rot_z=0.0, scale=1.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(GLB_DIR, sub, name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:                     # корни импорта (меш или пустышка-родитель) — сдвиг, поворот, масштаб
        if o.parent is None:
            o.location = Vector(loc) + o.location * scale
            o.rotation_euler.z += rot_z
            o.scale = o.scale * scale
    bpy.context.view_layer.update()
    return [o for o in new if o.type == 'MESH']


def hanging_chain(name, length, seed, end="hook"):
    """Цепь от верхнего края (z = 0 — точка подвеса, всё висит вниз) с крюком / магнитом / блоком."""
    RNG.seed(seed)
    K = Kit(name)
    K.add(g_box(0.8, 0.5, 0.3, bevel=0.04), "RustIronDark", loc=(0, 0, 0.15))
    tip = chain(K, [Vector((0, 0, 0.0)), Vector((0, 0, -length))], R=0.13, r=0.04)
    if end == "hook":
        hook(K, tip, scale=3.2)
    elif end == "magnet":
        magnet(K, tip, r=1.0)
    elif end == "block":
        K.add(g_box(0.7, 0.5, 1.1, bevel=0.06), "RustRedDark", loc=tip + Vector((0, 0, -0.55)))
        K.add(SK["g_torus"](0.28, 0.07, 12, 4), "RustIronDark", loc=tip + Vector((0, -0.28, -0.4)),
              rot=(math.pi / 2, 0, 0))
        hook(K, tip + Vector((0, 0, -1.1)), scale=2.4)
    return K.finish()


def hanging_beam(name, seed):
    """Две цепи держат двутавр."""
    RNG.seed(seed)
    K = Kit(name)
    L = RNG.uniform(4.5, 6.0)
    drop = RNG.uniform(3.5, 5.0)
    for x in (-L * 0.35, L * 0.35):
        K.add(g_box(0.6, 0.5, 0.3), "RustIronDark", loc=(x, 0, 0.15))
        chain(K, [Vector((x, 0, 0.0)), Vector((x, 0, -drop))], R=0.12, r=0.036)
    tilt = RNG.uniform(-0.08, 0.08)
    a, b = Vector((-L / 2, 0, -drop - 0.3 - tilt * L)), Vector((L / 2, 0, -drop - 0.3 + tilt * L))
    member(K, a, b, 0.55, "RustIronDark", d=0.4)
    for k in range(4):
        q = a + (b - a) * (0.2 + 0.2 * k)
        K.add(SK["g_lathe"]([(0.12, 0.0), (0.0, 0.0)], 10), "RustIron", loc=q + Vector((0, -0.21, 0)),
              rot=(math.pi / 2, 0, 0), uv=False)
    return K.finish()


def big_gear(name, r, teeth, seed):
    """Шестерня стоймя на земле: цельный обод-кольцо, зубья по кругу, 5 спиц, ступица."""
    RNG.seed(seed)
    K = Kit(name)
    cz = r * 1.12
    rim = 0.16 * r
    t = 0.22
    ring = g_lathe([(r - rim, -t), (r, -t), (r, t), (r - rim, t), (r - rim, -t)], 48)
    K.add(ring, "RustIronDark", loc=(0, 0, cz), rot=(math.pi / 2, 0, 0))
    for i in range(teeth):
        a = TAU * i / teeth + RNG.uniform(-0.02, 0.02)
        q = Vector((math.cos(a) * (r + 0.07 * r), 0, cz + math.sin(a) * (r + 0.07 * r)))
        K.add(g_box(0.2 * r, 0.4, 0.17 * r, bevel=0.02), "RustIronDark", loc=q, rot=(0, -a, 0))
    for k in range(5):
        a = TAU * k / 5 + RNG.uniform(0, 1)
        member(K, (0, 0, cz), (math.cos(a) * (r - rim * 0.8), 0, cz + math.sin(a) * (r - rim * 0.8)), 0.1 * r,
               "RustIronDark", d=0.3)
    K.add(g_lathe([(0.0, -0.3), (0.22 * r, -0.3), (0.22 * r, 0.3), (0.0, 0.3)], 16), "RustIron", loc=(0, 0, cz),
          rot=(math.pi / 2, 0, 0))
    K.add(g_box(0.5 * r, 0.8, 0.45, bevel=0.04), "RustIronDark", loc=(r * 0.6, 0, 0.22))   # подпирающий брусок
    return K.finish()


def tilted_beams(name, seed):
    RNG.seed(seed)
    K = Kit(name)
    L = RNG.uniform(6.0, 7.5)
    a = math.radians(RNG.uniform(55, 68))
    member(K, (-L * math.cos(a) / 2, 0, 0.0), (L * math.cos(a) / 2, 0, L * math.sin(a)), 0.5, "RustIronDark", d=0.4)
    b = math.radians(RNG.uniform(20, 30))
    member(K, (-0.4, 0.3, 0.0), (-0.4 + 4.5 * math.cos(b), 0.3, 4.5 * math.sin(b)), 0.35, "ScrapWoodDark")
    K.add(g_box(1.4, 1.0, 0.7, bevel=0.05), "RustIronDark", loc=(0.9, 0, 0.35))
    return K.finish()


def glb_pile(name, parts):
    """Куча из моделей арены: [(sub, glb, (x, y, z), rot_z, scale)]."""
    objs = []
    for sub, glb, loc, rz, sc in parts:
        objs += import_glb(sub, glb, loc, rz, sc)
    return objs


MID = [
    ("Tower_A", lambda: lattice_tower("Tower_A", 17.0, 1)),
    ("Tower_B", lambda: lattice_tower("Tower_B", 13.0, 2, flag_on=False)),
    ("Tower_C", lambda: lattice_tower("Tower_C", 21.0, 11)),
    ("Crane_A", lambda: gantry_crane("Crane_A", 14.0, 3)),
    ("Crane_B", lambda: gantry_crane("Crane_B", 11.0, 4)),
    ("Crane_C", lambda: gantry_crane("Crane_C", 18.0, 13)),
    ("Stack_A", lambda: smokestack("Stack_A", 19.0, 5)),
    ("Stack_Pair", lambda: stack_pair("Stack_Pair", 15)),
    ("Tank_A", lambda: water_tank("Tank_A", 10.0, 6)),
    ("Tank_B", lambda: water_tank("Tank_B", 6.5, 16)),
    ("Bridge_A", lambda: bridge_pair("Bridge_A", 11.0, 15.0, 12.5, 7)),
    ("Shed_A", lambda: shed_on_stilts("Shed_A", 8.0, 21)),
    ("Shed_B", lambda: shed_on_stilts("Shed_B", 11.0, 22)),
    ("Pipes_A", lambda: pipe_rack("Pipes_A", 7.0, 23)),
    ("Hopper_A", lambda: hopper("Hopper_A", 9.0, 24)),
    ("Factory_A", lambda: factory_block("Factory_A", 25)),
    ("Mast_A", lambda: signal_mast("Mast_A", 26.0, 26)),
    ("Conveyor_A", lambda: incline_conveyor("Conveyor_A", 27)),
    ("Hangar_A", lambda: hangar("Hangar_A", 28)),
]
FORE = [
    ("Chain_Hook", lambda: hanging_chain("Chain_Hook", 7.5, 31, "hook"), True),
    ("Chain_Magnet", lambda: hanging_chain("Chain_Magnet", 5.5, 32, "magnet"), True),
    ("Chain_Block", lambda: hanging_chain("Chain_Block", 6.5, 33, "block"), True),
    ("Chain_Short", lambda: hanging_chain("Chain_Short", 3.5, 34, "hook"), True),
    ("Hanging_Beam", lambda: hanging_beam("Hanging_Beam", 35), True),
    ("Gear_Big", lambda: big_gear("Gear_Big", 2.4, 14, 36), False),
    ("Gear_Small", lambda: big_gear("Gear_Small", 1.5, 10, 37), False),
    ("Beams_Tilted", lambda: tilted_beams("Beams_Tilted", 38), False),
    ("Pile_Massive", lambda: glb_pile("Pile_Massive", [("bodies", "Scrap_Heap_Massive", (0, 0, 0), 0.0, 1.0)]),
     False),
    ("Pile_Gears", lambda: glb_pile("Pile_Gears", [("bodies", "Gear_Heap", (-1.2, 0, 0), 0.3, 1.3),
                                                   ("bodies", "Broken_Weapons_Pile", (1.3, 0, 0), -0.4, 1.3)]), False, 2.2),
    ("Pile_Limbs", lambda: glb_pile("Pile_Limbs", [("bodies", "Puppet_Limb_Pile", (0, 0, 0), 0.2, 1.4),
                                                   ("props", "Wooden_Beam_Stack", (1.9, 0.4, 0), 0.5, 1.1)]), False, 2.2),
    ("Wagon", lambda: glb_pile("Wagon", [("props", "Rail_Scrap_Wagon_Full", (0, 0, 0), 0.0, 1.0)]), False, 2.2),
    ("Barrels_Pipes", lambda: glb_pile("Barrels_Pipes", [("props", "Metal_Barrel_Dented", (-1.3, 0, 0), 0.3, 1.2),
                                                         ("props", "Broken_Crate_A", (-0.1, 0.3, 0), -0.4, 1.2),
                                                         ("props", "Pipe_Bundle", (1.6, 0.4, 0), -0.25, 1.3)]), False, 2.2),
]
TAU = 2.0 * math.pi


# ----------------------------------------------------------------------------------------------------------------------
# рендер
# ----------------------------------------------------------------------------------------------------------------------
def sun(scn, name, direction, col, energy, angle=4.0):
    ld = bpy.data.lights.new(name, 'SUN')
    ld.color = col
    ld.energy = energy
    ld.angle = math.radians(angle)
    lo = bpy.data.objects.new(name, ld)
    scn.collection.objects.link(lo)
    lo.rotation_euler = Vector((0, 0, -1)).rotation_difference(Vector(direction).normalized()).to_euler()
    return lo


def setup_render(scn):
    engine = os.environ.get("SCRAP_BACKDROP_ENGINE", "EEVEE")
    ok = False
    if engine.startswith("EEVEE"):
        for eng in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
            try:
                scn.render.engine = eng
                ok = True
                break
            except Exception:
                pass
        if ok:
            try:
                scn.eevee.taa_render_samples = int(os.environ.get("SCRAP_BACKDROP_SAMPLES", "48"))
                scn.eevee.use_shadows = True
                scn.eevee.use_raytracing = True
            except Exception:
                pass
    if not ok:
        scn.render.engine = 'CYCLES'
        scn.cycles.samples = int(os.environ.get("SCRAP_BACKDROP_SAMPLES", "64"))
        scn.cycles.use_denoising = True
    scn.render.film_transparent = True
    scn.render.image_settings.file_format = 'PNG'
    scn.render.image_settings.color_mode = 'RGBA'
    scn.view_settings.view_transform = 'Standard'
    scn.view_settings.look = 'None'
    scn.view_settings.exposure = 0.0
    # «контражур» для орто-вида спереди: задний свет спереди не виден вовсе, поэтому два солнца светят почти вдоль
    # фасада — справа (тёплое) и слева (розоватое), чуть сверху и чуть сзади: на фасад почти не попадают, а фаски,
    # верхи и торцы деталей горят — кайма с обеих сторон силуэта; спереди — слабый холодный заполняющий
    sun(scn, "RimR", (-0.9, 0.12, -0.42), (1.0, 0.6, 0.32), 5.5, 2.0)
    sun(scn, "RimL", (0.9, 0.12, -0.42), (1.0, 0.5, 0.45), 4.0, 2.0)
    sun(scn, "FillFront", (0.05, 0.95, -0.3), (0.62, 0.62, 0.9), 0.45, 25.0)
    world = bpy.data.worlds.new("World")
    scn.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (0.09, 0.075, 0.13, 1.0)
    bg.inputs['Strength'].default_value = 0.55


def bbox(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    return (min(p.x for p in pts), max(p.x for p in pts), min(p.z for p in pts), max(p.z for p in pts))


def render_one(scn, cam, objs, path, ppm, hanging=False):
    """Кадр по bbox группы с полями 1 м; у подвешенных верхнее поле 0 — точка подвеса на верхнем краю (якорь top)."""
    x0, x1, z0, z1 = bbox(objs)
    m = 1.0
    top = 0.0 if hanging else m
    w, h = (x1 - x0) + 2 * m, (z1 - z0) + m + top
    scn.render.resolution_x = int(math.ceil(w * ppm))
    scn.render.resolution_y = int(math.ceil(h * ppm))
    scn.render.resolution_percentage = 100
    cam.data.ortho_scale = max(w, h)
    cam.location = ((x0 + x1) / 2, -200.0, z1 + top - h / 2)
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("render %s %dx%d (%.1f × %.1f м)" % (os.path.basename(path), scn.render.resolution_x,
                                               scn.render.resolution_y, x1 - x0, z1 - z0))


def main():
    args = dict(a.split("=", 1) for a in C.args_after_dashdash() if "=" in a)
    out = args.get("out", "/tmp/ragdoll_scrap_backdrop")
    ppm_mid = float(args.get("ppm", "50"))
    ppm_fore = float(args.get("ppm_fore", "120"))
    only = set(args["only"].split(",")) if "only" in args else None
    sets = args.get("sets", "mid,fore").split(",")
    C.reset_scene()
    # светящиеся окна — в словарь материалов кита (Kit.finish берёт материалы по имени через M()); после reset_scene
    SK["_MATS"]["WindowGlow"] = C.material("WindowGlow", (0.12, 0.06, 0.02, 1.0), 0.6, 0.0,
                                           emission=(1.0, 0.5, 0.16, 1.0), emission_strength=2.2)
    scn = bpy.context.scene
    setup_render(scn)
    cd = bpy.data.cameras.new("Cam")
    cd.type = 'ORTHO'
    cd.clip_end = 1000.0
    cam = bpy.data.objects.new("Cam", cd)
    scn.collection.objects.link(cam)
    cam.rotation_euler = (math.pi / 2, 0, 0)
    scn.camera = cam
    jobs = []   # (подпапка, имя, объекты, ppm, подвешен)
    for set_name, table, ppm in (("mid", MID, ppm_mid), ("fore", FORE, ppm_fore)):
        if set_name not in sets:
            continue
        for row in table:
            name, build = row[0], row[1]
            if only and name not in only:
                continue
            o = build()
            objs = o if isinstance(o, list) else [o]
            tris = sum(len(p.vertices) - 2 for ob in objs for p in ob.data.polygons)
            print("%s/%s: %d треугольников" % (set_name, name, tris))
            ppm_row = ppm * (row[3] if len(row) > 3 else 1.0)   # 4-й элемент строки — множитель ppm
            jobs.append((set_name, name, objs, ppm_row, len(row) > 2 and row[2]))
    all_objs = [ob for j in jobs for ob in j[2]]
    ppm_used = {}
    for set_name, name, objs, ppm, hanging in jobs:
        for ob in all_objs:
            ob.hide_render = ob not in objs
        d = os.path.join(out, set_name)
        os.makedirs(d, exist_ok=True)
        render_one(scn, cam, objs, os.path.join(d, name + ".png"), ppm, hanging)
        ppm_used.setdefault(set_name, {})[name] = ppm
    import json
    for set_name, table in ppm_used.items():      # масштаб каждого рендера — для manifest (m_per_px)
        with open(os.path.join(out, set_name, "_ppm.json"), "w") as f:
            json.dump(table, f, indent=1)
    if SK["FLAT_USED"]:
        print("FLAT:", sorted(SK["FLAT_USED"]))


main()
