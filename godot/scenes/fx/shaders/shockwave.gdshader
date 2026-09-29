// Ударная волна (HIT_FX.md §2.2): кольцо на кваде 2×2 лицом к камере; радиус — масштаб узла (Shockwave).
// Кольцо светится цветом удара и чуть искажает экран под собой (screen texture). arc_dir ≠ 0 — полукольцо
// в сторону нормали (удар о стену).
// v3 (HIT_FX.md §12.3): по обе стороны кольца — тёмная кайма (edge_dark): на белом небе Руин кольцо читается контуром.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 colour : source_color = vec4(1.0, 1.0, 1.0, 0.8);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float thickness = 0.16;
uniform vec2 arc_dir = vec2(0.0, 0.0);
uniform float distort = 0.012;
uniform vec3 edge_colour : source_color = vec3(0.04, 0.03, 0.06);
uniform float edge_dark = 0.6;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float r = length(p);
	float th = thickness * (1.0 - 0.5 * progress);
	float centre_r = 1.0 - th * 1.7;   // v3: снаружи место под тёмную кайму
	float ring = 1.0 - smoothstep(0.0, th, abs(r - centre_r));
	float rim = (1.0 - smoothstep(th * 0.9, th * 1.7, abs(r - centre_r))) * (1.0 - ring);
	float mask = 1.0;
	if (length(arc_dir) > 0.01) {
		mask = smoothstep(-0.25, 0.25, dot(p / max(r, 1e-4), normalize(arc_dir)));
	}
	float fade = 1.0 - progress;
	float a = ring * mask * fade;
	vec2 push = (p / max(r, 1e-4)) * vec2(1.0, -1.0) * distort * a;
	vec3 scr = textureLod(screen_tex, SCREEN_UV - push, 0.0).rgb;
	float ad = rim * mask * fade * edge_dark * colour.a;
	vec3 bright = scr + colour.rgb * a * colour.a * 0.9;
	ALBEDO = mix(bright, edge_colour, clamp(ad / max(ad + a * 1.5, 1e-3), 0.0, 1.0));
	ALPHA = clamp(max(a * 1.5, ad), 0.0, 1.0);
}
