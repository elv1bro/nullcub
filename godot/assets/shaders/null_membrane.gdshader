// Мембрана поля NULL (scenes/arena/null_field.gd, docs/plan-demo/ART_NULL.md): прозрачная энергетическая лента по контуру
// купола. Меш — полоса-полуокружность радиуса 1 (Membrane_Strip.glb), узел растянут до полуосей эллипса и глубины ленты.
// Почти невидима («видна только вблизи», лист камеры, правило 5): светится у точек hits и прогибается наружу на их растяжение.
// hits[i] = (x, y — точка на мембране в мире, z — растяжение, м; w — яркость 0..1).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec2 centre = vec2(0.0, 0.0);
uniform vec2 axes = vec2(16.0, 19.0);
uniform vec4 hits[4];
uniform float sigma = 2.4;                 // ширина вмятины вдоль мембраны, м
uniform vec3 colour : source_color = vec3(0.35, 0.68, 1.0);
uniform float idle = 0.015;                // едва заметное мерцание контура без бойцов рядом
uniform float cells_along = 70.0;          // ячейки «паутины» вдоль дуги
uniform float cells_across = 5.0;          // и поперёк ленты

varying vec3 wpos;
varying float heat;
varying float stretch;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = w.xy - centre;
	vec2 n = normalize(vec2(p.x / (axes.x * axes.x), p.y / (axes.y * axes.y)) + vec2(0.0, 1e-5));
	float push = 0.0;
	float h = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 d = w.xy - hits[i].xy;
		float r2 = dot(d, d);
		push += hits[i].z * exp(-r2 / (sigma * sigma));
		h = max(h, hits[i].w * exp(-r2 / (sigma * sigma * 3.0)));
	}
	// растяжение — наружу; ближе к краям ленты (по глубине) прогиб меньше: ткань держат якоря
	float across = 1.0 - pow(abs(UV.y - 0.5) * 2.0, 2.0);
	w.xy += n * push * (0.55 + 0.45 * across);
	heat = h;
	stretch = push;
	wpos = w;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
}

float web(vec2 uv) {
	// треугольная сетка: три семейства линий
	float a = abs(fract(uv.x + uv.y * 0.5) - 0.5);
	float b = abs(fract(uv.x - uv.y * 0.5) - 0.5);
	float c = abs(fract(uv.y) - 0.5);
	float m = min(min(a, b), c);
	return 1.0 - smoothstep(0.0, 0.07, m);
}

void fragment() {
	vec2 uv = vec2(UV.x * cells_along, UV.y * cells_across);
	float lines = web(uv + vec2(TIME * 0.05, 0.0));
	float spark = 0.5 + 0.5 * sin(TIME * 9.0 + wpos.x * 1.7 - wpos.y * 1.1);
	float edge = 1.0 - pow(abs(UV.y - 0.5) * 2.0, 3.0);   // к краям ленты гаснет
	float glow = heat * (0.18 + 0.82 * lines) * (0.7 + 0.3 * spark);
	glow += clamp(stretch * 0.25, 0.0, 0.6) * lines;      // растянутая ткань ярче
	glow += idle * (0.3 + 0.7 * lines);
	ALBEDO = colour * (1.0 + heat * 0.8) * glow * edge * 2.2;
}
