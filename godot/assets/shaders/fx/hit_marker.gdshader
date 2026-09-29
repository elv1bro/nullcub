// Маркер точки удара крита 33–150 мс (HIT_FX.md §12.3, CritOverlay.HitMarker): кольцо и 8 лучей, светлое тёплое ядро с тёмной
// обводкой — читается на белом небе Руин и на чёрном Void. centre / radius — ед. Root; phase 0 → 1 — лучи вытягиваются и поворачиваются.
shader_type canvas_item;

uniform vec2 centre = vec2(960.0, 540.0);
uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform float radius = 100.0;
uniform float alpha : hint_range(0.0, 1.0) = 0.0;
uniform float phase : hint_range(0.0, 1.0) = 0.0;
uniform vec3 core_colour : source_color = vec3(1.0, 0.93, 0.62);
uniform vec3 edge_colour : source_color = vec3(0.05, 0.02, 0.02);

void fragment() {
	vec2 d = UV * rect_size - centre;
	float r = length(d);
	float w = max(radius * 0.07, 3.0);
	// кольцо: ядро и более широкая тёмная обводка
	float ring_core = 1.0 - smoothstep(w * 0.45, w, abs(r - radius));
	float ring_halo = 1.0 - smoothstep(w * 1.1, w * 2.1, abs(r - radius));
	// 8 лучей от 0.35R до (0.9 + 0.5 phase)R, сужаются наружу
	float ang = atan(d.y, d.x) + phase * 0.35 + 0.3927;
	float sector = abs(fract(ang / 0.7853982) - 0.5) * 0.7853982;   // угол до оси ближайшего луча
	float lat = sector * r;                                           // поперечное расстояние, px
	float r0 = radius * 0.35;
	float r1 = radius * (0.9 + 0.5 * phase);
	float along = smoothstep(r0, r0 + w, r) * (1.0 - smoothstep(r1 - w * 2.0, r1, r));
	float taper = mix(1.0, 0.35, clamp((r - r0) / max(r1 - r0, 1.0), 0.0, 1.0));
	float ray_core = along * (1.0 - smoothstep(w * 0.4 * taper, w * 0.8 * taper, lat));
	float ray_halo = along * (1.0 - smoothstep(w * 1.0 * taper, w * 1.8 * taper, lat));
	// центр — вспышка в начале
	float dot_core = (1.0 - smoothstep(w * 1.2, w * 2.0, r)) * (1.0 - phase);
	float core = max(max(ring_core, ray_core), dot_core);
	float halo = max(max(ring_halo, ray_halo), dot_core);
	vec3 col = mix(edge_colour, core_colour, core / max(halo, 1e-3));
	COLOR = vec4(col, alpha * max(halo * 0.85, core));
}
