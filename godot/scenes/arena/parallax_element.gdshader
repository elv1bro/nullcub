// Элемент параллакса (ParallaxScatter3D): квад с PNG из parallax_elements_cut.py, без света и тени.
// Воздушная перспектива — смешивание с цветом дымки по глубине (haze), зеркало по x (flip), растворение основания
// в прозрачность (base_fade — доля высоты снизу; элемент «уходит в туман», а не обрывается кромкой листа).
// depth_prepass_alpha: плотные части пишут глубину — перекрывающиеся элементы разной глубины не путаются местами.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_prepass_alpha, fog_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 haze_color : source_color = vec4(0.62, 0.54, 0.68, 1.0);
instance uniform float haze = 0.0;
instance uniform float flip = 0.0;
instance uniform float base_fade = 0.0;

void fragment() {
	vec2 uv = vec2(flip > 0.5 ? 1.0 - UV.x : UV.x, UV.y);
	vec4 c = texture(tex, uv);
	ALBEDO = mix(c.rgb, haze_color.rgb, haze);
	float a = c.a;
	if (base_fade > 0.0) {
		a *= smoothstep(0.0, base_fade, 1.0 - UV.y);
	}
	ALPHA = a;
}
