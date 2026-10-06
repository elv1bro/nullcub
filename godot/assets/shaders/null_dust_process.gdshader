// Пыль и мелкий мусор в объёме поля NULL (scripts/look/null_dust.gd, docs/plan-demo/look/null.md): слой частиц в коробке box_min ..
// box_min + box_size (мир). Частица живёт life_s, появляется и гаснет плавно, дрейфует по вектору гравитации поля (drift, м/с) с
// лёгким вихрем; волны сильных ударов (waves) разгоняют частицы от центра кольцом, кильватер (wakes) тянет за быстрым бойцом, общий
// толчок push — смена поля. Вид частицы (пыль / осколок / искра) и размер — в CUSTOM: x — вид, y — возраст 0..1, z — размер, м, w — фаза.
// ellipsoid.w > 0.5 — частицы видны только внутри купола поля (полуэллипсоид с полуосями ellipsoid.xyz над полом, центр ell_centre).
shader_type particles;
render_mode disable_force;

uniform vec3 box_min = vec3(-16.0, 0.0, -4.0);
uniform vec3 box_size = vec3(32.0, 19.0, 3.0);
uniform vec4 ellipsoid = vec4(16.0, 19.0, 4.0, 0.0);
uniform vec3 ell_centre = vec3(0.0);
uniform vec3 drift = vec3(0.0, -0.2, 0.0);
uniform float relax = 0.9;            // 1/с: как быстро скорость возвращается к дрейфу
uniform float turb = 0.05;            // м/с: вихрь
uniform vec3 push = vec3(0.0);        // м/с²: общий толчок (смена поля)
uniform vec4 waves[4];                // xyz — центр волны, w — возраст, с (< 0 — нет волны)
uniform vec4 wave_power = vec4(0.0);  // сила каждой волны 0..1
uniform float wave_speed = 9.0;       // м/с: скорость кольца
uniform float wave_width = 1.3;       // м: толщина кольца
uniform float wave_kick = 3.2;        // м/с: прирост скорости частицы у центра при силе 1
uniform vec4 wakes[4];                // xyz — ЦМ бойца, w — радиус кильватера, м
uniform vec4 wake_vel[4];             // xyz — скорость бойца, w — сила 0..1 (0 — нет)
uniform float spark_frac = 0.07;      // доля искр цвета NULL
uniform float chip_frac = 0.22;       // доля осколков-мусора
uniform vec2 size_range = vec2(0.018, 0.05);
uniform float chip_size = 2.2;        // осколок крупнее пылинки во столько раз
uniform float life_s = 14.0;          // с: жизнь одной частицы (появилась — погасла — родилась в другом месте)

float hash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return float(x) / 4294967295.0;
}

// новая жизнь частицы: место в коробке, вид, размер, фаза — от зерна s
void reborn(uint s, inout mat4 xf, inout vec4 cust) {
	vec3 r = vec3(hash(s + 1u), hash(s + 2u), hash(s + 3u));
	xf = mat4(1.0);
	xf[3].xyz = box_min + r * box_size;
	float k = hash(s + 4u);
	float kind = k < spark_frac ? 2.0 : (k < spark_frac + chip_frac ? 1.0 : 0.0);
	float rs = hash(s + 5u);
	float size = mix(size_range.x, size_range.y, rs * rs);
	if (kind > 0.5 && kind < 1.5) {
		size *= chip_size;
	}
	cust = vec4(kind, 0.0, size, hash(s + 6u) * 6.2831853);
}

// Все частицы рождаются разом (explosiveness = 1, системная жизнь — час) и дальше перерождаются сами (process): начальный возраст
// случайный — с первого кадра коробка полна, частицы гаснут и появляются вразнобой (preprocess у GPUParticles3D здесь не помогал).
void start() {
	uint s = NUMBER * 9u + RANDOM_SEED * 31u + INDEX * 7919u;
	mat4 xf = TRANSFORM;
	vec4 cust = CUSTOM;
	reborn(s, xf, cust);
	cust.y = hash(s + 7u);
	if (RESTART_POSITION) {
		TRANSFORM = xf;
	}
	if (RESTART_VELOCITY) {
		VELOCITY = drift;
	}
	if (RESTART_CUSTOM) {
		CUSTOM = cust;
	}
	if (RESTART_COLOR) {
		COLOR = vec4(1.0, 1.0, 1.0, 0.0);
	}
}

void process() {
	float age = CUSTOM.y + DELTA / max(life_s, 0.1);
	if (age >= 1.0) {
		uint s = floatBitsToUint(CUSTOM.w) * 747796405u + INDEX * 2891336453u + uint(TIME * 61.0);
		mat4 xf = TRANSFORM;
		vec4 cust = CUSTOM;
		reborn(s, xf, cust);
		TRANSFORM = xf;
		CUSTOM = cust;
		VELOCITY = drift;
		age = 0.0;
	}
	CUSTOM.y = age;
	vec3 p = TRANSFORM[3].xyz;
	float ph = CUSTOM.w;
	// медленный вихрь: синусы по месту и времени — частицы плывут не строем
	vec3 t = vec3(sin(p.y * 0.61 + TIME * 0.29 + ph), sin(p.x * 0.53 - TIME * 0.23 + ph * 1.3),
		sin((p.x + p.y) * 0.41 + TIME * 0.19 + ph * 0.7) * 0.6) * turb;
	VELOCITY += (drift + t - VELOCITY) * (1.0 - exp(-relax * DELTA));
	VELOCITY += push * DELTA;
	for (int i = 0; i < 4; i++) {
		float a = waves[i].w;
		float pw = wave_power[i];
		if (a < 0.0 || pw <= 0.0) {
			continue;
		}
		vec3 d = p - waves[i].xyz;
		float dist = length(d) + 1e-4;
		float x = (dist - a * wave_speed) / wave_width;
		float band = exp(-x * x);
		float fade = exp(-a * 1.1) / (1.0 + dist * 0.12);
		// интеграл кольца по времени ≈ width·√π / speed — прирост скорости за проход кольца ≈ wave_kick · pw · fade
		VELOCITY += (d / dist) * wave_kick * pw * fade * band * DELTA * wave_speed / (wave_width * 1.7725);
	}
	for (int i = 0; i < 4; i++) {
		float w = wake_vel[i].w;
		if (w <= 0.0) {
			continue;
		}
		vec3 d = p - wakes[i].xyz;
		float r = wakes[i].w;
		float f = exp(-dot(d, d) / (r * r)) * w;
		// частицы у бойца увлекает следом (до 60 % его скорости) и чуть разводит в стороны
		VELOCITY += (wake_vel[i].xyz * 0.6 - VELOCITY) * clamp(f * DELTA * 5.0, 0.0, 1.0);
		VELOCITY += normalize(d + vec3(1e-4)) * f * length(wake_vel[i].xyz) * 0.25 * DELTA;
	}
	float alpha = smoothstep(0.0, 0.15, age) * (1.0 - smoothstep(0.82, 1.0, age));
	if (ellipsoid.w > 0.5) {
		vec3 q = (p - ell_centre) / ellipsoid.xyz;
		alpha *= 1.0 - smoothstep(0.9, 1.0, length(q));
		alpha *= smoothstep(-0.02, 0.03, q.y);
	}
	COLOR = vec4(1.0, 1.0, 1.0, alpha);
}
