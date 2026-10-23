## Реклама Лиги NULL на аренах (23.10.2026): LED-ленты на бортах трибун купола, изогнутые баннеры под верхним ярусом,
## щиты на фермах-мачтах и флаги за полем Свалки, борта у пола задней стены спорт-зала (щиты спонсоров ORBIT JOINTS,
## VOLTA CORES, NULL TV). Ставится в рантайме из _ready() арены (как NullLook) — сгенерированные
## сцены (tools/build_null_hall.gd, scenes/arena/scrap.tscn) не трогаются.
##
## Только фон: всё стоит вне поля боя (купол — на радиусе трибун 24–27 м, Свалка — z ≤ −7 за отвалами), коллизий нет
## (glb без -col; на всякий случай любые CollisionObject3D удаляются), тени не отбрасывает.
## Модели — tools/blender/arena_ads.py → assets/models/arena/ads/*.glb, картинки — tools/codex_art/arena_ads.py →
## assets/textures/arena_ads/*.jpg. Подробно — docs/plan-demo/CODEX_ART.md («Реклама на аренах»).
class_name LeagueBoards
extends Node3D

const LAYOUT_DOME := "dome"
const LAYOUT_SCRAP := "scrap"
const LAYOUT_SPORT := "sport"

const MODEL := "res://assets/models/arena/ads/%s.glb"
const TEX := "res://assets/textures/arena_ads/%s.jpg"
const RIBBONS := ["ribbon_league", "ribbon_joints", "ribbon_cores", "ribbon_nulltv"]

# купол (tools/build_null_hall.gd): секции трибун Stand_<ярус>_<секция>, 3 яруса × 11 секций по дуге 196°…344°
const HALL_TIERS := 3
const HALL_SEGMENTS := 11
const RIBBON_LOCAL := Vector3(0.0, 0.08, 0.125)   # лицо борта секции: панель 1 м, передняя грань z = 0.12
const CURVED_R := 26.0                            # радиус дуги Ad_Banner_Curved (центр окружности = центр зала)
const CURVED_Y := 10.3                            # под бортом верхнего яруса (13 м), над головами 2-го
# между колоннами каркаса: колонны на чётных стыках секций (ARC_FROM 196° + 148°/11 × 0, 2, 4…, tools/build_null_hall.gd
# _structure), дуги — у нечётных стыков 3, 5, 7. На 236/270/304° стойки резали надписи («NULL LEAG|», «SEA|SON»). Дуга (R 26)
# дальше колонн (R 22.8), поэтому в игровом кадре шире промежутка между ними: крайние уменьшены и сдвинуты к центру кадра
# (подобрано по null_hall_snapshot, кадр 1). [угол°, масштаб]
const CURVED := [[196.0 + 148.0 / 11.0 * 3.0 + 2.8, 0.84], [196.0 + 148.0 / 11.0 * 5.0, 0.92], [196.0 + 148.0 / 11.0 * 7.0 - 1.5, 0.88]]

static var _mats := {}


## Добавить рекламу к арене host по раскладке layout (LAYOUT_*). Возвращает узел LeagueBoards (дочерний host).
static func attach(host: Node3D, layout: String) -> LeagueBoards:
	if not is_instance_valid(host):
		return null
	var b := LeagueBoards.new()
	b.name = "LeagueBoards"
	host.add_child(b)
	match layout:
		LAYOUT_DOME:
			b._dome(host)
		LAYOUT_SCRAP:
			b._scrap()
		LAYOUT_SPORT:
			b._sport()
	return b


## Материал полотна: картинка и свечение той же картинкой (читается и в тёмном куполе, и на закате Свалки).
static func screen_material(tex_name: String, glow: float) -> StandardMaterial3D:
	var key := "%s@%.2f" % [tex_name, glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.resource_name = "Ad_Screen_" + tex_name
	var t: Texture2D = load(TEX % tex_name)
	m.albedo_texture = t
	m.roughness = 0.45
	m.emission_enabled = true
	m.emission_texture = t
	m.emission_energy_multiplier = glow
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


## Экземпляр модуля с картинкой tex_name на полотне Ad_Screen.
func place(module: String, tex_name: String, parent: Node3D, pos: Vector3, yaw_deg: float, glow := 0.9) -> Node3D:
	var ps: PackedScene = load(MODEL % module)
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	n.name = "%s_%d" % [module, get_child_count() if parent == self else parent.get_child_count()]
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	parent.add_child(n)
	_dress(n, screen_material(tex_name, glow))
	return n


func _dress(n: Node, screen: Material) -> void:
	for c in n.get_children():
		_dress(c, screen)
	if is_instance_valid(n) and n is CollisionObject3D:
		n.queue_free()
		return
	if is_instance_valid(n) and n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in range(mi.mesh.get_surface_count() if mi.mesh != null else 0):
			var m := mi.mesh.surface_get_material(i)
			if m != null and m.resource_name.begins_with("Ad_Screen"):
				mi.set_surface_override_material(i, screen)


# --- купол ----------------------------------------------------------------------------------------------------------
func _dome(host: Node3D) -> void:
	for t in range(HALL_TIERS):
		for s in range(HALL_SEGMENTS):
			var seg := host.find_child("Stand_%d_%d" % [t, s], true, false) as Node3D
			if seg == null:
				continue
			# лента — дочерний узел секции: стоит на её борту при любой раскладке зала
			place("Ad_Ribbon", RIBBONS[(s + t * 2) % RIBBONS.size()], seg, RIBBON_LOCAL, 0.0, 0.6)
	for c in CURVED:
		var a := deg_to_rad(float(c[0]))
		var p := Vector3(CURVED_R * cos(a), CURVED_Y, CURVED_R * sin(a))
		var d := Vector3(-p.x, 0.0, -p.z).normalized()
		var n := place("Ad_Banner_Curved", "banner_curved", self, p, rad_to_deg(atan2(d.x, d.z)), 0.7)
		if n != null:
			n.scale = Vector3.ONE * float(c[1])


# --- Свалка -----------------------------------------------------------------------------------------------------------
# Поле боя Свалки: x −18…18, z −1…1 (ScrapArena.arena_bounds); отвалы-бермы на z −3.4…−4.2, горы на z −12…−13.
func _scrap() -> void:
	# y −0.4, а не −2.2 (как правый): в кадре старта (scrap_snapshot start) щит стоял прямо за головой P2 на скате
	place("Ad_Billboard_Pole", "board_fight_night", self, Vector3(-9.5, -0.4, -13.5), 8.0, 0.55)
	place("Ad_Billboard_Pole", "board_scrap_cup", self, Vector3(11.5, -2.2, -14.5), -10.0, 0.55)
	place("Ad_Flag", "flag_null", self, Vector3(-14.5, -1.0, -7.0), 15.0, 0.5)
	place("Ad_Flag", "flag_null", self, Vector3(15.5, -1.0, -7.5), -15.0, 0.5)


# --- спорт-зал --------------------------------------------------------------------------------------------------------
# Задняя стена z −5.2 (tools/build_sport_hall.gd Z_BACK), табло по центру на y 3.4. Под табло — ряд бортов у пола, как
# реклама за полем на стадионе: экран 16:9 на тонкой раме, свечение слабое — за куклами и мячом не должно спорить с ними.
const SPORT_Z := -5.2 + 0.3
const SPORT_PANEL := Vector2(2.2, 2.2 * 9.0 / 16.0)
const SPORT_BOARDS := [["board_joints", -3.7], ["board_nulltv", 0.0], ["board_cores", 3.7]]   # колонны каркаса на x ±5.6 (z −4.3) — щиты внутри них


func _sport() -> void:
	for sb in SPORT_BOARDS:
		panel(String(sb[0]), self, Vector3(float(sb[1]), 0.25 + SPORT_PANEL.y * 0.5, SPORT_Z), SPORT_PANEL, 0.35)


## Плоский экран с картинкой tex_name в тёмной раме (без модели кита: для стен, где щит на ногах или мачте не встаёт).
func panel(tex_name: String, parent: Node3D, pos: Vector3, size: Vector2, glow := 0.5) -> Node3D:
	var root := Node3D.new()
	root.name = "Ad_Panel_" + tex_name
	root.position = pos
	parent.add_child(root)
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x + 0.12, size.y + 0.12, 0.08)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.06, 0.065, 0.075)
	fm.metallic = 0.6
	fm.roughness = 0.5
	bm.material = fm
	frame.mesh = bm
	frame.position.z = -0.05
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(frame)
	var scr := MeshInstance3D.new()
	scr.name = "Ad_Screen"
	var q := QuadMesh.new()
	q.size = size
	scr.mesh = q
	scr.material_override = screen_material(tex_name, glow)
	scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(scr)
	return root
