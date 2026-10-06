// Мембрана-пузырь поля NULL (scripts/look/null_look.gd, docs/plan-demo/look/null.md): полуэллипсоид над полом (полуоси axes: ширина,
// высота, глубина), две половины — задняя (за плоскостью боя) и передняя. Только вид, механика мембраны — scenes/arena/null_field.gd.
//   задняя половина: преломление фона через плёнку (screen texture),
//                     радужная плёнка, радужный френелевый край, светящийся шов по полу;
//   передняя: только добавляет свет — край, сетка у бойца и кольца волн; бойцов не искажает.
// Сетка (треугольная) видна только у бойца рядом с мембраной (hits из NullField, как у старой ленты), на кольцах волн от ударов (waves)
// и на фронте смены поля (shift). Прогиб к точкам hits — как в null_membrane.gdshader (растяжение наружу по нормали эллипса).
// Тело — null_bubble.gdshaderinc; этот вариант с преломлением (кромка и середина задней половины), null_bubble_glow — только свет
// (передняя половина и шов по полу).
shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#define REFRACT
#include "res://assets/shaders/null_bubble.gdshaderinc"
