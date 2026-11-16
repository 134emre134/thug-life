class_name HealthComponent
extends Node
## Health and the character's condition. M2 has two states (active, knocked
## out); M3a adds [code]DEAD[/code] and downed damage (GDD §7 Lethality), which
## is why this is a state field and not a bool.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node3D)
signal state_changed(state: State)
## The victim reached 0 health. [param by] is whoever dealt the last hit.
signal knocked_out(victim: Node3D, by: Node3D)
signal revived

enum State { ACTIVE, KNOCKED_OUT }

@export var max_health: float = 100.0
## Node reported as the victim in signals. Defaults to the parent.
@export var body: Node3D

var health: float = 0.0
var state: State = State.ACTIVE


func _ready() -> void:
	if body == null:
		body = get_parent() as Node3D
	health = max_health


func is_active() -> bool:
	return state == State.ACTIVE


func is_knocked_out() -> bool:
	return state == State.KNOCKED_OUT


func get_fraction() -> float:
	return health / max_health if max_health > 0.0 else 0.0


## Applies damage to an active character. [param attack] is passed along for
## M3a damage types (unused in M2).
func take_damage(amount: float, source: Node3D, _attack: AttackData = null) -> void:
	if state != State.ACTIVE or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	damaged.emit(amount, source)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_set_state(State.KNOCKED_OUT)
		knocked_out.emit(body, source)


## Restores health (as a fraction of [member max_health]) and makes the
## character active again.
func revive(fraction: float = 1.0) -> void:
	health = max_health * clampf(fraction, 0.0, 1.0)
	_set_state(State.ACTIVE if health > 0.0 else State.KNOCKED_OUT)
	health_changed.emit(health, max_health)
	revived.emit()


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)
