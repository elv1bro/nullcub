// Толпа спрайтами (tools/gen_crowd_people.py → assets/textures/crowd/crowd_atlas.png): очертания людей (06.10; до того — модульные
// существа кита, tools/blender/crowd_sprites.py) в атласе COLS × ROWS; у варианта POSES ячеек подряд (руки вниз / в стороны / вверх).
// Атлас белый (ноги чуть темнее) — цвет одежды даёт цвет экземпляра MultiMesh (COLOR), у каждого зрителя свой. Один MultiMesh квадов
// (scenes/arena/crowd_multimesh.gd): квад всегда развёрнут к камере вокруг вертикали (камера боя без наклона, лист камеры).
// INSTANCE_CUSTOM: x — вариант, y — фаза 0..1, z — яркость экземпляра, w — не занято.
// cheer 0..1 — насколько болеют (арена поднимает на ударах о мембрану и KO): доля времени с поднятыми руками и частота.
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

varying flat vec4 cust;

void vertex() {
	cust = INSTANCE_CUSTOM;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right = normalize(vec3(right.x, 0.0, right.z) + vec3(1e-5, 0.0, 0.0));
	vec3 world = origin + right * VERTEX.x * sx + vec3(0.0, VERTEX.y * sy, 0.0);
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
	float cell = variant * poses + min(pose, poses - 1.0);
	vec2 cr = vec2(mod(cell, cols), floor(cell / cols));
	vec2 uv = (cr + UV) / vec2(cols, rows);
	vec4 c = texture(atlas, uv);
	if (c.a < alpha_cut) {
		discard;
	}
	ALBEDO = c.rgb * COLOR.rgb * tint * brightness * cust.z;
}
