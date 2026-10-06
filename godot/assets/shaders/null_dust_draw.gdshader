// Вид частиц пыли поля NULL (scripts/look/null_dust.gd; движение — null_dust_process.gdshader). Квад лицом к камере; по INSTANCE_CUSTOM.x:
// 0 — пылинка (мягкая точка), 1 — осколок-мусор (кувыркается: ширина дышит по cos, на развороте к свету — блик), 2 — искра цвета NULL
// (добавляет свет, мерцает). Смешение — premultiplied alpha: пыль и осколки ложатся поверх, искры только светят. Мельче min_px пикселя
// частица не становится (не мерцает вдали) — вместо этого бледнеет. Туман сцены не применяется (на квадах дал бы серые квадраты) —
// вместо него частица бледнеет с расстоянием (far_fade).
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 dust_col : source_color = vec3(0.82, 0.82, 0.86);
uniform vec3 chip_col : source_color = vec3(0.30, 0.31, 0.34);
uniform vec3 glint_col : source_color = vec3(1.0, 0.86, 0.66);
uniform vec3 spark_col : source_color = vec3(0.35, 0.68, 1.0);
uniform float dust_alpha = 0.5;
uniform float chip_alpha = 0.85;
uniform float spark_gain = 2.6;
uniform float soft = 0.25;            // 0 — чёткая точка, 1 — мягкое пятно (ближний слой — «боке»)
uniform float min_px = 2.5;
uniform vec2 far_fade = vec2(18.0, 60.0);   // м от камеры: с какого расстояния частица бледнеет и где исчезает
uniform float opacity = 1.0;

varying flat vec4 cust;
varying float fade;
varying float glint;

void vertex() {
	cust = INSTANCE_CUSTOM;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float dist = length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float px = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float size = cust.z * (cust.x > 1.5 ? 3.0 : 1.0);   // у искры квад шире — под ореол
	float grow = max(size, min_px * px);
	fade = (size / grow) * (size / grow);
	fade *= 1.0 - smoothstep(far_fade.x, far_fade.y, dist);
	vec2 v = VERTEX.xy * grow;
	float ang = cust.w;
	glint = 0.0;
	if (cust.x > 0.5 && cust.x < 1.5) {
		float spin = (fract(cust.w * 3.7) - 0.5) * 3.0;
		float flip = cos(TIME * (0.8 + fract(cust.w * 5.3) * 1.6) + cust.w * 2.0);
		v.x *= max(abs(flip), 0.12);
		glint = pow(abs(flip), 24.0);
		ang += TIME * spin;
	}
	float c = cos(ang);
	float s = sin(ang);
	VERTEX = vec3(c * v.x - s * v.y, s * v.x + c * v.y, 0.0);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float a = COLOR.a * fade * opacity;
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	if (cust.x < 0.5) {
		// ядро ярче края: у мелкой пылинки — почти точка, у ближней (soft) — ровное пятно
		float m = mix(exp(-r * r * 2.2), 1.0 - smoothstep(0.55, 1.0, r), soft) * (1.0 - smoothstep(0.85, 1.0, r));
		alpha = m * dust_alpha * a;
		col = dust_col * alpha;
	} else if (cust.x < 1.5) {
		// неровный осколок: четырёхугольник со сдвинутыми гранями
		float e = max(abs(uv.x + uv.y * 0.35), abs(uv.y * 1.15 - uv.x * 0.2));
		float m = 1.0 - smoothstep(0.62, 0.8, e);
		alpha = m * chip_alpha * a;
		col = mix(chip_col, glint_col * 1.6, glint) * alpha;
	} else {
		float tw = 0.45 + 0.55 * sin(TIME * (5.0 + fract(cust.w * 7.1) * 6.0) + cust.w * 9.0);
		float core = exp(-r * r * 9.0);
		col = spark_col * core * spark_gain * tw * a;
		alpha = 0.0;
	}
	ALBEDO = col;
	ALPHA = alpha;
}
