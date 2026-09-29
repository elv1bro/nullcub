// Как parallax_layer_wrap.gdshader, но с прозрачностью (дальние башни: небо вырезано в alpha).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	vec2 t = (UV - uv_rect.xy) / uv_rect.zw;
	t.x = 1.0 - abs(mod(t.x, 2.0) - 1.0);
	t.y = clamp(t.y, 0.001, 0.999);
	vec4 c = texture(tex, t);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
