// Мембрана-пузырь поля NULL, вариант «только свет» (scripts/look/null_look.gd): передняя половина пузыря и шов по полу — без
// преломления, без чтения экрана и глубины. Тело — null_bubble.gdshaderinc, вариант с преломлением — null_bubble.gdshader.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://assets/shaders/null_bubble.gdshaderinc"
