## Картинки игрока для куклы (docs/plan-demo/BODY_PAINT.md §3): наклейки и фото на плашку лица.
## Импорт: любой png / jpg / webp / bmp / tga / svg с диска (кнопка «Импорт…» или файл, брошенный в окно) → RGBA8, большая сторона ≤
## MAX_SIDE (Lanczos, пропорции те же) → PNG в user://kit_images/<первые 16 hex sha256 байт этого PNG>.png. id = это имя: одна и та же
## картинка — один id, повторный импорт файл не дублирует. Чертёж хранит только id (ключи stickers[].img, face — §4).
## Формат — по сигнатуре байтов (расширение не важно: .jfif, .jpe, без расширения, jpg под именем .png); по расширению — только tga
## и svg (у них сигнатуры нет). Размер в пикселях читается из заголовка ДО декодирования (png, jpg, webp): > MAX_PIXELS — отказ без
## гигабайта в памяти; svg рисуется сразу в ≤ MAX_SIDE. Почему не вышло — import_file_ex / last_error (ERR_*), HEIC с iPhone
## узнаётся отдельно («сохрани как JPG»). Удалить — delete_image. Импорт не трогает общий кэш — его можно звать из потока
## (WorkerThreadPool, WorkshopPaint.import_files_async).
## Трафареты — «stencil:<имя>»: маска res://assets/textures/paint_stencils/<имя>.png (белая фигура на прозрачном, цвет — цвет
## наклейки), с мипмапами (в матче наклейка 10–17 px). Файла нет — texture() даёт null, кукла собирается без наклейки.
class_name KitImages
extends RefCounted

const DIR := "user://kit_images/"
const STENCIL_DIR := "res://assets/textures/paint_stencils/"
const STENCIL_PREFIX := "stencil:"
const MAX_SIDE := 512
## Больше не читаем (защита от случайно брошенного гигантского файла).
const MAX_FILE_BYTES := 64 * 1024 * 1024
## Больше пикселей не декодируем (40 Мп — с запасом больше фото телефона 12–24 Мп; PNG 16384² весит на диске мегабайты, а в памяти —
## гигабайт).
const MAX_PIXELS := 40000000
## Расширения диалога «Импорт…» (формат всё равно — по сигнатуре байтов).
const EXTENSIONS := ["png", "jpg", "jpeg", "jfif", "jpe", "webp", "bmp", "tga", "svg"]
## Почему импорт не вышел (import_file_ex / last_error).
const ERR_NOT_FOUND := "not_found"
const ERR_UNREADABLE := "unreadable"
const ERR_TOO_BIG_FILE := "too_big_file"
const ERR_TOO_BIG_PIXELS := "too_big_pixels"
const ERR_HEIC := "heic"
const ERR_UNSUPPORTED := "unsupported"
const ERR_WRITE := "write_failed"
## Порядок трафаретов на полке (§1) — как STENCILS в tools/gen_paint_assets.py; прочие файлы папки — по алфавиту после них.
const STENCIL_ORDER := [
	"star", "crown", "skull", "lightning", "heart", "arrow", "crossbones", "gear", "target", "flame",
	"digit_0", "digit_1", "digit_2", "digit_3", "digit_4", "digit_5", "digit_6", "digit_7", "digit_8", "digit_9",
]

static var _cache: Dictionary = {}   # id -> Texture2D
## Причина последней неудачи import_file ("" — удалось). Только для вызовов с главного потока (из потока — import_file_ex).
static var last_error := ""


## Загрузить картинку с диска (путь ОС, user:// или res://), уменьшить до ≤ MAX_SIDE, сохранить в DIR. id или "" — ошибка
## (причина — last_error). Формат — по сигнатуре байтов, а не по расширению: файл, который не картинка, отсекается без ошибок
## движка в логе.
static func import_file(path: String) -> String:
	var r := import_file_ex(path)
	last_error = String(r["error"])
	return String(r["id"])


## import_file без общего состояния (можно из потока): {id: String ("" — нет), error: ERR_* или "", pixels: int (если известно)}.
static func import_file_ex(path: String) -> Dictionary:
	var out := {"id": "", "error": "", "pixels": 0}
	if path == "":
		out["error"] = ERR_NOT_FOUND
		return out
	var p := path
	if p.begins_with("user://"):
		p = ProjectSettings.globalize_path(p)
	if not p.begins_with("res://") and not FileAccess.file_exists(p):
		out["error"] = ERR_NOT_FOUND
		return out
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		out["error"] = ERR_UNREADABLE
		return out
	var n := f.get_length()
	if n <= 0:
		f.close()
		out["error"] = ERR_UNREADABLE
		return out
	if n > MAX_FILE_BYTES:
		f.close()
		out["error"] = ERR_TOO_BIG_FILE
		return out
	var buf := f.get_buffer(n)
	f.close()
	var ext := path.get_extension().to_lower()
	var fmt := _sniff(buf, ext)
	if fmt == "heic":
		out["error"] = ERR_HEIC
		return out
	if fmt == "":
		out["error"] = ERR_UNSUPPORTED
		return out
	var dim := _header_size(buf, fmt)
	if dim.x > 0 and dim.y > 0:
		out["pixels"] = dim.x * dim.y
		if dim.x * dim.y > MAX_PIXELS:
			out["error"] = ERR_TOO_BIG_PIXELS
			return out
	var img := _decode(buf, fmt)
	if img == null or img.is_empty():
		out["error"] = ERR_UNSUPPORTED
		return out
	out["pixels"] = img.get_width() * img.get_height()
	if int(out["pixels"]) > MAX_PIXELS:   # bmp / tga без размера в заголовке
		out["error"] = ERR_TOO_BIG_PIXELS
		return out
	var id := import_image(img)
	if id == "":
		out["error"] = ERR_WRITE
	out["id"] = id
	return out


## Удалить импортированную картинку id (файл в DIR и кэш). false — не id картинки / файла нет / не удалить.
static func delete_image(id: String) -> bool:
	if not is_image_id(id):
		return false
	var fp := image_path(id)
	if not FileAccess.file_exists(fp):
		_cache.erase(id)
		return false
	var ok := DirAccess.remove_absolute(ProjectSettings.globalize_path(fp)) == OK
	_cache.erase(id)
	return ok


## То же для картинки в памяти (буфер обмена, скриншот): копия → RGBA8, ≤ MAX_SIDE → PNG в DIR. id или "".
static func import_image(src: Image) -> String:
	if src == null or src.is_empty():
		return ""
	var img := src.duplicate() as Image
	if img.is_compressed() and img.decompress() != OK:
		return ""
	img.clear_mipmaps()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return ""
	var m := maxi(w, h)
	if m > MAX_SIDE:
		var s := float(MAX_SIDE) / m
		img.resize(maxi(1, roundi(w * s)), maxi(1, roundi(h * s)), Image.INTERPOLATE_LANCZOS)
	var png := img.save_png_to_buffer()
	if png.is_empty():
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(png)
	var id := ctx.finish().hex_encode().substr(0, 16)
	var fp := DIR + id + ".png"
	if not FileAccess.file_exists(fp):
		DirAccess.make_dir_recursive_absolute(DIR)
		var out := FileAccess.open(fp, FileAccess.WRITE)
		if out == null:
			push_warning("KitImages: не записать %s (%s)" % [fp, error_string(FileAccess.get_open_error())])
			return ""
		out.store_buffer(png)
		out.close()
	return id


## Текстура по id: «stencil:<имя>» — маска трафарета из assets; «res://…» — ресурс проекта; иначе 16 hex — файл из DIR.
## Кэш; null — нет файла / битый id.
static func texture(id: String) -> Texture2D:
	if id == "":
		return null
	if _cache.has(id):
		var t: Texture2D = _cache[id]
		if t != null:
			return t
	var tex: Texture2D = null
	if id.begins_with(STENCIL_PREFIX):
		var nm := id.substr(STENCIL_PREFIX.length())
		if _safe_name(nm):
			tex = _load_res_png(STENCIL_DIR + nm + ".png")
	elif id.begins_with("res://"):
		if ResourceLoader.exists(id):
			tex = load(id) as Texture2D
	elif is_image_id(id):
		var fp := image_path(id)
		if FileAccess.file_exists(fp):
			var img := Image.load_from_file(fp)
			if img != null and not img.is_empty():
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
	if tex != null:
		_cache[id] = tex
	return tex


## Имена трафаретов (без .png) по порядку STENCIL_ORDER, остальные — по алфавиту. Папки нет — пусто.
static func stencils() -> PackedStringArray:
	var names := {}
	var d := DirAccess.open(STENCIL_DIR)
	if d == null:
		return PackedStringArray()
	for fn in d.get_files():
		var f := String(fn)
		if f.ends_with(".import"):
			f = f.trim_suffix(".import")
		if f.get_extension().to_lower() == "png":
			names[f.get_basename()] = true
	var out: Array = names.keys()
	out.sort_custom(func(a: String, b: String) -> bool:
		var ia := STENCIL_ORDER.find(a)
		var ib := STENCIL_ORDER.find(b)
		if ia < 0:
			ia = 1000
		if ib < 0:
			ib = 1000
		return ia < ib if ia != ib else a.naturalnocasecmp_to(b) < 0)
	return PackedStringArray(out)


## id импортированных картинок (DIR), новые первыми — список «мои картинки» мастерской.
static func list_images() -> PackedStringArray:
	var d := DirAccess.open(DIR)
	if d == null:
		return PackedStringArray()
	var rows: Array = []
	for fn in d.get_files():
		var f := String(fn)
		if f.get_extension().to_lower() == "png" and is_image_id(f.get_basename()):
			rows.append([FileAccess.get_modified_time(DIR + f), f.get_basename()])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] if a[0] != b[0] else String(a[1]) < String(b[1]))
	var out := PackedStringArray()
	for r in rows:
		out.append(String(r[1]))
	return out


## Путь файла картинки id в DIR.
static func image_path(id: String) -> String:
	return DIR + id + ".png"


## id импортированной картинки: 16 hex (защита от путей в чужих данных чертежа).
static func is_image_id(id: String) -> bool:
	return id.length() == 16 and id.is_valid_hex_number(false)


## Сбросить кэш текстур (пробы; мастерская после удаления файла).
static func clear_cache() -> void:
	_cache.clear()


## Формат по сигнатуре байтов: png, jpg, webp, bmp; без сигнатуры — по расширению (tga; svg / без расширения — с «<svg» в
## первых 4 КБ); «heic» —
## HEIC / HEIF с iPhone (ftyp heic / heix / mif1 / msf1 / hevc), его движок не читает; "" — не картинка.
static func _sniff(buf: PackedByteArray, ext: String) -> String:
	if buf.size() >= 8 and buf.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		return "png"
	if buf.size() >= 3 and buf[0] == 0xFF and buf[1] == 0xD8 and buf[2] == 0xFF:
		return "jpg"
	if buf.size() >= 12 and buf.slice(0, 4).get_string_from_ascii() == "RIFF" and buf.slice(8, 12).get_string_from_ascii() == "WEBP":
		return "webp"
	if buf.size() >= 2 and buf[0] == 0x42 and buf[1] == 0x4D:
		return "bmp"
	if buf.size() >= 12 and buf.slice(4, 8).get_string_from_ascii() == "ftyp":
		var brand := buf.slice(8, 12).get_string_from_ascii()
		if brand in ["heic", "heix", "heim", "heis", "hevc", "hevx", "mif1", "msf1", "avif"]:
			return "heic"
	if ext == "tga":
		return "tga"
	# ascii, а не utf8: у двоичного мусора utf8-разбор пишет ошибки в лог
	if (ext == "svg" or ext == "xml" or ext == "") and buf.slice(0, mini(buf.size(), 4096)).get_string_from_ascii().contains("<svg"):
		return "svg"
	return ""


## Размер из заголовка (без декодирования): png — IHDR, jpg — маркер SOF0..SOF15 (кроме DHT / JPG / DAC), webp — VP8 / VP8L / VP8X;
## svg — атрибуты width / height (или viewBox) тега svg. Vector2i(-1, -1) — не нашёлся.
static func _header_size(buf: PackedByteArray, fmt: String) -> Vector2i:
	var n := buf.size()
	match fmt:
		"png":
			if n >= 24:
				return Vector2i(_be32(buf, 16), _be32(buf, 20))
		"jpg":
			var i := 2
			while i + 9 < n:
				if buf[i] != 0xFF:
					i += 1
					continue
				var m := buf[i + 1]
				if m == 0xFF:
					i += 1
					continue
				if m == 0xD8 or m == 0x01 or (m >= 0xD0 and m <= 0xD7):
					i += 2
					continue
				var seg := (buf[i + 2] << 8) | buf[i + 3]
				if m >= 0xC0 and m <= 0xCF and m != 0xC4 and m != 0xC8 and m != 0xCC:
					return Vector2i((buf[i + 7] << 8) | buf[i + 8], (buf[i + 5] << 8) | buf[i + 6])
				if seg < 2:
					break
				i += 2 + seg
		"webp":
			if n >= 30:
				var chunk := buf.slice(12, 16).get_string_from_ascii()
				if chunk == "VP8X":
					return Vector2i(1 + (buf[24] | (buf[25] << 8) | (buf[26] << 16)), 1 + (buf[27] | (buf[28] << 8) | (buf[29] << 16)))
				if chunk == "VP8L" and n >= 25:
					var b0 := buf[21]
					var b1 := buf[22]
					var b2 := buf[23]
					var b3 := buf[24]
					return Vector2i(1 + (b0 | ((b1 & 0x3F) << 8)), 1 + (((b1 >> 6) | (b2 << 2) | ((b3 & 0x0F) << 10))))
				if chunk == "VP8 " and n >= 30:
					return Vector2i((buf[26] | (buf[27] << 8)) & 0x3FFF, (buf[28] | (buf[29] << 8)) & 0x3FFF)
		"svg":
			var head := buf.slice(0, mini(n, 4096)).get_string_from_ascii()
			var at := head.find("<svg")
			if at >= 0:
				var tag := head.substr(at, maxi(head.find(">", at) - at, 0))
				var w := _svg_len(tag, "width")
				var h := _svg_len(tag, "height")
				if w <= 0.0 or h <= 0.0:
					var vb := _svg_attr(tag, "viewBox").replace(",", " ").split(" ", false)
					if vb.size() == 4:
						w = vb[2].to_float()
						h = vb[3].to_float()
				if w > 0.0 and h > 0.0:
					return Vector2i(ceili(w), ceili(h))
	return Vector2i(-1, -1)


static func _be32(b: PackedByteArray, i: int) -> int:
	return (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]


static func _svg_attr(tag: String, attr: String) -> String:
	var re := RegEx.create_from_string("\\b%s\\s*=\\s*[\"']([^\"']*)[\"']" % attr)
	var m := re.search(tag)
	return m.get_string(1) if m != null else ""


static func _svg_len(tag: String, attr: String) -> float:
	var v := _svg_attr(tag, attr).strip_edges()
	if v == "" or v.ends_with("%"):
		return -1.0
	return v.to_float()


## Картинка из байтов формата fmt (_sniff); svg — сразу в ≤ MAX_SIDE по большей стороне. null — не картинка.
static func _decode(buf: PackedByteArray, fmt: String) -> Image:
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match fmt:
		"png":
			err = img.load_png_from_buffer(buf)
		"jpg":
			err = img.load_jpg_from_buffer(buf)
		"webp":
			err = img.load_webp_from_buffer(buf)
		"bmp":
			err = img.load_bmp_from_buffer(buf)
		"tga":
			err = img.load_tga_from_buffer(buf)
		"svg":
			var dim := _header_size(buf, "svg")
			var sc := 1.0
			if dim.x > 0 and dim.y > 0:
				sc = minf(1.0, float(MAX_SIDE) / float(maxi(dim.x, dim.y)))
			err = img.load_svg_from_buffer(buf, sc)
	return img if err == OK and not img.is_empty() else null


static func _safe_name(nm: String) -> bool:
	return nm != "" and nm.is_valid_filename() and not nm.contains("..") and not nm.contains("/")


## PNG из res://: импортированный ресурс, иначе (ещё не импортирован) — сам файл. С мипмапами: трафарет — наклейка, в матче она
## 10–17 px, без мипмапов рябит (импорт трафаретов их не делает — копия картинки с мипмапами, один раз, кэш texture()).
static func _load_res_png(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t := load(path) as Texture2D
		if t != null:
			var ti := t.get_image()
			if ti == null or ti.is_empty() or ti.has_mipmaps():
				return t
			if ti.is_compressed():
				ti.decompress()
			ti.generate_mipmaps()
			return ImageTexture.create_from_image(ti)
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	return null
