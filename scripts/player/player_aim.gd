class_name PlayerAim
extends Node
## Aim state and aim target.
##
## The aim target is a ray from the camera centre. The ray starts at the point
## of the camera ray closest to the character, so geometry *between* camera
## and character (e.g. a cover edge the camera peeks around) is ignored.
## A second ray from the aim origin (chest) to that point reports whether
## something is in the way of a shot ([member is_obstructed]); the HUD shows
## this as a separate marker.

signal aiming_changed(aiming: bool)

## Height of the aim origin (chest / shoulder) above the body origin.
@export var origin_height: float = 1.45
## Max aim distance in metres.
@export var max_distance: float = 250.0
## Layers the aim ray hits (world, props, npc by default).
@export_flags_3d_physics var collision_mask: int = 1 | 4 | 16
## Draw a small marker at the aim point.
@export var debug_draw: bool = false

var is_aiming: bool = false
## World-space point under the crosshair.
var aim_point: Vector3 = Vector3.ZERO
## Surface normal at [member aim_point] (zero if nothing was hit).
var aim_normal: Vector3 = Vector3.ZERO
## True if a line from the aim origin to [member aim_point] is blocked.
var is_obstructed: bool = false
## Where that line is blocked (only valid if [member is_obstructed]).
var obstructed_point: Vector3 = Vector3.ZERO

var _exclude: Array[RID] = []
var _debug_marker: MeshInstance3D


func add_collision_exception(rid: RID) -> void:
	if not _exclude.has(rid):
		_exclude.append(rid)


func update(wants_aim: bool, camera: Camera3D, origin: Vector3) -> void:
	if wants_aim != is_aiming:
		is_aiming = wants_aim
		aiming_changed.emit(is_aiming)
	_update_aim_point(camera, origin)
	_update_debug()


func _update_aim_point(camera: Camera3D, origin: Vector3) -> void:
	var space := camera.get_world_3d().direct_space_state
	var center := camera.get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(center)
	var ray_dir := camera.project_ray_normal(center)

	# Skip everything between the camera and the character's depth.
	var start := ray_origin + ray_dir * maxf(ray_dir.dot(origin - ray_origin), 0.0)
	var end := ray_origin + ray_dir * max_distance
	var hit := _raycast(space, start, end)
	if hit.is_empty():
		aim_point = end
		aim_normal = Vector3.ZERO
	else:
		aim_point = hit.position
		aim_normal = hit.normal

	# Is the line of fire from the character to the aim point clear?
	var to_target := aim_point - origin
	var stop_short := to_target - to_target.normalized() * 0.05
	var block := _raycast(space, origin, origin + stop_short)
	is_obstructed = not block.is_empty()
	obstructed_point = block.position if is_obstructed else aim_point


func _raycast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, _exclude)
	query.hit_from_inside = false
	return space.intersect_ray(query)


func _update_debug() -> void:
	if not debug_draw:
		if _debug_marker:
			_debug_marker.visible = false
		return
	if _debug_marker == null:
		_debug_marker = MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.05
		mesh.height = 0.1
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.RED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		mesh.material = material
		_debug_marker.mesh = mesh
		_debug_marker.top_level = true
		add_child(_debug_marker)
	_debug_marker.visible = is_aiming
	_debug_marker.global_position = aim_point
