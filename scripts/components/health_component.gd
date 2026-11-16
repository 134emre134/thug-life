class_name HealthComponent
extends Node
## Health and knocked-out state. Knocked out is the only "defeated" state in
## M2 (lethality is still open, GDD §7).

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node3D)
## The victim reached 0 health. [param by] is whoever dealt the last hit.
signal knocked_out(victim: Node3D, by: Node3D)
signal revived

@export var max_health: float = 100.0
## Node reported as the victim in signals. Defaults to the parent.
@export var body: Node3D

var health: float = 0.0

var _knocked_out: bool = false


func _ready() -> void:
	if body == null:
		body = get_parent() as Node3D
	health = max_health


func is_knocked_out() -> bool:
	return _knocked_out


func get_fraction() -> float:
	return health / max_health if max_health > 0.0 else 0.0


func take_damage(amount: float, source: Node3D) -> void:
	if _knocked_out or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	damaged.emit(amount, source)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_knocked_out = true
		knocked_out.emit(body, source)


## Restores health (as a fraction of [member max_health]) and clears the
## knocked-out state.
func revive(fraction: float = 1.0) -> void:
	health = max_health * clampf(fraction, 0.0, 1.0)
	_knocked_out = health <= 0.0
	health_changed.emit(health, max_health)
	revived.emit()
