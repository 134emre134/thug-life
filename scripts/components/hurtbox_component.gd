class_name HurtboxComponent
extends Area3D
## The volume where a character can be hit (detection only, layer 7 "hurtbox").
## Needs a CollisionShape3D child.
##
## Hits are passed to [member receiver] (usually the character's [MeleeCombat]),
## which resolves guard, dodge and reactions. Without a receiver the damage goes
## straight to [member health] (e.g. a breakable prop).

## Outcome of a hit, as reported back to the attacker. Everything from
## [code]GUARD_BROKEN[/code] up counts as a landed hit.
## [code]DOWNED_HIT[/code]: hit on a knocked-out body (downed damage).
enum HitResult { IGNORED, DODGED, BLOCKED, GUARD_BROKEN, HIT, KNOCKED_OUT, DOWNED_HIT, KILLED }

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

## While set, the hurtbox stays over this node horizontally (e.g. the root
## body of a knockout ragdoll), so a body on the ground can still be hit.
var follow: Node3D = null:
	set(value):
		follow = value
		if follow == null:
			position = Vector3.ZERO

var _capsule: CapsuleShape3D = null
var _stand_height: float = 0.0
var _stand_y: float = 0.0


func _ready() -> void:
	if body == null:
		body = get_parent() as Node3D
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = enabled


func _physics_process(_delta: float) -> void:
	if follow == null:
		return
	if not is_instance_valid(follow):
		follow = null
		return
	var point := follow.global_position
	global_position = Vector3(point.x, body.global_position.y, point.z)


## Shrinks the capsule to [param height] (crouching, M4b: low cover hides the
## body from shots), keeping its bottom where it is. A height <= 0 restores
## the scene's capsule.
func set_height(height: float) -> void:
	var collision := _get_collision()
	if collision == null or not collision.shape is CapsuleShape3D:
		return
	if _capsule == null:
		# Own copy: the scene's shape resource is shared between instances.
		_capsule = (collision.shape as CapsuleShape3D).duplicate()
		_stand_height = _capsule.height
		_stand_y = collision.position.y
		collision.shape = _capsule
	var target := _stand_height if height <= 0.0 else minf(height, _stand_height)
	_capsule.height = target
	collision.position.y = _stand_y - (_stand_height - target) * 0.5


## Current capsule height (the scene's when never changed).
func get_height() -> float:
	if _capsule != null:
		return _capsule.height
	var collision := _get_collision()
	if collision != null and collision.shape is CapsuleShape3D:
		return (collision.shape as CapsuleShape3D).height
	return 0.0


func can_be_hit() -> bool:
	return enabled and (health == null or health.can_take_damage())


## Point used for line-of-sight checks (centre of the shape).
func get_center() -> Vector3:
	var collision := _get_collision()
	return collision.global_position if collision != null else global_position


func receive_hit(attacker: Node3D, attack: AttackData, direction: Vector3) -> HitResult:
	if not can_be_hit():
		return HitResult.IGNORED
	if receiver != null and receiver.has_method(&"receive_hit"):
		return receiver.call(&"receive_hit", attacker, attack, direction)
	if health == null:
		return HitResult.IGNORED
	var was_down := health.is_down()
	health.take_damage(attack.damage, attacker, attack)
	if health.is_dead():
		return HitResult.KILLED
	if was_down:
		return HitResult.DOWNED_HIT
	return HitResult.KNOCKED_OUT if health.is_knocked_out() else HitResult.HIT


func _get_collision() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child
	return null
