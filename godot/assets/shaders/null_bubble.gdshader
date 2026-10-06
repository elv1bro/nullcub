// Мембрана-пузырь поля NULL (scripts/look/null_look.gd, docs/plan-demo/look/null.md): полуэллипсоид над полом (полуоси axes: ширина,
// высота, глубина), две половины — задняя (за плоскостью боя) и передняя. Только вид, механика мембраны — scenes/arena/null_field.gd.
//   задняя половина: преломление фона через плёнку (screen texture; пиксели того, что ближе плёнки, не берутся — проверка по глубине),
//                     радужная плёнка, радужный френелевый край, светящийся шов по полу;
//   передняя: только добавляет свет — край, сетка у бойца и кольца волн; бойцов не искажает.
// Сетка (треугольная) видна только у бойца рядом с мембраной (hits из NullField, как у старой ленты), на кольцах волн от ударов (waves)
// и на фронте смены поля (shift). Прогиб к точкам hits — как в null_membrane.gdshader (растяжение наружу по нормали эллипса).
shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform bool back_half = true;
uniform vec3 axes = vec3(16.0, 19.0, 4.0);
uniform vec2 centre = vec2(0.0, 0.0);
uniform vec4 hits[4];                    // x, y — точка мембраны, z — растяжение, м, w — яркость 0..1
uniform vec4 waves[4];                   // xyz — центр волны удара, w — возраст, с (< 0 — нет)
uniform vec4 wave_power = vec4(0.0);
uniform float wave_speed = 9.0;
uniform vec4 shift = vec4(0.0, -1.0, 0.0, 0.0);   // xy — направление нового поля, z — фронт вдоль него, м, w — сила 0..1
uniform float shift_w = 1.5;             // м: полуширина фронта
uniform float sigma = 2.4;
uniform float heat_r = 1.7;              // м: радиус свечения сетки у точки hits
uniform vec3 colour : source_color = vec3(0.35, 0.68, 1.0);
uniform float refract_rim = 0.012;      // сдвиг UV экрана у края купола
uniform float refract_base = 0.0;       // «дыхание» поля по всей задней стенке (0 — выкл: середина стенки не читает экран)
uniform float refract_wave = 0.01;      // сдвиг на кольце волны
uniform float film = 0.03;              // радужная плёнка задней стенки (в середине — четверть, к кромке — вся)
uniform float rim = 0.3;                // яркость радужного края
uniform vec2 rim_band = vec2(0.93, 1.0);  // кромка по контуру купола на плоскости боя (доли полуосей): от и до
uniform float floor_glow = 0.8;         // шов купола по полу
uniform float floor_y = 0.01;           // м: верх плит пола над центром эллипса (плиты купола — на y = 0, полосы — 0.06)
uniform float cell = 0.75;               // шаг сетки, м
uniform float grid_gain = 1.1;

varying vec3 wpos;
varying vec3 wnrm;
varying float heat;
varying float stretch;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 p = w - vec3(centre, 0.0);
	vec3 g = vec3(p.x / (axes.x * axes.x), p.y / (axes.y * axes.y), p.z / (axes.z * axes.z));
	wnrm = normalize(g + vec3(0.0, 1e-7, 0.0));
	vec2 n2 = normalize(g.xy + vec2(0.0, 1e-6));
	float push = 0.0;
	float h = 0.0;
	for (int i = 0; i < 4; i++) {
		// точка hits — на контуре в плоскости боя (z = 0): расстояние по объёму, иначе прогиб и свечение легли бы на всю
		// переднюю и заднюю стенку купола напротив точки
		vec3 d = vec3(w.xy - hits[i].xy, w.z);
		float r2 = dot(d, d);
		push += hits[i].z * exp(-r2 / (sigma * sigma));
		h = max(h, hits[i].w * exp(-r2 / (heat_r * heat_r)));
	}
	// у плоскости боя (z = 0) ткань тянется сильнее всего, к переднему и заднему краю купола — меньше
	float zk = 1.0 - clamp(abs(p.z) / axes.z, 0.0, 1.0);
	w.xy += n2 * push * (0.45 + 0.55 * zk);
	heat = h;
	stretch = push;
	wpos = w;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
}

float line_d(float t) {
	return abs(fract(t + 0.5) - 0.5);
}

// треугольная сетка: три семейства линий под 60°, сглажено по fwidth
float web(vec2 p) {
	float t1 = p.y / cell;
	float t2 = dot(p, vec2(0.8660254, 0.5)) / cell;
	float t3 = dot(p, vec2(-0.8660254, 0.5)) / cell;
	float w1 = fwidth(t1) * 1.2 + 0.035;
	float w2 = fwidth(t2) * 1.2 + 0.035;
	float w3 = fwidth(t3) * 1.2 + 0.035;
	float l1 = 1.0 - smoothstep(0.0, w1, line_d(t1));
	float l2 = 1.0 - smoothstep(0.0, w2, line_d(t2));
	float l3 = 1.0 - smoothstep(0.0, w3, line_d(t3));
	return max(max(l1, l2), l3);
}

void fragment() {
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 N = normalize(wnrm);
	float ndv = abs(dot(N, V));
	float fres = pow(1.0 - ndv, 3.0);
	// толщина плёнки — медленные разводы; цвет плёнки зависит и от угла взгляда (радужный край)
	float th = 0.5 + 0.28 * sin(wpos.x * 0.21 + wpos.y * 0.16 + TIME * 0.11)
		+ 0.22 * sin(wpos.x * 0.47 - wpos.y * 0.33 + wpos.z * 0.5 - TIME * 0.08);
	float ph = th * 1.6 + (1.0 - ndv) * 1.4;
	vec3 irid = 0.5 + 0.5 * cos(6.2831853 * (ph + vec3(0.0, 0.33, 0.67)));
	// кольца волн ударов по поверхности купола
	float ring = 0.0;
	float ring_s = 0.0;
	for (int i = 0; i < 4; i++) {
		float a = waves[i].w;
		if (a < 0.0 || wave_power[i] <= 0.0) {
			continue;
		}
		// по плоскости экрана (XY): на куполе — круги от точки удара, а не вспышка всей стенки, к которой сфера волны подошла касательно
		float dist = distance(wpos.xy, waves[i].xy);
		float x = (dist - a * wave_speed) / 0.7;
		float b = exp(-x * x) * wave_power[i] * exp(-a * 1.3);
		ring += b;
		ring_s += b * sin(x * 2.4);
	}
	// фронт смены поля
	float sb = 0.0;
	if (shift.w > 0.0) {
		float s = dot(wpos.xy, normalize(shift.xy + vec2(1e-5))) - shift.z;
		sb = exp(-s * s / (shift_w * shift_w)) * shift.w * 0.6;
	}
	float lines = web(wpos.xy + vec2(wpos.z * 0.45, wpos.z * 0.2));
	// передняя половина висит между камерой и бойцами: кольца и фронт смены на ней — только у кромки
	float front_k = back_half ? 1.0 : smoothstep(0.85, 1.0, length((wpos.xy - centre) / axes.xy));
	ring *= front_k;
	ring_s *= front_k;
	sb *= front_k;
	float lit = clamp(heat * 0.75 + ring * 0.6 + sb, 0.0, 1.5);
	float edge_fade = smoothstep(0.0, 0.5, wpos.y - centre.y + 0.25);
	vec3 add = colour * lines * lit * grid_gain;
	add += colour * (heat * 0.22 + clamp(stretch * 0.15, 0.0, 0.5) * lines + ring * 0.06);
	// кромка: френель плюс полоса у контура купола (вид спереди — край пузыря одной ширины по всей дуге)
	float rho = length((wpos.xy - centre) / axes.xy);
	float edge = max(fres, smoothstep(rim_band.x, rim_band.y, rho) * 0.8);
	add += mix(colour, irid, 0.7) * edge * rim;
	if (back_half) {
		add += irid * film * (0.1 + 0.9 * edge);
	}
	add *= edge_fade;
	// шов по полу: тонкая линия касания (шире нельзя: стенка у пола почти вертикальна, отсвет ложится на весь пол за ней)
	float fy = max(wpos.y - centre.y - floor_y, 0.0);
	float fl = exp(-fy / 0.04);
	add += colour * fl * floor_glow * (0.75 + 0.25 * sin(TIME * 1.1 + wpos.x * 0.35));
	if (back_half) {
		vec3 nv = normalize((VIEW_MATRIX * vec4(N, 0.0)).xyz);
		float breathe = sin(wpos.x * 0.37 + TIME * 0.6) * cos(wpos.y * 0.29 - TIME * 0.45);
		vec2 off = nv.xy * (refract_rim * edge + refract_wave * ring_s + refract_wave * 0.7 * sb)
			+ vec2(breathe, -breathe) * refract_base;
		if (dot(off, off) < 1e-8) {
			// середина стенки без волн: преломлять нечего — только свет, без чтения экрана и глубины (так дешевле)
			ALBEDO = add;
			ALPHA = 0.0;
		} else {
			vec2 uv2 = clamp(SCREEN_UV + off, vec2(0.001), vec2(0.999));
			// то, что ближе плёнки (бойцы, пол перед куполом), в преломление не берём
			float dz = textureLod(depth_tex, uv2, 0.0).r;
			vec4 vp = INV_PROJECTION_MATRIX * vec4(uv2 * 2.0 - 1.0, dz, 1.0);
			float scene_d = -vp.z / vp.w;
			if (scene_d < -VERTEX.z) {
				uv2 = SCREEN_UV;
			}
			vec3 bg = textureLod(screen_tex, uv2, 0.0).rgb;
			ALBEDO = bg + add;
			ALPHA = 1.0;
		}
	} else {
		ALBEDO = add * 0.5;
		ALPHA = 0.0;
	}
}
