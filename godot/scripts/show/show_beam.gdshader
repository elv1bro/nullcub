// Видимый луч прожектора фермы (scripts/show/hall_show.gd): конус от фонаря к бойцу. Рендерер Mobile без объёмного тумана — луч
// нарисован: аддитивный, без света, яркая сердцевина и мягкий край (по нормали к взгляду), гаснет к концу (у бойца — не засвечивать его).
// Только передние грани (cull_back): задняя стенка конуса удвоила бы «молоко» поверх трибун.
// Меш — CylinderMesh высотой 1 (UV.y: 0 — верх, у фонаря; 1 — низ, у бойца), масштаб и поворот ставит скрипт.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 colour : source_color = vec3(1.0, 0.95, 0.85);
uniform float strength = 0.12;
uniform float tail = 0.5;       // доля длины у бойца, где луч гаснет
uniform float core = 2.2;       // резкость края: больше — уже яркая сердцевина

void fragment() {
	float edge = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = pow(edge, core);
	float along = UV.y;
	float fade_src = smoothstep(0.0, 0.08, along);
	float fade_dst = 1.0 - smoothstep(1.0 - tail, 1.0, along);
	ALBEDO = colour;
	ALPHA = clamp(strength * soft * fade_src * fade_dst, 0.0, 1.0);
}
