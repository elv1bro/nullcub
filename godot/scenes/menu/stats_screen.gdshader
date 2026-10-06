// Экран монитора стены показателей (scenes/menu/garage_stats_wall.gd): кусок общего атласа (uv_rect), лёгкая развёртка,
// виньетка и помехи на смене данных. crt > 0 — выпуклый кинескоп (бочка и сильнее развёртка). Светится сам (unshaded).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float crt = 0.0;
uniform float power : hint_range(0.0, 2.0) = 1.0;
uniform float noise_amt = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - 0.5;
	uv = 0.5 + c * (1.0 + crt * 0.12 * dot(c, c));
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec2 a = uv_rect.xy + uv * uv_rect.zw;
	vec3 col = texture(atlas, a).rgb;
	float scan = 0.92 + 0.08 * sin(uv.y * (420.0 + crt * 200.0) + TIME * 4.0);
	float vig = 1.0 - 0.35 * dot(c, c) * (1.0 + crt);
	float n = hash(floor(uv * vec2(160.0, 90.0)) + floor(TIME * 24.0));
	col = mix(col, vec3(n), noise_amt);
	ALBEDO = col * scan * vig * power * inside;
}
