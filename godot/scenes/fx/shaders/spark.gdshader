// Искры и конус удара heavy (HIT_FX.md §11.3, SparkCone): квад в плоскости XY, локальная +Y — вдоль полёта искры.
// cone 0 — штрих-искра (узкая, раскалённое ядро, хвост к основанию); cone 1 — конус-вспышка от точки удара вдоль ctx.dir.
// Цвет и затухание — instance-параметры (материал общий).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

instance uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.6, 1.0);
instance uniform float fade = 1.0;
instance uniform float cone = 0.0;

void fragment() {
	float along = 1.0 - UV.y;            // 0 — основание (точка удара), 1 — кончик
	float x = abs(UV.x * 2.0 - 1.0);
	float a;
	vec3 col;
	if (cone > 0.5) {
		float w = mix(0.18, 1.0, sqrt(along));
		float body = 1.0 - smoothstep(w * 0.35, w, x);
		float len = smoothstep(0.0, 0.06, along) * pow(1.0 - along, 1.4);
		a = body * len;
		float core = (1.0 - smoothstep(0.0, w * 0.35, x)) * (1.0 - smoothstep(0.0, 0.6, along));
		col = mix(tint.rgb, vec3(1.0), core * 0.8);
	} else {
		float body = 1.0 - smoothstep(0.15, 1.0, x);
		float len = smoothstep(0.0, 0.55, along) * (1.0 - smoothstep(0.85, 1.0, along));
		a = body * body * len;
		float core = (1.0 - smoothstep(0.0, 0.45, x)) * smoothstep(0.5, 0.9, along);
		col = mix(tint.rgb, vec3(1.0), core);
	}
	ALBEDO = col * tint.a * fade * a * 1.6;
	ALPHA = clamp(a * fade, 0.0, 1.0);
}
