class_name RagdollComponent
extends Node
## Knockout ragdoll on the character's skeleton (physical bones).
##
## On [method activate] a PhysicalBoneSimulator3D with one PhysicalBone3D per
## entry in [member bones] is created under the skeleton and starts simulating
## from the current animated pose. Bones without a physical bone follow their
## parent. Capsules run from each bone to [member bone_ends] (or its first
## child). Built at runtime, so the imported model scene stays untouched.

## Skeleton to ragdoll.
@export var skeleton: Skeleton3D
## Bones that get a physical body. The first one is the root (pelvis).
@export var bones: PackedStringArray = [
	"Hips",
	"Spine",
	"UpperChest",
	"Head",
	"LeftUpperArm",
	"LeftLowerArm",
	"RightUpperArm",
	"RightLowerArm",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"RightUpperLeg",
	"RightLowerLeg",
]
## Bone whose origin ends a body's capsule, when it isn't the first child.
@export var bone_ends: Dictionary = {
	"Hips": "Spine",
	"Spine": "UpperChest",
	"UpperChest": "Neck",
	"Head": "",
	"LeftLowerArm": "LeftHand",
	"RightLowerArm": "RightHand",
	"LeftLowerLeg": "LeftFoot",
	"RightLowerLeg": "RightFoot",
}
## Bones that bend like a hinge (elbows, knees); the others use cone-twist joints.
@export var hinge_bones: PackedStringArray = [
	"LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg"
]
## Capsule radius per bone (m); missing bones use [member default_radius].
@export var radii: Dictionary = {
	"Hips": 0.13,
	"Spine": 0.12,
	"UpperChest": 0.14,
	"Head": 0.1,
	"LeftUpperLeg": 0.08,
	"RightUpperLeg": 0.08,
	"LeftLowerLeg": 0.06,
	"RightLowerLeg": 0.06,
}
@export var default_radius: float = 0.05
## Length used for bones without an end bone (e.g. the head).
@export var default_length: float = 0.22
@export var total_mass: float = 70.0
@export_flags_3d_physics var collision_layer: int = 1 << 7  # layer 8 "ragdoll"
@export_flags_3d_physics var collision_mask: int = 1 | 1 << 2 | 1 << 7
@export var linear_damp: float = 0.1
@export var angular_damp: float = 1.5
## Joint limits.
@export var swing_degrees: float = 45.0
@export var twist_degrees: float = 20.0
## Index into [member bones] that takes the extra topple impulse (chest).
@export var impulse_bone: int = 2
## Share of the impulse applied at the chest (topples the body).
@export_range(0.0, 1.0) var topple_share: float = 0.35
## Minimum topple impulse (N·s) at the chest, so even a weak final hit makes
## the body collapse. Pushes backwards when the hit has no direction.
@export var min_topple_impulse: float = 45.0

var is_active: bool = false

var _simulator: PhysicalBoneSimulator3D = null
var _bodies: Array[PhysicalBone3D] = []


## Starts the ragdoll from the current pose. [param impulse] (N·s) is spread
## over the body; [param velocity] is the character's velocity.
func activate(impulse: Vector3 = Vector3.ZERO, velocity: Vector3 = Vector3.ZERO) -> void:
	if is_active or skeleton == null or bones.is_empty():
		return
	is_active = true
	_simulator = PhysicalBoneSimulator3D.new()
	_simulator.name = "Ragdoll"
	skeleton.add_child(_simulator)
	var lengths := {}
	var total_volume := 0.0
	for bone in bones:
		var index := skeleton.find_bone(bone)
		if index < 0:
			push_warning("RagdollComponent: no bone '%s'." % bone)
			continue
		var length := _bone_length(index)
		var radius: float = radii.get(bone, default_radius)
		lengths[bone] = length
		total_volume += PI * radius * radius * (length + radius)
		_bodies.append(_create_body(bone, index, length, radius))
	for body in _bodies:
		var radius: float = radii.get(String(body.bone_name), default_radius)
		var volume := PI * radius * radius * (float(lengths[String(body.bone_name)]) + radius)
		body.mass = maxf(total_mass * volume / maxf(total_volume, 0.0001), 0.5)
	_simulator.physical_bones_start_simulation()

	for body in _bodies:
		body.linear_velocity = velocity
		body.apply_central_impulse(impulse * body.mass / total_mass * (1.0 - topple_share))
	if impulse_bone >= 0 and impulse_bone < _bodies.size():
		var chest := _bodies[impulse_bone]
		var topple := Vector3(impulse.x, 0.0, impulse.z) * topple_share
		if topple.length() < min_topple_impulse:
			var direction := topple.normalized() if topple.length() > 0.01 else _backwards()
			topple = direction * min_topple_impulse
		chest.apply_impulse(topple + Vector3.UP * impulse.y * topple_share, Vector3.UP * 0.2)


## Stops the ragdoll; the skeleton follows the animation again.
func deactivate() -> void:
	if _simulator != null:
		_simulator.physical_bones_stop_simulation()
		_simulator.get_parent().remove_child(_simulator)
		_simulator.queue_free()
		_simulator = null
	_bodies.clear()
	is_active = false


## Pushes the ragdoll (N·s), spread over its bodies by mass (hits on a body
## on the ground).
func apply_impulse(impulse: Vector3) -> void:
	for body in _bodies:
		body.apply_central_impulse(impulse * body.mass / total_mass)


## Pelvis body (null when inactive).
func get_root_body() -> PhysicsBody3D:
	return _bodies[0] if not _bodies.is_empty() else null


func _create_body(bone: String, index: int, length: float, radius: float) -> PhysicalBone3D:
	var body := PhysicalBone3D.new()
	body.name = bone
	body.bone_name = bone
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	body.linear_damp = linear_damp
	body.angular_damp = angular_damp
	if hinge_bones.has(bone):
		body.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
		body.set(&"joint_constraints/angular_limit_enabled", true)
		body.set(&"joint_constraints/angular_limit_upper", 0.0)
		body.set(&"joint_constraints/angular_limit_lower", -140.0)
	else:
		body.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		body.set(&"joint_constraints/swing_span", swing_degrees)
		body.set(&"joint_constraints/twist_span", twist_degrees)
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(length, radius * 2.0 + 0.01)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	# Bones point along +Y; the capsule spans the bone.
	collision.position = Vector3(0.0, length * 0.5, 0.0)
	body.add_child(collision)
	_simulator.add_child(body)
	body.global_transform = (
		(skeleton.global_transform * skeleton.get_bone_global_pose(index)).orthonormalized()
	)
	return body


func _bone_length(index: int) -> float:
	var bone := skeleton.get_bone_name(index)
	var end_name: String = bone_ends.get(bone, "_first_child")
	var end := -1
	if end_name == "_first_child":
		var children := skeleton.get_bone_children(index)
		end = children[0] if not children.is_empty() else -1
	elif end_name != "":
		end = skeleton.find_bone(end_name)
	if end < 0:
		return default_length
	return (
		skeleton.get_bone_rest(end).origin.length()
		if skeleton.get_bone_parent(end) == index
		else (skeleton.get_bone_global_rest(end).origin.distance_to(
			skeleton.get_bone_global_rest(index).origin
		))
	)


func _backwards() -> Vector3:
	# The model faces -Z in world space after its 180° turn in the scene; the
	# skeleton's own forward is +Z, so backwards is the skeleton's -Z.
	var back := -skeleton.global_basis.z
	back.y = 0.0
	return back.normalized() if back.length_squared() > 0.0001 else Vector3.BACK


## True while the ragdoll lies with its front toward the ground (get up from
## the front, M4a). Read from the simulated skeleton pose.
func is_face_down() -> bool:
	if skeleton == null:
		return false
	var hips := _bone_point(&"Hips")
	var head := _bone_point(&"Head")
	var left := _bone_point(&"LeftUpperLeg") - _bone_point(&"RightUpperLeg")
	# Character space: left = +X, up = +Y, so left x up = forward (+Z).
	var front := left.cross(head - hips)
	return front.y < 0.0


## Horizontal world direction from the pelvis to the head (zero if unknown).
func get_head_direction() -> Vector3:
	if skeleton == null:
		return Vector3.ZERO
	var direction := _bone_point(&"Head") - _bone_point(&"Hips")
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO


func _bone_point(bone: StringName) -> Vector3:
	var index := skeleton.find_bone(bone)
	if index < 0:
		return skeleton.global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
