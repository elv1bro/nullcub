// Сплошной слой параллакса (небо), бесшовно продолженный за края своей картинки без лишней памяти: по x — зеркальный
// повтор (на сгибе шва нет), по y — крайние строки (сверху ровный зенит, снизу дымка горизонта). uv_rect — где в UV
// квада лежит одна копия текстуры (x0, y0, w, h). Нужен для камер вне игрового диапазона (заставка смотрит вверх
// и вбок): раньше там были видны края квада. Вариант с прозрачностью — parallax_layer_wrap_alpha.gdshader.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	vec2 t = (UV - uv_rect.xy) / uv_rect.zw;
	t.x = 1.0 - abs(mod(t.x, 2.0) - 1.0);
	t.y = clamp(t.y, 0.001, 0.999);
	ALBEDO = texture(tex, t).rgb;
}
