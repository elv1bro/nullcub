// Энергетическая сетка по стенам тренировочного зала (scenes/arena/training_hall.gd; автор 02.10: «сетку, чтобы была энергетическая,
// по краям, как будто на стенах комнаты»). Светящиеся линии клеток на прозрачной панели: плавная волна по диагонали, подсветка
// ближе к бойцу (focus_x — мировая X ближайшего бойца), мерцание, затухание к «открытому» краю панели. Рисуется добавлением света.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.25, 0.62, 1.0, 1.0);
uniform vec2 cells = vec2(14.0, 8.0);         // клеток по UV (u, v)
uniform float line_w : hint_range(0.005, 0.5) = 0.08;
uniform float glow : hint_range(0.0, 6.0) = 1.7;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.06;   // слабая «плёнка» между линиями
uniform float wave_speed = 0.45;
uniform float focus_x = 0.0;
uniform float focus_amt : hint_range(0.0, 1.0) = 0.0;
uniform float fade_v : hint_range(0.0, 1.0) = 0.0;      // 0 — без затухания; >0 — затухание у края v = 0 (низ) на эту долю
uniform float fade_top : hint_range(0.0, 1.0) = 0.0;    // то же у края v = 1 (верх)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = UV * cells;
	vec2 f = fract(g);
	vec2 d = min(f, 1.0 - f);                       // расстояние до линии в клетках
	vec2 aa = fwidth(g) * 1.3;                      // сглаживание: линия не рассыпается в штрихи вдали
	vec2 l = 1.0 - smoothstep(vec2(line_w * 0.5), vec2(line_w * 0.5) + aa, d);
	float far = clamp(1.0 - max(aa.x, aa.y) * 0.8, 0.25, 1.0);   // вдали линии тусклее, а не мерцают
	float lines = max(l.x, l.y) * far;
	float wave = 0.5 + 0.5 * sin((UV.x * cells.x * 0.5 + UV.y * cells.y * 0.35) - TIME * wave_speed * 6.28318);
	float spot = exp(-pow((wpos.x - focus_x) * 0.28, 2.0)) * focus_amt;
	float flick = 0.94 + 0.06 * sin(TIME * 23.0 + wpos.x * 3.1 + wpos.y * 1.7);
	float fade = 1.0;
	if (fade_v > 0.0) fade *= smoothstep(0.0, fade_v, UV.y);
	if (fade_top > 0.0) fade *= smoothstep(0.0, fade_top, 1.0 - UV.y);
	float k = lines * (0.5 + 0.5 * wave + 1.6 * spot) + base_alpha * (0.6 + 0.4 * wave) + spot * 0.12;
	ALBEDO = color.rgb * glow * flick * k * fade;
	ALPHA = clamp(k * fade, 0.0, 1.0);
}
