// Толпа спрайтами (tools/blender/crowd_sprites.py → assets/textures/crowd/crowd_atlas.png): модульные существа из деталей кита,
// запечённые в атлас COLS × ROWS; у варианта POSES ячеек подряд (руки вниз / в стороны / вверх). Один MultiMesh квадов
// (scenes/arena/crowd_multimesh.gd): квад всегда развёрнут к камере вокруг вертикали (камера боя без наклона, лист камеры).
// INSTANCE_CUSTOM: x — вариант, y — фаза 0..1, z — яркость экземпляра, w — не занято.
// cheer 0..1 — насколько болеют (арена поднимает на ударах о мембрану и KO): доля времени с поднятыми руками и частота.
// Эфир Лиги (scripts/show/hall_show.gd, панель «ВИД», группа «Эфир»; все show_* по умолчанию 0 — вид ровно прежний):
//   show_dim 0..1   — толпа приглушена (яркость −40 %, насыщенность −25 %), чтобы не спорила с бойцами;
//   show_flash 0..1 — вспышки фотокамер: у доли зрителей на 1/14 с белая точка «камеры» у лица (сильный удар, KO);
//   show_wave 0..1  — где идёт «волна» (позиция по x зала −1..1 → 0..1; < 0 — волны нет): руки вверх и подскок;
//   show_sway 0..1  — лёгкое покачивание (верх спрайта ходит, сильнее при cheer);
//   show_light      — множитель света зала (свет финала гасит и толпу; 1 — как было).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float cols = 8.0;
uniform float rows = 6.0;
uniform float poses = 3.0;
uniform float brightness = 0.55;          // свет зала (спрайт запечён под ярким светом)
uniform vec3 tint : source_color = vec3(1.0, 0.92, 0.85);
uniform float cheer = 0.15;
uniform float alpha_cut = 0.5;
uniform float show_dim = 0.0;
uniform float show_flash = 0.0;
uniform float show_wave = -1.0;
uniform float show_wave_width = 0.09;
uniform float show_sway = 0.0;
uniform float show_hall_half_x = 26.0;
uniform float show_light = 1.0;           // свет зала (финал: общий свет гаснет — толпа тоже)

varying flat vec4 cust;
varying float wave_w;

float hash11(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	cust = INSTANCE_CUSTOM;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right = normalize(vec3(right.x, 0.0, right.z) + vec3(1e-5, 0.0, 0.0));
	wave_w = 0.0;
	if (show_wave >= 0.0) {
		float u = clamp(origin.x / show_hall_half_x * 0.5 + 0.5, 0.0, 1.0);
		wave_w = 1.0 - smoothstep(0.0, show_wave_width, abs(u - show_wave));
	}
	float top = VERTEX.y + 0.5;               // 0 — ноги, 1 — макушка (QuadMesh −0.5..0.5)
	float sway = show_sway * (0.05 + 0.08 * cheer) * sin(TIME * (1.4 + cust.y) + cust.y * 6.2832) * top;
	vec3 world = origin + right * (VERTEX.x * sx + sway * sx) + vec3(0.0, VERTEX.y * sy + wave_w * 0.6 * sy, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float variant = floor(cust.x + 0.5);
	float phase = cust.y;
	// поза: большинство сидит спокойно; при cheer — руки то в стороны, то вверх, у каждого своя фаза и частота
	float speed = mix(0.35, 2.2, cheer) * (0.8 + 0.4 * fract(phase * 7.13));
	float t = fract(TIME * speed + phase);
	float up = step(1.0 - clamp(cheer * 1.15, 0.0, 1.0), fract(phase * 3.71 + floor(TIME * 0.5 + phase * 4.0) * 0.618));
	float pose = up > 0.5 ? (t < 0.5 ? 1.0 : 2.0) : 0.0;
	if (wave_w > 0.35) {
		pose = 2.0;
	}
	float cell = variant * poses + min(pose, poses - 1.0);
	vec2 cr = vec2(mod(cell, cols), floor(cell / cols));
	vec2 uv = (cr + UV) / vec2(cols, rows);
	vec4 c = texture(atlas, uv);
	// вспышка камеры: белая точка у лица, держится один «тик» 1/14 с
	float flash = 0.0;
	if (show_flash > 0.0) {
		float tick = floor(TIME * 14.0);
		if (hash11(phase * 97.31 + tick * 0.173) < show_flash * 0.16) {
			vec2 p = vec2(0.5 + (fract(phase * 13.7) - 0.5) * 0.3, 0.3);
			float d = length((UV - p) * vec2(1.0, 1.6));
			flash = 1.0 - smoothstep(0.035, 0.11, d);
		}
	}
	if (c.a < alpha_cut && flash < 0.3) {
		discard;
	}
	vec3 col = c.rgb * tint * brightness * cust.z;
	if (show_dim > 0.0) {
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(lum), 0.25 * show_dim) * (1.0 - 0.4 * show_dim);
	}
	col *= show_light * (1.0 + 0.35 * wave_w);
	ALBEDO = mix(col, vec3(4.0), flash);
}
