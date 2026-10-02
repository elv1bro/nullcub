#!/usr/bin/env python3
"""Проверка микса по записи боя (docs/plan-demo/AUDIO.md §6): «уши» агента — числа вместо «послушай».

    python3 godot/tools/audio/mix_check.py fight.avi [--json out.json] [--skip 0.5]

Читает звуковую дорожку (любой формат ffmpeg: AVI Movie Maker, MP4, WAV) и считает по BS.1770 (audio_dsp):
  integrated   — интегральная громкость, LUFS: цель −20…−11 (игра под телевизор/наушники, запас под пики);
  true_peak    — dBTP: не выше −0.3 (лимитер Master −0.5 dB, кодек добавляет);
  momentary    — макс. моментальная, LUFS (пики боя); short_p10/p90 — разброс кратковременной (3 с) громкости;
  silence      — доля блоков 400 мс тише −50 LUFS и самый длинный провал тишины, с: толпа и фон не дают миру замолчать
                 больше MAX_GAP_S (кроме намеренной тишины стоп-кадра крита — она короче);
  clipping     — сэмплов у 0 dBFS (|x| ≥ 0.999).
Exit 0 — всё в пределах, 1 — нет (что не так — в checks).
"""
import argparse
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import audio_dsp as d  # noqa: E402

INTEGRATED_RANGE = (-20.0, -11.0)
TRUE_PEAK_MAX = -0.3
SILENCE_LUFS = -50.0
MAX_GAP_S = 1.5
CLIP_MAX = 50


def analyse(path, skip=0.5):
    x = d.load(path, stereo=True)
    x = x[d.ns(skip):]
    tot = sum(d._chan_power(x))
    w, step = d.ns(0.4), d.ns(0.1)
    blocks = np.array([tot[i:i + w].mean() for i in range(0, max(1, len(tot) - w + 1), step)])
    mom = -0.691 + 10 * np.log10(blocks + 1e-15)
    w3 = d.ns(3.0)
    short = np.array([tot[i:i + w3].mean() for i in range(0, max(1, len(tot) - w3 + 1), d.ns(0.5))])
    short_l = -0.691 + 10 * np.log10(short + 1e-15)
    quiet = mom < SILENCE_LUFS
    gap, best = 0, 0
    for q in quiet:
        gap = gap + 1 if q else 0
        best = max(best, gap)
    res = {
        "file": path, "dur_s": round(len(x) / d.SR, 2),
        "integrated": round(d.integrated(x), 2), "true_peak": round(d.true_peak_db(x), 2),
        "momentary_max": round(float(mom.max()), 2),
        "short_p10": round(float(np.percentile(short_l, 10)), 2), "short_p90": round(float(np.percentile(short_l, 90)), 2),
        "silence_share": round(float(quiet.mean()), 3), "max_gap_s": round(best * 0.1 + 0.3 if best else 0.0, 2),
        "clipping": int(np.sum(np.abs(x) >= 0.999)),
    }
    checks = [
        ["integrated", INTEGRATED_RANGE[0] <= res["integrated"] <= INTEGRATED_RANGE[1], f"{res['integrated']} LUFS ∈ {INTEGRATED_RANGE}"],
        ["true_peak", res["true_peak"] <= TRUE_PEAK_MAX, f"{res['true_peak']} dBTP ≤ {TRUE_PEAK_MAX}"],
        ["no_dead_air", res["max_gap_s"] <= MAX_GAP_S, f"провал тишины {res['max_gap_s']} с ≤ {MAX_GAP_S}"],
        ["clipping", res["clipping"] <= CLIP_MAX, f"{res['clipping']} сэмплов у 0 dBFS ≤ {CLIP_MAX}"],
    ]
    res["checks"] = [{"id": c[0], "ok": bool(c[1]), "detail": c[2]} for c in checks]
    res["ok"] = all(c[1] for c in checks)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--json", default="")
    ap.add_argument("--skip", type=float, default=0.5)
    a = ap.parse_args()
    res = analyse(a.file, a.skip)
    for c in res["checks"]:
        print(f"  {'ok  ' if c['ok'] else 'FAIL'} {c['id']}: {c['detail']}")
    print(f"  info: momentary max {res['momentary_max']} LUFS, short-term p10…p90 {res['short_p10']}…{res['short_p90']}, "
          f"тишина {res['silence_share'] * 100:.1f} %, длительность {res['dur_s']} с")
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(res, f, ensure_ascii=False, indent=1)
    print("=== mix_check: %s ===" % ("OK" if res["ok"] else "FAIL"))
    sys.exit(0 if res["ok"] else 1)


if __name__ == "__main__":
    main()
