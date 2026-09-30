// Краска куклы (docs/plan-demo/BODY_PAINT.md §2) — ЗАПАСНОЙ путь: next_pass поверх материала, который двойник «краска в том же
// проходе» не повторит (BodyPaint.inpass_block: прозрачные, triplanar, ShaderMaterial…); обычные поверхности кита и старых деталей
// красит сам двойник (BodyPaint.inpass_material) — без второго освещённого прохода.
// Слой — PaintLayer: 3D-текстура RGBA8 поверх габарита меша детали в кадре корня меша (Mesh / Mesh_<uid>); RGB предумножен на A
// (фильтрация на краю мазка не тянет чёрный из пустых ячеек) — здесь делится обратно. Цвета слоя — sRGB (Color / ColorPicker),
// ALBEDO — линейный: перевод здесь (source_color у sampler3D не везде есть).
// Прозрачный проход: blend_mix, глубину не пишет, тени не отбрасывает (материал с ALPHA в теневой проход не идёт), свет и тени
// получает; лёгкий сдвиг по нормали — от z-fighting с исходной поверхностью. Меш-наклейки (render_priority 1) рисуются после
// этого прохода — наклейка поверх краски.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler3D paint_tex : filter_linear, repeat_disable;
// Кадр MeshInstance3D → кадр слоя (корень меша детали): mesh_root⁻¹ · mesh_instance, посчитан один раз при сборке.
uniform mat4 to_layer = mat4(1.0);
uniform vec3 aabb_pos = vec3(0.0);
uniform vec3 aabb_size = vec3(1.0);
uniform float roughness_paint : hint_range(0.0, 1.0) = 0.45;
// Сдвиг по нормали, м (≈ 0.4 мм).
uniform float normal_offset = 0.0004;

varying vec3 layer_pos;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	VERTEX += NORMAL * normal_offset;
	layer_pos = (to_layer * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 p = texture(paint_tex, (layer_pos - aabb_pos) / aabb_size);
	if (p.a < 0.004) {
		discard;
	}
	ALBEDO = srgb_to_linear(clamp(p.rgb / p.a, vec3(0.0), vec3(1.0)));
	ALPHA = p.a;
	ROUGHNESS = roughness_paint;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
