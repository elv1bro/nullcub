// «Рентген» крупного плана сокрушительного удара (HIT_FX.md §3.2): полноэкранный квад — ребёнок CritCam, рисуется в прозрачном
// проходе 3D поверх всей сцены (HUD и CanvasLayer не затрагивает). Читает экран, глубину и нормали (Forward+; в Mobile буфера
// нормалей нет — внутренние контуры берутся из кривизны глубины, perf-pass):
// обесцвечивание → яркость по рампе #0b1630 → #2d7fd6 → #bfe9ff, контуры Собелем по линейной глубине и нормалям (#e8f6ff),
// виньетка. Ударенная деталь (оверлей xray_wood, render_priority выше) рисуется после и остаётся тёплой.
// v2 (HIT_FX.md §11.4): use_mask — фон вне маски кукол (DollMask, альфа) плоский тёмно-синий (bg_colour, мягкий радиальный
// градиент к центру) без рампы и контуров: на детальных аренах (Руины) стена не спорит с куклой. Без маски — как v1.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;
#endif
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform vec3 ramp_dark : source_color = vec3(0.043, 0.086, 0.188);
uniform vec3 ramp_mid : source_color = vec3(0.176, 0.498, 0.839);
uniform vec3 ramp_light : source_color = vec3(0.749, 0.914, 1.0);
uniform vec3 edge_colour : source_color = vec3(0.91, 0.965, 1.0);
uniform float edge_px = 1.5;
uniform float depth_edge = 0.06;     // относительный скачок линейной глубины → контур
uniform float normal_edge = 1.2;     // выше — меньше внутренних контуров (резьба/стыки деталей)
uniform float curv_edge = 0.045;     // Mobile: то же по кривизне глубины (Лапласиан / глубина)
uniform float vignette = 0.35;
uniform float flash = 0.0;           // вспышка «перелома» на 400 мс: осветление рампы
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform float use_mask = 0.0;
uniform vec3 bg_colour : source_color = vec3(0.027, 0.055, 0.13);
uniform vec3 bg_centre : source_color = vec3(0.06, 0.13, 0.28);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
vec3 nrm(vec2 uv) {
	return texture(normal_tex, uv).xyz * 2.0 - 1.0;
}
#endif

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = edge_px / VIEWPORT_SIZE;
	vec3 src = texture(screen_tex, uv).rgb;
	float lum = dot(src, vec3(0.299, 0.587, 0.114));
	float x = clamp(0.04 + lum * 0.62 + flash * 0.25, 0.0, 1.0);   // светлое дерево — середина рампы, светлее только контуры
	vec3 ramp = x < 0.5 ? mix(ramp_dark, ramp_mid, x * 2.0) : mix(ramp_mid, ramp_light, x * 2.0 - 1.0);
	// Собель по глубине (относительный) и нормалям
	float dc = lin_depth(uv, INV_PROJECTION_MATRIX);
	float gx = 0.0;
	float gy = 0.0;
	vec3 ngx = vec3(0.0);
	vec3 ngy = vec3(0.0);
	float lap = 0.0;
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			if (i == 0 && j == 0) continue;
			vec2 o = vec2(float(i), float(j)) * px;
			float w = (i == 0 || j == 0) ? 2.0 : 1.0;
			float d = lin_depth(uv + o, INV_PROJECTION_MATRIX);
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
			vec3 n = nrm(uv + o);
			ngx += float(i) * w * n;
			ngy += float(j) * w * n;
#else
			if (i == 0 || j == 0) lap += d - dc;   // 4 соседа: Σ(d − d0) = Лапласиан глубины
#endif
			gx += float(i) * w * d;
			gy += float(j) * w * d;
		}
	}
	float e_depth = smoothstep(depth_edge, depth_edge * 2.5, length(vec2(gx, gy)) / max(dc, 0.05));
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
	float e_norm = smoothstep(normal_edge, normal_edge * 2.0, length(ngx) + length(ngy)) * step(dc, 60.0);
#else
	float e_norm = smoothstep(curv_edge, curv_edge * 2.0, abs(lap) / max(dc, 0.05)) * step(dc, 60.0);
#endif
	float edge = clamp(max(e_depth, e_norm), 0.0, 1.0);
	vec3 col = mix(ramp, edge_colour, edge * 0.85);
	vec2 q = uv - 0.5;
	if (use_mask > 0.5) {
		float fig = smoothstep(0.2, 0.6, texture(mask_tex, uv).a);
		vec3 bg = mix(bg_centre, bg_colour, smoothstep(0.0, 0.6, length(q * vec2(1.4, 1.0)))) * (1.0 + flash * 0.4);
		col = mix(bg, col, fig);
	}
	col *= 1.0 - vignette * smoothstep(0.25, 0.75, length(q * vec2(1.25, 1.0)));
	ALBEDO = mix(src, col, intensity);
}
