// Оверлей остальных деталей жертвы в крупном плане: слабый голубой френель-обод — силуэт читается «насквозь». Аддитивно.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

uniform vec3 rim_colour : source_color = vec3(0.45, 0.8, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = rim_colour * (0.02 + fres * 0.4) * intensity;
}
