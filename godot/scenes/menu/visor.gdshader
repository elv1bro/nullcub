// Визор нейрошлема (scenes/menu/garage_headset.gd): окно очков закрывает и открывает кадр, когда герой надевает / снимает шлем.
// open 1.0 — кадр открыт целиком (окна не видно), 0 — окно сжалось в ноль (кадр чёрный). Края окна — скруглённый «суперэллипс»
// с голубым ободом подсветки; внутри — лёгкая развёртка (только пока окно не открыто полностью). black — поверх всего чернота
// (загрузка связи).
shader_type canvas_item;

uniform float open : hint_range(0.0, 1.6) = 1.6;
uniform float black : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rim_color : source_color = vec4(0.3, 0.88, 1.0, 1.0);
uniform float aspect = 1.7778;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	// окно — два слитых «стекла»: суперэллипс шире по X, с перемычкой-носом внизу посередине
	vec2 half_size = vec2(0.95 * aspect * 0.5, 0.62) * max(open, 0.0001);
	vec2 q = abs(p) / half_size;
	float d = pow(pow(q.x, 4.0) + pow(q.y, 4.0), 0.25);
	float nose = smoothstep(0.16, 0.0, abs(p.x)) * smoothstep(-0.05, -0.62 * open, p.y) * 0.35;
	d += nose;
	float edge = fwidth(d) * 1.5 + 0.004;
	float outside = smoothstep(1.0 - edge, 1.0 + edge, d);
	float rim = exp(-abs(d - 1.0) * 26.0) * (1.0 - smoothstep(1.2, 1.55, open));
	float inner = (1.0 - outside) * (1.0 - smoothstep(1.0, 1.5, open));
	float scan = inner * 0.08 * (0.5 + 0.5 * sin(UV.y * 900.0 + TIME * 30.0));
	vec3 col = rim_color.rgb * rim * 0.9;
	float a = clamp(outside + rim * 0.7 + scan + black, 0.0, 1.0);
	COLOR = vec4(mix(col, vec3(0.0), clamp(outside + black, 0.0, 1.0)), a);
}
