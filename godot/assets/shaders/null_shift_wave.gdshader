// Волна смены поля NULL по кадру (scripts/look/null_look.gd, docs/plan-demo/look/null.md): полоса поперёк направления новой
// гравитации проходит через экран по этому направлению; в полосе картинка сдвигается вдоль хода волны с разводом каналов (как
// линза), фронт чуть светится цветом поля, за фронтом — затухающая рябь. Полноэкранный ColorRect на своём CanvasLayer ниже HUD;
// виден только пока идёт волна (копия экрана — только в эти кадры).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 dir = vec2(0.0, 1.0);        // направление хода волны на экране (y вниз), нормировано
uniform float front = -1.0;               // положение фронта вдоль dir (единицы — высота экрана, центр экрана = 0)
uniform float width = 0.11;
uniform float strength = 0.032;           // сдвиг UV в полосе
uniform float trail = 0.22;               // длина ряби за фронтом
uniform float fade = 1.0;
uniform vec3 tint : source_color = vec3(0.35, 0.68, 1.0);

void fragment() {
	vec2 sz = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = sz.x / sz.y;
	vec2 p = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);
	vec2 d = normalize(dir + vec2(1e-5));
	float s = dot(p, d) - front;
	float x = s / width;
	float band = exp(-x * x);
	float behind = s < 0.0 ? exp(s / max(trail, 0.01)) : 0.0;
	float rip = behind * sin(s * 60.0) * 0.2;
	float k = (band * sin(x * 1.6) + rip) * fade;
	vec2 off = d / vec2(aspect, 1.0) * strength * k;
	vec2 uv = SCREEN_UV - off;
	vec3 c;
	c.r = textureLod(screen_tex, clamp(uv - off * 0.45, vec2(0.0), vec2(1.0)), 0.0).r;
	c.g = textureLod(screen_tex, clamp(uv, vec2(0.0), vec2(1.0)), 0.0).g;
	c.b = textureLod(screen_tex, clamp(uv + off * 0.45, vec2(0.0), vec2(1.0)), 0.0).b;
	// яркая кромка фронта (чуть впереди полосы) и голубой отсвет полосы
	float lead = exp(-pow((s - width * 0.9) / (width * 0.12), 2.0));
	c += tint * (band * 0.22 + lead * 0.55 + behind * 0.03) * fade;
	COLOR = vec4(c, 1.0);
}
