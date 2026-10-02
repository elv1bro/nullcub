## Карточка выхода бойца (docs/plan-demo/16-fighter-entrance.md, лор §7: «FIGHTER NAME / BUILD / MASS / MATCH HISTORY»):
## плашка внизу слева (P1) или справа (P2) — имя, сборка, масса и детали, счёт; подсказка «клавиша — быстрее, дважды — пропустить».
## Узел — scenes/arena/fighter_card.tscn, им управляет FighterEntrance (show_fighter / hide_now).
extends CanvasLayer

const COLORS := [Color(0.3, 0.6, 1.0), Color(1.0, 0.35, 0.3)]

@onready var box: Control = $Box
@onready var stripe: ColorRect = %Stripe


func _ready() -> void:
	box.visible = false
	%Skip.visible = false


## f: {name, build, mass, parts, record}; i — порядок выхода (0 — слева, 1 — справа).
func show_fighter(f: Dictionary, i: int) -> void:
	box.visible = true
	%Skip.visible = true
	%Name.text = String(f.get("name", "FIGHTER")).to_upper()
	var bits: PackedStringArray = []
	if String(f.get("build", "")) != "":
		bits.append(String(f["build"]))
	if float(f.get("mass", 0.0)) > 0.0:
		bits.append("%.1f кг" % float(f["mass"]))
	if int(f.get("parts", 0)) > 0:
		bits.append("деталей %d" % int(f["parts"]))
	%Build.text = " · ".join(bits)
	%Record.text = String(f.get("record", ""))
	stripe.color = COLORS[i % COLORS.size()]
	var right := i % 2 == 1
	box.anchor_left = 1.0 if right else 0.0
	box.anchor_right = 1.0 if right else 0.0
	box.offset_left = -660.0 if right else 60.0
	box.offset_right = -60.0 if right else 660.0


func hide_now() -> void:
	box.visible = false
	%Skip.visible = false
