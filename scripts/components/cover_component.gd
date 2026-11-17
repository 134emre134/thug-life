class_name CoverComponent
extends Node
## Sticky cover (GDD §7, M4b.3), driven each physics tick through
## [method physics_update] with a [CoverComponent.Intent], like the other
## components. It doesn't read input and changes movement only by editing the
## movement intent in [method apply_to_movement].
##
## - Enter (cover button): raycasts at knee height in the move (or look)
##   direction find a wall within reach; a second ray at chest height decides
##   whether it is low cover (crouch behind it) or high cover (stand).
##   The character slides in until it sits [member wall_gap] from the wall.
## - In cover: input moves the character along the wall only, at a fixed
##   distance (a ray keeps measuring it, so there is nothing to snag on).
##   Rays beside the body find the cover's edges; the character stops there
##   instead of walking off.
## - Peek and aim: aiming behind low cover stands up and aims over it; aiming
##   at an edge of high cover steps out around it, and back in when the aim is
##   released.
## - Leave: the cover button again, holding away from the wall, sprinting,
##   jumping, any melee action, or losing the wall.
##
## The character faces the cover while in it (there are no cover clips yet:
## the crouch, idle and rifle clips stand in, see CLIPS.md).

signal cover_entered(height: Height)
signal cover_left
## Peeking around an edge of high cover: -1 left, 1 right, 0 back in cover.
signal peek_changed(side: int)

enum Height { NONE, LOW, HIGH }


## What the controller wants this tick.
class Intent:
	## Cover button pressed this tick (enter, or leave when in cover).
	var toggle := false
	## World-space movement wish (camera-relative input).
	var move_direction := Vector3.ZERO
	## Where the controller looks (used to find cover when standing still).
	var look_direction := Vector3.FORWARD
	## Aiming: stand up behind low cover, step out at an edge of high cover.
	var aim := false
	## Leave cover now (sprint, jump, melee action...).
	var leave := false


@export var body: CharacterBody3D
## Layers that count as cover (static world geometry).
@export_flags_3d_physics var cover_mask: int = 1

@export_group("Detection")
## Reach from the body's surface to a wall that can be taken as cover (m).
@export var detect_distance: float = 1.2
## Rays (degrees around the search direction) used to find a wall.
@export var detect_angles_degrees: PackedFloat32Array = PackedFloat32Array([0.0, -25.0, 25.0])
## Height of the ray that finds cover (low objects from about 0.45 m count).
@export var low_probe_height: float = 0.4
## Height of the ray that tells high cover (hides a standing character) from low.
@export var high_probe_height: float = 1.45
## Only near-vertical surfaces are cover.
@export_range(0.0, 1.0) var max_wall_normal_y: float = 0.3
## Radius of the body's capsule (kept off the wall by [member wall_gap]).
@export var body_radius: float = 0.35

@export_group("In cover")
## Space between the capsule and the wall (m).
@export var wall_gap: float = 0.08
@export var low_move_speed: float = 1.3
@export var high_move_speed: float = 1.8
## Speed of sliding into cover and of keeping the distance (m/s).
@export var snap_speed: float = 5.0
## Sliding in gives up after this long (blocked on the way).
@export var enter_max_time: float = 0.6
## The body's centre stops this far inside the cover's edge.
@export var edge_inset: float = 0.2
## An edge counts as reached within this of the stopping point.
@export var edge_margin: float = 0.06
## Holding away from the wall this long leaves cover.
@export var leave_pull_time: float = 0.3
## How directly away from the wall the input must point to count as pulling.
@export_range(0.0, 1.0) var leave_pull_dot: float = 0.7
## The wall may turn by this much and still be followed (else it is an edge).
@export var max_turn_degrees: float = 35.0

@export_group("Peek")
## How far the character steps out past an edge of high cover to aim (m).
@export var peek_offset: float = 0.75
@export var peek_speed: float = 4.0
## Peeking steps out when the body is within this of an edge (m).
@export var peek_edge_reach: float = 0.35

var height: Height = Height.NONE
## Horizontal normal of the cover, pointing from the wall to the character.
var normal: Vector3 = Vector3.ZERO
## Sliding into cover.
var entering: bool = false
## No cover beside the body on that side (relative to facing the wall).
var at_left_edge: bool = false
var at_right_edge: bool = false
## Stepped out around an edge: -1 left, 1 right, 0 none.
var peek_side: int = 0
## Aiming from cover.
var is_aiming: bool = false

var _snap_point := Vector3.ZERO
var _time: float = 0.0
var _pull_time: float = 0.0
var _velocity := Vector3.ZERO
var _peek_origin := Vector3.ZERO
var _peek_returning: bool = false
var _last_side: int = 1
var _exclude: Array[RID] = []


func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody3D
	_exclude.append(body.get_rid())


func physics_update(delta: float, intent: Intent) -> void:
	_velocity = Vector3.ZERO
	if height == Height.NONE:
		if intent.toggle:
			try_enter(intent.move_direction, intent.look_direction)
		return
	if intent.toggle or intent.leave:
		exit()
		return
	_time += delta
	is_aiming = intent.aim
	if entering:
		_update_entering(delta)
		return
	if peek_side != 0:
		_update_peek(delta, intent)
		return
	var hit := _wall_ray(body.global_position, 0.0)
	if hit.is_empty():
		exit()
		return
	var hit_normal := _flat(hit.normal)
	if hit_normal.angle_to(normal) <= deg_to_rad(max_turn_degrees):
		normal = hit_normal
	var correction := _keep_distance(hit.position, delta)
	var right := get_right()
	if intent.move_direction.dot(normal) > leave_pull_dot:
		_pull_time += delta
		if _pull_time >= leave_pull_time:
			exit()
			return
	else:
		_pull_time = 0.0
	at_left_edge = not _has_cover_at(-1, edge_inset + edge_margin)
	at_right_edge = not _has_cover_at(1, edge_inset + edge_margin)
	var along := clampf(intent.move_direction.dot(right), -1.0, 1.0) * get_move_speed()
	if absf(along) > 0.01:
		var side := 1 if along > 0.0 else -1
		_last_side = side
		if not _has_cover_at(side, edge_inset + absf(along) * delta):
			along = 0.0
	_velocity = right * along + correction
	if intent.aim and height == Height.HIGH:
		_try_peek()


## Looks for cover in [param move_direction] (or [param look_direction] when
## not moving) and slides into it. Returns false if there is none in reach.
func try_enter(move_direction: Vector3, look_direction: Vector3) -> bool:
	var forward := _flat(move_direction)
	if forward == Vector3.ZERO:
		forward = _flat(look_direction)
	if forward == Vector3.ZERO:
		return false
	var origin := body.global_position + Vector3.UP * low_probe_height
	var best := {}
	var best_distance := INF
	for angle in detect_angles_degrees:
		var direction := forward.rotated(Vector3.UP, deg_to_rad(angle))
		var hit := _ray(origin, origin + direction * (body_radius + detect_distance))
		if hit.is_empty() or absf((hit.normal as Vector3).y) > max_wall_normal_y:
			continue
		var distance := origin.distance_to(hit.position)
		if distance < best_distance:
			best_distance = distance
			best = hit
	if best.is_empty():
		return false
	normal = _flat(best.normal)
	var wall: Vector3 = best.position
	var high_origin := wall + normal * 0.3
	high_origin.y = body.global_position.y + high_probe_height
	var high_hit := _ray(high_origin, high_origin - normal * 0.6)
	height = Height.HIGH if not high_hit.is_empty() else Height.LOW
	_snap_point = wall + normal * (body_radius + wall_gap)
	_snap_point.y = body.global_position.y
	entering = true
	_time = 0.0
	_pull_time = 0.0
	peek_side = 0
	is_aiming = false
	cover_entered.emit(height)
	return true


## Leaves cover (also from code: knockdowns, respawns).
func exit() -> void:
	if height == Height.NONE:
		return
	height = Height.NONE
	entering = false
	is_aiming = false
	_velocity = Vector3.ZERO
	at_left_edge = false
	at_right_edge = false
	if peek_side != 0:
		peek_side = 0
		peek_changed.emit(0)
	cover_left.emit()


func is_in_cover() -> bool:
	return height != Height.NONE


## Direction to the right when facing the cover.
func get_right() -> Vector3:
	return (-normal).cross(Vector3.UP)


func get_move_speed() -> float:
	return low_move_speed if height == Height.LOW else high_move_speed


## Distance from the body's origin to the wall (horizontal), or -1 without a wall.
func get_wall_distance() -> float:
	if height == Height.NONE:
		return -1.0
	var hit := _wall_ray(body.global_position, 0.0)
	if hit.is_empty():
		return -1.0
	return (body.global_position - (hit.position as Vector3)).dot(normal)


## Edits the movement intent while in cover: sliding along the wall, crouching
## behind low cover (standing to aim over it), facing the wall.
func apply_to_movement(intent: PlayerMovement.Intent) -> void:
	if height == Height.NONE:
		return
	intent.use_velocity_override = true
	intent.velocity_override = _velocity
	intent.sprint = false
	intent.jump = false
	intent.crouch = height == Height.LOW and not is_aiming
	if not is_aiming:
		intent.strafe = true
		intent.face_yaw = atan2(normal.x, normal.z)


func _update_entering(delta: float) -> void:
	var offset := _snap_point - body.global_position
	offset.y = 0.0
	if offset.length() < 0.03 or _time >= enter_max_time:
		entering = false
		return
	var speed := minf(snap_speed, offset.length() / delta)
	_velocity = offset.normalized() * speed


## Steps out past the edge on the side moved toward last (or the only edge).
func _try_peek() -> void:
	var side := 0
	var left_near := not _has_cover_at(-1, peek_edge_reach)
	var right_near := not _has_cover_at(1, peek_edge_reach)
	if right_near and (_last_side == 1 or not left_near):
		side = 1
	elif left_near:
		side = -1
	if side == 0:
		return
	peek_side = side
	_peek_origin = body.global_position
	_peek_returning = false
	peek_changed.emit(side)


func _update_peek(delta: float, intent: Intent) -> void:
	_peek_returning = not intent.aim
	var goal := _peek_origin
	if not _peek_returning:
		goal += get_right() * peek_side * peek_offset
	var offset := goal - body.global_position
	offset.y = 0.0
	if _peek_returning and offset.length() < 0.03:
		peek_side = 0
		peek_changed.emit(0)
		return
	var speed := minf(peek_speed, offset.length() / delta)
	_velocity = offset.normalized() * speed if offset.length() > 0.001 else Vector3.ZERO


## Velocity along the normal that holds the body at its distance from the wall.
func _keep_distance(wall_point: Vector3, delta: float) -> Vector3:
	var distance := (body.global_position - wall_point).dot(normal)
	var error := body_radius + wall_gap - distance
	return normal * clampf(error / delta, -snap_speed, snap_speed)


## Cover beside the body, [param offset] metres to [param side] (-1 left, 1 right).
func _has_cover_at(side: int, offset: float) -> bool:
	return not _wall_ray(body.global_position + get_right() * side * offset, 0.0).is_empty()


## Ray from [param from] (at the probe height of this cover) toward the wall.
func _wall_ray(from: Vector3, extra: float) -> Dictionary:
	var probe := high_probe_height if height == Height.HIGH else low_probe_height
	var origin := Vector3(from.x, body.global_position.y + probe, from.z)
	var reach := body_radius + wall_gap + 0.4 + extra
	var hit := _ray(origin, origin - normal * reach)
	if hit.is_empty() or absf((hit.normal as Vector3).y) > max_wall_normal_y:
		return {}
	return hit


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, cover_mask, _exclude)
	return body.get_world_3d().direct_space_state.intersect_ray(query)


static func _flat(vector: Vector3) -> Vector3:
	var flat := Vector3(vector.x, 0.0, vector.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO
