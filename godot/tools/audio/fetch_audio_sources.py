#!/usr/bin/env python3
"""Скачивает CC0-исходники звука (docs/plan-demo/AUDIO.md §3) в кэш вне git.

    python3 godot/tools/audio/fetch_audio_sources.py            # всё из манифеста (уже скачанное пропускается)
    python3 godot/tools/audio/fetch_audio_sources.py --list     # что в манифесте и что уже лежит в кэше

Кэш: $RAGDOLL_AUDIO_CACHE или ~/.cache/ragdoll-faces/audio_src (общий для всех worktree). В игру попадает только то, что
tools/audio/build_audio.py вырезал и обработал в godot/assets/audio/**; атрибуции — godot/assets/audio/LICENSES.md.

Манифест — audio_sources.json рядом: {"kenney": [{id, page}], "freesound": [{id, user, title, use}]}.
  kenney    — паки kenney.nl (CC0): zip со страницы ассета, распаковка в kenney/<id>/.
  freesound — звуки freesound.org с лицензией CC0: HQ-превью (OGG ~192 кбит/с) по странице звука в freesound/<id>.ogg;
              лицензия проверяется на странице (не CC0 — отказ).
"""
import argparse
import io
import json
import os
import re
import sys
import time
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "audio_sources.json")
UA = {"User-Agent": "Mozilla/5.0 (ragdoll-faces audio fetch)"}


def cache_dir():
    return os.environ.get("RAGDOLL_AUDIO_CACHE", os.path.expanduser("~/.cache/ragdoll-faces/audio_src"))


def get(url, binary=True, tries=3):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            return data if binary else data.decode("utf-8", "replace")
        except Exception as e:  # noqa: BLE001
            if i == tries - 1:
                raise
            print(f"  retry {url}: {e}", file=sys.stderr)
            time.sleep(6.0 * (i + 1))


def fetch_kenney(item, root):
    out = os.path.join(root, "kenney", item["id"])
    if os.path.isdir(out) and any(os.scandir(out)):
        return "cached"
    page = get(f"https://kenney.nl/assets/{item['page']}", binary=False)
    m = re.search(r"https://kenney\.nl/media/pages/assets/[^'\"]+\.zip", page)
    if not m:
        raise RuntimeError(f"zip не найден на странице {item['page']}")
    if "CC0" not in page and "Creative Commons Zero" not in page:
        raise RuntimeError(f"{item['page']}: на странице нет CC0")
    data = get(m.group(0))
    os.makedirs(out, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        z.extractall(out)
    return f"{len(data) // 1024} KB"


def fetch_freesound(item, root):
    out_dir = os.path.join(root, "freesound")
    out = os.path.join(out_dir, f"{item['id']}.ogg")
    if os.path.isfile(out) and os.path.getsize(out) > 0:
        return "cached"
    time.sleep(2.5)                     # freesound отвечает 503 на частые запросы
    page = get(f"https://freesound.org/people/{item['user']}/sounds/{item['id']}/", binary=False)
    if "publicdomain/zero" not in page:
        raise RuntimeError(f"freesound {item['id']}: лицензия не CC0")
    m = re.search(r"https://cdn\.freesound\.org/previews/\d+/%s_\d+-hq\.ogg" % item["id"], page)
    if not m:
        m2 = re.search(r"https://cdn\.freesound\.org/previews/\d+/%s_\d+-lq\.ogg" % item["id"], page)
        if not m2:
            raise RuntimeError(f"freesound {item['id']}: превью не найдено")
        url = m2.group(0).replace("-lq.ogg", "-hq.ogg")
    else:
        url = m.group(0)
    data = get(url)
    os.makedirs(out_dir, exist_ok=True)
    with open(out, "wb") as f:
        f.write(data)
    return f"{len(data) // 1024} KB"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--only", default="", help="kenney | freesound")
    args = ap.parse_args()
    with open(MANIFEST, encoding="utf-8") as f:
        man = json.load(f)
    root = cache_dir()
    os.makedirs(root, exist_ok=True)
    print(f"cache: {root}")
    fails = 0
    for kind, fn in (("kenney", fetch_kenney), ("freesound", fetch_freesound)):
        if args.only and args.only != kind:
            continue
        for item in man.get(kind, []):
            label = f"{kind}/{item['id']}"
            if args.list:
                p = os.path.join(root, kind, item["id"] if kind == "kenney" else f"{item['id']}.ogg")
                print(f"{'+' if os.path.exists(p) else '-'} {label}  {item.get('title', item.get('page', ''))}")
                continue
            try:
                print(f"{label}: {fn(item, root)}")
            except Exception as e:  # noqa: BLE001
                fails += 1
                print(f"{label}: FAIL {e}", file=sys.stderr)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
