// Луч прожектора в дымке зала (Light_Beam.glb: конус длиной 1, вершина в нуле, UV.y вдоль луча 0 → 1).
// Аддитивный и очень слабый: ярче у лампы, гаснет к концу, край конуса мягкий (по углу к взгляду). Лист камеры: без шума.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 colour : source_color = vec3(1.0, 0.9, 0.75);
uniform float intensity = 0.05;

varying float along;

void vertex() {
	along = UV.y;
}

void fragment() {
	float fade = (1.0 - along) * smoothstep(0.0, 0.06, along);
	float rim = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = colour * intensity * fade * rim;
}
