// Затемнение фона в замедлении после ката крита (HIT_FX.md §12.3, CritOverlay.BgDim): тёмно-синий слой amount вне круга radius вокруг
// жертвы (centre, ед. Root), мягкий край; у краёв кадра чуть сильнее. На светлых аренах (небо Руин) жертва и её след выходят вперёд.
shader_type canvas_item;

uniform vec2 centre = vec2(960.0, 540.0);
uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float radius = 220.0;
uniform vec3 colour : source_color = vec3(0.02, 0.03, 0.06);

void fragment() {
	vec2 px = UV * rect_size;
	float d = length(px - centre);
	float out_k = smoothstep(radius, radius * 1.9 + 80.0, d);
	vec2 q = UV - 0.5;
	float vig = smoothstep(0.3, 0.8, length(q * vec2(1.2, 1.0)));
	COLOR = vec4(colour, amount * clamp(out_k * (0.8 + 0.2 * vig), 0.0, 1.0));
}
