#!/usr/bin/env python3
"""Инструмент языков игры (docs/plan-demo/I18N.md). Запуск из любой папки:  python3 godot/tools/i18n.py <команда>

  check            проверка (код возврата ≠ 0 при ошибках): у каждой русской строки кода есть перевод в en.json и в каждом
                   языке; одинаковые подстановки (%s %d %.1f, {} …); нет русских букв в переводах; нет «висячих» ключей
  status           сводка по языкам: сколько строк переведено, сколько ещё равны английским
  new <код> <Название>   создать locale/<код>.json со всеми ключами (значения — английские, их переписывают на свой язык)
  sync             добавить в каждый язык недостающие ключи (en — пустые для ручного заполнения, остальные — из en), убрать висячие
  keys             напечатать все ключи (русские строки кода), по одной на строку
  where <часть пути>   ключи только из файлов, чей путь содержит эту часть (с файлом:строкой) — рабочий список переводчика

Ключ перевода = русская строка из кода дословно. Что считается строкой кода: литералы с кириллицей в .gd / .tscn / .tres под
godot/scenes, godot/scripts, godot/data, кроме отладочных (print, push_*, assert) и перечисленных в locale/ignore.txt.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
LOCALE = os.path.join(GODOT, "locale")
SCAN_DIRS = ["scenes", "scripts", "data"]
SKIP_PARTS = ("/tests/", "/tools/", "/_legacy/", "/.godot/", "/scenes/audio/")   # scenes/audio — отладочная звуковая доска
EXTS = (".gd", ".tscn", ".tres")
CYR = re.compile("[А-Яа-яЁё]")
DEBUG_LINE = re.compile(r"^\s*(print|print_rich|printerr|push_warning|push_error|assert|prints)\s*\(")
TR_CALL = re.compile(r"(?<![A-Za-z0-9_])(tr|translate)\($")
PLACEHOLDER = re.compile(r"%[-+ 0#]*\d*(?:\.\d+)?[sdfxXeEgGcbo]|%%|\{[A-Za-z0-9_]*\}")
ESC = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'", "r": "\r"}


def unescape(raw):
    out, i = [], 0
    while i < len(raw):
        c = raw[i]
        if c == "\\" and i + 1 < len(raw):
            n = raw[i + 1]
            if n == "u" and i + 5 < len(raw) + 0:
                try:
                    out.append(chr(int(raw[i + 2:i + 6], 16)))
                    i += 6
                    continue
                except ValueError:
                    pass
            out.append(ESC.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def string_literals(text, is_gd=True):
    """(начало, конец, значение, строка) всех строковых литералов файла; комментарии # пропускаются (только .gd)."""
    i, n, line = 0, len(text), 1
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif c == "#" and is_gd:
            while i < n and text[i] != "\n":
                i += 1
        elif c in "\"'":
            q = c
            triple = text.startswith(q * 3, i) and is_gd
            start = i
            i += 3 if triple else 1
            body = i
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if triple and text.startswith(q * 3, i):
                    break
                if not triple and text[i] == q:
                    break
                if text[i] == "\n" and not triple:
                    break
                i += 1
            raw = text[body:i]
            end = i + (3 if triple else 1)
            yield start, end, unescape(raw), line, triple
            line += text.count("\n", start, end)
            i = end
        else:
            i += 1


def source_files():
    for d in SCAN_DIRS:
        for root, _dirs, files in os.walk(os.path.join(GODOT, d)):
            p = root.replace(os.sep, "/") + "/"
            if any(s in p for s in SKIP_PARTS):
                continue
            for f in files:
                if f.endswith(EXTS):
                    yield os.path.join(root, f)


def load_ignore():
    path = os.path.join(LOCALE, "ignore.txt")
    out = set()
    if os.path.exists(path):
        for ln in open(path, encoding="utf8").read().split("\n"):
            if ln and not ln.startswith("#"):
                out.add(unescape(ln))
    return out


def collect():
    """{ключ: [(файл, строка), …]} — русские литералы кода."""
    ignore = load_ignore()
    keys = {}
    for p in source_files():
        text = open(p, encoding="utf8").read()
        lines = text.split("\n")
        is_gd = p.endswith(".gd")
        for _s, _e, val, line, triple in string_literals(text, is_gd):
            if not CYR.search(val):
                # английская подпись в tr("…") — тоже ключ (FIGHT!, MAIN MENU): в ru/en совпадает с самой строкой, другим языкам нужна
                if not (is_gd and TR_CALL.search(text[max(0, _s - 32):_s]) and re.search("[A-Za-z]{2}", val)):
                    continue
            if is_gd and (DEBUG_LINE.match(lines[line - 1]) or triple):
                continue
            if p.endswith(".tscn") and not re.match(r"^\s*(text|title|tooltip_text|placeholder_text)\b", lines[line - 1]):
                continue
            if p.endswith(".tres") and not re.match(r"^\s*(display_name|title|desc|description|hint|name_ru|label)\b", lines[line - 1]):
                continue
            if val in ignore or val.strip() == "" or len(val) == 1:   # одна буква — таблица транслита, не подпись
                continue
            keys.setdefault(val, []).append((os.path.relpath(p, GODOT), line))
    return keys


def lang_files():
    out = {}
    if os.path.isdir(LOCALE):
        for f in sorted(os.listdir(LOCALE)):
            if f.endswith(".json"):
                out[f[:-5]] = os.path.join(LOCALE, f)
    return out


def read_lang(path):
    return json.load(open(path, encoding="utf8"))


def write_lang(path, tbl):
    meta = {k: v for k, v in tbl.items() if k.startswith("@")}
    rest = {k: v for k, v in tbl.items() if not k.startswith("@")}
    out = dict(meta)
    out.update(rest)
    with open(path, "w", encoding="utf8") as f:
        json.dump(out, f, ensure_ascii=False, indent="\t")
        f.write("\n")


def placeholders(s):
    return sorted(PLACEHOLDER.findall(s))


def cmd_check():
    keys = collect()
    langs = lang_files()
    errors, warns, longer = [], [], []
    if "en" not in langs:
        errors.append("нет locale/en.json")
    for code, path in langs.items():
        tbl = read_lang(path)
        if code == "ru":
            continue
        for k in keys:
            v = tbl.get(k)
            if v is None or v == "":
                if not CYR.search(k):
                    continue   # английский ключ: «нет перевода» = как есть
                if code == "en" or v is None:
                    errors.append("%s: нет перевода «%s»  (%s:%d)" % (code, k[:70], *keys[k][0]))
                continue
            if placeholders(k) != placeholders(v):
                errors.append("%s: подстановки не совпадают «%s» → «%s»" % (code, k[:50], v[:50]))
            if CYR.search(v) and code != "ru":
                warns.append("%s: русские буквы в переводе «%s»" % (code, v[:60]))
            # интерфейс рисовался под русский: перевод заметно длиннее русской строки — риск, что не влезет (смотреть tests/i18n_layout_probe)
            if CYR.search(k) and len(k) <= 40 and len(v) > len(k) * 1.3 + 4:
                longer.append((len(v) / max(len(k), 1), code, k, v))
        for k in tbl:
            if not k.startswith("@") and k not in keys:
                warns.append("%s: висячий ключ «%s»" % (code, k[:70]))
    longer.sort(reverse=True)
    for ratio, code, k, v in longer[:25]:
        warns.append("%s: длиннее русского в %.1f× «%s» → «%s»" % (code, ratio, k[:40], v[:60]))
    for w in warns[:60]:
        print("warn:", w)
    for e in errors[:120]:
        print("ERROR:", e)
    print("ключей в коде: %d, языков: %s, ошибок: %d, предупреждений: %d" % (len(keys), ", ".join(langs) or "—", len(errors), len(warns)))
    return 1 if errors else 0


def cmd_status():
    keys = collect()
    langs = lang_files()
    en = read_lang(langs["en"]) if "en" in langs else {}
    print("ключей в коде: %d" % len(keys))
    for code, path in langs.items():
        tbl = read_lang(path)
        name = tbl.get("@name", code)
        if code == "ru":
            print("  %-6s %-14s исходный язык (в коде)" % (code, name))
            continue
        have = sum(1 for k in keys if tbl.get(k))
        same = sum(1 for k in keys if tbl.get(k) and tbl.get(k) == en.get(k) and code != "en")
        print("  %-6s %-14s переведено %d / %d, равно английскому: %d" % (code, name, have, len(keys), same))
    return 0


def cmd_new(code, name):
    langs = lang_files()
    if code in langs:
        print("locale/%s.json уже есть" % code)
        return 1
    en = read_lang(langs["en"])
    keys = collect()
    tbl = {"@name": name}
    for k in keys:
        tbl[k] = en.get(k, k if not CYR.search(k) else "")
    os.makedirs(LOCALE, exist_ok=True)
    write_lang(os.path.join(LOCALE, code + ".json"), tbl)
    print("создан locale/%s.json: %d строк (значения пока английские — переписать на %s)" % (code, len(keys), name))
    return 0


def cmd_sync():
    keys = collect()
    langs = lang_files()
    en = read_lang(langs["en"]) if "en" in langs else {}
    for code, path in langs.items():
        tbl = read_lang(path)
        out = {k: v for k, v in tbl.items() if k.startswith("@")}
        added = 0
        for k in keys:
            if k in tbl:
                out[k] = tbl[k]
            elif code == "ru":
                continue
            else:
                out[k] = "" if (code == "en" and CYR.search(k)) else en.get(k, k if not CYR.search(k) else "")
                added += 1
        dropped = [k for k in tbl if not k.startswith("@") and k not in keys]
        write_lang(path, out)
        print("%s: +%d, убрано висячих %d" % (code, added, len(dropped)))
    return 0


def main():
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if a[0] == "check":
        return cmd_check()
    if a[0] == "status":
        return cmd_status()
    if a[0] == "keys":
        for k in collect():
            print(k)
        return 0
    if a[0] == "where" and len(a) >= 2:
        for k, locs in collect().items():
            hit = [l for l in locs if a[1] in l[0]]
            if hit:
                print("%s:%d\t%s" % (hit[0][0], hit[0][1], json.dumps(k, ensure_ascii=False)))
        return 0
    if a[0] == "sync":
        return cmd_sync()
    if a[0] == "new" and len(a) >= 3:
        return cmd_new(a[1], " ".join(a[2:]))
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
