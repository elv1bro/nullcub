// Impact frame (HIT_FX.md §2.2, §11.4, ScreenFx): кадр-силуэт поверх 3D и слоёв ниже 5 (HUD на слое 10 не трогается).
// mode 0 — чёрные силуэты на белом, mode 1 — белые силуэты на тёмно-красном. Фон плоский.
// use_mask: фигура — маска кукол (DollMask, альфа) — одинаково на тёмном Void и на светлом небе Руин.
// Без маски (headless, нет DollMask) — старый путь: фигура — всё ярче порога (Void) или темнее фона (светлые арены).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform bool use_mask = false;
uniform int mode = 0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float fig;
	if (use_mask) {
		fig = smoothstep(0.35, 0.65, texture(mask_tex, SCREEN_UV).a);
	} else {
		vec3 avg = textureLod(screen_tex, vec2(0.5), 8.0).rgb;
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		float la = dot(avg, vec3(0.299, 0.587, 0.114));
		float thr = la < 0.35 ? max(la * 1.8, 0.08) : la * 0.7;
		fig = la < 0.35 ? smoothstep(thr - 0.02, thr + 0.02, l) : 1.0 - smoothstep(thr - 0.02, thr + 0.02, l);
	}
	vec3 a = mode == 0 ? mix(vec3(1.0), vec3(0.02), fig) : mix(vec3(0.3, 0.02, 0.03), vec3(1.0, 0.97, 0.92), fig);
	COLOR = vec4(mix(c, a, strength), 1.0);
}
