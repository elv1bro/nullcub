#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Фон Свалки из 3D одной командой: Blender-рендер конструкций (tools/blender/scrap_backdrop.py) → нарезка
parallax_elements_cut.py --single --ppm в godot/assets/textures/parallax/scrap_baked/<группа>/ + manifest.json.

Группы = папки полос ParallaxScatter3D в scenes/arena/parallax_scrap_scatter.tscn:
  mid        — 19 конструкций среднего плана (60 пкс/м); та же папка у полосы дальних силуэтов
  fore_tall  — высокие стоящие элементы переднего плана (шестерни, балки, большая куча) — редко
  fore_low   — низкие кучи из моделей арены (увеличиваются полосой ×1.6–2.2) — плотно у нижнего края
  fore_hang  — подвешенные (цепи с крюком/магнитом/блоком, балка на цепях), якорь top
Передний план — 180 пкс/м (≥ 240 пкс/м нужно для ×1 при максимальном приближении; полоса масштабирует 0.6–1.2), низкие
кучи — 396 пкс/м (полоса увеличивает их ×1.6–2.2). Точный ppm каждого рендера Blender пишет в <renders>/<set>/_ppm.json.

Запуск: /usr/local/bin/python3 godot/tools/parallax_bake_scrap.py [--only Name,…] [--keep /abs/renders]
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLENDER = "/Applications/Blender.app/Contents/MacOS/Blender"
SCRIPT = os.path.join(ROOT, "godot", "tools", "blender", "scrap_backdrop.py")
CUT = os.path.join(ROOT, "godot", "tools", "parallax_elements_cut.py")
OUT = os.path.join(ROOT, "godot", "assets", "textures", "parallax", "scrap_baked")
PPM = {"mid": 60, "fore": 180}
FORE_TALL = {"Gear_Big", "Gear_Small", "Beams_Tilted", "Pile_Massive"}
FORE_HANG = {"Chain_Hook", "Chain_Magnet", "Chain_Block", "Chain_Short", "Hanging_Beam"}


def group(set_name, name):
    if set_name == "mid":
        return "mid"
    if name in FORE_HANG:
        return "fore_hang"
    return "fore_tall" if name in FORE_TALL else "fore_low"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=None)
    ap.add_argument("--keep", default=None, help="папка для рендеров (иначе временная)")
    args = ap.parse_args()
    renders = args.keep or tempfile.mkdtemp(prefix="scrap_backdrop_")
    cmd = [BLENDER, "-b", "--python", SCRIPT, "--", "out=" + renders, "ppm=%d" % PPM["mid"],
           "ppm_fore=%d" % PPM["fore"]]
    if args.only:
        cmd.append("only=" + args.only)
    print(" ".join(cmd), flush=True)
    r = subprocess.run(cmd, capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if line.startswith("render ") or "Error" in line or "Traceback" in line:
            print(line)
    if r.returncode != 0:
        print(r.stderr[-3000:])
        sys.exit(r.returncode)
    if not args.only:  # полная пересборка: папки групп с нуля (manifest не копит удалённые элементы)
        for g in ("mid", "fore_tall", "fore_low", "fore_hang"):
            shutil.rmtree(os.path.join(OUT, g), ignore_errors=True)
    for set_name in ("mid", "fore"):
        d = os.path.join(renders, set_name)
        if not os.path.isdir(d):
            continue
        ppm_file = os.path.join(d, "_ppm.json")
        ppm_map = json.load(open(ppm_file)) if os.path.exists(ppm_file) else {}
        for f in sorted(os.listdir(d)):
            if not f.endswith(".png"):
                continue
            name = f[:-4]
            dst = os.path.join(OUT, group(set_name, name))
            ppm = ppm_map.get(name, PPM[set_name])
            subprocess.run([sys.executable, CUT, os.path.join(d, f), dst, "--single", "--ppm", str(ppm),
                            "--prefix", name.lower()], check=True, capture_output=True)
            print("%-14s → %s" % (name, os.path.relpath(dst, ROOT)))
    if not args.keep:
        shutil.rmtree(renders, ignore_errors=True)


if __name__ == "__main__":
    main()
