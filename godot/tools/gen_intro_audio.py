#!/usr/bin/env python3
"""Звуки заставки-комикса (docs/plan-demo/INTRO_COMIC.md): синтез без внешних файлов, numpy → WAV 44.1 кГц моно 16 бит.

    python3 godot/tools/gen_intro_audio.py            # → godot/assets/audio/intro/*.wav

Звуки — временные, пока нет настоящего саунд-дизайна: их легко заменить файлами с теми же именами.
  amb_scrap   — ветер Свалки, далёкий гул и скрипы металла (петля 16 с)
  whoosh      — перелёт камеры к панели           whoosh_big — отъезд на ряд / страницу
  type        — печать строки Башни (серия щелчков) beep       — появление таблички Башни
  tk          — тиканье Ядра                        stab       — «!» (кукла очнулась)
  bonk        — бочка по деревянной голове          scrape     — вытащила деталь из кучи
  click       — деталь встала на место              clank      — враг приземлился (металл)
  bam         — удар                                shatter    — кукла рассыпается на детали
  rain        — хлам сыплется сверху                sting      — логотип
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "intro")
rng = np.random.default_rng(7)


def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def env_exp(sec, decay, attack=0.002):
    t = t_axis(sec)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / decay)


def biquad(x, kind, f0, q=0.707, gain_db=0.0):
    """RBJ biquad: lp, hp, bp, peak."""
    w0 = 2 * np.pi * f0 / SR
    alpha = np.sin(w0) / (2 * q)
    c = np.cos(w0)
    if kind == "lp":
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
        a = [1 + alpha, -2 * c, 1 - alpha]
    elif kind == "hp":
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
        a = [1 + alpha, -2 * c, 1 - alpha]
    elif kind == "bp":
        b = [alpha, 0, -alpha]
        a = [1 + alpha, -2 * c, 1 - alpha]
    else:
        A = 10 ** (gain_db / 40)
        b = [1 + alpha * A, -2 * c, 1 - alpha * A]
        a = [1 + alpha / A, -2 * c, 1 - alpha / A]
    b = np.array(b) / a[0]
    a = np.array(a) / a[0]
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for n in range(len(x)):
        xn = x[n]
        yn = b[0] * xn + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        x2, x1, y2, y1 = x1, xn, y1, yn
        y[n] = yn
    return y


def sweep_bp(x, f_start, f_end, q=1.2, block=256):
    """Полосовой фильтр с плавающей частотой (по блокам)."""
    y = np.zeros_like(x)
    n_blocks = int(np.ceil(len(x) / block))
    state = [0.0, 0.0, 0.0, 0.0]
    for i in range(n_blocks):
        k = i / max(n_blocks - 1, 1)
        f0 = f_start * (f_end / f_start) ** k
        w0 = 2 * np.pi * f0 / SR
        alpha = np.sin(w0) / (2 * q)
        c = np.cos(w0)
        b0, b2 = alpha / (1 + alpha), -alpha / (1 + alpha)
        a1, a2 = -2 * c / (1 + alpha), (1 - alpha) / (1 + alpha)
        x1, x2, y1, y2 = state
        for n in range(i * block, min((i + 1) * block, len(x))):
            xn = x[n]
            yn = b0 * xn + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, xn, y1, yn
            y[n] = yn
        state = [x1, x2, y1, y2]
    return y


def reverb(x, mix=0.25, room=0.82, damp=0.3, tail=1.2):
    """Маленький Шрёдер: 4 гребёнки + 2 всепропускающих; хвост дописывается в конец."""
    x = np.concatenate([x, np.zeros(int(tail * SR))])
    out = np.zeros_like(x)
    for d in (1116, 1188, 1277, 1356):
        buf = np.zeros(d)
        idx = 0
        lp = 0.0
        y = np.zeros_like(x)
        for n in range(len(x)):
            o = buf[idx]
            lp = o * (1 - damp) + lp * damp
            buf[idx] = x[n] + lp * room
            idx = (idx + 1) % d
            y[n] = o
        out += y
    for d in (225, 556):
        buf = np.zeros(d)
        idx = 0
        y = np.zeros_like(out)
        for n in range(len(out)):
            b = buf[idx]
            v = out[n] + b * 0.5
            buf[idx] = v
            y[n] = b - v * 0.5
            idx = (idx + 1) % d
        out = y
    return x * (1 - mix) + out * mix * 0.25


def noise(sec):
    return rng.standard_normal(int(sec * SR))


def brown(sec):
    w = rng.standard_normal(int(sec * SR))
    b = np.cumsum(w)
    b -= biquad(b, "lp", 8.0)       # убрать дрейф
    return b / (np.max(np.abs(b)) + 1e-9)


def partials(sec, freqs, decays, amps):
    t = t_axis(sec)
    y = np.zeros_like(t)
    for f, d, a in zip(freqs, decays, amps):
        y += a * np.sin(2 * np.pi * f * t + rng.random() * 6.28) * np.exp(-t / d)
    return y


def fit(x, sec):
    n = int(sec * SR)
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def norm(x, peak=0.9):
    m = np.max(np.abs(x))
    return x / m * peak if m > 0 else x


def fade(x, fin=0.003, fout=0.02):
    n_in, n_out = int(fin * SR), int(fout * SR)
    x = x.copy()
    if n_in:
        x[:n_in] *= np.linspace(0, 1, n_in)
    if n_out:
        x[-n_out:] *= np.linspace(1, 0, n_out)
    return x


def save(name, x, peak=0.9, loop=False):
    os.makedirs(OUT, exist_ok=True)
    x = norm(x if loop else fade(x), peak)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{name}.wav  {len(x) / SR:.2f} s")


# ------------------------------------------------------------------------------------------------
def amb_scrap():
    sec = 16.0
    t = t_axis(sec)
    wind = biquad(brown(sec), "lp", 700.0) * 0.6
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / sec * 2 + 0.7) * np.sin(2 * np.pi * t / sec * 3 + 1.9)
    whistle = sweep_bp(noise(sec) * 0.25, 900, 1300, q=9.0) * (0.5 + 0.5 * np.sin(2 * np.pi * t / sec * 1))
    drone = 0.18 * np.sin(2 * np.pi * 55 * t) + 0.1 * np.sin(2 * np.pi * 82.4 * t + 1.0) * (0.6 + 0.4 * np.sin(2 * np.pi * t / sec * 2))
    y = wind * gust + whistle * 0.35 + drone
    # далёкие удары и скрипы металла
    for k in range(7):
        at = int((0.8 + k * 2.2 + rng.random() * 0.9) * SR)
        f = rng.choice([143, 171, 199, 233])
        ping = partials(2.5, [f, f * 2.76, f * 5.4, f * 8.93], [1.2, 0.7, 0.35, 0.2], [1, 0.6, 0.35, 0.2])
        ping = biquad(ping, "lp", 1800) * 0.12
        end = min(len(y), at + len(ping))
        y[at:end] += ping[:end - at]
    y = reverb(y, mix=0.35, room=0.86, tail=0.0)[:len(t)]
    # бесшовная петля: перекрёстное затухание хвоста в начало
    xf = int(1.5 * SR)
    head = y[:xf].copy()
    y[:xf] = head * np.linspace(0, 1, xf) + y[-xf:] * np.linspace(1, 0, xf)
    y = y[:-xf]
    save("amb_scrap", y, 0.7, loop=True)


def whoosh(name, sec, f0, f1, peak):
    t = t_axis(sec)
    e = np.sin(np.pi * np.clip(t / sec, 0, 1)) ** 1.6
    y = sweep_bp(noise(sec), f0, f1, q=1.4) * e + biquad(noise(sec), "lp", 300) * e * 0.3
    save(name, reverb(y, 0.2, tail=0.4), peak)


def type_run():
    # 26 щелчков за ~0.9 с (28 знаков/с), чуть разные
    sec = 1.0
    y = np.zeros(int(sec * SR))
    for k in range(26):
        at = int(k / 28.0 * SR + rng.integers(-150, 150))
        at = max(at, 0)
        click = partials(0.03, [2200 + rng.random() * 600, 4100], [0.004, 0.002], [1, 0.4]) + noise(0.03) * env_exp(0.03, 0.003) * 0.4
        y[at:at + len(click)] += click[:len(y) - at] * (0.7 + 0.3 * rng.random())
    save("type", biquad(y, "hp", 600), 0.5)


def beep():
    t = t_axis(0.16)
    sq = np.sign(np.sin(2 * np.pi * 880 * t)) * 0.5 + np.sign(np.sin(2 * np.pi * 1320 * t)) * 0.25
    e = np.where(t < 0.07, 1.0, 0.0) + np.where(t >= 0.09, 1.0, 0.0) * np.where(t < 0.16, 1.0, 0.0)
    save("beep", biquad(sq * e, "lp", 3000) * 0.6, 0.35)


def tk():
    sec = 1.6
    y = np.zeros(int(sec * SR))
    for k in range(4):
        at = int((0.05 + k * 0.38) * SR)
        c = partials(0.08, [3100, 5200, 1500], [0.01, 0.006, 0.02], [1, 0.5, 0.4])
        y[at:at + len(c)] += c * (1.0 if k % 2 == 0 else 0.7)
    save("tk", reverb(y, 0.15, tail=0.2), 0.45)


def stab():
    sec = 0.9
    t = t_axis(sec)
    tone = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(587, 1), (880, 0.6), (1175, 0.4), (1760, 0.2)])
    e = env_exp(sec, 0.25, 0.004)
    hit = biquad(noise(sec), "hp", 2000) * env_exp(sec, 0.02) * 0.5
    save("stab", reverb(tone * e * 0.5 + hit, 0.3, tail=0.6), 0.6)


def bonk():
    sec = 0.9
    t = t_axis(sec)
    f = 230 * np.exp(-t * 1.2)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = (np.sin(ph) + 0.4 * np.sin(2.7 * ph)) * env_exp(sec, 0.14)
    knock = biquad(noise(sec), "bp", 900, 2.0) * env_exp(sec, 0.012)
    # мультяшное «бойнг»: вибрато по высоте
    fb = 320 + 40 * np.sin(2 * np.pi * 14 * t) * np.exp(-t * 3)
    boing = np.sin(2 * np.pi * np.cumsum(fb) / SR) * env_exp(sec, 0.3, 0.02) * 0.35
    save("bonk", reverb(body + knock * 0.8 + boing, 0.2, tail=0.4), 0.9)


def scrape():
    sec = 0.5
    t = t_axis(sec)
    e = np.sin(np.pi * t / sec) ** 0.7
    rough = sweep_bp(noise(sec), 2500, 1200, q=2.5) * e * (0.7 + 0.3 * np.sign(np.sin(2 * np.pi * 38 * t)))
    knocks = np.zeros_like(t)
    for k in range(5):
        at = int((0.05 + k * 0.08) * SR)
        c = biquad(noise(0.05), "bp", 700 + 150 * k, 3.0) * env_exp(0.05, 0.01)
        knocks[at:at + len(c)] += c
    save("scrape", reverb(rough + knocks * 0.8, 0.15, tail=0.3), 0.6)


def click():
    sec = 0.6
    snap = biquad(noise(sec), "hp", 3000) * env_exp(sec, 0.004) * 1.2
    ring = partials(sec, [2870, 4210, 6630, 1370], [0.09, 0.05, 0.03, 0.12], [0.6, 0.45, 0.25, 0.4])
    ratchet = np.zeros(int(sec * SR))
    for k in range(3):
        at = int((0.025 + k * 0.03) * SR)
        c = biquad(noise(0.02), "bp", 5000, 4.0) * env_exp(0.02, 0.003)
        ratchet[at:at + len(c)] += c * 0.5
    save("click", reverb(snap + ring + ratchet, 0.2, tail=0.4), 0.8)


def clank():
    sec = 1.8
    f = 157.0
    metal = partials(sec, [f, f * 2.41, f * 4.13, f * 7.02, f * 10.4, f * 13.7], [0.9, 0.6, 0.35, 0.25, 0.15, 0.1], [1, 0.8, 0.6, 0.4, 0.3, 0.2])
    thud = np.sin(2 * np.pi * 70 * t_axis(sec)) * env_exp(sec, 0.08)
    hit = biquad(noise(sec), "bp", 2500, 1.0) * env_exp(sec, 0.02)
    save("clank", reverb(metal * 0.6 + thud * 0.9 + hit * 0.7, 0.3, room=0.85, tail=0.8), 0.9)


def bam():
    sec = 1.0
    t = t_axis(sec)
    f = 140 * np.exp(-t * 9) + 45
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(sec, 0.22, 0.001)
    crack = biquad(noise(sec), "hp", 1500) * env_exp(sec, 0.03) * 0.9
    wood = biquad(noise(sec), "bp", 650, 3.0) * env_exp(sec, 0.05)
    y = np.tanh((thump * 1.4 + crack + wood * 0.8) * 1.8)
    save("bam", reverb(y, 0.25, room=0.8, tail=0.8), 0.95)


def shatter():
    sec = 1.6
    y = np.zeros(int(sec * SR))
    for k in range(22):
        at = int((rng.random() ** 1.6) * 1.1 * SR)
        fq = rng.uniform(450, 1600)
        c = partials(0.25, [fq, fq * 2.3], [0.04, 0.02], [1, 0.4]) + biquad(noise(0.25), "bp", fq, 3.0) * env_exp(0.25, 0.015) * 0.6
        g = (1.0 - at / (1.3 * SR)) * rng.uniform(0.3, 1.0)
        end = min(len(y), at + len(c))
        y[at:end] += c[:end - at] * g
    save("shatter", reverb(y, 0.25, tail=0.5), 0.7)


def rain():
    sec = 3.6
    y = np.zeros(int(sec * SR))
    for k in range(34):
        at = int(rng.uniform(0.2, 3.2) * SR)
        if rng.random() < 0.5:
            fq = rng.uniform(300, 900)
            c = partials(0.3, [fq, fq * 2.2], [0.05, 0.03], [1, 0.4])
        else:
            f0 = rng.uniform(180, 320)
            c = partials(0.6, [f0, f0 * 2.76, f0 * 5.4], [0.3, 0.15, 0.08], [1, 0.5, 0.3])
        g = rng.uniform(0.15, 0.6)
        end = min(len(y), at + len(c))
        y[at:end] += c[:end - at] * g
    y += biquad(brown(sec), "lp", 400) * 0.15
    save("rain", reverb(biquad(y, "lp", 3500), 0.35, room=0.85, tail=0.8), 0.55)


def sting():
    sec = 4.0
    t = t_axis(sec)
    boom = np.sin(2 * np.pi * np.cumsum(38 + 60 * np.exp(-t * 6)) / SR) * env_exp(sec, 0.9, 0.003)
    hit = biquad(noise(sec), "lp", 5000) * env_exp(sec, 0.08) * 0.7
    # «медь»: пилы ре-минорного квинтаккорда через фильтр, раскрывается и гаснет
    chord = np.zeros_like(t)
    for f in (73.4, 110.0, 146.8, 220.0, 293.7):
        for det in (-0.12, 0.0, 0.13):
            ph = (t * (f + det)) % 1.0
            chord += (2 * ph - 1) * (0.5 if f > 150 else 0.8)
    chord = biquad(chord, "lp", 1400) * env_exp(sec, 1.3, 0.01) * 0.25
    y = np.tanh(boom * 1.3 + hit + chord)
    save("sting", reverb(y, 0.35, room=0.88, tail=1.5), 0.95)


if __name__ == "__main__":
    amb_scrap()
    whoosh("whoosh", 0.55, 300, 2400, 0.5)
    whoosh("whoosh_big", 1.1, 1800, 220, 0.55)
    type_run()
    beep()
    tk()
    stab()
    bonk()
    scrape()
    click()
    clank()
    bam()
    shatter()
    rain()
    sting()
