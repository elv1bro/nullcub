## Покраска куклы на сцене (docs/plan-demo/BODY_PAINT.md §2, §3, §5): слой краски на детали, наклейки, фото на плашку лица.
## Только статика. Зовёт ModularDoll после Doll._ready (Shirt уже в цвете игрока): tag_layers всегда, apply_node — узлам с ключами
## paint / stickers / face; мастерская рисует в живой слой через ModularDoll.ensure_paint / paint_handle.
##
## Правила:
##   • покраска косметическая: тела, формы, массы, центры масс и физматериалы не трогаются — только материалы поверхностей
##     (override на инстансе), узлы наклеек (MeshInstance3D без форм) и биты visual layers мешей;
##   • цвет игрока не закрашивается: поверхности, чей материал начинается на «Shirt» (шары шарниров, пояса, флажки, мазки v3), не
##     получают ни краски, ни наклеек; «Face» (плашка фото) — без краски, наклейку на неё можно (очки на фото, корона на лбу);
##     коннекторы шарниров (Connector_*) — ни того, ни другого;
##   • слой краски — в кадре корня меша детали (mesh_root_of): у своего тела узел «Mesh», у слитой детали «Mesh_<uid>» (ModularDoll
##     переименовывает детей слитой детали в <имя>_<uid>); у каждого MeshInstance3D свой to_layer = кадр меша в кадре корня
##     (glb кладёт меши со своими трансформами, у старых деталей — вложенно: FacePlate под Head);
##   • attach_layer: поверхность получает свой материал (Base_* и материалы glb общие между куклами): обычно — двойник
##     StandardMaterial3D с краской В ТОМ ЖЕ ПРОХОДЕ (inpass_material: второго освещённого прохода нет — он был 85–90 % цены краски,
##     4 куклы крупным планом теряли 12.6 % FPS, так — ≈ 1.4 %); материалы, которые двойник не повторит (inpass_block), — дубль с
##     next_pass = прозрачный проход краски (paint_overlay.gdshader); to_layer — свой у каждого меша, текстура слоя общая;
##   • наклейка — «меш-декаль»: MeshInstance3D «Sticker» ребёнком тела детали, кадр xf в кадре корня меша (−Y — в поверхность);
##     её меш — копия треугольников ЭТОЙ детали внутри коробки наклейки (без Shirt* и коннекторов), UV — проекция на XZ
##     кадра (как у Decal), чуть над поверхностью, прозрачный материал поверх краски. Не Decal: кластерные декали Forward+
##     отсекаются плитками экрана по 32 px, и наклейка шириной 10–17 px в матче пропадала кусками при каждом сдвиге камеры;
##     меш-наклейка не ложится на пояса, шары суставов и соседние детали (и чужих кукол в клинче);
##   • бит PAINT_LAYER_BIT (слой 12) tag_layers даёт мешам куклы, кроме коннекторов: слой «кукла, кроме шаров суставов» для
##     Decal-эффектов по куклам (наклейкам он не нужен — они меши);
##   • плохие данные (битый слой, нет картинки, нет узла) — предупреждение в лог, кукла собирается без этого куска.
class_name BodyPaint
extends RefCounted

const PAINT_LAYER_BIT := 1 << 11
const SHADER_PATH := "res://assets/materials/kit/paint_overlay.gdshader"
## Материалы с этими префиксами не красятся (цвет игрока и фото).
const SKIP_PREFIXES := ["Shirt", "Face"]
## Цвет игрока: на эти поверхности не ложится и наклейка.
const PLAYER_PREFIX := "Shirt"
const CONNECTOR_PREFIX := "Connector_"
## Имя узлов-наклеек (Godot добавит номер: Sticker, Sticker2…) и meta с их словарём из чертежа.
const STICKER_NAME := "Sticker"
const STICKER_META := "sticker"
const STICKER_DEPTH := 0.04
## n·Y поверхности (Y наклейки — наружу): ниже — наклейки нет, от него до STICKER_NORMAL_FULL — спад (бока конечностей).
const STICKER_NORMAL_FADE := 0.3
const STICKER_NORMAL_FULL := 0.55
const STICKER_FADE := 0.2
## Доля полуглубины коробки у её верха и низа, где наклейка гаснет (как upper / lower fade у Decal).
const STICKER_EDGE_FADE := 0.3
## Подъём над поверхностью вдоль +Y наклейки (м). Мал нарочно: край пояса бывает на 0.4 мм над стенкой под ним — наклейка выше
## легла бы на него полоской. Поверх краски (0.4 мм по нормали, прозрачная, глубину не пишет) наклейку кладёт render_priority, не
## высота; от z-fighting с деталью хватает (обратный Z, float-глубина).
const STICKER_LIFT := 0.0003
## render_priority материала наклейки: после прозрачного прохода краски (priority 0) — наклейка поверх краски.
const STICKER_PRIORITY := 1
## Большая сторона наклейки ≤ 40 см, как в мастерской (чертёж руками не даст метровую).
const STICKER_SIZE_RANGE := Vector2(0.005, 0.4)
## Сетка треугольников меша для наклеек: ячеек по длинной оси (запрос коробкой — только ближние треугольники).
const STICKER_GRID := 12
## Имя ShaderMaterial краски (мастерская и пробы узнают его в next_pass).
const PAINT_MAT_NAME := "Paint"
## meta двойника «материал + краска в том же проходе» (inpass_material): исходный материал поверхности.
const INPASS_META := "paint_src"
const STICKER_MAT_NAME := "Sticker"

static var _shader: Shader
static var _tris: Dictionary = {}          # instance id меша -> треугольники и сетка (_mesh_tris)
static var _sticker_mats: Dictionary = {}  # «img|цвет|альфа» -> StandardMaterial3D наклейки
static var _inpass_shaders: Dictionary = {}  # набор возможностей -> Shader двойника (inpass_material)
static var _cleanup_hooked := false


static func shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	return _shader


## Корень меша узла uid: у своего тела — «Mesh», у слитой детали — «Mesh_<uid>» на теле-хозяине. null — нет узла / меша.
static func mesh_root_of(doll: ModularDoll, uid: String) -> Node3D:
	var body := body_of(doll, uid)
	if body == null:
		return null
	var fixed := doll.blueprint != null and doll.blueprint.is_fixed(uid)
	return body.get_node_or_null(NodePath("Mesh_" + uid if fixed else "Mesh")) as Node3D


## Тело узла uid (у слитой детали — тело-хозяин). null — нет.
static func body_of(doll: ModularDoll, uid: String) -> Node3D:
	if doll == null or not doll.uid_body.has(uid):
		return null
	var bn := String(doll.uid_body[uid])
	var b: Variant = doll.parts.get(bn)
	if b is Node3D and is_instance_valid(b):
		return b
	return doll.get_node_or_null(NodePath(bn)) as Node3D


## Габарит мешей под корнем (без коннекторов) в кадре корня: по нему PaintLayer.for_aabb.
static func mesh_aabb(mesh_root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in meshes(mesh_root):
		var m := mi as MeshInstance3D
		var b: AABB = _rel_xf(m, mesh_root) * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Слой на все красимые поверхности мешей корня. {layer, tex, materials: [ShaderMaterial с paint_tex], mesh_root}. Повторный вызов
## на том же корне заменяет прежний слой (двойник собирается заново от исходника, next_pass — перезаписывается).
## Основной путь — краска в проходе самой поверхности (inpass_material): второго освещённого прохода нет. Материалы, которые двойник
## не повторит (inpass_block: прозрачные, triplanar, detail, rim, ORM, ShaderMaterial…), — по-старому: дубль материала для этого
## MeshInstance3D с next_pass = ShaderMaterial краски (paint_overlay.gdshader).
static func attach_layer(mesh_root: Node3D, layer: PaintLayer) -> Dictionary:
	if mesh_root == null or layer == null:
		return {}
	var tex := layer.make_texture()
	var mats: Array[ShaderMaterial] = []
	for mi in meshes(mesh_root):
		var m := mi as MeshInstance3D
		var to_layer := Projection(_rel_xf(m, mesh_root))
		var pm: ShaderMaterial = null   # прозрачный проход краски этого меша (только если он понадобился)
		var dups := {}   # исходный материал -> материал с краской (у этого меша)
		for s in m.mesh.get_surface_count():
			var cur := surface_material(m, s)
			if cur == null or is_protected(cur):
				continue
			var src: Material = cur.get_meta(INPASS_META) if cur.has_meta(INPASS_META) else cur
			if not dups.has(src):
				if inpass_block(src) == "":
					var im := inpass_material(src as BaseMaterial3D, tex, to_layer, layer.aabb)
					dups[src] = im
					mats.append(im)
				else:
					if pm == null:
						pm = ShaderMaterial.new()
						pm.resource_name = PAINT_MAT_NAME
						pm.shader = shader()
						pm.set_shader_parameter("paint_tex", tex)
						pm.set_shader_parameter("to_layer", to_layer)
						pm.set_shader_parameter("aabb_pos", layer.aabb.position)
						pm.set_shader_parameter("aabb_size", layer.aabb.size)
						mats.append(pm)
					var dup := src.duplicate() as Material
					var prev := dup.next_pass
					if prev != null and prev.resource_name != PAINT_MAT_NAME:
						# у исходника свой второй проход — краска встаёт перед ним (своя копия ShaderMaterial на эту цепочку)
						var pm2 := pm.duplicate() as ShaderMaterial
						pm2.next_pass = prev
						dup.next_pass = pm2
						mats.append(pm2)
					else:
						dup.next_pass = pm
					dups[src] = dup
			m.set_surface_override_material(s, dups[src])
	return {"layer": layer, "tex": tex, "materials": mats, "mesh_root": mesh_root}


## Почему материал m не переводится в двойник с краской в том же проходе ("" — переводится): двойник повторяет только
## StandardMaterial3D кита и старых деталей — непрозрачный, попиксельный, Burley / Schlick-GGX, любой cull (у glb старой куклы —
## двусторонний), альбедо / шероховатость / металл (текстуры
## с каналом) / блик / карта нормалей / свечение (сложением, UV1) / UV1 scale + offset / цвет вершин (линейный), фильтр и повтор
## текстур — любые. Остальное (ORM, triplanar, detail, rim, clearcoat, анизотропия, AO, высота, SSS, подсветка сзади, преломление,
## прозрачность, спецрежимы глубины и смешения, billboard, fade, …) — прозрачный проход, как раньше.
static func inpass_block(m: Material) -> String:
	if m == null:
		return "null"
	if not m is StandardMaterial3D:
		return "class:" + m.get_class()
	var b := m as StandardMaterial3D
	if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or b.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
		return "transparent"
	if b.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or b.diffuse_mode != BaseMaterial3D.DIFFUSE_BURLEY \
			or b.specular_mode != BaseMaterial3D.SPECULAR_SCHLICK_GGX:
		return "shading"
	if b.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY or b.no_depth_test:
		return "render_mode"
	if b.uv1_triplanar or b.uv2_triplanar or b.detail_enabled or b.rim_enabled or b.clearcoat_enabled or b.anisotropy_enabled \
			or b.ao_enabled or b.heightmap_enabled or b.subsurf_scatter_enabled or b.subsurf_scatter_transmittance_enabled \
			or b.backlight_enabled or b.refraction_enabled:
		return "feature"
	if b.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or b.grow or b.use_point_size or b.fixed_size or b.proximity_fade_enabled \
			or b.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED or b.albedo_texture_msdf or b.albedo_texture_force_srgb \
			or b.vertex_color_is_srgb or b.disable_ambient_light or b.disable_receive_shadows or b.shadow_to_opacity:
		return "flags"
	if b.emission_enabled and (b.emission_operator != BaseMaterial3D.EMISSION_OP_ADD or b.emission_on_uv2):
		return "emission"
	for extra in ["use_z_clip_scale", "use_fov_override", "disable_fog", "disable_specular_occlusion"]:   # новее 4.3 — если есть
		var v: Variant = b.get(extra)
		if v is bool and v:
			return "flags"
	var sm: Variant = b.get("stencil_mode")
	if sm is int and int(sm) != 0:
		return "stencil"
	return ""


## Двойник StandardMaterial3D b с краской в том же проходе: ShaderMaterial (шейдер — общий на набор возможностей), параметры b,
## слой (paint_tex, to_layer, габарит). meta INPASS_META = b, resource_name = b.resource_name, next_pass и render_priority — как у b.
static func inpass_material(b: BaseMaterial3D, tex: ImageTexture3D, to_layer: Projection, box: AABB) -> ShaderMaterial:
	var fa := b.albedo_texture != null
	var fr := b.roughness_texture != null
	var fm := b.metallic_texture != null
	var fn := b.normal_enabled and b.normal_texture != null
	var fe := b.emission_enabled
	var fet := fe and b.emission_texture != null
	var fv := b.vertex_color_use_as_albedo
	var hint := "%s, %s" % [_filter_hint(b.texture_filter), "repeat_enable" if b.texture_repeat else "repeat_disable"]
	var cull: String = ["cull_back", "cull_front", "cull_disabled"][clampi(b.cull_mode, 0, 2)]
	var key := "%d%d%d%d%d%d%d|%d|%d|%s|%s" % [int(fa), int(fr), int(fm), int(fn), int(fe), int(fet), int(fv), b.roughness_texture_channel,
		b.metallic_texture_channel, hint, cull]
	var sh: Shader = _inpass_shaders.get(key)
	if sh == null:
		sh = Shader.new()
		sh.code = _inpass_code(fa, fr, fm, fn, fe, fet, fv, b.roughness_texture_channel, hint, cull)
		_inpass_shaders[key] = sh
		_hook_cleanup()
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.resource_name = b.resource_name
	sm.set_meta(INPASS_META, b)
	sm.render_priority = b.render_priority
	sm.next_pass = b.next_pass
	sm.set_shader_parameter("albedo", b.albedo_color)
	sm.set_shader_parameter("roughness", b.roughness)
	sm.set_shader_parameter("metallic", b.metallic)
	sm.set_shader_parameter("specular", b.metallic_specular)
	sm.set_shader_parameter("uv1_scale", b.uv1_scale)
	sm.set_shader_parameter("uv1_offset", b.uv1_offset)
	var ch := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.333333, 0.333333, 0.333333, 0)]
	if fa:
		sm.set_shader_parameter("texture_albedo", b.albedo_texture)
	if fr:
		sm.set_shader_parameter("texture_roughness", b.roughness_texture)
		sm.set_shader_parameter("roughness_texture_channel", ch[clampi(b.roughness_texture_channel, 0, 4)])
	if fm:
		sm.set_shader_parameter("texture_metallic", b.metallic_texture)
		sm.set_shader_parameter("metallic_texture_channel", ch[clampi(b.metallic_texture_channel, 0, 4)])
	if fn:
		sm.set_shader_parameter("texture_normal", b.normal_texture)
		sm.set_shader_parameter("normal_scale", b.normal_scale)
	if fe:
		sm.set_shader_parameter("emission", b.emission)
		sm.set_shader_parameter("emission_energy", b.emission_energy_multiplier)
		if fet:
			sm.set_shader_parameter("texture_emission", b.emission_texture)
	sm.set_shader_parameter("paint_tex", tex)
	sm.set_shader_parameter("to_layer", to_layer)
	sm.set_shader_parameter("aabb_pos", box.position)
	sm.set_shader_parameter("aabb_size", box.size)
	return sm


## Кэши шейдеров-двойников и материалов наклеек (static) — очистить, когда корень дерева уходит (выход из игры): иначе Shader.new()
## переживал бы RenderingServer и выход ругался «RID allocations … Shader were leaked at exit».
static func _hook_cleanup() -> void:
	if _cleanup_hooked:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_cleanup_hooked = true
	tree.root.tree_exiting.connect(func() -> void:
		_inpass_shaders.clear()
		_sticker_mats.clear()
		_cleanup_hooked = false, CONNECT_ONE_SHOT)


static func _filter_hint(f: int) -> String:
	match f:
		BaseMaterial3D.TEXTURE_FILTER_NEAREST:
			return "filter_nearest"
		BaseMaterial3D.TEXTURE_FILTER_LINEAR:
			return "filter_linear"
		BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS:
			return "filter_nearest_mipmap"
		BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC:
			return "filter_nearest_mipmap_anisotropic"
		BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC:
			return "filter_linear_mipmap_anisotropic"
	return "filter_linear_mipmap"


## Код шейдера-двойника StandardMaterial3D (как его генерирует BaseMaterial3D для этого набора) + краска: слой смешивает альбедо,
## шероховатость (глянец краски roughness_paint), металл → 0, блик → 0.5 по альфе; свечение и карта нормалей под краской гаснут
## (иначе окошко ядра светило бы сквозь краску, доски проступали бы рельефом).
static func _inpass_code(fa: bool, fr: bool, fm: bool, fn: bool, fe: bool, fet: bool, fv: bool, rch: int, hint: String, cull: String) -> String:
	const RH := ["hint_roughness_r", "hint_roughness_g", "hint_roughness_b", "hint_roughness_a", "hint_roughness_gray"]
	var c := "// Двойник StandardMaterial3D + краска в том же проходе (BodyPaint.inpass_material, docs/plan-demo/BODY_PAINT.md §8).\n"
	c += "shader_type spatial;\nrender_mode blend_mix, depth_draw_opaque, %s, diffuse_burley, specular_schlick_ggx;\n\n" % cull
	c += "uniform vec4 albedo : source_color = vec4(1.0);\nuniform float roughness : hint_range(0.0, 1.0) = 1.0;\n"
	c += "uniform float metallic : hint_range(0.0, 1.0) = 0.0;\nuniform float specular : hint_range(0.0, 1.0) = 0.5;\n"
	c += "uniform vec3 uv1_scale = vec3(1.0);\nuniform vec3 uv1_offset = vec3(0.0);\n"
	if fa:
		c += "uniform sampler2D texture_albedo : source_color, %s;\n" % hint
	if fr:
		c += "uniform sampler2D texture_roughness : %s, %s;\nuniform vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);\n" \
			% [RH[clampi(rch, 0, 4)], hint]
	if fm:
		c += "uniform sampler2D texture_metallic : hint_default_white, %s;\nuniform vec4 metallic_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);\n" % hint
	if fn:
		c += "uniform sampler2D texture_normal : hint_roughness_normal, %s;\nuniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;\n" % hint
	if fe:
		c += "uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);\nuniform float emission_energy = 1.0;\n"
		if fet:
			c += "uniform sampler2D texture_emission : source_color, hint_default_black, %s;\n" % hint
	c += "\nuniform sampler3D paint_tex : filter_linear, repeat_disable;\nuniform mat4 to_layer = mat4(1.0);\n"
	c += "uniform vec3 aabb_pos = vec3(0.0);\nuniform vec3 aabb_size = vec3(1.0);\n"
	c += "uniform float roughness_paint : hint_range(0.0, 1.0) = 0.45;\nvarying vec3 paint_pos;\n\n"
	c += "vec3 paint_to_linear(vec3 x) {\n\treturn mix(pow((x + vec3(0.055)) / 1.055, vec3(2.4)), x / 12.92, lessThan(x, vec3(0.04045)));\n}\n\n"
	c += "void vertex() {\n\tpaint_pos = (to_layer * vec4(VERTEX, 1.0)).xyz;\n\tUV = UV * uv1_scale.xy + uv1_offset.xy;\n}\n\n"
	c += "void fragment() {\n\tvec2 base_uv = UV;\n"
	c += "\tvec4 albedo_tex = %s;\n" % ("texture(texture_albedo, base_uv)" if fa else "vec4(1.0)")
	if fv:
		c += "\talbedo_tex *= COLOR;\n"
	c += "\tALBEDO = albedo.rgb * albedo_tex.rgb;\n"
	c += "\tMETALLIC = %s;\n" % ("dot(texture(texture_metallic, base_uv), metallic_texture_channel) * metallic" if fm else "metallic")
	c += "\tROUGHNESS = %s;\n" % ("dot(texture(texture_roughness, base_uv), roughness_texture_channel) * roughness" if fr else "roughness")
	c += "\tSPECULAR = specular;\n"
	if fn:
		c += "\tNORMAL_MAP = texture(texture_normal, base_uv).rgb;\n\tNORMAL_MAP_DEPTH = normal_scale;\n"
	if fe:
		c += "\tEMISSION = (emission.rgb%s) * emission_energy;\n" % (" + texture(texture_emission, base_uv).rgb" if fet else "")
	c += "\tvec4 p = texture(paint_tex, (paint_pos - aabb_pos) / aabb_size);\n\tif (p.a > 0.004) {\n"
	c += "\t\tALBEDO = mix(ALBEDO, paint_to_linear(clamp(p.rgb / p.a, vec3(0.0), vec3(1.0))), p.a);\n"
	c += "\t\tROUGHNESS = mix(ROUGHNESS, roughness_paint, p.a);\n\t\tMETALLIC = mix(METALLIC, 0.0, p.a);\n"
	c += "\t\tSPECULAR = mix(SPECULAR, 0.5, p.a);\n"
	if fe:
		c += "\t\tEMISSION *= 1.0 - p.a;\n"
	if fn:
		c += "\t\tNORMAL_MAP_DEPTH *= 1.0 - p.a;\n"
	c += "\t}\n}\n"
	return c


## Наклейка: MeshInstance3D «Sticker» ребёнком body (меш-декаль, см. шапку). st = {img, xf (кадр в кадре корня меша, −Y — в
## поверхность), size: Vector2 (м), color} — он же meta «sticker». null — нет картинки / битый словарь (предупреждение).
static func add_sticker(body: Node3D, mesh_root: Node3D, st: Dictionary) -> MeshInstance3D:
	if body == null or mesh_root == null:
		return null
	var err := sticker_error(st)
	if err != "":
		push_warning("BodyPaint: наклейка пропущена — %s" % err)
		return null
	if KitImages.texture(String(st["img"])) == null:
		push_warning("BodyPaint: наклейка пропущена — нет картинки «%s»" % st["img"])
		return null
	var n := MeshInstance3D.new()
	n.name = STICKER_NAME
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.set_meta(STICKER_META, st)
	n.transform = _rel_xf(mesh_root, body) * (st["xf"] as Transform3D)
	body.add_child(n, true)
	bake_sticker(n, mesh_root)
	return n


## Размер наклейки-узла n (м): size из meta «sticker», зажатый в STICKER_SIZE_RANGE.
static func sticker_dims(n: Node) -> Vector2:
	var st: Variant = n.get_meta(STICKER_META, {}) if n != null else {}
	var sz: Variant = (st as Dictionary).get("size", Vector2(0.1, 0.1)) if st is Dictionary else Vector2(0.1, 0.1)
	if not sz is Vector2:
		sz = Vector2(0.1, 0.1)
	return (sz as Vector2).clamp(Vector2.ONE * STICKER_SIZE_RANGE.x, Vector2.ONE * STICKER_SIZE_RANGE.y)


## Пересобрать меш наклейки n по её НЫНЕШНЕМУ кадру (узел можно двигать) и meta «sticker» (img, size, color) на треугольниках
## мешей под mesh_root (корень меша детали: своей или той, над которой её тащат). alpha — множитель прозрачности (превью мастерской).
## Число треугольников (0 — коробка не задела красимых поверхностей: узел остаётся, меш пустой).
static func bake_sticker(n: MeshInstance3D, mesh_root: Node3D, alpha := 1.0) -> int:
	if n == null:
		return 0
	var st: Variant = n.get_meta(STICKER_META, {})
	var sd: Dictionary = st if st is Dictionary else {}
	var tex := KitImages.texture(String(sd.get("img", "")))
	var cv: Variant = sd.get("color", Color.WHITE)
	var col: Color = cv if cv is Color else Color.WHITE
	var am := ArrayMesh.new()
	var res := _sticker_arrays(n, mesh_root, sticker_dims(n))
	var arrays: Array = res[0]
	n.set_meta("sticker_guarded", int(res[1]))   # треугольников цвета игрока в коробке — пропущено (проба)
	var nv := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if not arrays.is_empty() else 0
	if nv > 0 and tex != null:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(0, sticker_material(tex, col, alpha))
	n.mesh = am
	var src := meshes(mesh_root)
	if not src.is_empty():
		n.layers = (src[0] as MeshInstance3D).layers
	return nv / 3 if tex != null else 0


## Материал наклейки (общий на картинку и цвет): альфа-смешение поверх краски, картинка × цвет, альфа вершин — спад по нормали и
## к краям коробки.
static func sticker_material(tex: Texture2D, col: Color, alpha := 1.0) -> StandardMaterial3D:
	var key := "%d|%s|%.3f" % [tex.get_instance_id(), col.to_html(true), alpha]
	var m: StandardMaterial3D = _sticker_mats.get(key)
	if m != null:
		return m
	m = StandardMaterial3D.new()
	m.resource_name = STICKER_MAT_NAME
	m.albedo_texture = tex
	m.albedo_color = Color(col.r, col.g, col.b, col.a * alpha)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.texture_repeat = false
	m.roughness = 0.6
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.render_priority = STICKER_PRIORITY
	_sticker_mats[key] = m
	_hook_cleanup()
	return m


## Треугольники мешей mesh_root в коробке наклейки n (size.x × STICKER_DEPTH × size.y вокруг кадра n), обрезанные по коробке, в
## кадре n: [[VERTEX, NORMAL, TEX_UV, COLOR] для ArrayMesh ([] — пусто), число пропущенных треугольников цвета игрока в коробке].
## Поверхности цвета игрока (Shirt*) и коннекторы пропускаются (плашка лица Face* — нет: наклейка на фото — можно),
## обращённые от наклейки (среднее нормалей вершин · Y < половины STICKER_NORMAL_FADE) — тоже. Порядок обхода вершин — как у меша
## (у зеркального кадра — обратный), UV = (x / w + ½, z / h + ½): верх картинки — −Z кадра, как у Decal.
static func _sticker_arrays(n: Node3D, mesh_root: Node3D, size: Vector2) -> Array:
	if n == null or mesh_root == null:
		return [[], 0]
	var guarded := 0
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	var hd := STICKER_DEPTH * 0.5
	var box := AABB(Vector3(-hw, -hd, -hh), Vector3(size.x, STICKER_DEPTH, size.y))
	var inv := _rel_xf(n, null).affine_inverse()
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cs := PackedColorArray()
	var face_min := STICKER_NORMAL_FADE * 0.5 * 3.0
	for mi in meshes(mesh_root):
		var m := mi as MeshInstance3D
		var t := inv * _rel_xf(m, null)   # кадр меша → кадр наклейки
		var det := t.basis.determinant()
		if absf(det) < 1e-12:
			continue
		var tri := _mesh_tris(m.mesh)
		if tri.is_empty():
			continue
		var ids := _tris_in(tri, t.affine_inverse() * box)
		if ids.is_empty():
			continue
		var sc := m.mesh.get_surface_count()
		var prot := PackedByteArray()
		prot.resize(sc)
		for s in sc:
			prot[s] = 1 if is_player_colour(surface_material(m, s)) else 0
		var v: PackedVector3Array = tri["v"]
		var nv: PackedVector3Array = tri["n"]
		var sf: PackedInt32Array = tri["s"]
		var nb := t.basis.inverse().transposed()
		var flip := det < 0.0
		for id in ids:
			var j := id * 3
			var a := t * v[j]
			var b := t * v[j + 1]
			var c := t * v[j + 2]
			if (a.x > hw and b.x > hw and c.x > hw) or (a.x < -hw and b.x < -hw and c.x < -hw) \
					or (a.z > hh and b.z > hh and c.z > hh) or (a.z < -hh and b.z < -hh and c.z < -hh) \
					or (a.y > hd and b.y > hd and c.y > hd) or (a.y < -hd and b.y < -hd and c.y < -hd):
				continue
			var na := (nb * nv[j]).normalized()
			var nb1 := (nb * nv[j + 1]).normalized()
			var nc := (nb * nv[j + 2]).normalized()
			if na.y + nb1.y + nc.y < face_min:
				continue
			if prot[sf[id]] != 0:
				guarded += 1
				continue
			var pp: Array = [a, c, b] if flip else [a, b, c]
			var pn: Array = [na, nc, nb1] if flip else [na, nb1, nc]
			var inside := true
			for q in pp:
				var qv := q as Vector3
				if absf(qv.x) > hw or absf(qv.z) > hh or absf(qv.y) > hd:
					inside = false
					break
			if not inside:
				for cut in [[0, hw, true], [0, -hw, false], [2, hh, true], [2, -hh, false], [1, hd, true], [1, -hd, false]]:
					var r := _clip_poly(pp, pn, int(cut[0]), float(cut[1]), bool(cut[2]))
					pp = r[0]
					pn = r[1]
					if pp.size() < 3:
						break
				if pp.size() < 3:
					continue
			for k in range(1, pp.size() - 1):
				for w in [0, k, k + 1]:
					var p: Vector3 = pp[w]
					var nn := (pn[w] as Vector3).normalized()
					vs.append(p + Vector3(0.0, STICKER_LIFT, 0.0))
					ns.append(nn)
					uvs.append(Vector2(p.x / size.x + 0.5, p.z / size.y + 0.5))
					var fade := smoothstep(STICKER_NORMAL_FADE, STICKER_NORMAL_FULL, nn.y) \
						* clampf((hd - absf(p.y)) / (hd * STICKER_EDGE_FADE), 0.0, 1.0)
					cs.append(Color(1.0, 1.0, 1.0, fade))
	if vs.is_empty():
		return [[], guarded]
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cs
	return [arr, guarded]


## Многоугольник (вершины pp, нормали pn) по одну сторону плоскости «ось ax = lim» (upper — оставить ≤ lim, иначе ≥ lim):
## [вершины, нормали] (Sutherland–Hodgman, нормали — линейно).
static func _clip_poly(pp: Array, pn: Array, ax: int, lim: float, upper: bool) -> Array:
	var op: Array = []
	var on: Array = []
	var cnt := pp.size()
	for k in cnt:
		var p0: Vector3 = pp[k]
		var p1: Vector3 = pp[(k + 1) % cnt]
		var d0 := (lim - p0[ax]) if upper else (p0[ax] - lim)
		var d1 := (lim - p1[ax]) if upper else (p1[ax] - lim)
		if d0 >= 0.0:
			op.append(p0)
			on.append(pn[k])
		if (d0 >= 0.0) != (d1 >= 0.0):
			var f := d0 / (d0 - d1)
			op.append(p0.lerp(p1, f))
			on.append((pn[k] as Vector3).lerp(pn[(k + 1) % cnt], f))
	return [op, on]


## Треугольники меша в его кадре (кэш по мешу — ресурсы glb общие у всех кукол): {v, n (по 3 на треугольник), s (поверхность),
## lo / hi (габарит треугольника), g0, gc, gd, cells (сетка: ячейка -> PackedInt32Array треугольников)}; {} — нет треугольников.
## Нормалей в меше нет — нормаль грани (лицо у Godot — по часовой: наружу −(b − a) × (c − a)).
static func _mesh_tris(mesh: Mesh) -> Dictionary:
	if mesh == null:
		return {}
	var key := mesh.get_instance_id()
	if _tris.has(key):
		return _tris[key]
	var v := PackedVector3Array()
	var nv := PackedVector3Array()
	var sf := PackedInt32Array()
	for s in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arr := mesh.surface_get_arrays(s)
		if arr.size() <= Mesh.ARRAY_INDEX or not arr[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			continue
		var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] is PackedVector3Array else PackedVector3Array()
		var has_n := nrm.size() == pos.size()
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		if idx.is_empty():
			idx.resize(pos.size() - pos.size() % 3)
			for k in idx.size():
				idx[k] = k
		for k in range(0, idx.size() - 2, 3):
			var ia := idx[k]
			var ib := idx[k + 1]
			var ic := idx[k + 2]
			v.append(pos[ia])
			v.append(pos[ib])
			v.append(pos[ic])
			if has_n:
				nv.append(nrm[ia])
				nv.append(nrm[ib])
				nv.append(nrm[ic])
			else:
				var fn := -(pos[ib] - pos[ia]).cross(pos[ic] - pos[ia]).normalized()
				nv.append(fn)
				nv.append(fn)
				nv.append(fn)
			sf.append(s)
	var nt := sf.size()
	if nt == 0:
		_tris[key] = {}
		return {}
	var box := mesh.get_aabb().grow(0.001)
	var gc := maxf(maxf(box.size.x, maxf(box.size.y, box.size.z)) / float(STICKER_GRID), 0.01)
	var gd := Vector3i(maxi(ceili(box.size.x / gc), 1), maxi(ceili(box.size.y / gc), 1), maxi(ceili(box.size.z / gc), 1))
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	lo.resize(nt)
	hi.resize(nt)
	var build := {}   # ячейка -> Array треугольников
	for id in nt:
		var a := v[id * 3]
		var b := v[id * 3 + 1]
		var c := v[id * 3 + 2]
		var l := a.min(b).min(c)
		var h := a.max(b).max(c)
		lo[id] = l
		hi[id] = h
		var c0 := ((l - box.position) / gc).floor()
		var c1 := ((h - box.position) / gc).floor()
		for z in range(clampi(int(c0.z), 0, gd.z - 1), clampi(int(c1.z), 0, gd.z - 1) + 1):
			for y in range(clampi(int(c0.y), 0, gd.y - 1), clampi(int(c1.y), 0, gd.y - 1) + 1):
				for x in range(clampi(int(c0.x), 0, gd.x - 1), clampi(int(c1.x), 0, gd.x - 1) + 1):
					var ck := (z * gd.y + y) * gd.x + x
					if not build.has(ck):
						build[ck] = []
					(build[ck] as Array).append(id)
	var cells := {}
	for ck in build:
		cells[ck] = PackedInt32Array(build[ck])
	var out := {"v": v, "n": nv, "s": sf, "lo": lo, "hi": hi, "g0": box.position, "gc": gc, "gd": gd, "cells": cells}
	_tris[key] = out
	return out


## Номера треугольников кэша tri, чей габарит задевает q (кадр меша).
static func _tris_in(tri: Dictionary, q: AABB) -> PackedInt32Array:
	var out := PackedInt32Array()
	var g0: Vector3 = tri["g0"]
	var gc: float = tri["gc"]
	var gd: Vector3i = tri["gd"]
	var c0 := ((q.position - g0) / gc).floor()
	var c1 := ((q.end - g0) / gc).floor()
	if c1.x < 0.0 or c1.y < 0.0 or c1.z < 0.0 or c0.x >= gd.x or c0.y >= gd.y or c0.z >= gd.z:
		return out
	var cells: Dictionary = tri["cells"]
	var lo: PackedVector3Array = tri["lo"]
	var hi: PackedVector3Array = tri["hi"]
	var seen := PackedByteArray()
	seen.resize(lo.size())
	seen.fill(0)
	var qe := q.end
	var qp := q.position
	for z in range(clampi(int(c0.z), 0, gd.z - 1), clampi(int(c1.z), 0, gd.z - 1) + 1):
		for y in range(clampi(int(c0.y), 0, gd.y - 1), clampi(int(c1.y), 0, gd.y - 1) + 1):
			for x in range(clampi(int(c0.x), 0, gd.x - 1), clampi(int(c1.x), 0, gd.x - 1) + 1):
				var bucket: Variant = cells.get((z * gd.y + y) * gd.x + x)
				if bucket == null:
					continue
				for id in (bucket as PackedInt32Array):
					if seen[id] != 0:
						continue
					seen[id] = 1
					var l := lo[id]
					var h := hi[id]
					if l.x <= qe.x and h.x >= qp.x and l.y <= qe.y and h.y >= qp.y and l.z <= qe.z and h.z >= qp.z:
						out.append(id)
	return out


## Почему словарь наклейки не годится ("" — годится).
static func sticker_error(st: Variant) -> String:
	if not st is Dictionary:
		return "не словарь"
	var d: Dictionary = st
	if not d.get("img") is String or String(d.get("img")) == "":
		return "нет img"
	if not d.get("xf") is Transform3D:
		return "нет xf (Transform3D)"
	var xf: Transform3D = d["xf"]
	if not xf.origin.is_finite() or absf(xf.basis.determinant()) < 1e-6:
		return "вырожденный xf"
	if d.has("size") and not d["size"] is Vector2:
		return "size — не Vector2"
	if d.has("color") and not d["color"] is Color:
		return "color — не Color"
	return ""


## Фото на плашку лица: поверхности с материалом Face* под корнем получают копию материала с albedo_texture = tex. Картинка ложится
## плоской проекцией вдоль Z меша (плашка смотрит в +Z; triplanar в кадре меша, резкий — по сути одна проекция XY), а не по UV:
## у плашки старой куклы (wood_head, v3) UV — атлас запечки, фото по нему рассыпалось бы. Без растяжения: картинка обрезается по
## центру под пропорции габарита плашки. false — плашки нет. NB: у wood_head плашка утоплена ≈ 2.5 мм под поверхность яйца головы —
## фото видно только в дырках глаз (так устроен ассет v3); у голов кита плашка снаружи.
static func set_face(mesh_root: Node3D, tex: Texture2D) -> bool:
	if mesh_root == null or tex == null:
		return false
	var found := false
	for mi in meshes(mesh_root):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var src := surface_material(m, s)
			if src == null or not src.resource_name.begins_with("Face"):
				continue
			var dup := src.duplicate() as Material
			if dup is BaseMaterial3D:
				var bm := dup as BaseMaterial3D
				bm.albedo_texture = tex
				var c := Color.WHITE
				c.a = bm.albedo_color.a
				bm.albedo_color = c
				_face_projection(bm, _surface_aabb(m.mesh, s), tex)
			elif dup is ShaderMaterial:
				(dup as ShaderMaterial).set_shader_parameter("albedo_texture", tex)
			m.set_surface_override_material(s, dup)
			found = true
	return found


## Фото на плашку лица (ключ face узла) — только у головы кита: у старых голов (wood_head, metal_head, junk_head_*) плашка утоплена
## под поверхность (фото видно лишь в дырках глаз) или её нет — им фото наклейкой на лицо (WorkshopPaint.set_face_image). Одно
## правило для мастерской и замены детали (CraftEdit._replace).
static func face_plate_ok(d: PartDef) -> bool:
	return d != null and d.kind == "head" and d.id.begins_with("kit_")


## Бит PAINT_LAYER_BIT всем MeshInstance3D под doll (в дополнение к их слоям), кроме коннекторов шарниров (Connector_*: шар и
## пояс — цвет игрока; Decal с cull_mask = бит на них не ляжет).
static func tag_layers(doll: Node) -> void:
	if doll == null or String(doll.name).begins_with(CONNECTOR_PREFIX):
		return
	if doll is MeshInstance3D:
		(doll as MeshInstance3D).layers |= PAINT_LAYER_BIT
	for c in doll.get_children():
		tag_layers(c)


## Покраска узла чертежа n (ключи paint / stickers / face, §4) на собранной кукле. {paint: ручка attach_layer или {}, stickers:
## [MeshInstance3D наклеек], face: bool}. Битое — предупреждение и пропуск. face ставится на любую плашку Face* (так собирается и
## старая кукла из чертежа); мастерская пишет его только голове кита (face_plate_ok).
static func apply_node(doll: ModularDoll, uid: String, n: Dictionary) -> Dictionary:
	var out := {"paint": {}, "stickers": [], "face": false}
	if not (n.has("paint") or n.has("stickers") or n.has("face")):
		return out
	var root := mesh_root_of(doll, uid)
	if root == null:
		push_warning("BodyPaint: у узла «%s» нет меша — покраска пропущена" % uid)
		return out
	if n.has("paint"):
		var layer := PaintLayer.from_dict(n["paint"])
		if layer == null:
			push_warning("BodyPaint: слой краски узла «%s» битый — пропущен" % uid)
		else:
			out["paint"] = attach_layer(root, layer)
	var sts: Variant = n.get("stickers")
	if sts is Array:
		var body := body_of(doll, uid)
		for st in sts:
			var d := add_sticker(body, root, st if st is Dictionary else {})
			if d != null:
				(out["stickers"] as Array).append(d)
	elif sts != null:
		push_warning("BodyPaint: stickers узла «%s» — не массив, пропущены" % uid)
	var fv: Variant = n.get("face")
	if fv is String and String(fv) != "":
		var tex := KitImages.texture(String(fv))
		if tex == null:
			push_warning("BodyPaint: фото «%s» узла «%s» не найдено" % [fv, uid])
		elif not set_face(root, tex):
			push_warning("BodyPaint: у узла «%s» нет плашки лица (Face)" % uid)
		else:
			out["face"] = true
	return out


## Материал поверхности s: override инстанса, иначе материал меша. material_override (призрак, подсветка — временные) не берётся.
static func surface_material(m: MeshInstance3D, s: int) -> Material:
	var o := m.get_surface_override_material(s)
	return o if o != null else m.mesh.surface_get_material(s)


## Поверхность цвета игрока (Shirt*): ни краски, ни наклеек.
static func is_player_colour(m: Material) -> bool:
	return m != null and m.resource_name.begins_with(PLAYER_PREFIX)


## Материал не красится (Shirt*, Face*).
static func is_protected(m: Material) -> bool:
	if m == null:
		return true
	for p in SKIP_PREFIXES:
		if m.resource_name.begins_with(p):
			return true
	return false


## ShaderMaterial краски материала поверхности: сам материал, если это двойник с краской в том же проходе (meta INPASS_META), иначе —
## в цепочке next_pass (null — краски нет). В обоих uniform paint_tex — 3D-текстура слоя.
static func paint_pass(m: Material) -> ShaderMaterial:
	if m is ShaderMaterial and m.has_meta(INPASS_META):
		return m
	var cur := m.next_pass if m != null else null
	var guard := 0
	while cur != null and guard < 8:
		if cur is ShaderMaterial and cur.resource_name == PAINT_MAT_NAME:
			return cur
		cur = cur.next_pass
		guard += 1
	return null


## MeshInstance3D с мешем под n (включая n), без поддеревьев Connector_* — меши, которые красит attach_layer.
static func meshes(n: Node) -> Array:
	var out: Array = []
	if n == null or String(n.name).begins_with(CONNECTOR_PREFIX):
		return out
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out += meshes(c)
	return out


## Кадр n в кадре предка up (произведение локальных трансформов; вне дерева тоже). up не предок — кадр n относительно корня цепочки.
static func _rel_xf(n: Node3D, up: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != up:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Плоская проекция фото на плашку b (габарит поверхности в кадре меша, лицом в +Z): triplanar BaseMaterial3D в кадре меша,
## у проекции Z uv = (x·s.x + o.x, −(y·s.y + o.y)) — центр плашки → (0.5, 0.5), верх картинки — вверху (+Y), слева — слева (−X);
## по более длинной стороне картинки — обрезка по центру (доля crop), без растяжения.
static func _face_projection(bm: BaseMaterial3D, b: AABB, tex: Texture2D) -> void:
	var th := float(tex.get_height())
	if b.size.x <= 1e-5 or b.size.y <= 1e-5 or th <= 0.0:
		return
	var plate := b.size.x / b.size.y
	var img := float(tex.get_width()) / th
	var crop := Vector2(plate / img, 1.0) if img > plate else Vector2(1.0, img / plate)
	var k := Vector2(crop.x / b.size.x, crop.y / b.size.y)
	var c := b.get_center()
	bm.uv1_triplanar = true
	bm.uv1_world_triplanar = false
	bm.uv1_triplanar_sharpness = 24.0
	bm.uv1_scale = Vector3(k.x, k.y, k.y)
	bm.uv1_offset = Vector3(0.5 - c.x * k.x, -0.5 - c.y * k.y, 0.0)
	bm.texture_repeat = false
	# прочие карты UV1 (запечённая резьба лица v3, шероховатость) легли бы той же проекцией криво: фото — плоская карточка
	bm.normal_enabled = false
	bm.ao_enabled = false
	bm.heightmap_enabled = false
	bm.roughness_texture = null
	bm.metallic_texture = null


## Габарит поверхности s меша (по вершинам; не вышло — габарит всего меша).
static func _surface_aabb(mesh: Mesh, s: int) -> AABB:
	var arr := mesh.surface_get_arrays(s)
	if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] is PackedVector3Array:
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if not v.is_empty():
			var box := AABB(v[0], Vector3.ZERO)
			for p in v:
				box = box.expand(p)
			return box
	return mesh.get_aabb()
