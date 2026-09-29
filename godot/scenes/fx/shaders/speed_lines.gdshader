// Линии скорости (HIT_FX.md §2.2, §11.3, ScreenFx.speed_lines): v2 — радиально от жертвы (centre — её ЦМ на экране), штрихи бегут
// наружу; гуще и ярче позади полёта (против dir), вокруг цели чисто (clear_radius), к краям ярче. Без мигания: альфа плавная.
// v3 (§12.3): светлое ядро штриха в тёмной обводке (outline_colour) — линии читаются и на белом небе Руин.
shader_type canvas_item;

uniform vec2 centre = vec2(0.5, 0.5);
uniform vec2 dir = vec2(1.0, 0.0);
uniform float alpha = 0.3;
uniform float t = 0.0;
uniform float aspect = 1.7778;
uniform float clear_radius = 0.24;
uniform float lanes = 110.0;
uniform float back_bias = 0.65;      // 0 — равномерно по кругу, 1 — только позади полёта
uniform vec3 outline_colour : source_color = vec3(0.06, 0.05, 0.08);
uniform float outline_alpha = 0.75;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - centre) * vec2(aspect, 1.0);
	float r = length(p);
	vec2 u = p / max(r, 1e-4);
	float a = (atan(u.y, u.x) / 6.2831853 + 0.5) * lanes;
	float lane = floor(a);
	float h = hash(lane + 3.0);
	float on = step(0.8, h);
	float lat = abs(fract(a) - 0.5);
	float thin = 1.0 - smoothstep(0.04, 0.16, lat);
	float halo = 1.0 - smoothstep(0.14, 0.34, lat);
	float ph = fract(r * (0.9 + h) - t * (1.6 + 2.2 * h) + h * 9.0);
	float streak = smoothstep(0.0, 0.05, ph) * (1.0 - smoothstep(0.22, 0.45, ph));
	float mask = smoothstep(clear_radius, clear_radius + 0.5, r);
	vec2 d = normalize(dir + vec2(1e-5, 0.0));
	float back = smoothstep(-0.35, 0.85, dot(u, -d));
	float bias = mix(1.0, back, back_bias);
	float k = alpha * on * streak * mask * bias;
	vec3 col = mix(outline_colour, vec3(1.0, 0.98, 0.94), thin / max(halo, 1e-3));
	COLOR = vec4(col, k * max(halo * outline_alpha, thin));
}
