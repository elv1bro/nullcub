// Кинескоп телевизора в гараже меню (scenes/menu/garage_menu.gd): картинка эфира из SubViewport, выпуклость, строки
// развёртки, виньетка, помехи при переключении канала (noise_amt) и схлопывание в полоску при выключении (power: 1 → 0).
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D screen_tex : source_color, filter_linear;
uniform float boost = 1.6;
uniform float noise_amt : hint_range(0.0, 1.0) = 0.0;
uniform float power : hint_range(0.0, 1.0) = 1.0;
uniform float lines = 480.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 c = UV - 0.5;
	vec2 uv = 0.5 + c * (1.0 + 0.07 * dot(c, c));
	// выключение: сначала сжатие по вертикали в полоску, потом полоска гаснет к центру
	float sy = clamp(power * 2.0, 0.004, 1.0);
	float sx = clamp(power * 2.0 + 0.02, 0.0, 1.0) > 0.99 ? 1.0 : clamp(power * 6.0, 0.0, 1.0);
	vec2 q = vec2((uv.x - 0.5) / max(sx, 0.001), (uv.y - 0.5) / sy) + 0.5;
	vec3 col = texture(screen_tex, q).rgb;
	float n = hash(floor(uv * vec2(240.0, 180.0)) + floor(TIME * 30.0));
	col = mix(col, vec3(n) * 1.1, noise_amt);
	float scan = 0.86 + 0.14 * sin(uv.y * lines * 3.14159);
	float vig = smoothstep(0.8, 0.3, length(c * vec2(1.0, 1.15)));
	col *= scan * (0.45 + 0.55 * vig) * boost;
	col *= 0.97 + 0.03 * sin(TIME * 7.0);
	if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) col = vec3(0.0);
	if (power < 0.5) col += vec3(1.0) * smoothstep(0.02, 0.0, abs(uv.y - 0.5)) * smoothstep(0.5 * sx, 0.0, abs(uv.x - 0.5)) * 2.0 * (power * 2.0);
	ALBEDO = col * step(0.001, power);
}
