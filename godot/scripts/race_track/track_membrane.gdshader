// Стенка-мембрана трубы «Гонки: трасса» (scripts/race_track/track_membrane.gd): свечение у стенки (UV.y = 0) тает к коридору,
// по стенке бежит рябь; hit (0..1, на экземпляр) — кукла вдавилась, вспышка.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never;

uniform vec4 colour : source_color = vec4(0.45, 0.75, 1.0, 1.0);
uniform float length_m = 4.0;
instance uniform float hit = 0.0;

void fragment() {
	float edge = 1.0 - UV.y;
	float body = pow(edge, 3.0);
	float line = smoothstep(0.9, 1.0, edge);
	float ripple = 0.5 + 0.5 * sin(UV.x * length_m * 2.2 - TIME * 3.0 + UV.y * 4.0);
	float a = body * (0.22 + 0.12 * ripple + 0.6 * hit) + line * (0.5 + 0.5 * hit);
	ALBEDO = colour.rgb * a;
}
