#!/usr/bin/env python3
"""Трейлер NULL GRAVITY: съёмка планов игрой (Godot Movie Maker) → монтаж по последовательности → проверка под Steam.

Последовательность — JSON рядом (teaser.json): shots — что снимать, edit — порядок склеек, texts — надписи на языках.
Поменять порядок, длину, надпись или сид — правка JSON; снятые планы с тем же описанием не переснимаются.

  python3 godot/tools/trailer/trailer.py all                 # shoot + cut + check (по умолчанию teaser.json, язык из JSON)
  python3 godot/tools/trailer/trailer.py shoot [--only a,b] [--force]
  python3 godot/tools/trailer/trailer.py cut   [--lang en]
  python3 godot/tools/trailer/trailer.py check [--lang en]
  --seq <путь к JSON>   другая последовательность (тизер, геймплейный трейлер, вертикальная нарезка…)

Всё пишется в test-artifacts/trailer/<name>/ (не в git): shots/<id>_<язык>.avi + .json (события плана), cards/, segs/,
<name>_<lang>.mp4 (ролик), check_<lang>.json и micro_<lang>.png (лист «микротрейлера» Steam: 6 кадров из разных мест).
Окно Godot — через godot/tools/godot_nofocus.sh: фокус и клавиатура остаются у человека.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GODOT_DIR = ROOT / "godot"
WRAPPER = GODOT_DIR / "tools" / "godot_nofocus.sh"
SHOT_SCENE = "res://tools/trailer/trailer_shot.tscn"
FONT = GODOT_DIR / "assets" / "fonts" / "Oswald.ttf"
DEFAULT_SEQ = Path(__file__).resolve().parent / "teaser.json"

ORANGE = (255, 140, 51)      # ACCENT гаража / GRAVITY (BRAND.md)
CREAM = (241, 224, 180)      # корпус N0
BG = (9, 14, 22)             # фон иконки #090e16
BANNED = ["ragdoll master"]  # чужое название (BRAND.md) — в надписях ролика нельзя

TEXT_DELAY_S = 0.2           # надпись появляется через столько после склейки
TEXT_FADE_S = 0.15
TEXT_BASELINE = 0.865        # доля высоты кадра: базовая линия надписи
TEXT_SIZE = 0.075            # доля высоты кадра: кегль надписи (длинные строки ужимаются до 80 % ширины)
MIN_FREE_GB = 2.0
TRUE_PEAK = -2.0             # dBTP для loudnorm: AAC поднимает пики на ~0.5–1 дБ, а Steam/YouTube хотят ≤ −1
COLOR_SRC = "in_color_matrix=bt601"                          # Movie Maker пишет MJPEG: BT.601, полный диапазон (yuvj420p)
COLOR_OUT = "out_color_matrix=bt709:out_range=tv"            # ролик: BT.709, ограниченный диапазон
COLOR_TAGS = ["-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv"]            # меньше свободного места — съёмку не начинаем (Movie Maker падает на полном диске)


# ---------------------------------------------------------------- общее

def log(msg: str) -> None:
    print(msg, flush=True)


def run(cmd: list, timeout: float | None = None, quiet: bool = True) -> subprocess.CompletedProcess:
    r = subprocess.run([str(c) for c in cmd], capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0 and not quiet:
        log(r.stdout[-3000:])
        log(r.stderr[-3000:])
    return r


def ffmpeg(args: list, what: str) -> None:
    r = run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y"] + args)
    if r.returncode != 0:
        log(r.stderr[-4000:])
        raise SystemExit(f"ffmpeg упал: {what}")


def probe(path: Path) -> dict:
    r = run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", path])
    return json.loads(r.stdout) if r.returncode == 0 else {}


def load_seq(path: Path) -> dict:
    seq = json.loads(path.read_text(encoding="utf-8"))
    seq.setdefault("name", path.stem)
    seq.setdefault("render", {})
    seq["render"].setdefault("width", 1920)
    seq["render"].setdefault("height", 1080)
    seq["render"].setdefault("fps", 60)
    return seq


def out_dir(seq: dict) -> Path:
    d = ROOT / "test-artifacts" / "trailer" / seq["name"]
    for sub in ["shots", "cards", "segs"]:
        (d / sub).mkdir(parents=True, exist_ok=True)
    return d


def text_for(seq: dict, key: str | None, lang: str) -> str:
    if not key:
        return ""
    t = seq.get("texts", {}).get(key)
    if t is None:
        return key   # прямой текст вместо ключа
    if isinstance(t, str):
        return t
    return t.get(lang) or t.get(seq.get("lang", "ru")) or next(iter(t.values()), "")


def shot_spec(seq: dict, sid: str, lang: str) -> dict:
    spec = json.loads(json.dumps(seq.get("defaults", {})))
    for k, v in seq["shots"][sid].items():
        if isinstance(v, dict) and isinstance(spec.get(k), dict):
            spec[k] = {**spec[k], **v}
        else:
            spec[k] = v
    spec.setdefault("ssaa", seq["render"].get("ssaa", 1.5))
    spec.setdefault("fps", seq["render"]["fps"])
    spec["lang"] = lang
    return spec


def spec_hash(spec: dict, seq: dict) -> str:
    key = {"spec": spec, "w": seq["render"]["width"], "h": seq["render"]["height"],
           "scene_src": hashlib.sha1((Path(__file__).parent / "trailer_shot.gd").read_bytes()).hexdigest()}
    return hashlib.sha1(json.dumps(key, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]


def used_shots(seq: dict) -> list:
    out = []
    for e in seq["edit"]:
        s = e.get("shot")
        if s and s not in out:
            out.append(s)
    return out


# ---------------------------------------------------------------- съёмка

def shot_base(d: Path, sid: str, lang: str) -> Path:
    """Файлы плана без расширения: shots/<id>_<язык> (HUD и реплики N0 сняты на этом языке)."""
    return d / "shots" / f"{sid}_{lang}"


def shot_file(d: Path, sid: str, lang: str) -> Path | None:
    """Снятый план: AVI Movie Maker (MJPEG + PCM, как записан)."""
    f = shot_base(d, sid, lang).with_suffix(".avi")
    return f if f.exists() else None


def shoot(seq: dict, lang: str, only: list | None, force: bool) -> None:
    d = out_dir(seq)
    free_gb = shutil.disk_usage(d).free / 2**30
    if free_gb < MIN_FREE_GB:
        raise SystemExit(f"Свободно {free_gb:.1f} ГБ — мало для записи (нужно ≥ {MIN_FREE_GB} ГБ).")
    for sid in (only or used_shots(seq)):
        if sid not in seq["shots"]:
            raise SystemExit(f"план {sid} не описан в shots")
        spec = shot_spec(seq, sid, lang)
        h = spec_hash(spec, seq)
        base = shot_base(d, sid, lang)
        ev_path = base.with_suffix(".json")
        if not force and shot_file(d, sid, lang) and ev_path.exists():
            old = json.loads(ev_path.read_text())
            if old.get("hash") == h:
                log(f"[shoot] {sid}: уже снят (сид {old.get('seed')}), пропуск")
                continue
        base.with_suffix(".avi").unlink(missing_ok=True)
        seeds = spec.get("seed", 1)
        seeds = seeds if isinstance(seeds, list) else [seeds]
        done = False
        for sd in seeds:
            one = dict(spec, seed=sd)
            spec_file = base.with_suffix(".spec.json")
            spec_file.write_text(json.dumps(one, ensure_ascii=False, indent=1))
            avi = base.with_suffix(".avi")
            fps = int(one.get("fps", seq["render"]["fps"]))
            cmd = [WRAPPER, "--path", GODOT_DIR, "--resolution", f"{seq['render']['width']}x{seq['render']['height']}",
                   "--fixed-fps", fps, "--write-movie", avi, SHOT_SCENE, "--", f"shot={spec_file}", f"out={ev_path}"]
            t0 = time.time()
            log(f"[shoot] {sid}: сид {sd}, сцена {one.get('scene')} …")
            ev_path.unlink(missing_ok=True)
            try:
                code = run(cmd, timeout=1200).returncode
            except subprocess.TimeoutExpired:
                code = -9
            ev = json.loads(ev_path.read_text()) if ev_path.exists() else {"code": code, "missing": ["нет отчёта"]}
            if code == 0 and ev.get("ok") and avi.exists():
                # AVI остаётся как есть: перекодировать на этой машине долго (ffmpeg x86 под Rosetta), монтаж читает MJPEG быстро
                ev["hash"] = h
                ev["spec"] = one
                ev_path.write_text(json.dumps(ev, ensure_ascii=False, indent=1))
                log(f"[shoot] {sid}: OK за {time.time() - t0:.0f} с — {ev['frames']} кадров ({ev['frames'] / fps:.1f} с), "
                    f"{avi.stat().st_size / 2**20:.0f} МБ, события {ev.get('counts')}")
                done = True
                break
            log(f"[shoot] {sid}: сид {sd} не подошёл (код {code}, нет {ev.get('missing')}), следующий")
            avi.unlink(missing_ok=True)
        if not done:
            raise SystemExit(f"план {sid}: ни один сид из {seeds} не дал {spec.get('require')}")


# ---------------------------------------------------------------- монтаж

def anchor_time(ev: dict, at) -> float:
    """Время (с от начала записи плана) для якоря склейки: число, start, fight, тип события, тип#N (N-е по счёту)."""
    fps = float(ev["fps"])
    if isinstance(at, (int, float)):
        return float(at)
    at = str(at)
    if at == "start":
        return 0.0
    if at == "fight":
        return ev["fight_frame"] / fps
    typ, _, n = at.partition("#")
    n = int(n) if n else 1
    hits = [e for e in ev["events"] if e["type"] == typ]
    if len(hits) < n:
        raise SystemExit(f"в плане {ev.get('scene')} (сид {ev.get('seed')}) нет события {at}: есть {ev.get('counts')}")
    return hits[n - 1]["frame"] / fps


def font(size: int, weight: str = "Bold"):
    from PIL import ImageFont
    f = ImageFont.truetype(str(FONT), size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def fit_font(draw, text: str, max_w: int, size: int, weight: str = "Bold"):
    while size > 24:
        f = font(size, weight)
        if draw.textlength(text, font=f) <= max_w:
            return f
        size -= 4
    return font(size, weight)


def render_text_card(text: str, w: int, h: int, path: Path) -> None:
    """Надпись поверх кадра: внизу по центру (над полом арены, ниже кукол и надписей удара игры), Oswald Bold, тень, оранжевая черта."""
    from PIL import Image, ImageDraw, ImageFilter
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = fit_font(d, text, int(w * 0.8), int(h * TEXT_SIZE))
    tw = d.textlength(text, font=f)
    asc, desc = f.getmetrics()
    x = (w - tw) / 2
    y = int(h * TEXT_BASELINE) - asc
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.text((x, y + 4), text, font=f, fill=(0, 0, 0, 230))
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    img = Image.alpha_composite(img, shadow)
    d = ImageDraw.Draw(img)
    d.text((x, y), text, font=f, fill=(255, 255, 255, 255))
    bar_w = min(tw, w * 0.18)
    by = y + asc + desc + int(h * 0.012)
    d.rectangle([w / 2 - bar_w / 2, by, w / 2 + bar_w / 2, by + max(4, h // 240)], fill=ORANGE + (255,))
    img.save(path)


def render_end_card(seq: dict, lang: str, w: int, h: int, path: Path) -> None:
    """Финальная плашка: знак N0, NULL (белый) GRAVITY (оранжевый), строка «Скоро в Steam» и призыв в рамке."""
    from PIL import Image, ImageDraw, ImageFilter
    ec = seq.get("end_card", {})
    img = Image.new("RGB", (w, h), BG)
    # радиальное свечение к центру
    glow = Image.new("L", (w, h), 0)
    gd = ImageDraw.Draw(glow)
    r = int(h * 0.55)
    gd.ellipse([w / 2 - r * 1.4, h * 0.36 - r, w / 2 + r * 1.4, h * 0.36 + r], fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(h // 6))
    img = Image.composite(Image.new("RGB", (w, h), (24, 38, 58)), img, glow)
    d = ImageDraw.Draw(img)
    badge_path = ROOT / ec.get("badge", "godot/assets/ui/brand/null_gravity_badge_512.png")
    bs = int(h * 0.36)
    if badge_path.exists():
        b = Image.open(badge_path).convert("RGBA").resize((bs, bs), Image.LANCZOS)
        img.paste(b, (int(w / 2 - bs / 2), int(h * 0.07)), b)
    ft = font(int(h * 0.15), "Bold")
    t1, t2 = "NULL ", "GRAVITY"
    w1, w2 = d.textlength(t1, font=ft), d.textlength(t2, font=ft)
    x0 = (w - w1 - w2) / 2
    ty = int(h * 0.46)
    d.text((x0, ty), t1, font=ft, fill=(255, 255, 255))
    d.text((x0 + w1, ty), t2, font=ft, fill=ORANGE)
    line = text_for(seq, ec.get("line"), lang)
    if line:
        fl = fit_font(d, line, int(w * 0.8), int(h * 0.055), "SemiBold")
        lw = d.textlength(line, font=fl)
        d.text(((w - lw) / 2, int(h * 0.68)), line, font=fl, fill=CREAM)
    cta = text_for(seq, ec.get("cta"), lang)
    if cta:
        fc = fit_font(d, cta, int(w * 0.6), int(h * 0.042), "Bold")
        cw = d.textlength(cta, font=fc)
        asc, desc = fc.getmetrics()
        px, py = int(h * 0.03), int(h * 0.016)
        cx0, cy0 = (w - cw) / 2 - px, int(h * 0.80)
        d.rounded_rectangle([cx0, cy0, cx0 + cw + 2 * px, cy0 + asc + desc + 2 * py], radius=int(h * 0.012), outline=ORANGE, width=max(3, h // 360))
        d.text((cx0 + px, cy0 + py), cta, font=fc, fill=(255, 255, 255))
    img.save(path)


def encoder_args(seq: dict) -> list:
    """Кодер ролика: videotoolbox (аппаратный H.264 на Mac, быстро; по умолчанию) или x264 (лучше на бит, медленно под Rosetta)."""
    r = seq["render"]
    fps = r["fps"]
    if r.get("encoder", "videotoolbox") == "x264":
        return ["-c:v", "libx264", "-preset", r.get("x264_preset", "slow"), "-crf", str(r.get("crf", 16)), "-profile:v", "high",
                "-pix_fmt", "yuv420p", "-g", str(fps), "-bf", "2"] + COLOR_TAGS
    br = str(r.get("bitrate", "40M"))
    return ["-c:v", "h264_videotoolbox", "-b:v", br, "-maxrate", str(r.get("maxrate", "60M")), "-bufsize", "120M",
            "-profile:v", "high", "-pix_fmt", "yuv420p", "-g", str(fps)] + COLOR_TAGS


def cut(seq: dict, lang: str) -> Path:
    """Один проход ffmpeg: куски планов (-ss/-t прямо из AVI) + надписи + плашка → concat → музыка → loudnorm → H.264 + AAC."""
    d = out_dir(seq)
    W, H, FPS = seq["render"]["width"], seq["render"]["height"], seq["render"]["fps"]
    audio = seq.get("audio", {})
    inputs: list = []
    vf: list = []
    af: list = []
    plan = []
    t_cursor = 0.0

    def add_input(args: list) -> int:
        inputs.extend(args)
        return sum(1 for a in inputs if a == "-i") - 1

    for i, e in enumerate(seq["edit"]):
        length = float(e["len"])
        nframes = int(round(length * FPS))
        seg = nframes / FPS
        if "card" in e:
            card = d / "cards" / f"end_{lang}.png"
            render_end_card(seq, lang, W * 2, H * 2, card)   # вдвое крупнее: медленный наезд без лесенки
            zoom = float(e.get("zoom", 0.04))
            k = add_input(["-loop", "1", "-framerate", str(FPS), "-t", f"{seg:.4f}", "-i", str(card)])
            vf.append(f"[{k}:v]zoompan=z='1+{zoom}*on/{max(nframes - 1, 1)}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s={W}x{H}:fps={FPS},"
                      f"fade=t=in:st=0:d={float(e.get('fade_in', 0.25))},trim=end_frame={nframes},setpts=PTS-STARTPTS,"
                      f"scale={COLOR_OUT},format=yuv420p,setsar=1[v{i}]")
            af.append(f"anullsrc=r=48000:cl=stereo,atrim=0:{seg:.4f}[a{i}]")
            plan.append({"i": i, "card": e["card"], "t": round(t_cursor, 2), "len": length})
        else:
            sid = e["shot"]
            ev_path = shot_base(d, sid, lang).with_suffix(".json")
            src = shot_file(d, sid, lang)
            if src is None or not ev_path.exists():
                raise SystemExit(f"план {sid} ({lang}) не снят — сначала shoot --lang {lang}")
            ev = json.loads(ev_path.read_text())
            dur = float(probe(src)["format"]["duration"])
            speed = float(e.get("speed", 1.0))
            src_len = length * speed
            start = anchor_time(ev, e.get("at", "fight")) + float(e.get("from", 0.0))
            clamped = min(max(start, 0.0), max(dur - src_len, 0.0))
            if abs(clamped - start) > 0.02:
                log(f"[cut] склейка {i} ({sid}): начало {start:.2f} с вне записи ({dur:.2f} с) — сдвинуто на {clamped:.2f}")
            start = clamped
            k = add_input(["-ss", f"{start:.4f}", "-t", f"{src_len + 0.2:.4f}", "-i", str(src)])
            base = (f"[{k}:v]setpts=(PTS-STARTPTS)/{speed},fps={FPS},scale={W}:{H}:flags=lanczos:{COLOR_SRC}:{COLOR_OUT},format=yuv420p,"
                    f"trim=end_frame={nframes},setpts=PTS-STARTPTS,setsar=1")
            txt = text_for(seq, e.get("text"), lang)
            if txt:
                if any(b in txt.lower() for b in BANNED):
                    raise SystemExit(f"надпись «{txt}» — чужое название (BRAND.md)")
                png = d / "cards" / f"text_{i:02d}_{lang}.png"
                render_text_card(txt, W, H, png)
                kt = add_input(["-loop", "1", "-framerate", str(FPS), "-t", f"{seg:.4f}", "-i", str(png)])
                t_in = float(e.get("text_at", TEXT_DELAY_S))
                t_out = max(seg - TEXT_FADE_S - 0.1, t_in + 0.3)
                vf.append(base + f"[b{i}]")
                vf.append(f"[{kt}:v]format=rgba,fade=t=in:st={t_in}:d={TEXT_FADE_S}:alpha=1,fade=t=out:st={t_out:.3f}:d={TEXT_FADE_S}:alpha=1,"
                          f"scale={COLOR_OUT},format=yuva420p[t{i}]")
                vf.append(f"[b{i}][t{i}]overlay=0:0:eof_action=pass,format=yuv420p[v{i}]")
            else:
                vf.append(base + f"[v{i}]")
            mute = e.get("audio") == "mute" or (speed != 1.0 and e.get("audio") != "game")
            if mute:
                af.append(f"anullsrc=r=48000:cl=stereo,atrim=0:{seg:.4f}[a{i}]")
            else:
                af.append(f"[{k}:a]asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo,atrim=0:{seg:.4f},"
                          f"apad=whole_dur={seg:.4f},volume={float(e.get('game_db', 0))}dB[a{i}]")
            plan.append({"i": i, "shot": sid, "seed": ev.get("seed"), "src_start": round(start, 2), "at": e.get("at", "fight"),
                         "t": round(t_cursor, 2), "len": length, "speed": speed, "text": txt})
        t_cursor += seg
    total = t_cursor
    n = len(seq["edit"])
    # звук: склейка дорожек игры + музыка (CC0 из игры) → громкость в два прохода
    af.append("".join(f"[a{k}]" for k in range(n)) + f"concat=n={n}:v=0:a=1,volume={float(audio.get('game_db', 0))}dB[g]")
    music = audio.get("music")
    if music:
        km = add_input(["-ss", f"{float(audio.get('music_start', 0))}", "-i", str(ROOT / music)])
        fo = float(audio.get("fade_out", 1.2))
        af.append(f"[{km}:a]aresample=48000,aformat=channel_layouts=stereo,volume={float(audio.get('music_db', -5))}dB,"
                  f"atrim=0:{total:.3f},afade=t=out:st={max(total - fo, 0):.3f}:d={fo}[m]")
        af.append("[g][m]amix=inputs=2:duration=first:normalize=0[mix]")
    else:
        af.append("[g]anull[mix]")
    target = float(audio.get("loudness_lufs", -14))
    mix_wav = d / "segs" / f"mix_{lang}.wav"
    ffmpeg(inputs + ["-filter_complex", ";".join(af), "-map", "[mix]", "-c:a", "pcm_s16le", "-ar", "48000", str(mix_wav)], "звук")
    meas = run(["ffmpeg", "-nostdin", "-hide_banner", "-i", mix_wav, "-af", f"loudnorm=I={target}:TP={TRUE_PEAK}:LRA=11:print_format=json", "-f", "null", "-"])
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", meas.stderr)
    ln = f"loudnorm=I={target}:TP={TRUE_PEAK}:LRA=11"
    if m:
        j = json.loads(m.group(0))
        ln += (f":measured_I={j['input_i']}:measured_TP={j['input_tp']}:measured_LRA={j['input_lra']}"
               f":measured_thresh={j['input_thresh']}:offset={j['target_offset']}:linear=true")
    vf.append("".join(f"[v{k}]" for k in range(n)) + f"concat=n={n}:v=1:a=0[v]")
    kw = add_input(["-i", str(mix_wav)])
    out = d / f"{seq['name']}_{lang}.mp4"
    t0 = time.time()
    ffmpeg(inputs + ["-filter_complex", ";".join(vf), "-map", "[v]", "-map", f"{kw}:a", "-af", f"{ln},aresample=48000",
                     "-frames:v", str(int(round(total * FPS))), "-r", str(FPS)] + encoder_args(seq) +
           ["-c:a", "aac", "-b:a", "320k", "-ar", "48000", "-ac", "2", "-movflags", "+faststart", "-t", f"{total:.4f}", str(out)], "ролик")
    (d / f"edit_{lang}.json").write_text(json.dumps({"total_s": round(total, 2), "segments": plan}, ensure_ascii=False, indent=1))
    log(f"[cut] {out.relative_to(ROOT)} — {total:.2f} с, {n} склеек, кодирование {time.time() - t0:.0f} с")
    for p in plan:
        log(f"   {p['t']:6.2f} с  {p.get('shot') or p.get('card'):<12} {p['len']:.1f} с  {p.get('text', '')}")
    return out


# ---------------------------------------------------------------- проверка

def check(seq: dict, lang: str) -> bool:
    d = out_dir(seq)
    f = d / f"{seq['name']}_{lang}.mp4"
    if not f.exists():
        raise SystemExit(f"нет ролика {f} — сначала cut")
    W, H, FPS = seq["render"]["width"], seq["render"]["height"], seq["render"]["fps"]
    edit = json.loads((d / f"edit_{lang}.json").read_text())
    total = float(edit["total_s"])
    p = probe(f)
    v = next(s for s in p["streams"] if s["codec_type"] == "video")
    a = next((s for s in p["streams"] if s["codec_type"] == "audio"), {})
    dur = float(p["format"]["duration"])
    kbps = int(p["format"].get("bit_rate", 0)) / 1000
    num, den = (int(x) for x in v["r_frame_rate"].split("/"))
    checks = []

    def add(cid: str, ok: bool, value, limit, what: str) -> None:
        checks.append({"id": cid, "ok": bool(ok), "value": value, "limit": limit, "what": what})

    add("resolution", v["width"] == W and v["height"] == H and W * 9 == H * 16, f"{v['width']}x{v['height']}", "1920x1080, 16:9", "Steam: до 1920×1080, лучше 16:9")
    add("fps", round(num / den, 2) in (30.0, 29.97, 60.0, 59.94), round(num / den, 2), "30 или 60", "Steam: 30/29.97 или 60/59.94")
    add("video_codec", v["codec_name"] == "h264" and v.get("pix_fmt") == "yuv420p", f"{v['codec_name']} {v.get('pix_fmt')}", "h264 yuv420p", "Steam: H.264 предпочтителен")
    add("audio_codec", a.get("codec_name") == "aac" and int(a.get("sample_rate", 0)) in (44100, 48000) and int(a.get("channels", 0)) == 2,
        f"{a.get('codec_name')} {a.get('sample_rate')} {a.get('channels')}ch", "aac 44.1/48 кГц стерео", "Steam: AAC, 44 или 48 кГц")
    add("bitrate", kbps >= 5000, round(kbps), "≥ 5000 кбит/с", "Steam: высокий битрейт (5000+)")
    add("duration", abs(dur - total) < 0.2, round(dur, 2), round(total, 2), "длина = сумма склеек")
    # чёрные и застывшие куски (плашка в конце статична — застывание там не считаем)
    bd = run(["ffmpeg", "-nostdin", "-hide_banner", "-i", f, "-vf", "blackdetect=d=0.4:pix_th=0.08", "-an", "-f", "null", "-"]).stderr
    blacks = [(float(x), float(y)) for x, y in re.findall(r"black_start:([\d.]+) black_end:([\d.]+)", bd)]
    add("no_black", not blacks, blacks, "нет черноты ≥ 0.4 с", "микротрейлер берёт куски из любого места")
    cards = [(s["t"], s["t"] + s["len"]) for s in edit["segments"] if "card" in s]
    fz = run(["ffmpeg", "-nostdin", "-hide_banner", "-i", f, "-vf", "freezedetect=n=0.002:d=1.0", "-an", "-f", "null", "-"]).stderr
    starts = [float(x) for x in re.findall(r"freeze_start: ([\d.]+)", fz)]
    freezes = [s for s in starts if not any(c0 - 0.1 <= s <= c1 for c0, c1 in cards)]
    add("no_freeze", not freezes, freezes, "нет застывания ≥ 1 с вне плашки", "бой не стоит на месте")
    eb = run(["ffmpeg", "-nostdin", "-hide_banner", "-nostats", "-i", f, "-af", "ebur128=peak=true", "-f", "null", "-"]).stderr
    mi = re.findall(r"I:\s+(-?[\d.]+) LUFS", eb)
    mp = re.findall(r"Peak:\s+(-?[\d.]+) dBFS", eb)
    target = float(seq.get("audio", {}).get("loudness_lufs", -14))
    lufs = float(mi[-1]) if mi else None
    tp = float(mp[-1]) if mp else None
    add("loudness", lufs is not None and abs(lufs - target) <= 1.5, lufs, f"{target} ± 1.5 LUFS", "громкость как у роликов на YouTube/Steam")
    add("true_peak", tp is not None and tp <= -0.9, tp, "≤ −1 dBTP", "без клиппинга после перекодирования")
    texts = " ".join(str(s.get("text", "")) for s in edit["segments"]).lower()
    add("brand", not any(b in texts for b in BANNED), [b for b in BANNED if b in texts], "нет", "чужое название в надписях (BRAND.md)")
    # лист «микротрейлера»: Steam режет 6 кусков по 1 с из разных мест первого трейлера — каждый должен читаться сам
    sheet = d / f"micro_{lang}.png"
    tiles = []
    for k in range(6):
        t = (k + 0.5) * dur / 6
        png = d / "segs" / f"micro_{k}.png"
        ffmpeg(["-ss", f"{t:.2f}", "-i", f, "-frames:v", "1", "-vf", "scale=640:-2", png], "кадр микротрейлера")
        tiles.append((t, png))
    from PIL import Image, ImageDraw
    tw, th = 640, 360
    sh = Image.new("RGB", (tw * 3, th * 2), (0, 0, 0))
    for k, (t, png) in enumerate(tiles):
        im = Image.open(png).convert("RGB")
        sh.paste(im, ((k % 3) * tw, (k // 3) * th))
        ImageDraw.Draw(sh).text(((k % 3) * tw + 10, (k // 3) * th + 8), f"{t:.1f} s", font=font(28), fill=(255, 220, 120))
    sh.save(sheet)
    ok = all(c["ok"] for c in checks)
    rep = {"ok": ok, "file": str(f.relative_to(ROOT)), "checks": checks, "micro_sheet": str(sheet.relative_to(ROOT)), "edit": edit}
    (d / f"check_{lang}.json").write_text(json.dumps(rep, ensure_ascii=False, indent=1))
    for c in checks:
        log(f"{'OK  ' if c['ok'] else 'FAIL'} {c['id']:<12} {c['value']}  ({c['limit']})")
    log(f"=== {'OK' if ok else 'FAIL'} === {rep['file']}, лист микротрейлера {rep['micro_sheet']}")
    return ok


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["shoot", "cut", "check", "all"])
    ap.add_argument("--seq", default=str(DEFAULT_SEQ))
    ap.add_argument("--lang", default=None)
    ap.add_argument("--only", default=None, help="планы через запятую (для shoot)")
    ap.add_argument("--force", action="store_true", help="переснять, даже если описание плана не менялось")
    a = ap.parse_args()
    seq = load_seq(Path(a.seq))
    lang = a.lang or seq.get("lang", "ru")
    only = [s.strip() for s in a.only.split(",")] if a.only else None
    if a.cmd in ("shoot", "all"):
        shoot(seq, lang, only, a.force)
    if a.cmd in ("cut", "all"):
        cut(seq, lang)
    if a.cmd in ("check", "all"):
        sys.exit(0 if check(seq, lang) else 1)


if __name__ == "__main__":
    main()
