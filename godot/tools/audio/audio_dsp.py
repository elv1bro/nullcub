"""DSP-хелперы сборки звука (tools/audio/build_audio.py, docs/plan-demo/AUDIO.md §3): загрузка через ffmpeg, фильтры, питч,
нарезка по тишине, громкость по BS.1770 (K-взвешивание: моментальная 400 мс и интегральная с гейтом), true-peak, бесшовные
петли, запись OGG Vorbis. Сигнал — numpy float64: моно (n,) или стерео (n, 2).
"""
import os
import subprocess
import tempfile
import wave

import numpy as np
from scipy import signal

SR = 44100


# --- ввод / вывод ---

def load(path, ss=None, t=None, stereo=False, sr=SR):
    """Файл → float64 (моно (n,) или стерео (n, 2)); ss/t — окно в секундах."""
    cmd = ["ffmpeg", "-v", "error"]
    if ss is not None:
        cmd += ["-ss", f"{ss:.4f}"]
    if t is not None:
        cmd += ["-t", f"{t:.4f}"]
    cmd += ["-i", os.path.expanduser(path), "-ac", "2" if stereo else "1", "-ar", str(sr), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    return x.reshape(-1, 2) if stereo else x


def write_ogg(path, x, q="5"):
    """float → OGG Vorbis (libvorbis, качество q). Каталог создаётся."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.asarray(x)
    ch = 2 if x.ndim == 2 else 1
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        tmp = tf.name
    try:
        with wave.open(tmp, "wb") as w:
            w.setnchannels(ch)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", q, path], check=True)
    finally:
        os.remove(tmp)


# --- форма сигнала ---

def ns(sec):
    return int(round(sec * SR))


def mono(x):
    return x.mean(axis=1) if x.ndim == 2 else x


def to_stereo(x, width=0.0, seed=0):
    """Моно → стерео; width > 0 — лёгкая декорреляция (разные all-pass в каналах)."""
    if x.ndim == 2:
        return x
    if width <= 0:
        return np.stack([x, x], axis=1)
    rng = np.random.default_rng(seed)
    out = []
    for c in range(2):
        y = x.copy()
        for _ in range(3):
            a = rng.uniform(0.3, 0.7) * (1 if c == 0 else -1)
            d = rng.integers(20, 120)
            y = allpass(y, d, a)
        out.append((1 - width) * x + width * y)
    return np.stack(out, axis=1)


def allpass(x, d, g):
    b = np.zeros(d + 1)
    a = np.zeros(d + 1)
    b[0], b[d] = -g, 1.0
    a[0], a[d] = 1.0, -g
    return signal.lfilter(b, a, x)


def _apply(x, fn):
    if x.ndim == 2:
        return np.stack([fn(x[:, 0]), fn(x[:, 1])], axis=1)
    return fn(x)


def hp(x, fc, order=2):
    b, a = signal.butter(order, fc, "high", fs=SR)
    return _apply(x, lambda c: signal.lfilter(b, a, c))


def lp(x, fc, order=2):
    b, a = signal.butter(order, min(fc, SR * 0.45), "low", fs=SR)
    return _apply(x, lambda c: signal.lfilter(b, a, c))


def band(x, f1, f2, order=2):
    b, a = signal.butter(order, [f1, min(f2, SR * 0.45)], "band", fs=SR)
    return _apply(x, lambda c: signal.lfilter(b, a, c))


def peak_eq(x, f0, gain_db, q=1.0):
    """Пиковый эквалайзер (RBJ)."""
    A = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / SR
    al = np.sin(w0) / (2 * q)
    b = np.array([1 + al * A, -2 * np.cos(w0), 1 - al * A])
    a = np.array([1 + al / A, -2 * np.cos(w0), 1 - al / A])
    return _apply(x, lambda c: signal.lfilter(b / a[0], a / a[0], c))


def shelf(x, f0, gain_db, high=True):
    """Полочный фильтр (RBJ, S = 1)."""
    A = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / SR
    al = np.sin(w0) / 2 * np.sqrt(2)
    cw = np.cos(w0)
    s = 1 if high else -1
    b = np.array([A * ((A + 1) + s * (A - 1) * cw + 2 * np.sqrt(A) * al),
                  -2 * s * A * ((A - 1) + s * (A + 1) * cw),
                  A * ((A + 1) + s * (A - 1) * cw - 2 * np.sqrt(A) * al)])
    a = np.array([(A + 1) - s * (A - 1) * cw + 2 * np.sqrt(A) * al,
                  2 * s * ((A - 1) - s * (A + 1) * cw),
                  (A + 1) - s * (A - 1) * cw - 2 * np.sqrt(A) * al])
    return _apply(x, lambda c: signal.lfilter(b / a[0], a / a[0], c))


def resonator(x, f0, q, gain=1.0):
    """Резонатор (iirpeak) — «корпус» детали: гулкость головы, звон металла."""
    b, a = signal.iirpeak(min(f0, SR * 0.45), q, fs=SR)
    return _apply(x, lambda c: signal.lfilter(b, a, c) * gain)


def pitch(x, ratio):
    """Ленточный питч: ratio > 1 — выше и короче (ресемплинг)."""
    if abs(ratio - 1.0) < 1e-4:
        return x
    from fractions import Fraction
    fr = Fraction(1.0 / ratio).limit_denominator(200)
    return _apply(x, lambda c: signal.resample_poly(c, fr.numerator, fr.denominator))


def stretch_pitch(x, ratio):
    return pitch(x, ratio)


def reverse(x):
    return x[::-1].copy()


def saturate(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def gain_db(x, db):
    return x * 10 ** (db / 20)


def fade(x, fin=0.002, fout=0.02, curve=2.0):
    x = x.copy()
    n = len(x)
    ni = min(n, max(1, ns(fin)))
    no = min(n, max(1, ns(fout)))
    ein = np.linspace(0, 1, ni)
    eout = np.linspace(1, 0, no) ** curve
    if x.ndim == 2:
        x[:ni] *= ein[:, None]
        x[-no:] *= eout[:, None]
    else:
        x[:ni] *= ein
        x[-no:] *= eout
    return x


def env(n, attack, hold, release, curve=2.0):
    """Огибающая длиной n: подъём, удержание, спад (экспоненциальная форма curve)."""
    e = np.zeros(n)
    a, h = ns(attack), ns(hold)
    r = max(1, n - a - h)
    if a > 0:
        e[:a] = np.linspace(0, 1, a) ** 0.7
    e[a:a + h] = 1.0
    e[a + h:] = np.linspace(1, 0, n - a - h) ** curve if n - a - h > 0 else 0
    return e[:n]


def apply_env(x, e):
    return x * (e[:, None] if x.ndim == 2 else e)


def exp_decay(n, tau, attack=0.0005):
    t = np.arange(n) / SR
    return np.clip(t / max(attack, 1e-5), 0, 1) * np.exp(-t / tau)


def fit(x, sec):
    n = ns(sec)
    if len(x) >= n:
        return x[:n].copy()
    pad = [(0, n - len(x))] + ([(0, 0)] if x.ndim == 2 else [])
    return np.pad(x, pad)


def mix(parts, length=None):
    """parts: [(x, offset_s, gain_db)] → сумма (моно/стерео по первому стерео в списке)."""
    st = any(p[0].ndim == 2 for p in parts)
    n = length if length is not None else max(ns(o) + len(x) for x, o, _ in parts)
    out = np.zeros((n, 2) if st else n)
    for x, o, g in parts:
        if st and x.ndim == 1:
            x = to_stereo(x)
        i = ns(o)
        if i >= n:
            continue
        m = min(len(x), n - i)
        out[i:i + m] += x[:m] * 10 ** (g / 20)
    return out


# --- нарезка ---

def envelope_db(x, win=0.01):
    m = mono(x)
    h = max(1, ns(win))
    k = len(m) // h
    r = np.sqrt(np.mean(m[:k * h].reshape(k, h) ** 2, axis=1) + 1e-12)
    return 20 * np.log10(r + 1e-12), h


def trim(x, thr_db=-50.0, pre=0.003, post=0.04):
    """Обрезка тишины по краям (порог относительно пика огибающей)."""
    e, h = envelope_db(x, 0.005)
    if len(e) == 0:
        return x
    ref = e.max()
    idx = np.where(e > ref + thr_db)[0]
    if len(idx) == 0:
        return x
    a = max(0, idx[0] * h - ns(pre))
    b = min(len(x), (idx[-1] + 1) * h + ns(post))
    return x[a:b].copy()


def split(x, thr_db=-35.0, min_gap=0.08, min_len=0.05, pad=0.01):
    """Делит запись с несколькими событиями по тишине: [(start_s, end_s)]."""
    e, h = envelope_db(x, 0.005)
    ref = e.max()
    on = e > ref + thr_db
    segs, start, gap = [], None, 0
    gap_n = int(min_gap / 0.005)
    for i, v in enumerate(on):
        if v:
            if start is None:
                start = i
            gap = 0
        elif start is not None:
            gap += 1
            if gap > gap_n:
                segs.append((start, i - gap))
                start, gap = None, 0
    if start is not None:
        segs.append((start, len(on) - 1))
    out = []
    for a, b in segs:
        s0 = max(0.0, a * h / SR - pad)
        s1 = min(len(x) / SR, (b + 1) * h / SR + pad)
        if s1 - s0 >= min_len:
            out.append((s0, s1))
    return out


def cut(x, s0, s1):
    return x[ns(s0):ns(s1)].copy()


# --- громкость (ITU-R BS.1770) ---

def _kweight(m):
    # pre-filter (high shelf +4 dB @ ~1.68 кГц) и RLB (high-pass ~38 Гц), коэффициенты для 48 кГц пересчитаны билинейно под SR
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = np.tan(np.pi * f0 / SR)
    Vh = 10 ** (G / 20)
    Vb = Vh ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    b1 = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a1 = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = np.tan(np.pi * f0 / SR)
    a0 = 1 + K / Q + K * K
    b2 = [1, -2, 1]
    a2 = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    return signal.lfilter(b2, a2, signal.lfilter(b1, a1, m))


def _chan_power(x):
    if x.ndim == 2:
        return [_kweight(x[:, 0]) ** 2, _kweight(x[:, 1]) ** 2]
    return [_kweight(x) ** 2]


def momentary_max(x):
    """Максимальная моментальная громкость (LUFS, окно 400 мс, шаг 10 мс) — мера громкости коротких звуков."""
    pw = _chan_power(x)
    w = ns(0.4)
    tot = sum(pw)
    if len(tot) <= w:
        # короче окна: энергия, отнесённая к 400 мс (как если бы дальше была тишина)
        return -0.691 + 10 * np.log10(np.sum(tot) / w + 1e-15)
    cs = np.concatenate([[0], np.cumsum(tot)])
    step = ns(0.01)
    s = (cs[w::step] - cs[:-w:step][:len(cs[w::step])]) / w
    return -0.691 + 10 * np.log10(s.max() + 1e-15)


def integrated(x):
    """Интегральная громкость (LUFS) с абсолютным −70 и относительным −10 гейтами (блоки 400 мс, перекрытие 75 %)."""
    tot = sum(_chan_power(x))
    w, step = ns(0.4), ns(0.1)
    if len(tot) < w:
        return momentary_max(x)
    blocks = np.array([tot[i:i + w].mean() for i in range(0, len(tot) - w + 1, step)])
    lk = -0.691 + 10 * np.log10(blocks + 1e-15)
    g = blocks[lk > -70]
    if len(g) == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(g.mean()) - 10
    g2 = blocks[(lk > -70) & (lk > rel)]
    return -0.691 + 10 * np.log10(g2.mean() + 1e-15)


def true_peak_db(x):
    m = signal.resample_poly(x, 4, 1, axis=0)
    return 20 * np.log10(np.max(np.abs(m)) + 1e-12)


def limit(x, ceiling_db=-1.0):
    """Мягкий лимитер: всё выше колена сжимается tanh, true-peak не выше ceiling_db."""
    c = 10 ** (ceiling_db / 20)
    for _ in range(4):
        tp = 10 ** (true_peak_db(x) / 20)
        if tp <= c:
            return x
        knee = 0.7 * c
        ax = np.abs(x)
        over = ax > knee
        y = x.copy()
        y[over] = np.sign(x[over]) * (knee + (c - knee) * np.tanh((ax[over] - knee) / (c - knee)))
        x = y * 0.995
    return x * (c / max(10 ** (true_peak_db(x) / 20), 1e-9))


def norm_loudness(x, target_lufs, mode="momentary", ceiling_db=-1.0):
    """Нормализация громкости: momentary (короткие звуки) или integrated (петли, музыка), затем true-peak ≤ ceiling."""
    cur = momentary_max(x) if mode == "momentary" else integrated(x)
    y = x * 10 ** ((target_lufs - cur) / 20)
    return limit(y, ceiling_db)


# --- петли ---

def make_loop(x, xfade=1.0):
    """Бесшовная петля: хвост длиной xfade с равной мощностью наложен на начало. Длина = len(x) − xfade."""
    n = ns(xfade)
    if len(x) <= 2 * n:
        n = len(x) // 3
    body = x[n:].copy()
    head = x[:n]
    tail_start = len(body) - n
    t = np.linspace(0, np.pi / 2, n)
    fin, fout = np.sin(t), np.cos(t)
    if x.ndim == 2:
        fin, fout = fin[:, None], fout[:, None]
    body[tail_start:] = body[tail_start:] * fout + head * fin
    return body


# --- синтез ---

def noise(n, seed=0):
    return np.random.default_rng(seed).uniform(-1, 1, n)


def pink(n, seed=0):
    w = noise(n, seed)
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    return signal.lfilter(b, a, w) * 4.0


def sub_thump(dur=0.35, f0=72.0, f1=38.0, tau=0.12, click=0.25, seed=0):
    """Низ удара: синус с падающей частотой + щелчок, сатурация (слой «веса» под деревом/металлом)."""
    n = ns(dur)
    t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t / 0.04)
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) * exp_decay(n, tau, 0.002)
    c = lp(noise(n, seed), 2500) * exp_decay(n, 0.006, 0.0002) * click
    return saturate(y + c, 1.6)


def tone(freq, dur, kind="sine", seed=0):
    t = np.arange(ns(dur)) / SR
    if kind == "square":
        return np.sign(np.sin(2 * np.pi * freq * t))
    if kind == "saw":
        return 2 * (t * freq % 1.0) - 1
    return np.sin(2 * np.pi * freq * t)
