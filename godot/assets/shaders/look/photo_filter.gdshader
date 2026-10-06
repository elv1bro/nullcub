// Фильтры фоторежима (scripts/look/photo_mode.gd): 1 — тёплый, 2 — холодный, 3 — ч/б «плакат» (контраст, ступени тона, зерно,
// бумага). 0 («как есть») — прямоугольник с этим шейдером спрятан. Читает экран под собой: на слое фоторежима всё, что ниже, —
// только 3D-кадр (HUD спрятан).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform int mode = 0;
uniform float grain_seed = 0.0;
uniform float vignette = 0.55;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	vec2 d = SCREEN_UV - 0.5;
	d.x *= 1.3;
	float vig = clamp(1.0 - dot(d, d) * 1.6, 0.0, 1.0);
	if (mode == 1) {
		// тёплый: янтарь зала в светах, мягкий подъём теней, чуть насыщеннее
		c = c * vec3(1.09, 1.0, 0.84) + vec3(0.025, 0.012, -0.012);
		float l = luma(c);
		c = mix(vec3(l), c, 1.12);
		c = (c - 0.5) * 1.05 + 0.5;
		c *= mix(1.0, vig, vignette * 0.7);
	} else if (mode == 2) {
		// холодный: голубое поле NULL — тени в бирюзу, света в холодный белый, чуть меньше цвета
		float l = luma(c);
		c = c * vec3(0.86, 0.99, 1.12) + vec3(-0.01, 0.04, 0.08) * (1.0 - l);
		c = mix(vec3(luma(c)), c, 0.85);
		c = (c - 0.5) * 1.08 + 0.5;
		c *= mix(1.0, vig, vignette * 0.7);
	} else if (mode == 3) {
		// ч/б плакат: крутая S-кривая, ступени тона, зерно, тёплая бумага
		float l = luma(c);
		l = smoothstep(0.06, 0.8, l);
		l = l * l * (3.0 - 2.0 * l);
		float lp = floor(l * 5.0 + 0.5) / 5.0;
		l = mix(l, lp, 0.25);
		l += (hash(floor(FRAGCOORD.xy) + grain_seed) - 0.5) * 0.07;
		l *= mix(1.0, vig, vignette);
		c = vec3(l) * vec3(1.0, 0.975, 0.93);
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
