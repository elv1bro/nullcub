// Лист чертежа на стене мастерской (scenes/workshop/decor/workshop_decor.tscn): синяя калька, сетка, контур сустава и рычага,
// размерные линии, штамп. Рисуется процедурно (без новой растровой графики) и освещается как обычная бумага — в полутени фона
// читается как пыльный синий лист, не спорит с куклой. «Приглушённый голубой» — механический акцент палитры, не свечение.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 paper_color : source_color = vec3(0.15, 0.23, 0.33);
uniform vec3 line_color : source_color = vec3(0.52, 0.65, 0.78);
uniform float line_alpha : hint_range(0.0, 1.0) = 0.6;
uniform vec2 sheet_size = vec2(0.46, 0.34);   // метры: толщина линий задаётся в метрах, не в долях листа

float line_at(float d, float w) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + 0.0008, abs(d));
}

float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return line_at(length(pa - ba * h), w);
}

float ring(vec2 p, vec2 c, float r, float w) {
	return line_at(length(p - c) - r, w);
}

void fragment() {
	vec2 p = UV * sheet_size;                      // координаты листа в метрах, (0,0) — левый верх
	float ink = 0.0;
	// сетка: тонкая каждые 2 см, чуть плотнее каждые 10 см
	vec2 g = abs(fract(p / 0.02 + 0.5) - 0.5) * 0.02;
	ink = max(ink, 0.18 * line_at(min(g.x, g.y), 0.0006));
	vec2 G = abs(fract(p / 0.1 + 0.5) - 0.5) * 0.1;
	ink = max(ink, 0.32 * line_at(min(G.x, G.y), 0.0008));
	// рамка
	vec2 q = min(p, sheet_size - p);
	ink = max(ink, line_at(min(q.x, q.y) - 0.012, 0.0014));
	// узел: сустав (две окружности и ось), рычаг к нему, второй сустав поменьше
	vec2 j1 = vec2(0.13, 0.15);
	vec2 j2 = vec2(0.31, 0.21);
	ink = max(ink, ring(p, j1, 0.045, 0.0016));
	ink = max(ink, ring(p, j1, 0.018, 0.0012));
	ink = max(ink, ring(p, j2, 0.028, 0.0014));
	ink = max(ink, ring(p, j2, 0.010, 0.0010));
	vec2 dir = normalize(j2 - j1);
	vec2 nrm = vec2(-dir.y, dir.x);
	ink = max(ink, seg(p, j1 + dir * 0.045 + nrm * 0.022, j2 - dir * 0.028 + nrm * 0.014, 0.0014));
	ink = max(ink, seg(p, j1 + dir * 0.045 - nrm * 0.022, j2 - dir * 0.028 - nrm * 0.014, 0.0014));
	// осевые линии (пунктир)
	float dash = step(0.5, fract(dot(p - j1, dir) / 0.012));
	ink = max(ink, 0.6 * dash * seg(p, j1 - dir * 0.07, j2 + dir * 0.05, 0.0008));
	// размерная линия под узлом с засечками
	vec2 d0 = vec2(j1.x, 0.265);
	vec2 d1 = vec2(j2.x, 0.265);
	ink = max(ink, 0.8 * seg(p, d0, d1, 0.0009));
	ink = max(ink, 0.8 * seg(p, d0 - vec2(0.0, 0.008), d0 + vec2(0.0, 0.008), 0.0009));
	ink = max(ink, 0.8 * seg(p, d1 - vec2(0.0, 0.008), d1 + vec2(0.0, 0.008), 0.0009));
	// штамп в правом нижнем углу
	vec2 s0 = sheet_size - vec2(0.14, 0.06);
	vec2 s1 = sheet_size - vec2(0.012, 0.012);
	vec2 sc = clamp(p, s0, s1);
	float inside = step(length(p - sc), 0.0);
	ink = max(ink, line_at(length(p - sc), 0.0012) * (1.0 - inside));
	ink = max(ink, 0.7 * seg(p, vec2(s0.x, s0.y + 0.024), vec2(s1.x, s0.y + 0.024), 0.0008));
	ink = max(ink, 0.7 * seg(p, vec2(s0.x + 0.05, s0.y + 0.024), vec2(s0.x + 0.05, s1.y), 0.0008));
	// бумага: сгиб посередине и потёртые края
	float fold = 1.0 - 0.08 * line_at(p.x - sheet_size.x * 0.5, 0.004);
	float edge = smoothstep(0.0, 0.03, min(q.x, q.y));
	vec3 col = mix(paper_color * (0.8 + 0.2 * edge), line_color, ink * line_alpha) * fold;
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
