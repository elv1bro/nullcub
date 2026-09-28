## Стеновой сегмент мастерской с высоким окном (workshop_window_wall.tscn, tools/build_workshop_props_scenes.gd) —
## только переключатели декора за проёмом: нарисованный задник (квад «Exterior» 5.4 × 12.4 м, покрывает оба ряда стены)
## и листва «Foliage» (даёт пятнистые лучи). У верхнего ряда стены задник и листву выключают, чтобы не дублировать квад
## нижнего ряда (он и так дотягивается до y ≈ 12). Стекло Glass внутри glb в _ready теряет тень (иначе shadow map стекла
## режет лучи солнца в объёмном тумане); в .tscn это не сохранить без вшивания всего меша (editable instance).
class_name WorkshopWindowWall
extends Node3D

@export var exterior_visible := true: set = _set_exterior
@export var foliage_visible := true: set = _set_foliage


func _ready() -> void:
	var g := glass()
	if g != null:
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply()


func _set_exterior(v: bool) -> void:
	exterior_visible = v
	if is_inside_tree():
		_apply()


func _set_foliage(v: bool) -> void:
	foliage_visible = v
	if is_inside_tree():
		_apply()


func _apply() -> void:
	var ext := get_node_or_null("Exterior") as Node3D
	if ext != null:
		ext.visible = exterior_visible
	var fol := get_node_or_null("Foliage") as Node3D
	if fol != null:
		fol.visible = foliage_visible


## Стекло окна (MeshInstance3D «Glass» внутри Mesh) — для проверок.
func glass() -> MeshInstance3D:
	var m := get_node_or_null("Mesh")
	if m == null:
		return null
	return m.find_child("Glass", true, false) as MeshInstance3D
