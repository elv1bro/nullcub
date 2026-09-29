// Оверлей ударенной детали в крупном плане (material_overlay инстанса, материал куклы не меняется): светящиеся волокна вдоль
// длинной оси детали (процедурный шум в пространстве тела детали — не зависит от меша), трещины из crack_screen.png
// (G — путь от точки удара: раскрытие reveal 0 → 1), френель-обод, тлеющая основа. Смешивание по альфе (на светлом рентгене
// аддитив выгорал в белое); render_priority выше квада рентгена — рисуется после него и остаётся тёплой.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

uniform mat4 world_to_part;                 // обратная глобальная матрица тела детали (скрипт обновляет каждый кадр)
uniform vec3 grain_axis = vec3(0.0, 1.0, 0.0);   // длинная ось детали в её пространстве
uniform vec3 hit_local = vec3(0.0);         // точка удара в пространстве детали
uniform vec3 proj_u = vec3(0.0, 1.0, 0.0);  // плоскость проекции трещин (пространство детали)
uniform vec3 proj_v = vec3(1.0, 0.0, 0.0);
uniform float crack_size = 0.45;            // м на всю текстуру трещин
uniform sampler2D crack_tex : filter_linear, repeat_disable;
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float flash = 0.0;
uniform vec3 fibre_colour : source_color = vec3(1.0, 0.8, 0.35);
uniform vec3 crack_colour : source_color = vec3(1.0, 0.93, 0.7);
uniform vec3 rim_colour : source_color = vec3(1.0, 0.78, 0.45);
uniform vec3 ember_colour : source_color = vec3(0.95, 0.36, 0.06);
uniform float ember_alpha = 0.9;

varying vec3 p_part;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	p_part = (world_to_part * vec4(w, 1.0)).xyz;
}

void fragment() {
	vec3 g = normalize(grain_axis);
	vec3 a = abs(g.x) < 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 t1 = normalize(cross(g, a));
	vec3 t2 = cross(g, t1);
	float along = dot(p_part, g);
	vec2 across = vec2(dot(p_part, t1), dot(p_part, t2));
	// волокна: полосы поперёк оси с медленным извивом вдоль неё
	float wob = noise(vec2(along * 6.0, across.x * 3.0)) * 1.4;
	float s = across.x * 90.0 + across.y * 35.0 + wob * 3.0;
	float fibre = pow(1.0 - abs(fract(s) * 2.0 - 1.0), 7.0);
	fibre *= 0.55 + 0.45 * noise(vec2(along * 18.0, s * 0.5));
	// трещины от точки удара
	vec3 d = p_part - hit_local;
	vec2 cuv = vec2(dot(d, normalize(proj_u)), dot(d, normalize(proj_v))) / crack_size + 0.5;
	float crack = 0.0;
	if (cuv.x > 0.0 && cuv.x < 1.0 && cuv.y > 0.0 && cuv.y < 1.0) {
		vec4 c = texture(crack_tex, cuv);
		crack = c.r * (1.0 - smoothstep(reveal - 0.04, reveal, c.g));
	}
	float near_hit = 1.0 - smoothstep(0.0, crack_size * 0.6, length(d));
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.5);
	float heat = 0.45 + 0.55 * near_hit + flash;
	float f = clamp(fibre * heat * 1.4, 0.0, 1.0);
	float c = clamp(crack * (1.2 + flash), 0.0, 1.0);
	vec3 col = ember_colour * (1.0 + flash);
	col = mix(col, fibre_colour * (1.2 + flash), f);
	col = mix(col, rim_colour, fres * 0.7);
	col = mix(col, crack_colour * 1.6, c);
	ALBEDO = col;
	ALPHA = clamp(max(max(ember_alpha * (0.6 + 0.4 * near_hit), f), max(c, fres * 0.8)) * intensity, 0.0, 1.0);
}
