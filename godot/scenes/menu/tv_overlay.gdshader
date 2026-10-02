// Экранный слой «мы внутри телевизора» (scenes/menu/garage_campaign.gd): поверх готового кадра — строки развёртки, виньетка,
// закруглённый чёрный угол кинескопа, лёгкое расщепление цветов у краёв, дрожание яркости и помехи при переключении канала
// (noise_amt: 1 — сплошной снег, 0 — чисто). Геометрию кадра не искривляем: мышь и кнопки интерфейса должны попадать точно.
// strength — общая сила (в бою ниже, чтобы не мешать игре), power: 1 → 0 — схлопывание в полоску (выключение).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float noise_amt : hint_range(0.0, 1.0) = 0.0;
uniform float power : hint_range(0.0, 1.0) = 1.0;
uniform float lines = 540.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	// расщепление цветов: заметно только к краям
	float split = 0.0009 * strength * dot(c, c) * 4.0;
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(split, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(split, 0.0)).b;
	// помехи
	float n = hash(floor(uv * vec2(320.0, 200.0)) + floor(TIME * 30.0));
	float band = step(0.985, hash(vec2(floor(uv.y * 40.0), floor(TIME * 12.0)))) * noise_amt;
	col = mix(col, vec3(n) * 1.05, clamp(noise_amt + band * 0.4, 0.0, 1.0));
	// развёртка и виньетка
	float scan = 1.0 - 0.10 * strength * (0.5 + 0.5 * sin(uv.y * lines * 3.14159));
	float vig = smoothstep(0.95, 0.35, length(c * vec2(1.0, 1.1)));
	col *= scan * mix(1.0, 0.55 + 0.45 * vig, strength);
	col *= 1.0 - 0.025 * strength * sin(TIME * 7.0);
	// закруглённый угол кинескопа
	vec2 q = abs(c) * 2.0;
	float corner = smoothstep(1.02, 0.995, pow(pow(q.x, 12.0) + pow(q.y, 12.0), 1.0 / 12.0));
	col *= mix(1.0, corner, strength);
	// выключение: схлопывание по вертикали, затем гаснущая полоска
	float sy = clamp(power * 2.0, 0.004, 1.0);
	float inside = step(abs(c.y) * 2.0, sy);
	col *= mix(1.0, inside, step(power, 0.999));
	col += vec3(1.0) * smoothstep(0.02, 0.0, abs(c.y)) * (1.0 - step(0.5, power)) * power * 2.0;
	COLOR = vec4(col * step(0.001, power), 1.0);
}
