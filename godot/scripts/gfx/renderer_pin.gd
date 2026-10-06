## Рендерер под пресет графики (docs/plan-demo/look/frame.md, «Ультра на Forward+»): рендерер на лету не меняется, поэтому выбор
## пресета пишет переопределение настроек проекта, которое Godot читает при следующем запуске. project.godot:
## application/config/project_settings_override = "user://renderer.cfg" (проверено 06.10: Godot 4.7 читает файл из user:// до выбора
## рендерера — второй запуск идёт на Forward+; ключ --rendering-method в командной строке сильнее файла).
##   «ultra» → [rendering] renderer/rendering_method = "forward_plus" (SSAO / SSIL / объёмный туман арен остаются — Gfx._drop_unsupported
##   на Forward+ их не выключает); остальные пресеты — файла нет, проектный Mobile.
## Пишет только Gfx.set_preset(..., save = true) с окном (пробы зовут save = false); headless не пишет никогда.
class_name RendererPin
extends RefCounted

const SECTION := "rendering"
const KEY := "renderer/rendering_method"
const ULTRA_METHOD := "forward_plus"
const PROJECT_METHOD := "mobile"   # rendering/renderer/rendering_method в project.godot

## Путь файла: пробы подменяют его, чтобы не трогать настоящий (user:// общий у всех чекаутов проекта).
static var path := "user://renderer.cfg"


## Какой рендерер нужен пресету: "forward_plus" для ультра, "" — проектный (Mobile).
static func wanted_for(preset: String) -> String:
	return ULTRA_METHOD if preset == "ultra" else ""


## Записанный в файл рендерер ("" — файла нет).
static func pinned() -> String:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return ""
	return String(cf.get_value(SECTION, KEY, ""))


## Записать (или убрать) переопределение под пресет. Возвращает true, если файл поменялся.
static func write(preset: String) -> bool:
	var want := wanted_for(preset)
	if want == pinned():
		return false
	if want == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return true
	var cf := ConfigFile.new()
	cf.set_value(SECTION, KEY, want)
	return cf.save(path) == OK


## Рендерер, с которым игра стартует в следующий раз без ключа командной строки: из файла, иначе проектный.
static func next_method() -> String:
	var p := pinned()
	return p if p != "" else PROJECT_METHOD


## Нужен ли перезапуск: сейчас идёт не тот рендерер, что будет при следующем запуске (пресет записал другой).
static func restart_needed() -> bool:
	return RenderingServer.get_current_rendering_method() != next_method()
