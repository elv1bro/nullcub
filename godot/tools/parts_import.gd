## Пост-импорт старых деталей мастерской (assets/models/body/parts/*.glb: киянка, топор, меч, булава, цепь, рукояти, крюк, щит…;
## их берут пулы QuickBuild и «Нарисуй»). «Взрослый вид», проход 2 (docs/plan-demo/grownup_art/README.md): материалы этих glb — те же
## роли, что у кита (Rust, RustDark, Steel, Wood, WoodDark, Brass, Rope, Joint, Pin, RustRed), но со старыми мультяшными картами
## craft_parts.py (клён, рыжая ржавчина пятнами). Здесь — материалы кита по имени роли, как tools/kit_import.gd (новые PBR-папки
## kit/tex/), и детали рядом с китом одного вида. Меши, формы и массы glb не меняются.
## Отличие от кита: роль Face не подменяется — у старых голов плашка утоплена в меш и с UV под фото (BodyPaint.set_face), визор кита
## на ней лёг бы мимо.
## Подключено в assets/models/body/parts/*.glb.import (import_script/path); после правки — godot --headless --path godot --import.
@tool
extends "res://tools/kit_import.gd"

const KEEP := ["Face"]


func _kit_material(cur: Material, surface_name: String, cache: Dictionary) -> Material:
	for raw in [cur.resource_name if cur != null else "", surface_name]:
		if KEEP.has(_clean(String(raw))):
			return null
	return super._kit_material(cur, surface_name, cache)
