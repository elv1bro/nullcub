## №067 Crushing Press (лист 04; kit-02 №54 Press: off / warning / active / cooldown): ползун падает на наковальню. Дерево —
## scenes/props/scrap/machine_press.tscn: Frame (StaticBody3D: траверса, цилиндр и наковальня на плоскости боя; колонны станины за
## плоскостью, без коллизий) с Model, Ram (AnimatableBody3D: блок ползуна) с Model, LampLight (красный), Dust / Sparks (разовые
## вспышки удара), Sfx.
##
## Цикл (ScrapMachine):
##   OFF       ползун поднят: низ на rest_y (под ним проходит кукла 1.8 м);
##   WARNING   лампы мигают красным, гудок, ползун «взводится» на windup_m вверх с дрожью, сыплется пыль;
##   ACTIVE    удар: за slam_s вниз до наковальни (ускоряясь), коллизия ползуна выключена (ничего не зажимает в пол) — всё, что
##             в зоне под ним (x ± RAM_HALF_X, от наковальни до низа ползуна), обрабатывается один раз за удар:
##               кукла — урон damage (Doll.take_damage, вид "environment", attacker null: урон окружения в DollCombat выключен
##               — Tuning.ENV_DAMAGE_ENABLED, — поэтому пресс зовёт take_damage сам, как ThrownCredit), отброс
##               Damage.knockback_impulse вбок от оси пресса, стан Damage.stun_seconds, щепки, Match.on_hit; только в бою
##               (Match.combat_active), вне боя — только отброс;
##               Breakable (ящик, бочка) — take_damage(BREAK_DAMAGE): ломается, роняет лут (scrap.gd);
##               прочие тела (железная бочка, куски, оружие, части разбитых кукол) — выталкиваются вбок push_speed;
##             внизу — пыль, искры, удар, тряска камеры; ползун стоит hold до конца ACTIVE;
##   COOLDOWN  подъём до rest_y (плавно); коллизия ползуна включается, когда он выше наковальни на COLLIDE_FROM_M и не
##             пересекается ни с чем.
class_name PressMachine
extends ScrapMachine

const RAM_HALF_X := 1.0
const RAM_HALF_Z := 0.6
const RAM_H := 0.8
const BREAK_DAMAGE := 1000.0
const COLLIDE_FROM_M := 1.2
const FX_STRENGTH := 14.0

@export var rest_y := 3.3
@export var anvil_y := 0.12
@export var windup_m := 0.25
@export var slam_s := 0.14
@export var damage := 30.0
@export var push_speed := 6.0

var ram: AnimatableBody3D
var ram_shape: CollisionShape3D
var dust: GPUParticles3D
var sparks: GPUParticles3D
## Удары этого цикла и все: [{victim, damage, t}], сломанные пропсы (имена), вытолкнутые тела.
var hits: Array = []
var broken: Array = []
var pushed := 0
var slams := 0
var ram_y := 0.0
var _handled: Dictionary = {}
var _impact_done := false
var _zone: BoxShape3D
var _ram_probe: BoxShape3D
var _exclude: Array[RID] = []


func _machine_ready() -> void:
	ram = get_node_or_null("Ram") as AnimatableBody3D
	ram_shape = get_node_or_null("Ram/Shape") as CollisionShape3D
	dust = get_node_or_null("Dust") as GPUParticles3D
	sparks = get_node_or_null("Sparks") as GPUParticles3D
	_zone = BoxShape3D.new()
	_ram_probe = BoxShape3D.new()
	_ram_probe.size = Vector3(RAM_HALF_X * 2.0, RAM_H, RAM_HALF_Z * 2.0)
	var frame := get_node_or_null("Frame") as CollisionObject3D
	if frame != null:
		_exclude.append(frame.get_rid())
	if ram != null:
		_exclude.append(ram.get_rid())
	_set_ram(rest_y)


func _set_ram(y: float) -> void:
	ram_y = y
	if ram != null:
		ram.position = Vector3(0.0, y, 0.0)


func _on_state(s: int, _prev: int) -> void:
	match s:
		State.WARNING:
			play_sfx("beep", 0.9)
		State.ACTIVE:
			_handled.clear()
			_impact_done = false
			slams += 1
			_set_collision(false)


func _set_collision(on: bool) -> void:
	if ram_shape != null and ram_shape.disabled == on:
		ram_shape.set_deferred("disabled", not on)


func _machine_tick(_delta: float) -> void:
	match state:
		State.OFF:
			_set_ram(rest_y)
			_set_collision(true)
		State.WARNING:
			var u := clampf(state_t / maxf(warning_s, 0.01), 0.0, 1.0)
			var jitter := 0.02 * sin(time * 60.0) * u
			_set_ram(rest_y + windup_m * smoothstep(0.0, 1.0, u) + jitter)
		State.ACTIVE:
			var top := rest_y + windup_m
			var u2 := clampf(state_t / maxf(slam_s, 0.01), 0.0, 1.0)
			_set_ram(lerpf(top, anvil_y, u2 * u2))
			if not _impact_done:
				_crush()   # только на ходу вниз и в момент удара: в опущенный ползун (коллизия ещё выключена) можно войти без урона
				if u2 >= 1.0:
					_impact_done = true
					_impact()
		State.COOLDOWN:
			var u3 := clampf(state_t / maxf(cooldown_s, 0.01), 0.0, 1.0)
			_set_ram(lerpf(anvil_y, rest_y, smoothstep(0.0, 1.0, u3)))
			if ram_shape != null and ram_shape.disabled and ram_y >= anvil_y + COLLIDE_FROM_M and not _ram_overlaps():
				_set_collision(true)


## Всё в зоне под ползуном (от наковальни до его низа) — один раз за удар.
func _crush() -> void:
	var o := global_position
	var h := maxf(ram_y - anvil_y, 0.05)
	_zone.size = Vector3(RAM_HALF_X * 2.0 + 0.1, h, RAM_HALF_Z * 2.0)
	var xf := Transform3D(Basis.IDENTITY, Vector3(o.x, o.y + anvil_y + h * 0.5, o.z))
	for b in bodies_in(_zone, xf, _exclude):
		var rb := b as RigidBody3D
		var dl := doll_of(rb)
		var side := signf(rb.global_position.x - o.x)
		if side == 0.0:
			side = 1.0 if (rb.get_instance_id() % 2) == 0 else -1.0
		if dl != null and dl.alive:
			if not _handled.has(dl):
				_handled[dl] = true
				_hit_doll(dl, rb, side)
			rb.linear_velocity.x = side * maxf(absf(rb.linear_velocity.x), push_speed)
			continue
		if _handled.has(rb):
			continue
		_handled[rb] = true
		if rb is Breakable and (rb as Breakable).state != Breakable.State.DESTROYED:
			broken.append(String(rb.name))
			(rb as Breakable).take_damage(BREAK_DAMAGE)
			continue
		pushed += 1
		if rb.sleeping:
			rb.sleeping = false
		rb.linear_velocity = Vector3(side * maxf(absf(rb.linear_velocity.x), push_speed), maxf(rb.linear_velocity.y, 0.5), 0.0)


func _hit_doll(d: Doll, part: RigidBody3D, side: float) -> void:
	var com := d.centre_of_mass()
	var dir := Vector3(side, -0.15, 0.0)
	var pos := part.global_position
	var m := match_node()
	var kb_mult := float(m.call("knockback_mult")) if m != null and m.has_method("knockback_mult") else 1.0
	var in_fight := combat_on()
	var dmg := damage if in_fight and d.can_take_damage() else 0.0
	var stun_s := Damage.stun_seconds(dmg) if dmg > 0.0 else 0.0
	if dmg > 0.0:
		d.hit_meta = {"speed": 20.0, "weapon_id": "machine:press", "striker": ram, "combo_mult": 1.0, "double_blow": false,
			"knockback_mult": kb_mult, "stun_s": stun_s}
		d.take_damage(dmg, null, String(part.name), pos, Vector3.UP, "environment")
		hits.append({"victim": d, "damage": dmg, "t": snappedf(time, 0.001), "part": String(part.name)})
		if d.alive and stun_s > 0.0:
			d.stun(stun_s)
		ImpactFx.spawn_impact(m if m != null else get_parent(), pos, Vector3.UP, FX_STRENGTH + dmg * 0.4, "weapon")
		if m != null and m.has_method("on_hit"):
			m.call("on_hit", d, null, dmg, "environment", pos, 0, false, "machine:press", 20.0)
	if not d.is_broken():
		var j := maxf(Damage.knockback_impulse(maxf(dmg, damage * 0.5), kb_mult), Tuning.KNOCKBACK_MIN * kb_mult)
		d.apply_knockback(Damage.knockback_dir(dir) * j, part, stun_s, dir, Tuning.KNOCKBACK_MIN * kb_mult)
	if com.y < anvil_y + global_position.y + 1.2:
		camera_shake(0.12)


func _impact() -> void:
	play_sfx("thud")
	camera_shake(0.2)
	for p in [dust, sparks]:
		if p != null:
			p.restart()
			p.emitting = true


func _ram_overlaps() -> bool:
	if ram == null:
		return false
	var xf := Transform3D(Basis.IDENTITY, ram.global_position + Vector3(0.0, RAM_H * 0.5, 0.0))
	return not bodies_in(_ram_probe, xf, _exclude, 4).is_empty()
