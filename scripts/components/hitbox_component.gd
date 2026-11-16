class_name HitboxComponent
extends Area3D
## The damaging volume of an attack (detection only, layer 6 "hitbox").
##
## Put it under the node that turns with the character (the model), so local
## -Z is forward. [method configure] sizes and places it from an [AttackData]
## at the start of the windup, so the overlap list is ready when the active
## phase starts. While active, [method collect_hits] returns each newly
## overlapped [HurtboxComponent] once per activation.

const LAYER := 1 << 5  # physics layer 6 "hitbox"

## Layers that block a hit (no punching through walls).
@export_flags_3d_physics var line_of_sight_mask: int = 1
## Height above the attacker's origin used for the line-of-sight ray.
@export var line_of_sight_height: float = 1.3

var is_active: bool = false

var _shape: SphereShape3D
var _already_hit: Array[HurtboxComponent] = []


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = HurtboxComponent.LAYER
	monitorable = false
	monitoring = true
	var collision: CollisionShape3D = null
	for child in get_children():
		if child is CollisionShape3D:
			collision = child
			break
	if collision == null:
		collision = CollisionShape3D.new()
		add_child(collision)
	# Own copy: the shape is resized per attack and must not be shared between
	# instances of the same scene.
	_shape = SphereShape3D.new()
	_shape.radius = 0.4
	collision.shape = _shape
	collision.position = Vector3.ZERO


## Places and sizes the hitbox for [param attack] (local space of the parent).
func configure(attack: AttackData) -> void:
	position = Vector3(0.0, attack.hit_height, -attack.reach)
	_shape.radius = attack.hit_radius


func begin() -> void:
	is_active = true
	_already_hit.clear()


func end() -> void:
	is_active = false
	_already_hit.clear()


## Hurtboxes hit for the first time in this activation. Skips [param team]
## members, the attacker itself and targets behind walls.
func collect_hits(attacker: Node3D, team: StringName) -> Array[HurtboxComponent]:
	var result: Array[HurtboxComponent] = []
	if not is_active:
		return result
	for area in get_overlapping_areas():
		var hurtbox := area as HurtboxComponent
		if hurtbox == null or _already_hit.has(hurtbox) or not hurtbox.can_be_hit():
			continue
		if hurtbox.body == attacker or (team != &"" and hurtbox.team == team):
			continue
		if not _has_line_of_sight(attacker, hurtbox):
			continue
		_already_hit.append(hurtbox)
		result.append(hurtbox)
	return result


func _has_line_of_sight(attacker: Node3D, hurtbox: HurtboxComponent) -> bool:
	var from := attacker.global_position + Vector3.UP * line_of_sight_height
	var query := PhysicsRayQueryParameters3D.create(from, hurtbox.get_center(), line_of_sight_mask)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
