"""Шарниры-коннекторы кита (единичный радиус: Godot масштабирует по суставу), шар — цвет игрока."""
import math

from mathutils import Matrix, Vector  # noqa: F401

from kit_common import *  # noqa: F401,F403 — примитивы craft_parts, материалы и узлы кита


def build_Joint_Pin():
    """Шарнир-ось: шар в цвете игрока, на оси (к камере) железные ступицы с шестигранным болтом, поясок-обод."""
    objs = [fin(sphere("J_Ball", 1.0, (0, 0, 0), "Shirt_Kit", 24, 12), angle=80)]
    for sz in (1, -1):
        objs.append(fin(revolve("J_Hub", [(0.0, 0.0), (0.64, 0.0), (0.66, 0.08), (0.58, 0.2), (0.0, 0.2)], "Iron", 22,
                                align_y((0, 0, sz), (0, 0, sz * 0.8))), 0.02, 1, uv="cyl", axis='Z'))
        objs.append(fin(stud("J_Bolt", (0, 0, sz * 0.99), (0, 0, sz), "Steel", 0.3, 0.16, 6)))
    objs.append(fin(torus("J_Rim", (0, 0, 0), 1.0, 0.06, "Iron", 'XY', 28, 6), angle=80))
    return objs, [socket()]


def build_Joint_Free():
    """Свободный шарнир (кистень, «тряпочная» конечность): шар в кольце-кардане, без ступиц."""
    objs = [fin(sphere("JF_Ball", 0.9, (0, 0, 0), "Shirt_Kit", 24, 12), angle=80)]
    objs.append(fin(torus("JF_Gimbal", (0, 0, 0), 1.02, 0.12, "Iron", 'YZ', 28, 8), angle=80))
    objs.append(fin(torus("JF_Gimbal2", (0, 0, 0), 1.02, 0.1, "Iron", 'XY', 28, 8), angle=80))
    return objs, [socket()]


def build_Joint_Spring():
    """Пружинный шарнир: шар + пружина-воротник (сталь) вокруг — «мягкая» связь."""
    objs = [fin(sphere("JS_Ball", 0.85, (0, 0, 0), "Shirt_Kit", 24, 12), angle=80)]
    pts = []
    for i in range(97):
        t = i / 96
        a = TAU * 4 * t
        pts.append((math.cos(a) * 0.95, -0.75 + 1.5 * t, math.sin(a) * 0.95))
    objs.append(fin(sweep("JS_Coil", pts, 0.1, "Steel", sides=6), angle=80))
    return objs, [socket()]


def _gear_outline(r_root, r_tip, teeth):
    """Контур шестерни в плоскости XY: зубец — трапеция на 0.2…0.8 шага, между зубцами — дуга впадины."""
    step = TAU / teeth
    pts = []
    for i in range(teeth):
        a = i * step
        for f, r in ((0.0, r_root), (0.2, r_root), (0.32, r_tip), (0.68, r_tip), (0.8, r_root)):
            pts.append((r * math.cos(a + f * step), r * math.sin(a + f * step)))
    return pts


def build_Joint_Motor():
    """Мотор-шарнир: шар в цвете игрока, железная шестерня (10 зубцов) вокруг оси Z с заклёпками, на оси — ступицы
    с латунным шестигранным болтом."""
    objs = [fin(sphere("JM_Ball", 0.86, (0, 0, 0), "Shirt_Kit", 24, 12), angle=80)]
    objs.append(fin(extrude2d("JM_Gear", _gear_outline(1.0, 1.3, 10), -0.16, 0.16, "Iron"), 0.03, 1, angle=40))
    for sz in (1, -1):
        objs.append(fin(revolve("JM_Hub", [(0.0, 0.0), (0.5, 0.0), (0.53, 0.07), (0.46, 0.17), (0.0, 0.17)], "Iron", 22,
                                align_y((0, 0, sz), (0, 0, sz * 0.8))), 0.02, 1, uv="cyl", axis='Z'))
        objs.append(fin(stud("JM_Bolt", (0, 0, sz * 0.96), (0, 0, sz), "Brass", 0.34, 0.2, 6)))
        for k in range(5):
            a = TAU * k / 5 + TAU / 20
            objs.append(fin(stud("JM_Rivet", (math.cos(a) * 0.93, math.sin(a) * 0.93, sz * 0.16), (0, 0, sz), "Steel", 0.05, 0.035, 6)))
    return objs, [socket()]


# Метаданные для kit_catalog.json (tools/build_body_kit.gd): коннекторы — не детали, а визуал сустава (BODY_KIT.md §3.4)
META = {
    "Joint_Pin": {"kind": "connector", "title": "Ось"},
    "Joint_Free": {"kind": "connector", "title": "Свободный"},
    "Joint_Spring": {"kind": "connector", "title": "Пружина"},
    "Joint_Motor": {"kind": "connector", "title": "Мотор"},
}
