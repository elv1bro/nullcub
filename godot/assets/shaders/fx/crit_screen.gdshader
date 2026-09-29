// Полноэкранный слой CritOverlay/CutFlash: кадры удара (invert 1 — чёрные силуэты на белом, 2 — белые на тёмно-красном),
// белый кадр (flash) и белая кромка-виньетка (edge). Всё множится на flash_intensity в скрипте.
// use_mask (HIT_FX.md §11.4): силуэты — маска кукол DollMask (альфа), фон плоский на любой арене; без маски — порог яркости.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform bool use_mask = false;
uniform float invert = 0.0;
uniform float flash = 0.0;
uniform float edge = 0.0;

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(src, vec3(0.299, 0.587, 0.114));
	float fig = use_mask ? smoothstep(0.35, 0.65, texture(mask_tex, SCREEN_UV).a) : smoothstep(0.02, 0.12, lum);
	vec3 col = src;
	float a = 0.0;
	if (invert > 0.5 && invert < 1.5) {
		col = vec3(1.0 - fig);
		a = 1.0;
	} else if (invert >= 1.5) {
		col = mix(vec3(0.25, 0.0, 0.02), vec3(1.0), fig);
		a = 1.0;
	}
	vec2 q = UV - 0.5;
	float v = smoothstep(0.42, 0.78, length(q * vec2(1.2, 1.0)));
	col = mix(col, vec3(1.0), clamp(flash + edge * v, 0.0, 1.0));
	a = max(a, clamp(flash + edge * v, 0.0, 1.0));
	COLOR = vec4(col, a);
}
