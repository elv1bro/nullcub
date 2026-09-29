// Послеобраз удара (HIT_FX.md §2.2, AfterimageTrail): аддитивный силуэт цвета игрока, ярче по краю (френель).
// Затухание — GeometryInstance3D.transparency инстанса (материал общий на цвет).
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 colour : source_color = vec4(1.0, 1.0, 1.0, 0.35);
uniform float rim_power = 2.2;
uniform float base = 0.3;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = colour.rgb;
	ALPHA = colour.a * (base + (1.0 - base) * rim);
}
