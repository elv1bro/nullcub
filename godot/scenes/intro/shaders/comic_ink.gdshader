// Чернильный контур кадра комикса (пост-эффект на квадрате перед камерой IntroStage).
// Рисует ТОЛЬКО линии поверх кадра (ALPHA = сила линии): цвет кадра не трогает, поэтому прозрачные частицы
// (искры, угли, пыль) не пропадают. Линии — разрывы глубины (силуэты) и нормалей (грани), тоньше и слабее с расстоянием,
// дальний фон (слои параллакса) без линий. Цвет, растр и бумага — в 2D-шейдере панели comic_panel.gdshader.
shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, blend_mix;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;

uniform float strength : hint_range(0.0, 1.0) = 0.85;
uniform float line_px : hint_range(0.5, 4.0) = 1.4;
uniform float depth_rel : hint_range(0.005, 0.5) = 0.035;
uniform float normal_min : hint_range(0.0, 1.0) = 0.35;
uniform float normal_weight : hint_range(0.0, 1.0) = 0.55;
uniform float near_full = 3.0;     // м: до этой глубины линии полной силы
uniform float far_zero = 16.0;     // м: дальше линий нет
uniform vec3 ink = vec3(0.07, 0.045, 0.035);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 nrm(vec2 uv) {
	return normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
}

void fragment() {
	vec2 px = line_px / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	float d0 = lin_depth(uv, INV_PROJECTION_MATRIX);
	float dl = lin_depth(uv - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float dr = lin_depth(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float du = lin_depth(uv - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float dd = lin_depth(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	// силуэт: ближняя сторона разрыва — линия рисуется по объекту, а не по фону за ним
	float dmin = min(min(dl, dr), min(du, dd));
	float dmax = max(max(dl, dr), max(du, dd));
	float rel = (dmax - d0) / max(d0, 0.05);
	float e_depth = smoothstep(depth_rel, depth_rel * 2.5, rel);
	// грани: разрыв нормалей
	vec3 n0 = nrm(uv);
	float nd = min(min(dot(n0, nrm(uv - vec2(px.x, 0.0))), dot(n0, nrm(uv + vec2(px.x, 0.0)))),
			min(dot(n0, nrm(uv - vec2(0.0, px.y))), dot(n0, nrm(uv + vec2(0.0, px.y)))));
	float e_norm = smoothstep(1.0 - normal_min, 1.0 - normal_min * 2.2, nd) * normal_weight;
	// сила по глубине: ближние линии полные, к far_zero гаснут
	float fade = 1.0 - smoothstep(near_full, far_zero, d0);
	float e = max(e_depth, e_norm) * fade * strength;
	ALBEDO = ink;
	ALPHA = clamp(e, 0.0, 1.0);
}
