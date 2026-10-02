## Материал удара (HIT_FX.md §13): из чего сделана ударенная деталь — от этого обломки (ImpactFx), след на детали (HitMarks) и повод N0.
## Удар в игре выражается материалом, а не цветом игрока: дерево колется щепками, краска — хлопьями своего цвета, железо искрит,
## кость крошится белым, резина только пылит.
##   id_of(doll, body)  — id MaterialDef (data/body/materials/<id>.tres): у ModularDoll — материал узла чертежа (BodyBlueprint.node_mat),
##                        у куклы-манекена doll.tscn — клён (maple), у doll_dark.tscn — орех (wood_dark); кэш — meta "fx_mat" тела;
##   cls(id)            — класс обломков: wood, wood_dark, paint, metal, rust, bone, rubber;
##   tint_of(id, doll)  — цвет хлопьев краски: у краски — плашка материала, у манекена — цвет игрока (мазки краски и обмотки, ART v3 §3);
##   striker_metal(s)   — бьёт металл (оружие, железная деталь): искры и на дереве не нужны, только металл о металл.
class_name FxMaterial
extends RefCounted

const WOOD := "wood"
const WOOD_DARK := "wood_dark"
const PAINT := "paint"
const METAL := "metal"
const RUST := "rust"
const BONE := "bone"
const RUBBER := "rubber"
const CLASSES := [WOOD, WOOD_DARK, PAINT, METAL, RUST, BONE, RUBBER]
const BY_ID := {
	"wood": WOOD, "maple": WOOD, "planks": WOOD, "wood_dark": WOOD_DARK,
	"paint_red": PAINT, "paint_blue": PAINT, "paint_yellow": PAINT, "paint_white": PAINT, "paint_green": PAINT,
	"iron": METAL, "brass": METAL, "rust": RUST, "rust_red": RUST, "bone": BONE, "rubber": RUBBER,
}
## Щепки и хлопья (color_initial_ramp частиц: случайная точка градиента на частицу). Краска — своим цветом.
const CHIP_COLOURS := {
	WOOD: [Color(1.0, 0.9, 0.66), Color(0.72, 0.5, 0.27)],
	WOOD_DARK: [Color(0.62, 0.42, 0.26), Color(0.32, 0.19, 0.1)],
	RUST: [Color(0.66, 0.33, 0.16), Color(0.36, 0.17, 0.08)],
	BONE: [Color(1.0, 0.97, 0.88), Color(0.8, 0.74, 0.6)],
	METAL: [Color(0.62, 0.62, 0.66), Color(0.3, 0.3, 0.33)],
}
## След на детали (doll_marks.gdshader): [скол, трещина, металличность скола, шероховатость скола].
const MARK_LOOK := {
	WOOD: [Color(0.96, 0.84, 0.62), Color(0.16, 0.09, 0.04), 0.0, 0.85],
	WOOD_DARK: [Color(0.8, 0.6, 0.4), Color(0.07, 0.04, 0.02), 0.0, 0.85],
	PAINT: [Color(0.94, 0.82, 0.6), Color(0.14, 0.08, 0.04), 0.0, 0.85],   # краска откололась — под ней дерево
	METAL: [Color(0.86, 0.87, 0.9), Color(0.12, 0.12, 0.14), 1.0, 0.3],   # вмятина: свежий металл и тёмная тень
	RUST: [Color(0.66, 0.6, 0.54), Color(0.2, 0.09, 0.04), 0.7, 0.45],    # ржавчина слетела — под ней металл
	BONE: [Color(0.86, 0.8, 0.66), Color(0.24, 0.2, 0.15), 0.0, 0.9],   # пористая желтоватая сердцевина — на белой кости видно
	RUBBER: [Color(0.07, 0.07, 0.07), Color(0.03, 0.03, 0.03), 0.0, 1.0], # резина не колется — тёмный мазок
}
const PAINT_SHARE := 0.6     # краска: доля хлопьев краски, остальное — щепки дерева под ней
const STROKE_SHARE := 0.2    # манекен: доля хлопьев цвета игрока (мазки краски на клёне/орехе)


static func id_of(doll: Node, body: Node) -> String:
	if body != null and is_instance_valid(body) and body.has_meta("fx_mat"):
		return String(body.get_meta("fx_mat"))
	var id := _resolve(doll, body)
	if body != null and is_instance_valid(body):
		body.set_meta("fx_mat", id)
	return id


static func _resolve(doll: Node, body: Node) -> String:
	if doll == null or not is_instance_valid(doll):
		return "wood"
	var bp: Variant = doll.get("blueprint")
	var ub: Variant = doll.get("uid_body")
	if bp is BodyBlueprint and ub is Dictionary and body != null:
		for uid in (ub as Dictionary).keys():
			if String((ub as Dictionary)[uid]) == String(body.name):
				var m := (bp as BodyBlueprint).node_mat(String(uid))
				if m != "":
					return m
				break
	if doll.get_node_or_null("EnemyLook") != null:
		return "wood_dark"   # враги PvE — тёмное ржавое дерево (EnemyLook.WOOD_TINT)
	if String(doll.scene_file_path).contains("dark"):
		return "wood_dark"
	return "maple"


static func cls(id: String) -> String:
	return String(BY_ID.get(id, WOOD))


static func is_metal(c: String) -> bool:
	return c == METAL or c == RUST


## Цвет хлопьев: краска — плашка материала; манекен (не ModularDoll с материалом) — цвет игрока; иначе — прозрачный (без хлопьев).
static func tint_of(id: String, doll: Node) -> Color:
	if cls(id) == PAINT:
		var d := MaterialDef.get_def(id)
		return d.swatch if d != null else Color(0.85, 0.2, 0.15)
	if (id == "maple" or id == "wood_dark") and doll != null and is_instance_valid(doll) and doll.get_node_or_null("EnemyLook") == null \
			and not (doll.get("blueprint") is BodyBlueprint):
		var pi: Variant = doll.get("player_index")
		var i := int(pi) if pi != null else 0
		return Tuning.PLAYER_COLORS[clampi(i, 0, Tuning.PLAYER_COLORS.size() - 1)]
	return Color(0, 0, 0, 0)


## Бьющее тело — металл: оружие (молот, меч, топор, булава, сковорода; крафтовое — тоже), железная деталь куклы.
static func striker_metal(striker: Object, striker_doll: Node = null) -> bool:
	if striker == null or not is_instance_valid(striker):
		return false
	if striker is Weapon:
		return true
	if striker is Node and striker_doll != null:
		return is_metal(cls(id_of(striker_doll, striker as Node)))
	return false


## Градиент щепок класса (с хлопьями краски tint, если a > 0). Кэш по ключу.
static var _ramps: Dictionary = {}


static func chip_ramp(c: String, tint: Color) -> GradientTexture1D:
	var key := "%s|%s" % [c, tint.to_html()] if tint.a > 0.0 else c
	if _ramps.has(key):
		return _ramps[key]
	var g := Gradient.new()
	var wood: Array = CHIP_COLOURS.get(c, CHIP_COLOURS[WOOD]) if c != PAINT else CHIP_COLOURS[WOOD]
	if tint.a > 0.0:
		var share := PAINT_SHARE if c == PAINT else STROKE_SHARE
		var t := Color(tint.r, tint.g, tint.b, 1.0)
		# хлопья краски — нижняя доля градиента (ступенькой), дерево — остальное
		g.offsets = PackedFloat32Array([0.0, share - 0.001, share, 1.0])
		g.colors = PackedColorArray([t.lightened(0.12), t.darkened(0.2), wood[0], wood[1]])
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	else:
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([wood[0], wood[1]])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	_ramps[key] = tex
	return tex
