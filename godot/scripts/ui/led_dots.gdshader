// Точки светодиодного табло (скин HUD «led», scripts/ui/hud_skin.gd): у текста видны только круглые «диоды» сетки cell
// (пиксели окна), между ними тёмный зазор; слабый остаток base — чтобы ореол свечения не рассыпался в крошку.
shader_type canvas_item;

uniform float cell = 5.0;
uniform float radius = 0.36;
uniform float base = 0.1;

void fragment() {
	vec2 p = fract(FRAGCOORD.xy / cell) - 0.5;
	float m = 1.0 - smoothstep(radius - 0.08, radius + 0.04, length(p));
	COLOR = vec4(COLOR.rgb * (0.8 + 0.35 * m), COLOR.a * max(m, base));
}
