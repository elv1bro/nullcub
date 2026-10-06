// Тень-пятно бойца (FrameShadows, docs/plan-demo/look/frame.md): экранная «декаль» на плоском квадрате, лежащем на поверхности
// под куклой. Квадрат только задаёт область экрана: в каждом пикселе по глубине восстанавливается точка сцены, переводится в кадр
// квадрата, и пятно ложится лишь туда, где сцена у его плоскости (|y| < half_h) — над краем платформы пятно не висит в воздухе,
// на стопах — мягкое затемнение. Чёрный с альфой поверх итогового цвета: гасит и свет, и блик, и эмиссию полос пола (Decal менял
// бы только альбедо — на тёмном блестящем полу купола его не видно). Не blend_mul: Mobile хранит цвет с множителем яркости, и
// «белый» в blend_mul там темнил весь квадрат вдвое (проверено 06.10). Тест глубины выключен — квадрат лежит в полу, мерцания нет.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
instance uniform float half_h = 0.45;  // м по нормали: дальше от плоскости — без тени
instance uniform float strength = 0.0;  // 0..1 — сила пятна в центре

varying vec3 v_o;
varying vec3 v_x;
varying vec3 v_y;
varying vec3 v_z;

void vertex() {
	v_o = MODEL_MATRIX[3].xyz;
	v_x = MODEL_MATRIX[0].xyz;
	v_y = MODEL_MATRIX[1].xyz;
	v_z = MODEL_MATRIX[2].xyz;
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	view.xyz /= view.w;
	vec3 p = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz - v_o;
	float lx = dot(p, v_x) / dot(v_x, v_x);   // −0.5..0.5 по ширине квадрата
	float lz = dot(p, v_z) / dot(v_z, v_z);
	float ly = dot(p, normalize(v_y));        // метры по нормали
	float r = length(vec2(lx, lz)) * 2.0;
	float blob = 1.0 - smoothstep(0.0, 1.0, r);
	blob = blob * (0.6 + 0.4 * blob);
	float h = 1.0 - smoothstep(half_h * 0.35, half_h, abs(ly));
	ALBEDO = vec3(0.0);
	ALPHA = clamp(strength * blob * h, 0.0, 1.0);
}
