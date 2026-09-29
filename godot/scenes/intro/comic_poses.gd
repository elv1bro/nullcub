## Позы марионетки для заставки-комикса (числа, как Tuning для боя). Ключ — сустав ComicPuppet, значение — углы Эйлера
## в градусах (X− — конечность вперёд, Z+ — левая наружу / правая внутрь, локоть X−, колено X+); "Root_pos" — сдвиг таза, м.
## Кадры (ComicShot.hero_keys / enemy_keys) ссылаются на позы по имени.
class_name ComicPoses
extends RefCounted

const P := {
	# 02: лежит в куче лицом вверх, головой влево, правого предплечья нет
	"lying": {
		"Root": Vector3(-72, 8, 96), "Root_pos": Vector3(0.0, -0.72, 0.0),
		"Neck": Vector3(-10, -34, 0),
		"Shoulder_L": Vector3(-4, 0, 22), "Elbow_L": Vector3(-28, 0, 0), "Wrist_L": Vector3(0, 0, 20),
		"Shoulder_R": Vector3(6, 0, -30), "Elbow_R": Vector3(0, 0, 0),
		"Hip_L": Vector3(-8, 0, 10), "Knee_L": Vector3(18, 0, 0),
		"Hip_R": Vector3(-34, 0, -6), "Knee_R": Vector3(58, 0, 0), "Ankle_R": Vector3(-20, 0, 0),
	},
	# 02→03: дёрнулась
	"lying_twitch": {
		"Root": Vector3(-66, 8, 94), "Root_pos": Vector3(0.0, -0.64, 0.0),
		"Neck": Vector3(-14, -26, 6),
		"Shoulder_L": Vector3(-14, 0, 30), "Elbow_L": Vector3(-50, 0, 0), "Wrist_L": Vector3(0, 0, 30),
		"Shoulder_R": Vector3(0, 0, -24),
		"Hip_L": Vector3(-30, 0, 10), "Knee_L": Vector3(50, 0, 0),
		"Hip_R": Vector3(-52, 0, -6), "Knee_R": Vector3(72, 0, 0), "Ankle_R": Vector3(-20, 0, 0),
	},
	# 03: резко села в куче, смотрит в камеру
	"sit_up": {
		"Root": Vector3(-8, 0, 0), "Root_pos": Vector3(0.0, -0.74, 0.0),
		"Neck": Vector3(-6, 0, 4),
		"Shoulder_L": Vector3(24, 0, 26), "Elbow_L": Vector3(-8, 0, 0), "Wrist_L": Vector3(40, 0, 0),
		"Shoulder_R": Vector3(10, 0, -22),
		"Hip_L": Vector3(-82, -8, 14), "Knee_L": Vector3(62, 0, 0), "Ankle_L": Vector3(-20, 0, 0),
		"Hip_R": Vector3(-76, 10, -10), "Knee_R": Vector3(38, 0, 0), "Ankle_R": Vector3(-20, 0, 0),
	},
	# 04: стоит спиной к камере, смотрит вверх на Башню
	"stand_look": {
		"Root": Vector3(0, 0, 0),
		"Neck": Vector3(-24, 0, 0),
		"Shoulder_L": Vector3(4, 0, 10), "Elbow_L": Vector3(-10, 0, 0),
		"Shoulder_R": Vector3(4, 0, -12),
		"Hip_L": Vector3(0, 0, 5), "Hip_R": Vector3(-6, 0, -6), "Knee_R": Vector3(8, 0, 0),
	},
	# 05: бочка на голову — колени подогнулись, руки врастопырку, голову вдавило
	"bonk": {
		"Root": Vector3(10, 0, 4), "Root_pos": Vector3(0.0, -0.16, 0.0),
		"Neck": Vector3(22, 0, -8),
		"Shoulder_L": Vector3(-20, 0, 100), "Elbow_L": Vector3(-40, 0, 0), "Wrist_L": Vector3(0, 0, 30),
		"Shoulder_R": Vector3(-20, 0, -96),
		"Hip_L": Vector3(-26, 0, 16), "Knee_L": Vector3(40, 0, 0),
		"Hip_R": Vector3(-20, 0, -16), "Knee_R": Vector3(36, 0, 0),
	},
	# 06: присела, тянется левой рукой в кучу конечностей
	"reach": {
		"Root": Vector3(34, -20, 0), "Root_pos": Vector3(0.0, -0.3, 0.0),
		"Neck": Vector3(18, -8, 0),
		"Shoulder_L": Vector3(-78, 0, -4), "Elbow_L": Vector3(-24, 0, 0), "Wrist_L": Vector3(-10, 0, 0),
		"Shoulder_R": Vector3(10, 0, -18),
		"Hip_L": Vector3(-60, 0, 10), "Knee_L": Vector3(84, 0, 0), "Ankle_L": Vector3(-20, 0, 0),
		"Hip_R": Vector3(-24, 0, -10), "Knee_R": Vector3(56, 0, 0), "Ankle_R": Vector3(-20, 0, 0),
	},
	# 06→07: вытащила деталь
	"pull": {
		"Root": Vector3(12, -10, 0), "Root_pos": Vector3(0.0, -0.12, 0.0),
		"Neck": Vector3(6, -4, 0),
		"Shoulder_L": Vector3(-40, 0, 8), "Elbow_L": Vector3(-60, 0, 0), "Wrist_L": Vector3(-10, 0, 0),
		"Shoulder_R": Vector3(10, 0, -18),
		"Hip_L": Vector3(-28, 0, 10), "Knee_L": Vector3(40, 0, 0),
		"Hip_R": Vector3(-10, 0, -10), "Knee_R": Vector3(24, 0, 0),
	},
	# 07: подняла деталь к небу
	"hold_up": {
		"Root": Vector3(-6, 0, 0),
		"Neck": Vector3(-34, 0, 0),
		"Shoulder_L": Vector3(-158, 0, 14), "Elbow_L": Vector3(-14, 0, 0), "Wrist_L": Vector3(-20, 0, 0),
		"Shoulder_R": Vector3(8, 0, -20),
		"Hip_L": Vector3(-4, 0, 9), "Hip_R": Vector3(6, 0, -10), "Knee_R": Vector3(10, 0, 0),
	},
	# 08: прикручивает предплечье к правому локтю
	"attach": {
		"Root": Vector3(8, 18, 0),
		"Neck": Vector3(26, -30, 0),
		"Shoulder_L": Vector3(-64, 0, -46), "Elbow_L": Vector3(-72, 0, 0), "Wrist_L": Vector3(0, 0, -10),
		"Shoulder_R": Vector3(-46, 0, -34), "Elbow_R": Vector3(-30, 0, 0),
		"Hip_L": Vector3(-6, 0, 8), "Hip_R": Vector3(4, 0, -8),
	},
	"attach_done": {
		"Root": Vector3(4, 10, 0),
		"Neck": Vector3(4, -38, 0),
		"Shoulder_L": Vector3(-12, 0, 16), "Elbow_L": Vector3(-34, 0, 0),
		"Shoulder_R": Vector3(-58, 0, -38), "Elbow_R": Vector3(-100, 0, 0), "Wrist_R": Vector3(0, 0, 0),
		"Hip_L": Vector3(-6, 0, 8), "Hip_R": Vector3(4, 0, -8),
	},
	# 09: летит вправо (+X), конечности отстают
	"hover": {
		"Root": Vector3(0, 30, -16),
		"Neck": Vector3(-10, 0, 8),
		"Shoulder_L": Vector3(20, 0, 28), "Elbow_L": Vector3(-20, 0, 0),
		"Shoulder_R": Vector3(20, 0, -52), "Elbow_R": Vector3(-24, 0, 0),
		"Hip_L": Vector3(14, 0, -6), "Knee_L": Vector3(40, 0, 0), "Ankle_L": Vector3(30, 0, 0),
		"Hip_R": Vector3(24, 0, -22), "Knee_R": Vector3(48, 0, 0), "Ankle_R": Vector3(30, 0, 0),
	},
	# 10–11: стойка, кулаки подняты, корпус к врагу (+X)
	"stance": {
		"Root": Vector3(6, 38, 0), "Root_pos": Vector3(0.0, -0.1, 0.0),
		"Neck": Vector3(10, 10, 0),
		"Shoulder_L": Vector3(-64, 0, 24), "Elbow_L": Vector3(-112, 0, 0), "Wrist_L": Vector3(0, 0, -10),
		"Shoulder_R": Vector3(-56, 0, -30), "Elbow_R": Vector3(-118, 0, 0), "Wrist_R": Vector3(0, 0, 10),
		"Hip_L": Vector3(-24, 0, 16), "Knee_L": Vector3(28, 0, 0),
		"Hip_R": Vector3(18, 0, -14), "Knee_R": Vector3(22, 0, 0),
	},
	# 12: рывок с ударом правой (+X)
	"punch": {
		"Root": Vector3(0, 82, -22), "Root_pos": Vector3(0.0, 0.05, 0.0),
		"Neck": Vector3(6, -6, 0),
		"Shoulder_L": Vector3(34, 0, 30), "Elbow_L": Vector3(-96, 0, 0),
		"Shoulder_R": Vector3(-96, 0, -6), "Elbow_R": Vector3(-6, 0, 0),
		"Hip_L": Vector3(40, 0, 6), "Knee_L": Vector3(74, 0, 0), "Ankle_L": Vector3(30, 0, 0),
		"Hip_R": Vector3(-34, 0, -6), "Knee_R": Vector3(52, 0, 0), "Ankle_R": Vector3(20, 0, 0),
	},
	# 13: парит над обломками, кулаки сжаты, руки врозь
	"victory": {
		"Root": Vector3(-4, 12, 0),
		"Neck": Vector3(-12, 8, 0),
		"Shoulder_L": Vector3(-20, 0, 62), "Elbow_L": Vector3(-50, 0, 0),
		"Shoulder_R": Vector3(-20, 0, -62), "Elbow_R": Vector3(-50, 0, 0),
		"Hip_L": Vector3(-10, 0, 12), "Knee_L": Vector3(30, 0, 0), "Ankle_L": Vector3(24, 0, 0),
		"Hip_R": Vector3(4, 0, -14), "Knee_R": Vector3(40, 0, 0), "Ankle_R": Vector3(24, 0, 0),
	},
	# враг-Разборщик: сгорбился, топор над головой (правая рука)
	"scrapling_idle": {
		"Root": Vector3(22, -40, 0), "Root_pos": Vector3(0.0, -0.14, 0.0),
		"Neck": Vector3(-26, 0, 0),
		"Shoulder_L": Vector3(-30, 0, 34), "Elbow_L": Vector3(-50, 0, 0),
		"Shoulder_R": Vector3(-150, 0, -16), "Elbow_R": Vector3(-40, 0, 0), "Wrist_R": Vector3(-20, 0, 0),
		"Hip_L": Vector3(-34, 0, 16), "Knee_L": Vector3(50, 0, 0),
		"Hip_R": Vector3(-10, 0, -18), "Knee_R": Vector3(40, 0, 0),
	},
	"scrapling_swing": {
		"Root": Vector3(34, -50, 0), "Root_pos": Vector3(0.0, -0.18, 0.0),
		"Neck": Vector3(-30, 0, 0),
		"Shoulder_L": Vector3(-10, 0, 50), "Elbow_L": Vector3(-40, 0, 0),
		"Shoulder_R": Vector3(-178, 0, -6), "Elbow_R": Vector3(-60, 0, 0), "Wrist_R": Vector3(-30, 0, 0),
		"Hip_L": Vector3(-40, 0, 16), "Knee_L": Vector3(56, 0, 0),
		"Hip_R": Vector3(-6, 0, -18), "Knee_R": Vector3(40, 0, 0),
	},
}


static func pose(name: String) -> Dictionary:
	return P.get(name, {})
