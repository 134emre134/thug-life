class_name RagdollComponent
extends Node
## Knockout ragdoll built from the model's parts.
##
## On [method activate] the model is hidden and every segment pivot listed in
## [member segments] becomes a RigidBody3D carrying copies of its meshes, joined
## to its nearest parent segment with a cone-twist joint at the pivot.
## Works with any node-hierarchy model (the primitive mannequin). A skinned
## Mixamo model would use PhysicalBoneSimulator3D instead; keep the
## activate/deactivate API so callers don't change.

@export var model: Node3D
## Segment pivots, relative to [member model]. The first one is the root.
@export var segments: Array[NodePath] = []
@export var total_mass: float = 70.0
@export_flags_3d_physics var collision_layer: int = 1 << 7  # layer 8 "ragdoll"
@export_flags_3d_physics var collision_mask: int = 1 | 1 << 2 | 1 << 7
@export var linear_damp: float = 0.1
@export var angular_damp: float = 1.5
## Joint limits.
@export var swing_degrees: float = 55.0
@export var twist_degrees: float = 25.0
## Shapes are shrunk by this factor so neighbouring segments don't start overlapping.
@export_range(0.5, 1.0) var shape_scale: float = 0.9
## Index into [member segments] that takes the extra topple impulse (chest).
@export var impulse_segment: int = 1
## Share of the impulse applied at the top of [member impulse_segment] (topples).
@export_range(0.0, 1.0) var topple_share: float = 0.35
## Minimum topple impulse (N·s) at the chest, so even a weak final hit makes
## the body collapse instead of balancing on its legs. Pushes backwards when
## the hit has no direction.
@export var min_topple_impulse: float = 45.0
## Segments longer than this ratio (length / thickness) get a capsule, which
## rolls instead of standing on flat ends.
@export var capsule_min_aspect: float = 1.8

var is_active: bool = false

var _container: Node3D = null
var _bodies: Array[RigidBody3D] = []


## Spawns the ragdoll in the model's current pose. [param impulse] (N·s) is
## spread over the whole ragdoll; [param velocity] is the character's velocity.
func activate(impulse: Vector3 = Vector3.ZERO, velocity: Vector3 = Vector3.ZERO) -> void:
	if is_active or model == null or segments.is_empty():
		return
	is_active = true
	_container = Node3D.new()
	_container.name = "RagdollBodies"
	_container.top_level = true
	add_child(_container)
	_container.global_transform = Transform3D.IDENTITY

	var pivots: Array[Node3D] = []
	for path in segments:
		pivots.append(model.get_node(path) as Node3D)
	var volumes: Array[float] = []
	var total_volume := 0.0
	for pivot in pivots:
		var body := _build_segment(pivot, pivots)
		_bodies.append(body)
		var volume := _shape_volume(body)
		volumes.append(volume)
		total_volume += volume
	for i in _bodies.size():
		_bodies[i].mass = maxf(total_mass * volumes[i] / maxf(total_volume, 0.0001), 0.5)
	for i in range(1, pivots.size()):
		var parent_index := _parent_segment(pivots[i], pivots)
		if parent_index >= 0:
			_join(_bodies[parent_index], _bodies[i], pivots[i].global_position)

	model.visible = false
	for i in _bodies.size():
		var body := _bodies[i]
		body.linear_velocity = velocity
		body.apply_central_impulse(impulse * body.mass / total_mass * (1.0 - topple_share))
	if impulse_segment >= 0 and impulse_segment < _bodies.size():
		var chest := _bodies[impulse_segment]
		var topple := impulse * topple_share
		topple.y = 0.0
		if topple.length() < min_topple_impulse:
			var direction := topple.normalized() if topple.length() > 0.01 else model.global_basis.z
			direction.y = 0.0
			topple = direction.normalized() * min_topple_impulse
		chest.apply_impulse(
			topple + Vector3.UP * impulse.y * topple_share, chest.global_basis.y * 0.3
		)


## Removes the ragdoll and shows the model again.
func deactivate() -> void:
	if _container != null:
		_container.queue_free()
		_container = null
	_bodies.clear()
	if model != null:
		model.visible = true
	is_active = false


## Root body of the ragdoll (null when inactive).
func get_root_body() -> RigidBody3D:
	return _bodies[0] if not _bodies.is_empty() else null


func _build_segment(pivot: Node3D, pivots: Array[Node3D]) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	body.linear_damp = linear_damp
	body.angular_damp = angular_damp
	_container.add_child(body)
	var pivot_xform := pivot.global_transform.orthonormalized()
	body.global_transform = pivot_xform

	var bounds := AABB()
	var has_bounds := false
	for mesh_instance in _collect_meshes(pivot, pivots):
		var local := pivot_xform.affine_inverse() * mesh_instance.global_transform
		var copy := MeshInstance3D.new()
		copy.mesh = mesh_instance.mesh
		copy.material_override = mesh_instance.material_override
		copy.transform = local
		body.add_child(copy)
		var box := local * mesh_instance.mesh.get_aabb()
		bounds = bounds.merge(box) if has_bounds else box
		has_bounds = true
	if not has_bounds:
		bounds = AABB(Vector3.ONE * -0.05, Vector3.ONE * 0.1)

	var collision := CollisionShape3D.new()
	collision.shape = _fit_shape(bounds.size * shape_scale, collision)
	collision.position = bounds.get_center()
	body.add_child(collision)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = bounds.get_center()
	body.reset_physics_interpolation()
	return body


## Visible meshes under [param pivot], not descending into other segments.
func _collect_meshes(pivot: Node, pivots: Array[Node3D]) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in pivot.get_children():
		if child is Node3D and pivots.has(child):
			continue
		if child.is_queued_for_deletion():
			continue
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			if (child as MeshInstance3D).visible:
				result.append(child)
		result.append_array(_collect_meshes(child, pivots))
	return result


func _parent_segment(pivot: Node3D, pivots: Array[Node3D]) -> int:
	var node := pivot.get_parent()
	while node != null and node != model.get_parent():
		var index := pivots.find(node as Node3D) if node is Node3D else -1
		if index >= 0:
			return index
		node = node.get_parent()
	return 0 if pivots[0] != pivot else -1


func _join(parent_body: RigidBody3D, child_body: RigidBody3D, at: Vector3) -> void:
	var joint := ConeTwistJoint3D.new()
	_container.add_child(joint)
	# The cone axis (local X) points along the child limb.
	var axis := child_body.global_transform * child_body.center_of_mass - at
	axis = axis.normalized() if axis.length_squared() > 0.0001 else Vector3.DOWN
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var z := axis.cross(up).normalized()
	var y := z.cross(axis).normalized()
	joint.global_transform = Transform3D(Basis(axis, y, z), at)
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(swing_degrees))
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(twist_degrees))
	joint.node_a = joint.get_path_to(parent_body)
	joint.node_b = joint.get_path_to(child_body)


## Capsule along the longest axis for long segments (limbs), box otherwise.
## Rotates [param collision] to match.
func _fit_shape(size: Vector3, collision: CollisionShape3D) -> Shape3D:
	size = size.max(Vector3.ONE * 0.04)
	var axis := size.max_axis_index()
	var length := size[axis]
	var thickness := maxf(size[(axis + 1) % 3], size[(axis + 2) % 3])
	if length < thickness * capsule_min_aspect:
		var box := BoxShape3D.new()
		box.size = size
		return box
	var capsule := CapsuleShape3D.new()
	capsule.radius = thickness * 0.5
	capsule.height = length
	# Capsules extend along local Y.
	if axis == Vector3.AXIS_X:
		collision.rotation = Vector3(0.0, 0.0, PI * 0.5)
	elif axis == Vector3.AXIS_Z:
		collision.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	return capsule


func _shape_volume(body: RigidBody3D) -> float:
	for child in body.get_children():
		var collision := child as CollisionShape3D
		if collision == null:
			continue
		if collision.shape is BoxShape3D:
			var size := (collision.shape as BoxShape3D).size
			return size.x * size.y * size.z
		if collision.shape is CapsuleShape3D:
			var capsule := collision.shape as CapsuleShape3D
			return PI * capsule.radius * capsule.radius * capsule.height
	return 0.001
