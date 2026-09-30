## Материалы деталей NULL League (tools/blender/kit_league.py; docs/plan-demo/ART_NULL.md, листы 3–4): фиксированные роли League_*
## в assets/materials/kit/ — рядом с материалами кита, их ставит тот же пост-импорт tools/kit_import.gd по имени роли.
## Отдельный builder, а не таблица MATS в tools/build_body_kit.gd: кит ведёт соседняя сессия (BODY_KIT.md §0), здесь — только новое.
## Порядок для новых деталей: blender -b --python tools/blender/body_kit.py -- --export <Имя…> → --import → этот builder →
## -s res://tools/build_body_kit.gd → --import (детали и PartDef — общим builder-ом кита).
## Металл не зеркальный (как железо кита, BODY_KIT.md §2): в сценах без неба metallic 0.85+ отражал пустоту и выходил чёрным.
extends SceneTree

const DIR := "res://assets/materials/kit/"

## роль → параметры (цвета линейные): albedo, rough, metal, glow + energy, alpha
const MATS := {
	"League_Void": {"albedo": [0.05, 0.042, 0.07], "rough": 0.3, "metal": 0.5},
	"League_Glow": {"albedo": [0.1, 0.02, 0.22], "rough": 0.3, "metal": 0.0, "glow": [0.55, 0.12, 1.0], "energy": 1.3},
	"League_Cyan": {"albedo": [0.03, 0.2, 0.28], "rough": 0.3, "metal": 0.0, "glow": [0.15, 0.8, 1.0], "energy": 1.2},
	"League_Crystal": {"albedo": [0.35, 0.72, 0.95], "rough": 0.05, "metal": 0.1, "glow": [0.2, 0.6, 1.0], "energy": 0.5, "alpha": 0.55},
	"League_Gold": {"albedo": [0.85, 0.58, 0.2], "rough": 0.3, "metal": 0.6},
}


func _init() -> void:
	var errors := 0
	for role in MATS:
		var d: Dictionary = MATS[role]
		var m := StandardMaterial3D.new()
		m.resource_name = role
		var a: Array = d["albedo"]
		m.albedo_color = Color(a[0], a[1], a[2]).linear_to_srgb()
		m.roughness = float(d["rough"])
		m.metallic = float(d["metal"])
		if d.has("glow"):
			var g: Array = d["glow"]
			m.emission_enabled = true
			m.emission = Color(g[0], g[1], g[2]).linear_to_srgb()
			m.emission_energy_multiplier = float(d["energy"])
		if d.has("alpha"):
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = float(d["alpha"])
		var err := ResourceSaver.save(m, DIR + role + ".tres")
		if err != OK:
			push_error("build_league_mats: %s — %d" % [role, err])
			errors += 1
	print("build_league_mats: %d materials, errors=%d" % [MATS.size(), errors])
	quit(1 if errors > 0 else 0)
