class_name HealthComponent
extends Node
## Health and the character's condition (GDD §7 Lethality):
## [code]ACTIVE[/code] -> [code]KNOCKED_OUT[/code] -> [code]DEAD[/code].
##
## Blunt damage that empties [member health] knocks out. Hits on a knocked-out
## body drain [member downed_health] instead ("downed damage"); when that runs
## out the character dies. Blade and firearm damage that empties
## [member health] kills straight away. An untouched knocked-out character
## recovers after [member knockout_recovery_time].

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node3D)
signal state_changed(state: State)
## The victim reached 0 health from blunt damage. [param by] dealt the last hit.
signal knocked_out(victim: Node3D, by: Node3D)
## The victim died (from active or knocked out). [param by] dealt the last hit.
signal killed(victim: Node3D, by: Node3D)
## A knocked-out character got back up on its own (recovery timer).
signal recovered(victim: Node3D)
## Restored by [method revive] (fight restart, respawn).
signal revived

enum State { ACTIVE, KNOCKED_OUT, DEAD }

@export var max_health: float = 100.0
## Node reported as the victim in signals. Defaults to the parent.
@export var body: Node3D

@export_group("Knocked out")
## Damage a knocked-out body takes before it dies.
@export var downed_health: float = 40.0
## Downed damage multiplier per [enum AttackData.DamageType] (blunt, blade,
## firearm). Missing entries count as 1.
@export var downed_damage_scale: PackedFloat32Array = PackedFloat32Array([1.0, 2.0, 4.0])
## An untouched knocked-out character gets up after this many seconds.
## Every downed hit restarts the timer. 0 = stays down (until revived).
@export var knockout_recovery_time: float = 0.0
## Health (fraction of [member max_health]) after recovering from a knockout.
@export_range(0.0, 1.0) var recovery_health_fraction: float = 0.3

var health: float = 0.0
var state: State = State.ACTIVE
## Downed damage left before death (only meaningful while knocked out).
var downed_health_left: float = 0.0
## Seconds left until a knocked-out character recovers (INF = never).
var recovery_time_left: float = INF


func _ready() -> void:
	if body == null:
		body = get_parent() as Node3D
	health = max_health


func _physics_process(delta: float) -> void:
	if state != State.KNOCKED_OUT or recovery_time_left == INF:
		return
	recovery_time_left -= delta
	if recovery_time_left <= 0.0:
		_recover()


func is_active() -> bool:
	return state == State.ACTIVE


func is_knocked_out() -> bool:
	return state == State.KNOCKED_OUT


func is_dead() -> bool:
	return state == State.DEAD


## Knocked out or dead.
func is_down() -> bool:
	return state != State.ACTIVE


## Dead bodies take no more damage.
func can_take_damage() -> bool:
	return state != State.DEAD


func get_fraction() -> float:
	return health / max_health if max_health > 0.0 else 0.0


## Applies damage. On an active character it lowers [member health]; on a
## knocked-out one it is downed damage. [param attack] decides the damage type
## (no attack = blunt).
func take_damage(amount: float, source: Node3D, attack: AttackData = null) -> void:
	if amount <= 0.0:
		return
	var damage_type := attack.damage_type if attack != null else AttackData.DamageType.BLUNT
	match state:
		State.ACTIVE:
			health = maxf(health - amount, 0.0)
			damaged.emit(amount, source)
			health_changed.emit(health, max_health)
			if health > 0.0:
				return
			if damage_type == AttackData.DamageType.BLUNT:
				_knock_out(source)
			else:
				_die(source)
		State.KNOCKED_OUT:
			var scaled := amount * _downed_scale(damage_type)
			downed_health_left = maxf(downed_health_left - scaled, 0.0)
			damaged.emit(scaled, source)
			if downed_health_left <= 0.0:
				_die(source)
			else:
				_restart_recovery()


## Restores health (as a fraction of [member max_health]) and makes the
## character active again, from any state.
func revive(fraction: float = 1.0) -> void:
	health = max_health * clampf(fraction, 0.0, 1.0)
	recovery_time_left = INF
	_set_state(State.ACTIVE if health > 0.0 else State.KNOCKED_OUT)
	health_changed.emit(health, max_health)
	revived.emit()


func _knock_out(source: Node3D) -> void:
	downed_health_left = downed_health
	_restart_recovery()
	_set_state(State.KNOCKED_OUT)
	knocked_out.emit(body, source)


func _die(source: Node3D) -> void:
	health = 0.0
	downed_health_left = 0.0
	recovery_time_left = INF
	_set_state(State.DEAD)
	health_changed.emit(health, max_health)
	killed.emit(body, source)


func _recover() -> void:
	recovery_time_left = INF
	health = maxf(max_health * recovery_health_fraction, 1.0)
	_set_state(State.ACTIVE)
	health_changed.emit(health, max_health)
	recovered.emit(body)


func _restart_recovery() -> void:
	recovery_time_left = knockout_recovery_time if knockout_recovery_time > 0.0 else INF


func _downed_scale(damage_type: AttackData.DamageType) -> float:
	var index := int(damage_type)
	return downed_damage_scale[index] if index < downed_damage_scale.size() else 1.0


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)
