// Следы ударов на детали куклы (docs/plan-demo/HIT_FX.md §13): material_overlay мешей ударенной детали (HitMarks).
// След — объёмный: всё, что поверхности детали ближе радиуса к точке удара (координаты меша), поэтому он ложится по форме детали без
// декалей (Decal в Forward+ мерцает плитками — PERF_AUDIT.md) и виден с камеры, даже если удар пришёл сбоку.
// В центре — скол (материал под поверхностью: светлое дерево под краской, свежий металл под ржавчиной), вокруг — тёмная кромка,
// от него — трещины по границам ячеек Вороного, тоньше к краю. Глубина power растёт с силой и повторными ударами в то же место.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

const int MAX_MARKS = 8;

uniform vec4 marks[8];        // xyz — центр в координатах меша, w — радиус (в тех же единицах)
uniform float power[8];       // 0.3…1.5 — глубина следа
uniform int count = 0;
uniform vec3 chip_colour : source_color = vec3(0.96, 0.84, 0.62);
uniform vec3 crack_colour : source_color = vec3(0.16, 0.09, 0.04);
uniform float chip_metal = 0.0;
uniform float chip_rough = 0.85;

varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash3(i).x;
	float b = hash3(i + vec3(1.0, 0.0, 0.0)).x;
	float c = hash3(i + vec3(0.0, 1.0, 0.0)).x;
	float d = hash3(i + vec3(1.0, 1.0, 0.0)).x;
	float e = hash3(i + vec3(0.0, 0.0, 1.0)).x;
	float g = hash3(i + vec3(1.0, 0.0, 1.0)).x;
	float h = hash3(i + vec3(0.0, 1.0, 1.0)).x;
	float k = hash3(i + vec3(1.0, 1.0, 1.0)).x;
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

// F2 − F1 ячеек Вороного: около нуля — граница ячеек (линия трещины)
float cell_edge(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = hash3(i + g);
				float d = length(g + o - f);
				if (d < f1) {
					f2 = f1;
					f1 = d;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}
	return f2 - f1;
}

void fragment() {
	float chip = 0.0;
	float rim = 0.0;
	float crack = 0.0;
	for (int i = 0; i < MAX_MARKS; i++) {
		if (i >= count) {
			break;
		}
		vec4 m = marks[i];
		if (m.w <= 0.0) {
			continue;
		}
		float q = length(obj - m.xyz) / m.w;   // 0 — центр, 1 — радиус
		if (q > 1.3) {
			continue;
		}
		float pw = power[i];
		vec3 sp = (obj - m.xyz) / m.w;
		float n = vnoise(sp * 3.1 + vec3(float(i) * 5.3));
		float qn = q + (n - 0.5) * 0.4;
		// скол: неровное пятно в центре, растёт с глубиной
		float rc = 0.18 + 0.26 * clamp(pw, 0.0, 1.5);
		float blob = 1.0 - smoothstep(rc - 0.05, rc + 0.02, qn);
		chip = max(chip, blob);
		rim = max(rim, (1.0 - smoothstep(rc + 0.02, rc + 0.12, qn)) * (1.0 - blob));
		// трещины: границы ячеек в масштабе радиуса, тоньше к краю; длина растёт с глубиной
		float e = cell_edge(sp * 2.6 + vec3(float(i) * 7.1));
		float reach = 0.55 + 0.45 * clamp(pw, 0.0, 1.5);
		float fade = 1.0 - smoothstep(reach * 0.55, reach, q);
		float width = 0.1 * fade + 0.012;
		crack = max(crack, (1.0 - smoothstep(width * 0.45, width, e)) * fade * step(rc * 0.8, qn));
	}
	float a = max(max(chip, crack * 0.95), rim * 0.8);
	if (a < 0.02) {
		discard;
	}
	// волокно в сколе: полосы вдоль оси Y меша (детали кита и манекена вытянуты по Y) — скол читается как дерево, а не пятно краски
	float grain = vnoise(obj * vec3(140.0, 9.0, 140.0));
	vec3 chip_col = chip_colour * mix(0.78, 1.08, grain);
	vec3 col = mix(chip_col, crack_colour, clamp(max(crack, rim) * (1.0 - chip), 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = mix(chip_rough, 1.0, crack);
	METALLIC = chip_metal * chip;
}
