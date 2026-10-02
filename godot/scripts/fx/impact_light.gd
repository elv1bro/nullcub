## Свет удара (HIT_FX.md §13, стиль «серьёзный»): короткий тёплый OmniLight3D в точке удара — освещает куклы, пол и пыль на 2–6 кадров,
## удар читается силой, а не наклейкой (звезда-блик RM — стиль «мульт»). Без теней (дёшево в Forward+, кластерный свет). Гаснет по
## реальному времени (FxClock): в стоп-кадре удара свет горит — как вспышка камеры на кадре удара. Яркость × FxPreset.flash().
##   ImpactLight.flash(parent, pos, energy, range_m, life_s, colour) -> ImpactLight
class_name ImpactLight
extends OmniLight3D

const WARM := Color(1.0, 0.88, 0.7)

var _life := 0.08
var _t := 0.0
var _peak := 1.0


static func flash(parent: Node, pos: Vector3, energy: float, range_m: float, life_s: float, colour: Color = WARM) -> ImpactLight:
	if parent == null or not parent.is_inside_tree():
		return null
	var k := FxPreset.flash()
	if k <= 0.001 or energy <= 0.0:
		return null
	var l := ImpactLight.new()
	l.name = "ImpactLight"
	l.light_color = colour
	l.omni_range = range_m
	l.omni_attenuation = 1.6
	l.shadow_enabled = false
	l.light_specular = 0.6
	l._peak = energy * k
	l.light_energy = l._peak
	l._life = maxf(life_s, 0.016)
	parent.add_child(l, true)
	l.global_position = pos + Vector3(0.0, 0.0, 0.25)   # чуть к камере: свет ложится на лицевую сторону кукол
	return l


func _process(delta: float) -> void:
	_t += minf(FxClock.real_delta(delta), 1.0 / 30.0)
	var u := clampf(_t / _life, 0.0, 1.0)
	light_energy = _peak * (1.0 - u) * (1.0 - u)
	if u >= 1.0:
		queue_free()
