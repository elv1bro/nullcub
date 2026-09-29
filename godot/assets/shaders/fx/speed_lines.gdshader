// Радиальные линии скорости вокруг жертвы после ката назад (620–1050 мс): тонкие лучи от центра, без мигания (медленный дрейф).
// v3 (HIT_FX.md §12.3): светлое ядро луча в тёмной обводке — читается и на белом небе Руин.
shader_type canvas_item;

uniform vec2 centre = vec2(960.0, 540.0);
uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float phase = 0.0;
uniform vec3 colour : source_color = vec3(1.0, 0.96, 0.85);
uniform vec3 outline_colour : source_color = vec3(0.05, 0.04, 0.07);

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 d = UV * rect_size - centre;
	float r = length(d) / rect_size.y;
	float ang = atan(d.y, d.x) / 6.2831853 + 0.5;
	float n = 150.0;
	float id = floor(ang * n);
	float f = fract(ang * n);
	float on = step(0.72, hash(id));
	float wdt = 0.18 + hash(id + 3.0) * 0.2;
	float thin = 1.0 - smoothstep(0.0, wdt * 0.6, abs(f - 0.5) * 2.0);
	float halo = 1.0 - smoothstep(wdt * 0.6, wdt * 1.9, abs(f - 0.5) * 2.0);
	halo = max(halo, thin);
	float start = 0.28 + hash(id + 9.0) * 0.25 - phase * 0.15;
	float radial = smoothstep(start, start + 0.12, r);
	vec3 col = mix(outline_colour, colour, thin / max(halo, 1e-3));
	COLOR = vec4(col, amount * on * radial * max(halo * 0.45, thin * 0.6));
}
