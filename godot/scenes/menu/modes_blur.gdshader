// Размытый фон экрана «ВСЕ РЕЖИМЫ» (scenes/menu/test_menu.gd): снимок выбранного режима, читаемый с дальнего мипа.
// У снимков assets/ui/modes/*.jpg в импорте включены мипмапы; без них фон будет просто резким.
shader_type canvas_item;

uniform float lod = 5.0;

void fragment() {
	COLOR = textureLod(TEXTURE, UV, lod) * COLOR;
}
