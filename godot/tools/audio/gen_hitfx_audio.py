#!/usr/bin/env python3
"""Звук ударов «как в боевике» (docs/plan-demo/HIT_FX.md §2.5, §4.4): слои SfxDirector → godot/assets/audio/sfx/<слой>/*.ogg.

    python3 godot/tools/audio/gen_hitfx_audio.py          # нужны numpy, scipy, ffmpeg (libvorbis)

Два источника:
  1. CC0-сэмплы старого TS-проекта public/sounds/{combat,sfx} (README.txt там же; атрибуции — assets/audio/sfx/LICENSES.md):
     обрезка тишины/хвоста, моно, нормализация пика, фильтр при необходимости.
  2. Синтез (numpy + scipy, seed 29; результат наш, CC0) — того, чего в паке нет: деревянный «ток», треск волокна,
     низкий тумп, бум крита, «вух» отлёта, вдох-реверс перед критом, скрип волокна, crash, рассыпание куклы, «ох» толпы
     (crowd-oof.ogg из TS-проекта — тишина −91 dB, битый файл).

Слои (папка = слой; Godot-сцена scenes/audio/sfx_director.tscn собирается tools/audio/build_sfx_director_scene.gd из папок):
  tok        — лёгкий удар: деревянный стук (модальный синтез: шум-возбуждение → резонаторы бруска)
  punch      — удар heavy/crit: qubodup Punch 1–5 + тяжёлые hits 28/34
  crack      — треск дерева (снап + щепки)            creak   — скрип волокна на крупном плане крита
  thud       — низкий «тумп» (синтез + hits 19/35 через low-pass)
  boom       — бум крита (суб-провал 90→32 Гц + шум)  inhale  — вдох-реверс в стоп-кадре крита (обрывается на пике)
  zap_low    — Kenney zap 1/2 (директор играет с питчем 0.5)
  whistle    — Kenney phaser_up 1/3 (свист на выходе из крупного плана, питч 0.6)
  whoosh     — «вух» отлёта (шум, полоса скользит вверх-вниз)
  crash      — удар о стену в крит-полёте             shatter — кукла рассыпается на KO (треск + стук деталей)
  ko         — ko-01/02 TS-проекта (это копии hit-37 и qubodupPunch05)
  gong       — боксёрский колокол (Umplix)            crowd_cheer — аплодисменты (qubodup «Well Done»)
  crowd_oof  — «ох» толпы (синтез: 28 голосов, форманты «о»)
"""
import os
import shutil
import subprocess
import tempfile
import wave

import numpy as np
from scipy import signal

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.normpath(os.path.join(HERE, "..", ".."))
REPO = os.path.normpath(os.path.join(GODOT, ".."))
SRC = os.path.join(REPO, "public", "sounds")
OUT = os.path.join(GODOT, "assets", "audio", "sfx")
OGG_Q = "4"
PEAK_DB = -1.0

rng = np.random.default_rng(29)


# --- утилиты ---

def ns(sec):
    return int(round(sec * SR))


def t_axis(sec):
    return np.arange(ns(sec)) / SR


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def bp(x, f0, q):
    b, a = signal.iirpeak(min(f0, SR * 0.45), q, fs=SR)
    return signal.lfilter(b, a, x)


def lp(x, fc, order=2):
    b, a = signal.butter(order, min(fc, SR * 0.45), "low", fs=SR)
    return signal.lfilter(b, a, x)


def hp(x, fc, order=2):
    b, a = signal.butter(order, fc, "high", fs=SR)
    return signal.lfilter(b, a, x)


def band(x, f1, f2, order=2):
    b, a = signal.butter(order, [f1, min(f2, SR * 0.45)], "band", fs=SR)
    return signal.lfilter(b, a, x)


def env_exp(n, tau, attack=0.0005):
    t = np.arange(n) / SR
    return np.clip(t / max(attack, 1e-5), 0, 1) * np.exp(-t / tau)


def fade(x, fade_in=0.0005, fade_out=0.02):
    x = x.copy()
    ni = max(1, int(fade_in * SR))
    no = max(1, int(fade_out * SR))
    x[:ni] *= np.linspace(0, 1, ni)
    x[-no:] *= np.linspace(1, 0, no) ** 2
    return x


def fit(x, sec):
    n = int(round(sec * SR))
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def place(buf, x, at_s, gain=1.0):
    i = int(round(at_s * SR))
    if i >= len(buf):
        return
    m = min(len(x), len(buf) - i)
    buf[i:i + m] += x[:m] * gain


def norm(x, peak_db=PEAK_DB):
    p = np.max(np.abs(x))
    return x if p < 1e-9 else x / p * 10 ** (peak_db / 20)


def loud(x, target_rms_db, max_k=12.0):
    """Мягкая сатурация tanh(k·x) до RMS target (для треска и толпы: пик снапа иначе «съедает» громкость)."""
    x = norm(x, 0.0)
    lo, hi = 1.0, max_k
    for _ in range(24):
        k = (lo + hi) / 2
        y = np.tanh(k * x) / np.tanh(k)
        if 20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-12) < target_rms_db:
            lo = k
        else:
            hi = k
    return norm(np.tanh(lo * x) / np.tanh(lo))


def trim_source(x, pre=0.004, length=None, thr_db=-30.0, fade_out=0.03):
    """Обрезает тишину до атаки (порог от пика) и хвост до length (или до −50 dB), с фейдом."""
    peak = np.max(np.abs(x)) + 1e-12
    on = np.where(np.abs(x) > peak * 10 ** (thr_db / 20))[0]
    start = max(0, on[0] - int(pre * SR)) if len(on) else 0
    x = x[start:]
    if length is None:
        tail = np.where(np.abs(x) > peak * 10 ** (-50 / 20))[0]
        length = (tail[-1] + 1) / SR if len(tail) else len(x) / SR
    x = x[:int(round(length * SR))]
    return fade(x, 0.0005, min(fade_out, len(x) / SR * 0.5))


# --- синтез ---

def wood_tok(f0, tau=0.035, body=160.0, seed_gain=1.0, dur=0.2):
    """Деревянный стук: короткий шум + импульс → банк резонаторов свободного бруска (1, 2.76, 5.40, 8.93)."""
    n = ns(dur)
    exc = np.zeros(n)
    exc[0] = 1.0
    exc[:int(0.002 * SR)] += rng.standard_normal(int(0.002 * SR)) * env_exp(int(0.002 * SR), 0.0006) * 0.6
    y = np.zeros(n)
    for r, g, q in ((1.0, 1.0, 28), (2.76, 0.55, 34), (5.40, 0.28, 40), (8.93, 0.12, 44)):
        f = f0 * r * (1 + rng.uniform(-0.02, 0.02))
        if f > SR * 0.42:
            continue
        y += bp(exc, f, q) * g
    y = norm(y * env_exp(n, tau, 0.0003), 0.0)
    # «тело» детали и щелчок кромки
    y += np.sin(2 * np.pi * body * t_axis(dur)) * env_exp(n, 0.012, 0.001) * 0.18
    click = hp(rng.standard_normal(n) * env_exp(n, 0.0007), 2500)
    y += norm(click, 0.0) * 0.3
    return fade(norm(y) * seed_gain, 0.0002, 0.03)


def wood_crack(dur=0.38, clicks=36, body_f=(320, 610), tail_tau=0.09):
    """Треск дерева: снап (широкий импульс) + щепки (микрощелчки в полосах 1.5–6 кГц, гуще в начале) + резонанс детали."""
    n = ns(dur)
    y = np.zeros(n)
    snap = hp(rng.standard_normal(int(0.006 * SR)) * env_exp(int(0.006 * SR), 0.0012), 700)
    place(y, snap, 0.0, 1.4)
    for _ in range(clicks):
        t0 = min(-0.035 * np.log(rng.uniform(1e-3, 1.0)), dur * 0.8)
        ln = int(rng.uniform(0.0008, 0.004) * SR)
        c = rng.standard_normal(ln) * env_exp(ln, ln / SR * 0.3)
        c = bp(c, rng.uniform(1500, 6000), rng.uniform(2, 6))
        place(y, c, t0, rng.uniform(0.3, 1.0) * np.exp(-t0 / tail_tau) * (1 if rng.random() > 0.5 else -1))
    exc = np.zeros(n)
    exc[0] = 1.0
    for f in body_f:
        y += bp(exc, f * rng.uniform(0.95, 1.05), 18) * env_exp(n, 0.03) * 0.8
    y = hp(y, 150)
    return fade(loud(y, -24.0), 0.0002, 0.05)


def creak(dur=0.5, rate=(28, 85, 40)):
    """Скрип волокна: stick-slip — нерегулярные импульсы 28→85→40 Гц через резонаторы 380/820/1650/2900 Гц; в конце щепки."""
    n = ns(dur)
    t = t_axis(dur)
    k = t / dur
    r = np.where(k < 0.55, rate[0] + (rate[1] - rate[0]) * (k / 0.55), rate[1] + (rate[2] - rate[1]) * ((k - 0.55) / 0.45))
    jit = lp(rng.standard_normal(n), 18)
    r *= 1 + 0.2 * jit / (np.max(np.abs(jit)) + 1e-9)
    phase = np.cumsum(r / SR)
    pulses = np.zeros(n)
    idx = np.where(np.diff(np.floor(phase)) > 0)[0]
    pulses[idx] = rng.uniform(0.5, 1.0, len(idx))
    y = np.zeros(n)
    for f, g, q in ((380, 1.0, 14), (820, 0.7, 16), (1650, 0.45, 18), (2900, 0.25, 20)):
        y += bp(pulses, f * rng.uniform(0.97, 1.03), q) * g
    amp = np.clip(k / 0.12, 0, 1) * np.clip((1 - k) / 0.2, 0, 1) ** 0.5
    y *= amp * (0.8 + 0.2 * np.sin(2 * np.pi * 7 * t))
    y = norm(y) * 0.8
    tail = wood_crack(0.2, clicks=14, tail_tau=0.05) * 0.5
    place(y, tail, dur - 0.16)
    return fade(norm(y), 0.004, 0.04)


def thud(f_start=120.0, f_end=46.0, dur=0.42, tau=0.12):
    """Низкий тумп: синус с провалом частоты + шум под 300 Гц, мягкая сатурация."""
    n = ns(dur)
    t = t_axis(dur)
    f = f_end + (f_start - f_end) * np.exp(-t / 0.035)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(n, tau, 0.001)
    y += lp(rng.standard_normal(n), 300) * env_exp(n, 0.025) * 0.9
    y += hp(rng.standard_normal(n) * env_exp(n, 0.002), 1500) * 0.25
    y = np.tanh(1.6 * y) / np.tanh(1.6)
    return fade(norm(y), 0.0005, 0.05)


def boom(dur=1.6, f_start=92.0, f_end=32.0):
    """Бум крита: суб-провал + средний удар 180 Гц + шум под 900 Гц + длинный тёмный хвост; сатурация."""
    n = ns(dur)
    t = t_axis(dur)
    f = f_end + (f_start - f_end) * np.exp(-t / 0.22)
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(n, 0.5, 0.002)
    mid = np.sin(2 * np.pi * 180 * t) * env_exp(n, 0.05, 0.001) * 0.6
    burst = lp(rng.standard_normal(n), 900) * env_exp(n, 0.12, 0.001) * 0.9
    tail = lp(rng.standard_normal(n), 380, 3) * env_exp(n, 0.55, 0.05) * 0.35
    click = hp(rng.standard_normal(n) * env_exp(n, 0.003), 1200) * 0.35
    y = sub + mid + burst + tail + click
    y = np.tanh(2.0 * y) / np.tanh(2.0)
    return fade(norm(y), 0.001, 0.25)


def whoosh(dur=0.5, f_lo=320.0, f_hi=1500.0, peak=0.42, q=1.4):
    """Вух: шум через полосовой фильтр, центр скользит f_lo → f_hi → f_lo·1.3, огибающая-горб; снизу гул."""
    n = ns(dur)
    x = rng.standard_normal(n)
    block = 128
    y = np.zeros(n)
    zi = None
    for i in range(0, n, block):
        k = i / n
        if k < peak:
            fc = f_lo * (f_hi / f_lo) ** (k / peak)
        else:
            fc = f_hi * ((f_lo * 1.3) / f_hi) ** ((k - peak) / (1 - peak))
        b, a = signal.iirpeak(fc, q, fs=SR)
        if zi is None:
            zi = signal.lfilter_zi(b, a) * 0.0
        seg, zi = signal.lfilter(b, a, x[i:i + block], zi=zi)
        y[i:i + block] = seg
    k = np.arange(n) / n
    amp = np.where(k < peak, (k / peak) ** 1.6, ((1 - k) / (1 - peak)) ** 1.3)
    y = y * amp + lp(rng.standard_normal(n), 160) * amp * 0.5
    return fade(norm(y), 0.005, 0.03)


def inhale(dur=0.095):
    """Вдох-реверс: хвост треска и шипения, развёрнутый назад, — нарастает и обрывается на пике (дальше тишина до бума)."""
    n = ns(0.6)
    src = np.zeros(n)
    place(src, wood_crack(0.3, clicks=30), 0.0, 0.8)
    place(src, band(rng.standard_normal(n), 400, 5000) * env_exp(n, 0.12, 0.001), 0.0, 0.7)
    ir = rng.standard_normal(int(0.25 * SR)) * env_exp(int(0.25 * SR), 0.07)
    wet = signal.fftconvolve(src, ir)[:n]
    wet = norm(wet)
    rev = wet[::-1]
    y = rev[-ns(dur):]
    y = y * np.linspace(0.2, 1.0, len(y)) ** 1.5
    y = norm(y)
    y[-int(0.0015 * SR):] *= np.linspace(1, 0, int(0.0015 * SR))
    return y


def crash(dur=0.6):
    """Удар о стену в крит-полёте: тумп + треск + стук разлетающихся щепок."""
    n = ns(dur)
    y = np.zeros(n)
    place(y, thud(130, 44, 0.45, 0.1), 0.0, 0.9)
    place(y, wood_crack(0.35, clicks=48), 0.0, 0.8)
    place(y, hp(rng.standard_normal(n), 400) * env_exp(n, 0.06, 0.001), 0.0, 0.35)
    t0 = 0.03
    for i in range(9):
        t0 += rng.uniform(0.02, 0.06) * (1 + i * 0.15)
        if t0 > dur - 0.1:
            break
        place(y, wood_tok(rng.uniform(700, 1900), 0.02, rng.uniform(180, 260), dur=0.12), t0, 0.35 * np.exp(-t0 / 0.25))
    return fade(norm(y), 0.0005, 0.08)


def shatter(dur=0.8):
    """Кукла рассыпается (KO): снап + детали стучат об пол с укорачивающимися интервалами."""
    n = ns(dur)
    y = np.zeros(n)
    place(y, wood_crack(0.3, clicks=40), 0.0, 1.0)
    for _ in range(4):
        t0 = rng.uniform(0.05, 0.12)
        gap = rng.uniform(0.09, 0.16)
        f = rng.uniform(500, 1500)
        amp = rng.uniform(0.35, 0.6)
        while t0 < dur - 0.12 and amp > 0.05:
            place(y, wood_tok(f * rng.uniform(0.97, 1.03), 0.022, rng.uniform(150, 240), dur=0.12), t0, amp)
            t0 += gap
            gap *= 0.72
            amp *= 0.62
    return fade(norm(y), 0.0005, 0.08)


def crowd_oof(dur=0.95, voices=28):
    """«Ох» толпы: 28 голосов (пила до 4 кГц, f0 100–260 Гц, падение тона ~15 %, вибрато), форманты «о» 500/850/2500 Гц."""
    n = ns(dur)
    t = t_axis(dur)
    y = np.zeros(n)
    for _ in range(voices):
        f0 = rng.uniform(100, 150) if rng.random() < 0.6 else rng.uniform(180, 260)
        onset = rng.uniform(0.0, 0.07)
        k = np.clip((t - onset) / (dur - onset), 0, 1)
        glide = 1.06 - 0.17 * (k * k * (3 - 2 * k))
        vib = 1 + 0.015 * np.sin(2 * np.pi * rng.uniform(4.5, 6.0) * t + rng.uniform(0, 6.28))
        f = f0 * glide * vib
        ph = 2 * np.pi * np.cumsum(f) / SR
        v = np.zeros(n)
        for h in range(1, int(4000 / f0)):
            v += np.sin(h * ph) / h
        att = rng.uniform(0.04, 0.09)
        a = np.clip((t - onset) / att, 0, 1) * np.exp(-np.clip(t - onset - 0.15, 0, None) / rng.uniform(0.25, 0.4))
        y += v * a * rng.uniform(0.5, 1.0)
    breath = rng.standard_normal(n) * np.clip(t / 0.05, 0, 1) * np.exp(-t / 0.35) * 0.5
    src = y / voices + breath * 0.04
    out = bp(src, 500, 4) * 1.0 + bp(src, 850, 5) * 0.6 + bp(src, 2500, 7) * 0.12
    out = lp(out, 3500)
    return fade(norm(out), 0.01, 0.2)


# --- запись ---

def write_ogg(x, rel):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.clip(x, -1, 1)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav = tmp.name
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", OGG_Q, path], check=True)
    os.unlink(wav)
    rms = 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
    print(f"  {rel:34s} {len(x) / SR:5.2f} s  rms {rms:6.1f} dBFS  {os.path.getsize(path) / 1024:5.1f} KB")


def src(rel):
    return load(os.path.join(SRC, rel))


def main():
    if os.path.isdir(OUT):
        for d in os.listdir(OUT):
            p = os.path.join(OUT, d)
            if os.path.isdir(p):
                for f in os.listdir(p):
                    if f.endswith(".ogg"):
                        os.unlink(os.path.join(p, f))
    os.makedirs(OUT, exist_ok=True)
    print("CC0-сэмплы:")
    for i in range(1, 6):
        write_ogg(norm(trim_source(src(f"combat/qubodup/qubodupPunch0{i}.ogg"), length=0.32)), f"punch/qubodup_punch_0{i}.ogg")
    for i in (28, 34):
        write_ogg(norm(trim_source(src(f"combat/hits/hit-{i}.ogg"), length=0.3)), f"punch/hit_{i}.ogg")
    for i in (19, 35):
        write_ogg(norm(lp(trim_source(src(f"combat/hits/hit-{i}.ogg"), length=0.34), 380, 4)), f"thud/hit_{i}_low.ogg")
    for i in (1, 2):
        write_ogg(norm(trim_source(src(f"combat/ko-0{i}.ogg"), length=0.42)), f"ko/ko_0{i}.ogg")
    for i in (1, 2):
        write_ogg(norm(trim_source(src(f"combat/zap_{i}.ogg"), length=0.85, fade_out=0.2), -3.0), f"zap_low/zap_{i}.ogg")
    for i in (1, 3):
        write_ogg(norm(trim_source(src(f"combat/phaser_up_{i}.ogg"), fade_out=0.06), -3.0), f"whistle/phaser_up_{i}.ogg")
    write_ogg(norm(trim_source(src("sfx/fight-gong.ogg"), pre=0.0, fade_out=0.08)), "gong/fight_gong.ogg")
    write_ogg(fade(loud(trim_source(src("sfx/crowd-cheer.ogg"), length=2.6, fade_out=0.01), -20.0), 0.0005, 0.7), "crowd_cheer/crowd_cheer.ogg")
    print("Синтез (seed 29):")
    for i, (f0, tau, body) in enumerate(((430, 0.040, 150), (520, 0.034, 170), (610, 0.030, 160), (700, 0.036, 185),
                                         (820, 0.028, 175), (940, 0.026, 200), (560, 0.045, 140), (760, 0.032, 190))):
        write_ogg(wood_tok(f0, tau, body), f"tok/wood_tok_{i + 1:02d}.ogg")
    for i, (d, c, bf) in enumerate(((0.36, 34, (320, 610)), (0.4, 44, (280, 540)), (0.3, 28, (360, 700)), (0.45, 52, (300, 580)))):
        write_ogg(wood_crack(d, c, bf), f"crack/wood_crack_{i + 1:02d}.ogg")
    for i, (fs, fe, d, tau) in enumerate(((120, 46, 0.42, 0.12), (105, 40, 0.48, 0.14), (140, 52, 0.38, 0.1))):
        write_ogg(thud(fs, fe, d, tau), f"thud/thud_{i + 1:02d}.ogg")
    write_ogg(boom(1.6, 92, 32), "boom/boom_01.ogg")
    write_ogg(boom(1.4, 84, 36), "boom/boom_02.ogg")
    for i, (d, lo, hi, pk) in enumerate(((0.5, 320, 1500, 0.42), (0.6, 260, 1200, 0.38), (0.42, 380, 1900, 0.45), (0.55, 300, 1000, 0.5))):
        write_ogg(whoosh(d, lo, hi, pk), f"whoosh/whoosh_{i + 1:02d}.ogg")
    write_ogg(inhale(0.095), "inhale/inhale_rev_01.ogg")
    write_ogg(inhale(0.095), "inhale/inhale_rev_02.ogg")
    write_ogg(creak(0.5), "creak/fiber_creak_01.ogg")
    write_ogg(creak(0.45, (34, 95, 50)), "creak/fiber_creak_02.ogg")
    write_ogg(crash(0.6), "crash/crash_01.ogg")
    write_ogg(crash(0.55), "crash/crash_02.ogg")
    write_ogg(shatter(0.8), "shatter/shatter_01.ogg")
    write_ogg(shatter(0.75), "shatter/shatter_02.ogg")
    write_ogg(crowd_oof(0.95), "crowd_oof/crowd_oof_01.ogg")
    write_ogg(crowd_oof(0.85, 24), "crowd_oof/crowd_oof_02.ogg")
    total = 0
    for root, _, files in os.walk(OUT):
        for f in files:
            if f.endswith(".ogg"):
                total += os.path.getsize(os.path.join(root, f))
    print(f"итого {total / 1024:.0f} KB → {OUT}")


if __name__ == "__main__":
    if shutil.which("ffmpeg") is None:
        raise SystemExit("нужен ffmpeg с libvorbis")
    main()
