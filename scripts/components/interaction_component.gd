class_name InteractionComponent
extends Area3D
## Finds the best [Interactable] around its owner and triggers it.
##
## Needs a CollisionShape3D child that defines the search volume. Candidates
## are scored by how closely they match the view direction and how close they
## are; objects behind walls are rejected with a line-of-sight check.

## Emitted when the best target changes (null = no target).
signal target_changed(target: Interactable)

## Max angle between the view direction and the target (horizontal).
@export_range(0.0, 180.0) var max_angle_degrees: float = 65.0
## Within this distance the angle limit is ignored (things at your feet).
@export var close_range: float = 0.9
## Score penalty per metre of distance.
@export var distance_weight: float = 0.3
@export var require_line_of_sight: bool = true
## Layers that block line of sight to an interactable.
@export_flags_3d_physics var line_of_sight_mask: int = 1

var current_target: Interactable = null

var _exclude: Array[RID] = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = Interactable.LAYER_INTERACTABLE
	monitoring = true
	monitorable = false


func add_collision_exception(rid: RID) -> void:
	if not _exclude.has(rid):
		_exclude.append(rid)


## Re-evaluates the best target. [param view_origin] is the eye/chest point,
## [param view_direction] usually the camera forward vector.
func update(view_origin: Vector3, view_direction: Vector3) -> void:
	var best: Interactable = null
	var best_score := -INF
	var flat_view := Vector3(view_direction.x, 0.0, view_direction.z).normalized()
	var min_dot := cos(deg_to_rad(max_angle_degrees))

	for area in get_overlapping_areas():
		var candidate := area as Interactable
		if candidate == null or not _is_usable(candidate):
			continue
		if not candidate.can_interact(owner as Node3D):
			continue
		var to_target := candidate.get_focus_position() - view_origin
		var flat := Vector3(to_target.x, 0.0, to_target.z)
		var distance := to_target.length()
		var facing := flat_view.dot(flat.normalized()) if flat.length_squared() > 0.0001 else 1.0
		if distance > close_range and facing < min_dot:
			continue
		var score := facing - distance * distance_weight + candidate.focus_priority
		if score <= best_score:
			continue
		if require_line_of_sight and not _has_line_of_sight(view_origin, candidate):
			continue
		best = candidate
		best_score = score

	if best != current_target:
		if is_instance_valid(current_target):
			current_target.focus_changed.emit(false)
		current_target = best
		if best:
			best.focus_changed.emit(true)
		target_changed.emit(best)


## Uses the current target. Returns true if something was triggered.
func try_interact(interactor: Node3D) -> bool:
	if not is_instance_valid(current_target) or not _is_usable(current_target):
		return false
	if not current_target.can_interact(interactor):
		return false
	current_target.interact(interactor)
	return true


## Interactables leaving the scene (picked up, level reset) can still be in the
## overlap list for one physics tick.
func _is_usable(candidate: Interactable) -> bool:
	return candidate.is_inside_tree() and not candidate.is_queued_for_deletion()


func _has_line_of_sight(from: Vector3, candidate: Interactable) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		from, candidate.get_focus_position(), line_of_sight_mask, _exclude
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	# The object the interactable belongs to (e.g. the door leaf) doesn't count.
	var collider := hit.collider as Node
	return collider != null and (collider == candidate or collider.is_ancestor_of(candidate))
