#!/usr/bin/env python3
"""Страница каталога элементов игры: docs/catalog/index.html + img/ + fonts/ (открывается с диска, сервер не нужен).

Вход — папка экспорта tools/catalog_export.tscn (catalog.json и raw/**.png), из корня репозитория:
    godot/tools/godot_nofocus.sh --path godot --resolution 640x360 res://tools/catalog_export.tscn -- lang=ru out=/абс/папка
    python3 godot/tools/build_catalog.py /абс/папка [--out docs/catalog] [--jobs 8] [--skip-images]

Картинки: вьюпорт Godot с прозрачным фоном отдаёт цвет, умноженный на альфу В ЛИНЕЙНОМ пространстве и потом закодированный в sRGB —
на краях без поправки остаётся цветная кайма. Здесь кадр переводится в линейный, уменьшается (Lanczos, в умноженном виде — так
правильно), делится на альфу и кодируется обратно; пишется WebP. Детали — PART_PX, те же детали в чужих материалах — VARIANT_PX,
бойцы / враги / оружие обрезаются по содержимому и вписываются в BIG_PX.
Страница — tools/catalog_template.html: данные подставляются в /*__DATA__*/, сборка (коммит, дата) — в __BUILD__.
"""
import argparse
import json
import shutil
import subprocess
import sys
from multiprocessing import Pool
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = Path(__file__).with_name("catalog_template.html")
FONTS = ["Oswald.ttf", "Rubik.ttf", "JetBrainsMono.ttf", "OFL-oswald.txt", "OFL-rubik.txt", "OFL-jetbrainsmono.txt"]
BRAND = ROOT / "godot/assets/ui/brand/null_gravity_icon.png"

PART_PX = 384
VARIANT_PX = 288
BIG_PX = 720
SMALL_PX = 320          # шары материалов, коннекторы шарниров


def _to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def convert(job):
    src, dst, px, quality, trim = job
    a = np.asarray(Image.open(src).convert("RGBA"), dtype=np.float32) / 255.0
    rgb, alpha = _to_lin(a[..., :3]), a[..., 3]
    if trim:
        ys, xs = np.nonzero(alpha > 0.01)
        if len(xs):
            pad = int(0.02 * max(alpha.shape))
            x0, x1 = max(xs.min() - pad, 0), min(xs.max() + pad + 1, alpha.shape[1])
            y0, y1 = max(ys.min() - pad, 0), min(ys.max() + pad + 1, alpha.shape[0])
            rgb, alpha = rgb[y0:y1, x0:x1], alpha[y0:y1, x0:x1]
    h, w = alpha.shape
    k = min(px / max(w, h), 1.0)
    size = (max(round(w * k), 1), max(round(h * k), 1))
    chans = [rgb[..., 0], rgb[..., 1], rgb[..., 2], alpha]
    if size != (w, h):
        chans = [np.asarray(Image.fromarray(np.ascontiguousarray(c), mode="F").resize(size, Image.LANCZOS)) for c in chans]
    alpha = np.clip(chans[3], 0.0, 1.0)
    safe = np.maximum(alpha, 1e-4)
    out = np.stack([_to_srgb(c / safe) for c in chans[:3]] + [alpha], axis=-1)
    out[alpha < 1.0 / 510.0] = 0.0
    dst.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), mode="RGBA").save(dst, "WEBP", quality=quality, method=4)
    return dst.stat().st_size


def image_jobs(raw: Path, out: Path):
    jobs = []
    for src in sorted(raw.rglob("*.png")):
        rel = src.relative_to(raw)
        section = rel.parts[0]
        dst = out / "img" / rel.with_suffix(".webp")
        if section == "parts":
            variant = "__" in src.stem
            jobs.append((src, dst, VARIANT_PX if variant else PART_PX, 78 if variant else 84, False))
        elif section in ("fighters", "enemies", "weapons"):
            jobs.append((src, dst, BIG_PX, 84, True))
        else:
            jobs.append((src, dst, SMALL_PX, 84, False))
    return jobs


def git(*args):
    try:
        return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("export_dir", type=Path, help="папка с catalog.json и raw/ (out= экспорта)")
    ap.add_argument("--out", type=Path, default=ROOT / "docs/catalog")
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--skip-images", action="store_true", help="только пересобрать index.html")
    args = ap.parse_args()

    data = json.loads((args.export_dir / "catalog.json").read_text(encoding="utf-8"))
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)

    if not args.skip_images:
        jobs = image_jobs(args.export_dir / "raw", out)
        if not jobs:
            sys.exit("нет кадров в %s/raw" % args.export_dir)
        shutil.rmtree(out / "img", ignore_errors=True)
        with Pool(args.jobs) as pool:
            sizes = pool.map(convert, jobs, chunksize=16)
        print("картинок: %d, %.1f МБ" % (len(sizes), sum(sizes) / 1e6))

    (out / "fonts").mkdir(exist_ok=True)
    for f in FONTS:
        shutil.copyfile(ROOT / "godot/assets/fonts" / f, out / "fonts" / f)
    (out / "img").mkdir(exist_ok=True)
    Image.open(BRAND).convert("RGBA").resize((96, 96), Image.LANCZOS).save(out / "img" / "brand.png", optimize=True)

    # картинки, которых нет на диске, страница не показывает (экспорт с only= / mats=0)
    have = {p.relative_to(out / "img").with_suffix("").as_posix() for p in (out / "img").rglob("*.webp")}
    for p in data["parts"]:
        p["image"] = ("parts/" + p["id"]) in have
        p["variants"] = [m for m in p["variants"] if "parts/%s__%s" % (p["id"], m) in have]
    for key in ("weapons", "fighters", "enemies", "materials"):
        for e in data[key]:
            e["image"] = ("%s/%s" % (key, e["id"])) in have
    for j in data["joints"]:
        j["image"] = ("joints/" + j["id"]) in have

    build = {"commit": git("rev-parse", "--short", "HEAD"), "date": git("log", "-1", "--format=%cd", "--date=format:%d.%m.%Y"),
             "version": ""}
    for line in (ROOT / "godot/project.godot").read_text(encoding="utf-8").splitlines():
        if line.startswith("config/version="):
            build["version"] = line.split("=", 1)[1].strip().strip('"')
    data["build"] = build

    html = TEMPLATE.read_text(encoding="utf-8")
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    html = html.replace("/*__DATA__*/null", payload)
    (out / "index.html").write_text(html, encoding="utf-8")
    total = sum(f.stat().st_size for f in out.rglob("*") if f.is_file())
    print("%s: %d деталей, %d материалов, %d бойцов; папка %.1f МБ" % (
        out / "index.html", len(data["parts"]), len(data["materials"]), len(data["fighters"]), total / 1e6))


if __name__ == "__main__":
    main()
