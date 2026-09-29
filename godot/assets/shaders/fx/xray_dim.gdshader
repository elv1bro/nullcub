// Оверлей атакующего в рентгене крита (HIT_FX.md §12.3): тёмный полупрозрачный слой с тонким холодным ободом — атакующий уходит в тень,
// ударенная деталь жертвы (xray_wood) и её обод (xray_ghost) остаются яркими: видно, чья «кость» ломается.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

uniform vec3 dim_colour : source_color = vec3(0.03, 0.035, 0.05);
uniform vec3 rim_colour : source_color = vec3(0.25, 0.45, 0.7);
uniform float dim_alpha : hint_range(0.0, 1.0) = 0.86;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = mix(dim_colour, rim_colour, fres * 0.45);
	ALPHA = dim_alpha;
}
