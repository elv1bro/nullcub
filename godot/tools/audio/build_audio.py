#!/usr/bin/env python3
"""Сборка всех звуков игры (docs/plan-demo/AUDIO.md §3) из CC0-исходников в кэше + синтеза.

    python3 godot/tools/audio/fetch_audio_sources.py      # один раз: исходники в кэш (~42 МБ, вне git)
    python3 godot/tools/audio/build_audio.py              # всё → godot/assets/audio/**, LICENSES.md, отчёт громкости
    python3 godot/tools/audio/build_audio.py --only sfx   # группа: sfx | crowd | amb | loops | machines | enemies | ui | music

Каждый слой — папка с вариантами (*.ogg); SfxDirector / CrowdDirector грузят слой как AudioStreamRandomizer. Громкость
нормализована по BS.1770: короткие звуки — по максимальной моментальной громкости (LUFS-M), петли и музыка — по интегральной;
true-peak ≤ −1 dBTP. Баланс слоёв — в коде (LAYER_DB), здесь только единый уровень внутри группы. Нужны numpy, scipy, ffmpeg.

Группы и уровни: sfx −14 LUFS-M (моно), crowd one-shot −16 LUFS-M (стерео), петли толпы −20 LUFS (стерео), фон арен −26 LUFS
(стерео), петли движения/машин −20 LUFS (моно), машины/враги −14 LUFS-M, ui −18 LUFS-M, музыка −16 LUFS.
"""
import argparse
import glob
import json
import os
import shutil
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import audio_dsp as d  # noqa: E402
from fetch_audio_sources import cache_dir  # noqa: E402

GODOT = os.path.normpath(os.path.join(HERE, "..", ".."))
REPO = os.path.normpath(os.path.join(GODOT, ".."))
OUT = os.path.join(GODOT, "assets", "audio")
CACHE = cache_dir()
KEN = os.path.join(CACHE, "kenney")
FS = os.path.join(CACHE, "freesound")

rng = np.random.default_rng(29)
REPORT = []          # [{path, group, lufs, tp, dur}]
USED = {}            # группа/слой -> set(источник)


# --- источники ---

def click():
    """Один щелчок metalClick (в файле их три)."""
    return d.fade(d.cut(K("rpg", "metalClick"), 0.05, 0.16), 0.0005, 0.02)


def K(pack, name):
    """Kenney: pack ∈ impact | rpg | ui | scifi."""
    folder = {"impact": "impact-sounds", "rpg": "rpg-audio", "ui": "interface-sounds", "scifi": "sci-fi-sounds"}[pack]
    _use(f"kenney:{folder}")
    return d.trim(d.load(os.path.join(KEN, folder, "Audio", name + ".ogg")), -55)


def F(sid, ss=None, t=None, stereo=False):
    _use(f"freesound:{sid}")
    return d.load(os.path.join(FS, f"{sid}.ogg"), ss, t, stereo)


def LOCAL(rel, ss=None, t=None, stereo=False):
    _use(f"local:{rel}")
    return d.load(os.path.join(REPO, rel), ss, t, stereo)


_cur_layer = [""]


def _use(src):
    USED.setdefault(_cur_layer[0], set()).add(src)


# --- запись ---

def out_layer(group, layer, variants, target, mode="momentary", stereo=False, ceiling=-1.0):
    """Пишет варианты слоя в assets/audio/<group>/<layer>/<layer>_NN.ogg (папка очищается)."""
    folder = os.path.join(OUT, group, layer)
    if os.path.isdir(folder):
        for f in glob.glob(os.path.join(folder, "*.ogg")):
            os.remove(f)
    for i, x in enumerate(variants):
        if stereo:
            x = d.to_stereo(x)
        elif x.ndim == 2:
            x = d.mono(x)
        y = d.norm_loudness(x, target, mode, ceiling)
        p = os.path.join(folder, f"{layer}_{i + 1:02d}.ogg")
        d.write_ogg(p, y)
        _report(p, group, y, mode)
    print(f"  {group}/{layer}: {len(variants)}")


def out_file(group, name, x, target, mode="integrated", stereo=False, loop_xfade=None, ceiling=-1.0):
    """Один файл assets/audio/<group>/<name>.ogg; loop_xfade — бесшовная петля с перекрытием (с)."""
    if stereo:
        x = d.to_stereo(x, 0.0)
    elif x.ndim == 2:
        x = d.mono(x)
    if loop_xfade:
        x = d.make_loop(x, loop_xfade)
    y = d.norm_loudness(x, target, mode, ceiling)
    p = os.path.join(OUT, group, name + ".ogg")
    d.write_ogg(p, y)
    _report(p, group, y, mode)
    print(f"  {group}/{name}.ogg {len(y) / d.SR:.1f}s")


def _report(p, group, y, mode):
    REPORT.append({"path": os.path.relpath(p, GODOT), "group": group, "mode": mode,
                   "lufs": round(d.momentary_max(y) if mode == "momentary" else d.integrated(y), 2),
                   "tp": round(d.true_peak_db(y), 2), "dur": round(len(y) / d.SR, 3)})


def layer(name):
    _cur_layer[0] = name


# --- общие заготовки ---

def snaps():
    """Короткие сухие трески дерева (транзиенты для heavy/crit/отрыва), 0.06–0.3 с."""
    out = []
    ply = F("518791")
    for s0, s1 in d.split(ply, -28, 0.05, 0.03)[:40]:
        c = d.cut(ply, s0, min(s1, s0 + 0.3))
        if d.momentary_max(c) > -40:
            out.append(c)
    for sid in ("637746", "322416", "845993"):
        x = F(sid)
        for s0, s1 in d.split(x, -30, 0.05, 0.03)[:8]:
            out.append(d.cut(x, s0, min(s1, s0 + 0.3)))
    out = [d.fade(d.hp(c, 400), 0.0005, 0.04) for c in out if len(c) > d.ns(0.03)]
    out.sort(key=lambda c: -np.max(np.abs(c)) / (np.sqrt(np.mean(c ** 2)) + 1e-9))   # самые «щёлкающие» первыми
    return out


def splinter_tail(seed, n_hits=9, dur=0.55):
    """Хвост щепок: россыпь мелких деревянных стуков (Kenney, питч ×1.7–2.5) с затуханием."""
    r = np.random.default_rng(seed)
    srcs = [K("impact", f"impactWood_light_{i:03d}") for i in range(5)] + [K("impact", f"footstep_wood_{i:03d}") for i in range(5)]
    parts = []
    t = 0.0
    for k in range(n_hits):
        x = d.pitch(srcs[r.integers(len(srcs))], r.uniform(1.7, 2.5))
        parts.append((d.fade(x, 0.0005, 0.03), t, -2.0 - 2.2 * k + r.uniform(-2, 2)))
        t += r.uniform(0.025, 0.07) * (1.0 + 0.25 * k)
    return d.fit(d.mix(parts), dur)


# --- слои ударов и тела (sfx, моно, −14 LUFS-M) ---

def build_sfx():
    print("sfx")
    S = snaps()
    T = -14.0
    G = "sfx"

    layer("wood_l")
    v = [K("impact", f"impactWood_light_{i:03d}") for i in range(5)]
    v += [d.pitch(K("impact", f"impactPlank_medium_{i:03d}"), 1.18) for i in range(5)]
    out_layer(G, "wood_l", [d.fade(x, 0.0005, 0.05) for x in v], T)

    layer("wood_m")
    v = []
    for i in range(5):
        a = K("impact", f"impactWood_medium_{i:03d}")
        v.append(d.mix([(a, 0, 0), (d.sub_thump(0.25, 95, 55, 0.07, 0.0, i), 0, -14)]))
        b = d.pitch(K("impact", f"impactPlank_medium_{i:03d}"), 0.92)
        v.append(d.mix([(b, 0, 0), (S[i % len(S)], 0, -12)]))
    out_layer(G, "wood_m", [d.fade(d.trim(x), 0.0005, 0.06) for x in v], T)

    layer("wood_h")
    v = []
    for i in range(5):
        a = K("impact", f"impactWood_heavy_{i:03d}")
        v.append(d.mix([(a, 0, 0), (S[(i * 3) % len(S)], 0, -5), (d.sub_thump(0.4, 80, 40, 0.11, 0.2, i), 0, -7),
                        (splinter_tail(100 + i), 0.05, -16)]))
    for i, sid in enumerate(("447922", "667655", "667654")):
        if not os.path.exists(os.path.join(FS, f"{sid}.ogg")):
            continue
        a = d.trim(F(sid))
        v.append(d.mix([(a, 0, 0), (d.sub_thump(0.4, 80, 40, 0.11, 0.2, 10 + i), 0, -8)]))
    out_layer(G, "wood_h", [d.fade(d.trim(x), 0.0005, 0.1) for x in v], T)

    layer("metal_l")
    v = [K("impact", f"impactMetal_light_{i:03d}") for i in range(5)]
    v += [d.pitch(K("impact", f"impactTin_medium_{i:03d}"), 1.1) for i in range(5)]
    out_layer(G, "metal_l", [d.fade(x, 0.0005, 0.08) for x in v], T)

    layer("metal_m")
    v = [K("impact", f"impactMetal_medium_{i:03d}") for i in range(5)]
    v += [K("impact", f"impactPlate_medium_{i:03d}") for i in range(5)]
    out_layer(G, "metal_m", [d.fade(x, 0.0005, 0.1) for x in v], T)

    layer("metal_h")
    v = []
    clang = d.trim(F("842171"))
    for i in range(5):
        a = K("impact", f"impactMetal_heavy_{i:03d}")
        b = K("impact", f"impactPlate_heavy_{i:03d}")
        v.append(d.mix([(a, 0, 0), (b, 0.004, -4), (d.sub_thump(0.4, 75, 38, 0.1, 0.2, 20 + i), 0, -8)]))
    v.append(d.mix([(clang, 0, 0), (d.sub_thump(0.4, 75, 38, 0.1, 0.2, 30), 0, -8)]))
    out_layer(G, "metal_h", [d.fade(d.trim(x), 0.0005, 0.15) for x in v], T)

    # голова: гулкий деревянный «бонк» — удар + резонанс полости (≈ 330/520 Гц), короче и выше тела
    layer("head")
    v = []
    for i in range(5):
        a = d.pitch(K("impact", f"impactWood_medium_{i:03d}"), 0.86)
        body = d.resonator(a, 330 + 25 * i, 9) * 0.9 + d.resonator(a, 540 + 30 * i, 12) * 0.5
        body = d.apply_env(body, d.exp_decay(len(body), 0.09))
        v.append(d.mix([(a, 0, -2), (body, 0, 0), (S[(i + 5) % len(S)], 0, -16)]))
    out_layer(G, "head", [d.fade(d.trim(x), 0.0005, 0.08) for x in v], T)

    # сковорода: «БОНГ» — колокол + жесть ниже, длинный звон
    layer("pan")
    v = []
    for i in range(5):
        a = K("impact", f"impactBell_heavy_{i:03d}")
        b = d.pitch(K("impact", f"impactTin_medium_{i:03d}"), 0.72)
        v.append(d.mix([(a, 0, 0), (b, 0, -5), (d.sub_thump(0.3, 110, 70, 0.08, 0.1, 40 + i), 0, -12)]))
    out_layer(G, "pan", [d.fade(d.trim(x, -60), 0.0005, 0.25) for x in v], T)

    # лезвие: рубящий «чок» (меч, топор): chop / slice + деревянный удар
    layer("blade")
    v = []
    srcs = [K("rpg", "chop"), K("rpg", "knifeSlice"), K("rpg", "knifeSlice2"), K("rpg", "drawKnife1"), K("rpg", "drawKnife2"),
            K("rpg", "drawKnife3")]
    for i, s in enumerate(srcs):
        w = K("impact", f"impactWood_medium_{i % 5:03d}")
        v.append(d.mix([(d.fit(s, 0.45), 0, 0), (w, 0.0, -6)]))
    out_layer(G, "blade", [d.fade(d.trim(x), 0.0005, 0.08) for x in v], T)

    layer("bone")
    v = []
    for i in range(5):
        a = d.pitch(K("impact", f"impactGeneric_light_{i:03d}"), 0.9)
        v.append(d.mix([(a, 0, 0), (S[(i + 9) % len(S)], 0, -4)]))
    out_layer(G, "bone", [d.fade(d.trim(x), 0.0005, 0.06) for x in v], T)

    layer("rubber")
    v = [d.mix([(K("impact", f"impactSoft_medium_{i:03d}"), 0, 0), (d.sub_thump(0.3, 130, 80, 0.06, 0, 50 + i), 0, -10)])
         for i in range(5)]
    out_layer(G, "rubber", [d.fade(d.trim(x), 0.0005, 0.06) for x in v], T)

    layer("snap")
    out_layer(G, "snap", [d.fit(S[i], 0.3) for i in range(min(10, len(S)))], T)

    layer("splinter")
    out_layer(G, "splinter", [splinter_tail(200 + i, 8 + i % 4, 0.6) for i in range(6)], T)

    layer("sub")
    out_layer(G, "sub", [d.sub_thump(0.5, 70 - 4 * i, 36, 0.14, 0.15, 60 + i) for i in range(4)], T)

    layer("thud")
    v = []
    for i in range(5):
        a = K("impact", f"impactSoft_heavy_{i:03d}")
        v.append(d.mix([(a, 0, 0), (d.sub_thump(0.4, 75, 40, 0.1, 0.1, 70 + i), 0, -6)]))
    for i in range(2):
        v.append(d.mix([(d.lp(K("impact", f"impactPunch_heavy_{i:03d}"), 900), 0, 0), (d.sub_thump(0.4, 70, 38, 0.1, 0.1, 75 + i), 0, -5)]))
    out_layer(G, "thud", [d.fade(d.trim(x), 0.0005, 0.08) for x in v], T)

    # бум крита: трейлерный удар + низ взрыва + суб
    layer("boom")
    boom = F("816376", 0, 3.2)
    ex = F("560510", 3.0, 3.6)
    v = [d.mix([(boom, 0, 0), (d.sub_thump(0.8, 60, 30, 0.3, 0.3, 80), 0, -4)]),
         d.mix([(d.lp(ex, 500), 0, 0), (boom, 0, -6), (d.sub_thump(0.8, 55, 28, 0.3, 0.3, 81), 0, -4)]),
         d.mix([(d.pitch(boom, 0.85), 0, 0), (S[1], 0, -6), (d.sub_thump(0.8, 65, 32, 0.3, 0.3, 82), 0, -4)])]
    out_layer(G, "boom", [d.fade(x, 0.0005, 1.0) for x in v], T)

    # вдох перед критом: развёрнутый хвост бума + вух, обрыв на пике (стоп-кадр — дальше тишина)
    layer("inhale")
    v = []
    wh = F("427979")
    segs = d.split(wh, -40, 0.1, 0.1)
    for i in range(3):
        b = d.reverse(d.fit(d.cut(boom, 0.05, 1.2), 1.15))
        w = d.reverse(d.pitch(d.cut(wh, *segs[i]), 0.7))
        x = d.mix([(b, 0, -3), (w, max(0.0, len(b) / d.SR - len(w) / d.SR), 0)])
        x = d.fit(d.cut(x, len(x) / d.SR - 0.42, len(x) / d.SR), 0.42)
        v.append(d.fade(x, 0.25, 0.004, 1.0))
    out_layer(G, "inhale", v, T)

    layer("creak")
    v = [d.trim(F("618082")), d.trim(F("618085")), d.trim(F("506665"))]
    v += [K("rpg", f"creak{i}") for i in (1, 2, 3)]
    v = [d.fade(d.fit(d.hp(x, 150), 1.0), 0.005, 0.15) for x in v]
    out_layer(G, "creak", v, T)

    layer("crash")
    v = []
    for i, sid in enumerate(("667652", "667653")):
        cb = d.trim(F(sid))
        for j in range(2):
            w = K("impact", f"impactWood_heavy_{(i * 2 + j) % 5:03d}")
            v.append(d.mix([(w, 0, 0), (cb, 0.01, -2 - 3 * j), (d.sub_thump(0.5, 70, 34, 0.14, 0.2, 90 + i * 2 + j), 0, -5),
                            (splinter_tail(300 + i * 2 + j, 10, 0.8), 0.08, -10)]))
    out_layer(G, "crash", [d.fade(d.trim(x), 0.0005, 0.15) for x in v], T)

    # рассыпание куклы на KO: треск + деревяшки разлетаются и стучат
    layer("shatter")
    v = []
    for i, sid in enumerate(("667653", "667652", "667653", "667652")):
        cb = d.trim(F(sid))
        v.append(d.mix([(S[i], 0, 0), (cb, 0.005, -3), (splinter_tail(400 + i, 12, 1.2), 0.12, -6),
                        (splinter_tail(410 + i, 7, 0.9), 0.35, -12)]))
    out_layer(G, "shatter", [d.fade(d.trim(x), 0.0005, 0.2) for x in v], T)

    # вух отлёта: 13 коротких свистов Kinoton ниже на тон (глубже), разные по длине
    layer("whoosh")
    v = [d.fade(d.pitch(d.cut(wh, s0, s1), 0.82), 0.01, 0.06) for s0, s1 in d.split(wh, -40, 0.1, 0.1)]
    out_layer(G, "whoosh", v, T)

    layer("swing_l")
    v = [d.trim(F("420668")), d.trim(F("719636"))]
    v += [d.fade(d.pitch(d.cut(wh, s0, s1), 1.25), 0.005, 0.04) for s0, s1 in segs[:5]]
    out_layer(G, "swing_l", [d.hp(x, 300) for x in v], T)

    layer("swing_h")
    v = [d.trim(F("422513")), d.pitch(d.trim(F("422513")), 0.8)]
    v += [d.fade(d.lp(d.pitch(d.cut(wh, s0, s1), 0.62), 3500), 0.01, 0.06) for s0, s1 in segs[5:10]]
    out_layer(G, "swing_h", v, T)

    # рывок: короткий выхлоп тяги + вух
    layer("dash")
    v = []
    for i in range(4):
        th = d.fade(d.lp(d.fit(K("scifi", f"thrusterFire_{i:03d}"), 0.45), 2800), 0.005, 0.2)
        w = d.pitch(d.cut(wh, *segs[(i * 3) % len(segs)]), 0.75)
        v.append(d.mix([(th, 0, -3), (w, 0.02, 0)]))
    out_layer(G, "dash", v, T)

    layer("flip")
    v = [d.fade(d.pitch(d.cut(wh, s0, s1), 1.5), 0.005, 0.04) for s0, s1 in segs[8:13]]
    out_layer(G, "flip", v, T)

    layer("grab")
    v = []
    for i in range(4):
        w = d.pitch(K("impact", f"impactWood_light_{i:03d}"), 1.35)
        c = K("rpg", f"cloth{i + 1}")
        v.append(d.mix([(w, 0, 0), (d.fit(c, 0.25), 0.0, -8)]))
    out_layer(G, "grab", [d.fade(x, 0.0005, 0.05) for x in v], T)

    layer("equip")
    v = [K("rpg", "metalLatch"), K("rpg", "beltHandle1"), K("rpg", "beltHandle2"), K("rpg", "drawKnife2"), click()]
    out_layer(G, "equip", [d.fade(d.fit(x, 0.5), 0.0005, 0.08) for x in v], T)

    layer("detach")
    v = [d.mix([(S[i + 2], 0, 0), (click(), 0.01, -6), (splinter_tail(500 + i, 5, 0.4), 0.03, -12)])
         for i in range(4)]
    out_layer(G, "detach", [d.fade(x, 0.0005, 0.05) for x in v], T)

    layer("attach")
    v = [d.mix([(click(), 0, 0), (K("impact", f"impactWood_light_{i:03d}"), 0.005, -4)]) for i in range(3)]
    out_layer(G, "attach", [d.fade(x, 0.0005, 0.05) for x in v], T)

    layer("bell")
    v = [LOCAL("public/sounds/sfx/fight-gong.ogg")]
    out_layer(G, "bell", [d.fade(d.trim(x), 0.001, 0.3) for x in v], T)

    layer("horn")
    a = F("131930", 0.33, 1.75)
    b = F("702099", 3.7, 2.4)
    out_layer(G, "horn", [d.fade(a, 0.01, 0.35), d.fade(d.hp(b, 120), 0.02, 0.5)], T)

    layer("explosion")
    v = []
    for i, (s0, s1) in enumerate(((0.0, 1.9), (3.0, 6.8), (8.0, 12.3))):
        e = F("560510", s0, s1 - s0)
        cr = K("scifi", f"explosionCrunch_{i:03d}")
        v.append(d.mix([(e, 0, 0), (cr, 0, -6), (d.sub_thump(0.9, 55, 26, 0.35, 0.3, 600 + i), 0, -3)]))
    out_layer(G, "explosion", [d.fade(x, 0.0005, 0.5) for x in v], T)

    layer("clank")
    ch = F("637356")
    v = [d.cut(ch, s0, min(s1, s0 + 0.5)) for s0, s1 in d.split(ch, -32, 0.08, 0.08)[:8]]
    out_layer(G, "clank", [d.fade(x, 0.002, 0.08) for x in v], T)

    layer("scrape")
    v = [d.trim(F("743259"))] + [d.fit(d.hp(K("impact", f"footstep_concrete_{i:03d}"), 800), 0.3) for i in range(3)]
    out_layer(G, "scrape", [d.fade(x, 0.002, 0.05) for x in v], T)

    layer("stun")
    v = []
    for i in range(3):
        b = d.pitch(K("impact", f"impactBell_heavy_{i:03d}"), 1.9)
        v.append(d.fade(d.hp(b, 900), 0.002, 0.4))
    out_layer(G, "stun", v, T)


# --- толпа (стерео) ---

def build_crowd():
    print("crowd")
    G = "crowd"
    layer("crowd_loops")
    calm = d.hp(F("424297", 60, 33, stereo=True), 180)
    out_file(G, "loop_calm", calm, -20, loop_xfade=2.0, stereo=True)
    eng = d.hp(F("829454", 298, 33, stereo=True), 120)
    out_file(G, "loop_engaged", eng, -20, loop_xfade=2.0, stereo=True)
    roar = d.mix([(d.hp(F("455660", 22, 30, stereo=True), 120), 0, 0), (d.hp(F("130568", 1.5, 17, stereo=True), 120), 6, -5)])
    out_file(G, "loop_roar", d.fit(roar, 30), -20, loop_xfade=2.5, stereo=True)

    layer("crowd_ooh")
    oo = F("264499", stereo=True)
    v = [d.fade(d.cut(oo, s0, s1), 0.04, 0.3) for s0, s1 in d.split(oo, -30, 0.25, 0.8)]
    v.append(d.fade(d.trim(F("870650", stereo=True)), 0.05, 0.3))
    v.append(d.fade(F("264376", 0.1, 2.6, stereo=True), 0.05, 0.9))
    out_layer(G, "crowd_ooh", v, -16, stereo=True)

    layer("crowd_gasp")
    a = F("324898", 0.6, 1.6, stereo=True)
    b = F("635110", 0.0, 0.95, stereo=True)
    v = [d.fade(a, 0.02, 0.5), d.fade(b, 0.01, 0.3), d.fade(d.pitch(a, 0.93), 0.02, 0.5), d.fade(d.pitch(b, 1.07), 0.01, 0.3)]
    out_layer(G, "crowd_gasp", v, -16, stereo=True)

    layer("crowd_cheer")
    fh = F("324756", stereo=True)
    v = []
    for s0, s1 in ((5.0, 11.5), (45.0, 53.0), (181.5, 189.0), (254.8, 262.0)):   # подъёмы по огибающей (шаг 0.1 с)
        v.append(d.fade(d.cut(fh, s0, s1), 0.08, 2.5))
    v.append(d.fade(F("829454", 251.5, 9.0, stereo=True), 0.1, 2.5))
    out_layer(G, "crowd_cheer", v, -16, stereo=True)

    # большой рёв на KO: начало резкое, держится и спадает (из плотных записей с огибающей)
    layer("crowd_roar")
    v = []
    for i, (sid, s0) in enumerate((("455660", 38.0), ("130568", 1.0), ("455660", 8.0))):
        x = F(sid, s0, 6.5, stereo=True)
        x = d.apply_env(x, d.env(len(x), 0.12, 2.2, 6.5 - 2.32, 1.6))
        v.append(x)
    out_layer(G, "crowd_roar", v, -16, stereo=True)

    layer("crowd_applause")
    ap = F("160493", stereo=True)
    v = [d.fade(d.cut(ap, s0, s0 + 5.0), 0.15, 2.0) for s0 in (3.0, 30.0, 61.0)]
    v.append(d.fade(F("706732", 23.5, 5.5, stereo=True), 0.1, 2.0))
    out_layer(G, "crowd_applause", v, -16, stereo=True)

    layer("crowd_boo")
    v = [d.fade(F("557189", 1.0, 6.0, stereo=True), 0.4, 2.0)]
    bo = F("264378", stereo=True)
    v += [d.fade(d.cut(bo, s0, s0 + 4.0), 0.3, 1.5) for s0 in (1.0, 8.0, 14.0)]
    out_layer(G, "crowd_boo", v, -16, stereo=True)


# --- фон арен (стерео петли) и разовые звуки фона ---

def build_amb():
    print("amb")
    G = "amb"
    layer("amb")
    wind = F("591664", stereo=True)
    out_file(G, "scrap_wind", wind, -26, loop_xfade=2.0, stereo=True)
    out_file(G, "scrap_industrial", d.hp(F("453462", 2, 42, stereo=True), 60), -28, loop_xfade=3.0, stereo=True)
    out_file(G, "ruins_wind", d.band(d.pitch(wind, 1.12), 180, 6000), -27, loop_xfade=2.0, stereo=True)
    # Void: низкий гул поля — два расстроенных тона + розовый шум, медленная пульсация (синтез, CC0)
    n = d.ns(24)
    t = np.arange(n) / d.SR
    drone = 0.5 * np.sin(2 * np.pi * 55 * t) + 0.35 * np.sin(2 * np.pi * 55.37 * t) + 0.2 * np.sin(2 * np.pi * 110.2 * t)
    drone *= 0.75 + 0.25 * np.sin(2 * np.pi * t / 8.0)
    air = d.band(d.pink(n, 7), 80, 900) * 0.25
    vd = np.stack([drone + air, drone * 0.98 + d.band(d.pink(n, 8), 80, 900) * 0.25], axis=1)
    out_file(G, "void_drone", vd, -30, loop_xfade=2.0, stereo=True)
    # Мастерская: тон комнаты + гудение ламп (100 Гц и гармоники)
    room = np.stack([d.lp(d.pink(n, 9), 700), d.lp(d.pink(n, 10), 700)], axis=1) * 0.3
    buzz = sum(a * np.sin(2 * np.pi * f * t) for f, a in ((100, 0.05), (200, 0.03), (300, 0.02), (400, 0.012)))
    out_file(G, "workshop_room", room + buzz[:, None], -32, loop_xfade=2.0, stereo=True)

    layer("amb_clank")
    cl = F("240463")
    v = [d.lp(d.cut(cl, s0, min(s1, s0 + 2.5)), 2200) for s0, s1 in d.split(cl, -30, 0.3, 0.2)[:8]]
    out_layer(G, "amb_clank", [d.fade(x, 0.003, 0.6) for x in v], -14)
    layer("amb_creak")
    v = [d.lp(d.pitch(d.trim(F(s)), 0.6), 1800) for s in ("618082", "618085", "506665")]
    out_layer(G, "amb_creak", [d.fade(x, 0.01, 0.3) for x in v], -14)


# --- петли движения и машин (моно) ---

def build_loops():
    print("loops")
    G = "loops"
    layer("loops")
    n = d.ns(8)
    # поток воздуха в полёте: розовый шум в полосе + шум ветра; громкость/питч/срез — в DollAudio по скорости
    a = d.band(d.pink(n, 11), 250, 3500)
    t = np.arange(n) / d.SR
    a *= 0.8 + 0.2 * np.sin(2 * np.pi * t / 1.3) * np.sin(2 * np.pi * t / 2.9)
    w = d.mono(d.hp(F("591664", 4, 8), 200))
    out_file(G, "wind_flight", d.mix([(a, 0, 0), (w, 0, -3)]), -20, loop_xfade=1.0)
    out_file(G, "fuse_hiss", d.hp(F("438640", 23.0, 6.0), 1500), -22, loop_xfade=1.0)
    out_file(G, "press_motor", F("866648", 0.6, 5.8), -22, loop_xfade=1.0)
    hum = sum(a_ * np.sin(2 * np.pi * f * t) for f, a_ in ((50, 0.5), (100, 0.35), (150, 0.2), (200, 0.12), (250, 0.06)))
    ff = d.mono(d.fit(K("scifi", "forceField_000"), 8.0))
    out_file(G, "magnet_hum", d.mix([(hum * 0.6, 0, 0), (d.lp(ff, 1500), 0, -10)]), -22, loop_xfade=1.0)


# --- машины Свалки и враги (замена синтезированных заглушек; имена = kind в ScrapMachine.synth / EnemyLook._wav) ---

def klaxon(dur=0.32, f=(660.0, 880.0)):
    n = d.ns(dur)
    t = np.arange(n) / d.SR
    half = n // 2
    x = np.zeros(n)
    x[:half] = np.sign(np.sin(2 * np.pi * f[0] * t[:half]))
    x[half:] = np.sign(np.sin(2 * np.pi * f[1] * t[half:]))
    x = d.band(x, 300, 3200) * d.env(n, 0.005, dur - 0.04, 0.035, 1.0)
    gate = (np.fmod(t, 0.16) < 0.12).astype(float)
    return d.saturate(x * gate, 2.0)


def build_machines():
    print("machines")
    G = "machines"
    layer("machines")
    out_file(G, "beep", d.mix([(klaxon(), 0, 0), (d.fit(K("ui", "error_004"), 0.3), 0, -12)]), -16, "momentary")
    h = F("438640", 21.0, 1.6)
    out_file(G, "hiss", d.fade(d.hp(h, 300), 0.03, 0.5), -14, "momentary")
    clunk = F("866648", 6.85, 0.8)
    th = d.mix([(K("impact", "impactMetal_heavy_002"), 0, 0), (K("impact", "impactPlate_heavy_001"), 0.005, -3),
                (clunk, 0, -4), (d.sub_thump(0.6, 60, 30, 0.2, 0.3, 700), 0, -2)])
    out_file(G, "thud", d.fade(th, 0.0005, 0.2), -13, "momentary")
    t = np.arange(d.ns(1.0)) / d.SR
    hum = sum(a * np.sin(2 * np.pi * f * t) for f, a in ((50, 0.5), (100, 0.35), (150, 0.2), (200, 0.12)))
    ff = d.mono(d.fit(K("scifi", "forceField_001"), 1.0))
    out_file(G, "hum", d.fade(d.mix([(hum, 0, 0), (ff, 0, -6)]), 0.12, 0.25), -16, "momentary")
    rb = d.mix([(d.lp(F("560510", 3.05, 1.6), 900), 0, 0), (d.fit(F("637356", 2.0, 1.2), 1.2), 0.1, -6)])
    out_file(G, "rumble", d.fade(rb, 0.05, 0.4), -14, "momentary")


def build_enemies():
    print("enemies")
    G = "enemies"
    layer("enemies")
    n = d.ns(0.65)
    t = np.arange(n) / d.SR
    f = 110 * (4.5 ** (t / t[-1]))
    ph = 2 * np.pi * np.cumsum(f) / d.SR
    whir = d.band(2 * (ph / (2 * np.pi) % 1.0) - 1, 150, 4000) * d.env(n, 0.05, 0.5, 0.1, 1.0)
    out_file(G, "warn_sweep", d.mix([(whir, 0, 0), (d.fade(d.fit(d.pitch(K("scifi", "engineCircular_000"), 1.6), 0.65), 0.01, 0.1), 0, -8)]), -15, "momentary")
    out_file(G, "warn_grab", d.mix([(K("ui", "question_002"), 0, 0), (d.pitch(K("ui", "question_002"), 1.5), 0.08, -4)]), -15, "momentary")
    clk = click()
    out_file(G, "ratchet", d.mix([(d.pitch(clk, rng.uniform(0.9, 1.15)), 0.055 * i, -1.0 * (i % 2)) for i in range(9)]), -15, "momentary")
    out_file(G, "yoink", d.mix([(d.pitch(d.trim(F("420668")), 1.3), 0, 0), (K("rpg", "metalLatch"), 0.06, -3)]), -14, "momentary")
    out_file(G, "drop", d.mix([(K("impact", "impactMetal_light_001"), 0, 0), (K("impact", "impactMetal_light_003"), 0.09, -5),
                               (K("impact", "impactTin_medium_002"), 0.21, -9)]), -15, "momentary")


# --- UI и диктор ---

def build_ui():
    print("ui")
    G = "ui"
    layer("countdown")
    n = d.ns(0.16)
    t = np.arange(n) / d.SR
    beep = (np.sin(2 * np.pi * 880 * t) + 0.3 * np.sin(2 * np.pi * 1760 * t)) * d.env(n, 0.003, 0.09, 0.06, 1.5)
    out_layer(G, "countdown", [d.mix([(beep, 0, 0), (K("ui", "tick_002"), 0, -6)])], -18)
    layer("combo")
    out_layer(G, "combo", [K("ui", f"confirmation_00{i}") for i in (1, 2, 3, 4)], -18)
    layer("callout")
    out_layer(G, "callout", [K("ui", "select_003"), K("ui", "select_006"), K("ui", "pluck_001")], -20)
    layer("ko_slam")
    v = [d.mix([(K("impact", f"impactPlate_heavy_00{i}"), 0, 0), (d.sub_thump(0.6, 60, 30, 0.2, 0.3, 800 + i), 0, -3)]) for i in range(3)]
    out_layer(G, "ko_slam", [d.fade(x, 0.0005, 0.2) for x in v], -15)
    layer("tick")
    out_layer(G, "tick", [d.fade(d.fit(K("ui", n), 0.09), 0.0005, 0.03) for n in ("tick_001", "tick_004", "scroll_002")], -20)
    layer("heartbeat")
    hb = d.mix([(d.sub_thump(0.3, 65, 40, 0.07, 0.05, 900), 0, 0), (d.sub_thump(0.3, 58, 38, 0.08, 0.05, 901), 0.24, -3)])
    out_layer(G, "heartbeat", [d.fit(hb, 0.7)], -18)


# --- музыка (CC0 из TS-проекта, public/sounds/music/README.txt) ---

def build_music():
    print("music")
    G = "music"
    layer("music")
    for i in range(1, 5):
        x = LOCAL(f"public/sounds/music/battle-0{i}.ogg", stereo=True)
        out_file(G, f"battle_0{i}", d.fade(x, 0.01, 1.5), -16, stereo=True)
    out_file(G, "victory", d.fade(LOCAL("public/sounds/sfx/victory.ogg", stereo=True), 0.005, 0.5), -16, stereo=True)
    out_file(G, "defeat", d.fade(LOCAL("public/sounds/sfx/defeat.ogg", stereo=True), 0.005, 0.5), -16, stereo=True)


# --- лицензии ---

SOURCE_TEXT = {
    "kenney:impact-sounds": "Kenney — Impact Sounds, https://kenney.nl/assets/impact-sounds (CC0)",
    "kenney:rpg-audio": "Kenney — RPG Audio, https://kenney.nl/assets/rpg-audio (CC0)",
    "kenney:interface-sounds": "Kenney — Interface Sounds, https://kenney.nl/assets/interface-sounds (CC0)",
    "kenney:sci-fi-sounds": "Kenney — Sci-fi Sounds, https://kenney.nl/assets/sci-fi-sounds (CC0)",
    "local:public/sounds/sfx/fight-gong.ogg": "Umplix — boxing_matchbell.wav, https://opengameart.org/content/boxing-ring-0 (CC0)",
    "local:public/sounds/sfx/victory.ogg": "Spring Enterprises — Fanfares, https://opengameart.org/content/fanfares (CC0)",
    "local:public/sounds/sfx/defeat.ogg": "Spring Enterprises — Fanfares, https://opengameart.org/content/fanfares (CC0)",
    "local:public/sounds/music/battle-01.ogg": "HydroGene — JRPG Epic Rock Battle Theme #1, https://opengameart.org/content/jrpg-epic-rock-battle-theme-1 (CC0)",
    "local:public/sounds/music/battle-02.ogg": "The Real Monoton Artist — Metal Song – Energetic, https://opengameart.org/content/metal-song-energetic (CC0)",
    "local:public/sounds/music/battle-03.ogg": "MintoDog — Trance Boss Battle, https://opengameart.org/content/trance-boss-battle (CC0)",
    "local:public/sounds/music/battle-04.ogg": "cynicmusic / pixelsphere.org — Battle Theme A, https://opengameart.org/content/battle-theme-a (CC0)",
}


def write_licenses():
    with open(os.path.join(HERE, "audio_sources.json"), encoding="utf-8") as f:
        man = json.load(f)
    fs = {i["id"]: i for i in man["freesound"]}
    lines = ["# Звук игры — источники и лицензии", "",
             "Собрано `godot/tools/audio/build_audio.py` из исходников, которые скачивает `fetch_audio_sources.py` (манифест "
             "`audio_sources.json`). Все внешние исходники — CC0 (public domain): атрибуция не обязательна, но мы её ведём. "
             "Синтез (numpy/scipy) сделан для проекта, тоже CC0. Обработка: нарезка, фильтры, питч, слои, громкость по BS.1770.",
             "", "| Слой | Источники |", "|---|---|"]
    for lay in sorted(USED):
        if not lay:
            continue
        srcs = []
        for s in sorted(USED[lay]):
            if s.startswith("freesound:"):
                i = fs.get(s.split(":")[1], {})
                srcs.append(f"{i.get('user', '?')} — {i.get('title', s)}, https://freesound.org/s/{s.split(':')[1]}/ (CC0)")
            else:
                srcs.append(SOURCE_TEXT.get(s, s))
        lines.append(f"| `{lay}` | {'<br>'.join(srcs) if srcs else 'синтез (CC0)'} |")
    lines += ["", "Слои без внешних источников (`sub`, `void_drone`, `workshop_room`, `wind_flight` частично, `klaxon`, отсчёт, "
              "сердцебиение) синтезированы в `build_audio.py`."]
    with open(os.path.join(OUT, "LICENSES.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


GROUPS = {"sfx": build_sfx, "crowd": build_crowd, "amb": build_amb, "loops": build_loops, "machines": build_machines,
          "enemies": build_enemies, "ui": build_ui, "music": build_music}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    if not os.path.isdir(KEN) or not os.path.isdir(FS):
        sys.exit(f"нет исходников в {CACHE}: сначала fetch_audio_sources.py")
    groups = [g for g in GROUPS if not args.only or g in args.only.split(",")]
    for g in groups:
        GROUPS[g]()
    if not args.only:
        write_licenses()
        old = os.path.join(OUT, "sfx", "LICENSES.md")
        if os.path.exists(old):
            os.remove(old)
    rep = os.path.join(HERE, "build_audio_report.json")
    prev = []
    if args.only and os.path.exists(rep):
        with open(rep, encoding="utf-8") as f:
            prev = [r for r in json.load(f) if r["group"] not in groups]
    with open(rep, "w", encoding="utf-8") as f:
        json.dump(prev + REPORT, f, ensure_ascii=False, indent=1)
    total = sum(os.path.getsize(os.path.join(GODOT, r["path"])) for r in prev + REPORT)
    print(f"файлов {len(prev + REPORT)}, {total / 1e6:.1f} МБ")


if __name__ == "__main__":
    main()
