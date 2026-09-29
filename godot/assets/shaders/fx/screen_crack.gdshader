// Экранные трещины сокрушительного удара (CritOverlay/ScreenCrack): crack_screen.png — R маска, G путь от центра, B осколок.
// Центр — точка удара на экране (centre, пиксели rect), раскрытие progress 0 → 1; осколки чуть смещают и подсвечивают картинку
// под собой (hint_screen_texture), щели — светлая кромка + тёмная сердцевина.
shader_type canvas_item;

uniform sampler2D crack_tex : filter_linear, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform vec2 centre = vec2(960.0, 540.0);
uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform float tex_px = 1500.0;       // размер текстуры на экране (px rect)
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float shard_shift = 3.0;     // px смещения осколков

float hash(float n) {
	return fract(sin(n * 91.345) * 47453.21);
}

void fragment() {
	vec2 p = UV * rect_size;
	vec2 tuv = (p - centre) / tex_px + 0.5;
	vec4 c = vec4(0.0, 1.0, 0.0, 0.0);
	if (tuv.x > 0.0 && tuv.x < 1.0 && tuv.y > 0.0 && tuv.y < 1.0) {
		c = texture(crack_tex, tuv);
	}
	float open = 1.0 - smoothstep(progress - 0.03, progress, c.g);
	float line = c.r * open;
	float shard = floor(c.b * 255.0 / 20.0 + 0.5);
	float r = length(p - centre) / (tex_px * 0.5);
	float inside = (1.0 - smoothstep(progress * 0.9, progress * 1.05 + 0.02, r)) * step(0.001, progress);
	vec2 dir = normalize(vec2(hash(shard) - 0.5, hash(shard + 7.0) - 0.5) + 1e-4);
	vec2 off = dir * shard_shift * inside / rect_size;
	vec3 under = texture(screen_tex, SCREEN_UV + off).rgb;
	vec3 shard_col = under * (1.0 + (hash(shard + 3.0) - 0.5) * 0.18 * inside);
	vec3 crack_col = mix(vec3(0.02, 0.03, 0.05), vec3(0.92, 0.97, 1.0), smoothstep(0.35, 0.9, c.r));
	vec3 col = mix(shard_col, crack_col, line);
	COLOR = vec4(col, alpha * max(line, inside * 0.999));
}
