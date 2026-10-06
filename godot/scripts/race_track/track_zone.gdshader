// Поле гравитации «Гонки: трасса» (scripts/race_track/track_zone.gd): сетка и бегущие шевроны по направлению поля. dir — «низ» поля
// в плоскости квада, size_m — размер квада (м), speed — скорость шевронов (м/с), strength — 0..1 по силе поля.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never;

uniform vec4 colour : source_color = vec4(0.35, 0.6, 1.0, 1.0);
uniform vec2 dir = vec2(0.0, -1.0);
uniform vec2 size_m = vec2(10.0, 10.0);
uniform float speed = 1.5;
uniform float strength = 0.6;

void fragment() {
	vec2 p = vec2(UV.x, 1.0 - UV.y) * size_m;
	vec2 d = normalize(dir);
	vec2 s = vec2(-d.y, d.x);
	float along = dot(p, d) - TIME * speed;
	float side = dot(p, s);
	// шеврон: «галочка» остриём по полю, шаг 1.6 м вдоль, 2.4 м поперёк
	float cell = fract(side / 2.4) - 0.5;
	float v = fract((along + abs(cell) * 1.4) / 1.6);
	float chev = smoothstep(0.0, 0.08, v) * (1.0 - smoothstep(0.18, 0.3, v));
	vec2 g = abs(fract(p / 1.0) - 0.5);
	float grid = 1.0 - smoothstep(0.0, 0.03, min(g.x, g.y));
	vec2 e = min(UV, 1.0 - UV) * size_m;
	float edge = 1.0 - smoothstep(0.0, 0.25, min(e.x, e.y));
	float a = (0.05 * grid + 0.28 * chev) * strength + 0.45 * edge;
	ALBEDO = colour.rgb * a;
}
