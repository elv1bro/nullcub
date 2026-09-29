// Панель страницы комикса (Polygon2D с кадром IntroStage): печать поверх 3D-рендера.
//   цвет     — контраст, насыщенность, раздельное тонирование (тени лиловые, света тёплые), виньетка
//   растр    — точки в тенях по сетке 45°, размер клетки в пикселях СТРАНИЦЫ (при наезде точки растут, как на бумаге)
//   бумага   — зерно
//   проявка  — reveal 0..1: чернильная кромка по диагонали с рваным краем; flash — вспышка удара (белым)
shader_type canvas_item;

uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float reveal_slope = 0.45;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform vec2 art_px = vec2(1000.0, 700.0);   // размер панели в пикселях страницы
uniform float halftone : hint_range(0.0, 1.0) = 0.42;
uniform float dot_px = 9.0;
uniform float dot_lo = 0.05;
uniform float dot_hi = 0.42;
uniform vec3 ink : source_color = vec3(0.11, 0.06, 0.07);
uniform float contrast = 1.08;
uniform float saturation = 1.14;
uniform vec3 shadow_tint : source_color = vec3(0.36, 0.30, 0.52);
uniform vec3 light_tint : source_color = vec3(1.0, 0.86, 0.66);
uniform float split = 0.12;
uniform float vignette = 0.32;
uniform float grain = 0.035;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.1) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	vec3 c = texture(TEXTURE, uv).rgb;
	// тон: контраст вокруг середины, насыщенность
	c = clamp((c - 0.5) * contrast + 0.5, 0.0, 1.0);
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, saturation);
	// раздельное тонирование
	c = mix(c, c * shadow_tint * 1.6, split * (1.0 - smoothstep(0.0, 0.5, l)));
	c = mix(c, c * light_tint * 1.1, split * smoothstep(0.45, 1.0, l));
	// растр в тенях: клетка 45°, радиус точки растёт с темнотой
	vec2 p = uv * art_px / dot_px;
	mat2 rot = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071));
	vec2 q = rot * p;
	vec2 cell = fract(q) - 0.5;
	float dark = 1.0 - smoothstep(dot_lo, dot_hi, l);
	float r = sqrt(dark) * 0.55;
	float d = length(cell);
	float aa = fwidth(d) * 1.2;
	float dotm = 1.0 - smoothstep(r - aa, r + aa, d);
	c = mix(c, c * ink * 2.2, dotm * halftone * dark);
	// виньетка и зерно бумаги
	vec2 v = uv - 0.5;
	c *= 1.0 - vignette * smoothstep(0.35, 0.85, length(v * vec2(1.0, art_px.x / art_px.y * 0.8)));
	c += (hash(uv * art_px) - 0.5) * grain;
	// вспышка удара
	c = mix(c, flash_color.rgb, flash);
	// проявка: рваная диагональная кромка слева-направо
	float edge = (uv.x + (1.0 - uv.y) * reveal_slope) / (1.0 + reveal_slope);
	float jag = (vnoise(uv * art_px / 22.0) - 0.5) * 0.06 + (vnoise(uv * art_px / 5.0) - 0.5) * 0.015;
	float front = reveal * 1.12 - 0.06;
	float a = smoothstep(front + 0.004, front - 0.004, edge + jag);
	// тонкая тёплая кромка на фронте проявки
	float rim = smoothstep(0.02, 0.0, abs(edge + jag - front)) * step(0.001, reveal) * step(reveal, 0.999);
	c = mix(c, vec3(1.0, 0.82, 0.5), rim * 0.8);
	COLOR = vec4(c, max(a, rim));
}
