class_name HurtboxComponent
extends Area3D
## The volume where a character can be hit (detection only, layer 7 "hurtbox").
## Needs a CollisionShape3D child.
##
## Hits are passed to [member receiver] (usually the character's [MeleeCombat]),
## which resolves guard, dodge and reactions. Without a receiver the damage goes
## straight to [member health] (e.g. a breakable prop).

## Outcome of a hit, as reported back to the attacker.
enum HitResult { IGNORED, DODGED, BLOCKED, GUARD_BROKEN, HIT, KNOCKED_OUT }

const LAYER := 1 << 6  # physics layer 7 "hurtbox"

@export var health: HealthComponent
## Resolves hits: needs [code]receive_hit(attacker: Node3D, attack: AttackData,
## direction: Vector3) -> HitResult[/code]. Optional.
@export var receiver: Node
## Hits from the same team are ignored (no friendly fire).
@export var team: StringName = &""
## The character this hurtbox belongs to. Defaults to the parent.
@export var body: Node3D
## Disabled hurtboxes can't be hit.
@export var enabled: bool = true:
	set(value):
		enabled = value
		set_deferred(&"monitorable", value)


func _ready() -> void:
	if body == null:
		body = get_parent() as Node3D
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = enabled


func can_be_hit() -> bool:
	return enabled and (health == null or not health.is_knocked_out())


## Point used for line-of-sight checks (centre of the shape).
func get_center() -> Vector3:
	for child in get_children():
		if child is CollisionShape3D:
			return (child as CollisionShape3D).global_position
	return global_position


func receive_hit(attacker: Node3D, attack: AttackData, direction: Vector3) -> HitResult:
	if not can_be_hit():
		return HitResult.IGNORED
	if receiver != null and receiver.has_method(&"receive_hit"):
		return receiver.call(&"receive_hit", attacker, attack, direction)
	if health == null:
		return HitResult.IGNORED
	health.take_damage(attack.damage, attacker, attack)
	return HitResult.KNOCKED_OUT if health.is_knocked_out() else HitResult.HIT
