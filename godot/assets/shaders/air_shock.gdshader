// Волна воздуха сильного удара (docs/plan-demo/HIT_FX.md §13, стиль «серьёзный»): бесцветное кольцо-искажение — картинка за ним
// смещается от центра, как горячий воздух. Вместо цветных колец цвета атакующего (стиль «мульт»). Квад лицом к камере (+Z),
// progress 0…1 — радиус кольца в долях половины квада; гаснет к концу.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float progress = 0.0;
uniform float strength = 0.025;   // смещение UV экрана на кольце
uniform float width = 0.22;       // толщина кольца (доля радиуса квада)
uniform float brighten = 0.05;

void fragment() {
	vec2 c = UV - vec2(0.5);
	float d = length(c) * 2.0;
	float ring = 1.0 - smoothstep(0.0, width, abs(d - progress));
	float fade = 1.0 - progress;
	vec2 dir = d > 0.0001 ? c / max(length(c), 0.0001) : vec2(0.0);
	vec2 off = dir * ring * strength * fade;
	vec3 col = textureLod(screen_tex, SCREEN_UV + vec2(off.x, off.y), 0.0).rgb;
	ALBEDO = col * (1.0 + brighten * ring * fade);
	ALPHA = clamp(ring * fade * 3.0, 0.0, 1.0) * (1.0 - step(1.0, d));
}
