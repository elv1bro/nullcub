## Сцена-коробка испытания во встроенной мастерской (гараж меню, docs/plan-demo/MENU_GARAGE.md §0): у гаража нет арены, поэтому
## здесь только то, что нужно бою 2.5D в плоскости z = 0: невидимые пол, стены и потолок (StaticBody3D Bounds в сцене) и bounds()
## для DynamicCamera — как у арен (WorkshopArena.bounds). Видимые пол и стены — сам гараж.
class_name GarageStage
extends Node3D

## Границы боя: пол y = 0, комната гаража x ±4.5, потолок y = 3.4; по z — тонкая плоскость боя.
@export var stage_bounds := AABB(Vector3(-4.5, 0.0, -1.0), Vector3(9.0, 3.4, 2.0))


func bounds() -> AABB:
	return stage_bounds
