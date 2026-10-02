// Луч света из окна для рендереров без объёмного тумана (Mobile / Compatibility): плоский квад вдоль направления солнца, аддитивный,
// мягкие края, затухание к дальнему концу и медленно плывущая «пыль». Забирает на себя только роль луча Forward+ (volumetric fog);
// стоит один прозрачный квад. UV.x — вдоль луча (0 у окна), UV.y — поперёк.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.82, 0.55);
uniform float intensity : hint_range(0.0, 2.0) = 0.3;
uniform float edge : hint_range(0.02, 0.5) = 0.2;
uniform float drift = 0.04;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float across = smoothstep(0.0, edge, UV.y) * smoothstep(1.0, 1.0 - edge, UV.y);
	float along = smoothstep(0.0, 0.06, UV.x) * pow(1.0 - UV.x, 0.9);
	float dust = vnoise(vec2(UV.x * 7.0 - TIME * drift * 6.0, UV.y * 3.0)) * 0.6 + vnoise(vec2(UV.x * 17.0 + TIME * drift * 4.0, UV.y * 6.0)) * 0.4;
	ALBEDO = tint * intensity;
	ALPHA = clamp(across * along * (0.55 + 0.9 * dust), 0.0, 1.0);
}
