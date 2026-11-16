extends Area3D
## Applies a knockback impulse to any body that steps on it and supports
## `apply_knockback(impulse: Vector3)` (duck-typed, works for NPCs later).

## Impulse in N·s. 80 kg player: 600 → 7.5 m/s.
@export var impulse_strength: float = 600.0
## Launch direction in local space (normalised on use).
@export var local_direction: Vector3 = Vector3(0.0, 0.6, -1.0)
## Per-body cooldown in seconds.
@export var cooldown: float = 0.8
## Rigid bodies get pushed too.
@export var affect_rigid_bodies: bool = true

var _last_hit: Dictionary = {}


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var id := body.get_instance_id()
	if now - float(_last_hit.get(id, -INF)) < cooldown:
		return
	_last_hit[id] = now
	var impulse := global_basis * local_direction.normalized() * impulse_strength
	if body.has_method(&"apply_knockback"):
		body.call(&"apply_knockback", impulse)
	elif affect_rigid_bodies and body is RigidBody3D:
		var rigid := body as RigidBody3D
		rigid.apply_central_impulse(impulse * rigid.mass / 80.0)
