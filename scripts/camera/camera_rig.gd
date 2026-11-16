class_name CameraRig
extends Node3D
## Over-the-shoulder camera rig.
##
## Structure: CameraRig (top_level) -> Yaw -> Pitch -> SpringArm3D -> Camera3D.
## Follows the target in _process. The target's position is sampled every
## physics tick and interpolated by hand with the physics interpolation
## fraction, so it stays smooth at any frame rate.
##
## The SpringArm3D node holds the arm settings (shape, mask, margin) but the
## collision sweep is done here in _process instead of by the node's own
## physics-tick update: mixing a physics-rate arm with a frame-rate rig is a
## classic source of camera jitter. Two sweeps are done: pivot -> shoulder
## (keeps the side offset out of walls in narrow corridors) and
## shoulder -> camera (the regular spring arm).
##
## Camera shake uses a "trauma" value (0..1) that decays over time; the
## offset grows with trauma². It is applied to the Camera3D only, after the
## collision sweep.

## Node to follow (usually the Player).
@export var target: Node3D

@export_group("Follow")
## Height of the pivot above the target origin.
@export var pivot_height: float = 1.55
## Vertical smoothing (stairs, steps). Higher = tighter.
@export var vertical_follow_speed: float = 14.0
## Max vertical lag before the camera is pulled along (falls, knockback).
@export var max_vertical_lag: float = 0.6

@export_group("Look")
## Radians per pixel of mouse motion.
@export var mouse_sensitivity: float = 0.0025
@export var invert_y: bool = false
@export_range(-89.0, 0.0) var min_pitch_degrees: float = -70.0
@export_range(0.0, 89.0) var max_pitch_degrees: float = 60.0

@export_group("Framing: normal")
@export var normal_distance: float = 3.2
@export var normal_shoulder_offset: float = 0.55
@export var normal_height_offset: float = 0.05
@export var normal_fov: float = 70.0

@export_group("Framing: aim")
@export var aim_distance: float = 1.5
@export var aim_shoulder_offset: float = 0.65
@export var aim_height_offset: float = 0.1
@export var aim_fov: float = 50.0
## Duration of the normal <-> aim tween.
@export var aim_transition_time: float = 0.18

@export_group("Shoulder")
## Start on the right shoulder (true) or left (false).
@export var start_on_right: bool = true
@export var shoulder_swap_time: float = 0.25

@export_group("Collision")
## Distance kept between the camera probe and geometry.
@export var collision_margin: float = 0.1
## How fast the arm extends again after an obstruction clears (m/s).
@export var arm_return_speed: float = 10.0

@export_group("Shake")
## Max rotation offset at full trauma (degrees: pitch, yaw, roll).
@export var shake_max_degrees: Vector3 = Vector3(2.5, 2.5, 3.5)
## Max position offset at full trauma (metres, camera space).
@export var shake_max_offset: float = 0.06
## Trauma lost per second.
@export var shake_decay: float = 1.8
## Noise speed (higher = more jittery).
@export var shake_frequency: float = 22.0

## Current yaw in radians (0 = looking toward -Z).
var yaw: float = 0.0
## Current pitch in radians.
var pitch: float = -0.15

var _aim_blend: float = 0.0
var _aim_goal: float = 0.0
var _shoulder_side: float = 1.0
var _target_side: float = 1.0
var _current_distance: float = 0.0
var _aim_tween: Tween
var _shoulder_tween: Tween
var _exclude: Array[RID] = []
var _probe := PhysicsShapeQueryParameters3D.new()
var _target_prev := Vector3.ZERO
var _target_curr := Vector3.ZERO
var _trauma: float = 0.0
var _shake_time: float = 0.0
var _shake_noise := FastNoiseLite.new()

@onready var spring_arm: SpringArm3D = $Yaw/Pitch/SpringArm3D
@onready var camera: Camera3D = $Yaw/Pitch/SpringArm3D/Camera3D
@onready var _yaw_node: Node3D = $Yaw
@onready var _pitch_node: Node3D = $Yaw/Pitch


func _ready() -> void:
	if target == null:
		target = get_parent() as Node3D
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# We sweep ourselves (see class docs); keep the node only as data holder.
	spring_arm.process_mode = Node.PROCESS_MODE_DISABLED
	spring_arm.spring_length = 0.0
	if spring_arm.shape == null:
		var sphere := SphereShape3D.new()
		sphere.radius = 0.2
		spring_arm.shape = sphere
	_probe.shape = spring_arm.shape
	_probe.collision_mask = spring_arm.collision_mask
	_shoulder_side = 1.0 if start_on_right else -1.0
	_target_side = _shoulder_side
	_current_distance = normal_distance
	if target:
		_target_prev = target.global_position
		_target_curr = _target_prev
		global_position = target.global_position + Vector3.UP * pivot_height
		yaw = target.global_rotation.y
	_update_rig(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := (event as InputEventMouseMotion).screen_relative
		yaw = wrapf(yaw - motion.x * mouse_sensitivity, -PI, PI)
		var y_sign := -1.0 if invert_y else 1.0
		pitch = clampf(
			pitch - motion.y * mouse_sensitivity * y_sign,
			deg_to_rad(min_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)


func _physics_process(_delta: float) -> void:
	# Runs after the parent body moved this tick (parents process before children).
	if target:
		_target_prev = _target_curr
		_target_curr = target.global_position


func _process(delta: float) -> void:
	_follow_target(delta)
	_update_rig(delta)


func add_collision_exception(rid: RID) -> void:
	if not _exclude.has(rid):
		_exclude.append(rid)
	_probe.exclude = _exclude


func set_aiming(aiming: bool) -> void:
	var goal := 1.0 if aiming else 0.0
	var tween_running := _aim_tween != null and _aim_tween.is_running()
	if is_equal_approx(goal, _aim_blend) or (tween_running and _aim_goal == goal):
		return
	_aim_goal = goal
	if _aim_tween:
		_aim_tween.kill()
	var duration := aim_transition_time * absf(goal - _aim_blend)
	_aim_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_aim_tween.tween_property(self, "_aim_blend", goal, duration)


## Adds camera shake trauma (0..1, clamped).
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func get_trauma() -> float:
	return _trauma


func swap_shoulder() -> void:
	_target_side = -_target_side
	if _shoulder_tween:
		_shoulder_tween.kill()
	var duration := shoulder_swap_time * absf(_target_side - _shoulder_side) * 0.5
	_shoulder_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_shoulder_tween.tween_property(self, "_shoulder_side", _target_side, duration)


func is_right_shoulder() -> bool:
	return _target_side > 0.0


## Basis containing only the yaw; use to make input camera-relative.
func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func _follow_target(delta: float) -> void:
	if target == null:
		return
	var fraction := Engine.get_physics_interpolation_fraction()
	var goal := _target_prev.lerp(_target_curr, fraction) + Vector3.UP * pivot_height
	var pos := global_position
	pos.x = goal.x
	pos.z = goal.z
	pos.y = lerpf(pos.y, goal.y, 1.0 - exp(-vertical_follow_speed * delta))
	pos.y = clampf(pos.y, goal.y - max_vertical_lag, goal.y + max_vertical_lag)
	global_position = pos


func _update_rig(delta: float) -> void:
	_yaw_node.rotation = Vector3(0.0, yaw, 0.0)
	_pitch_node.rotation = Vector3(pitch, 0.0, 0.0)

	var shoulder := lerpf(normal_shoulder_offset, aim_shoulder_offset, _aim_blend) * _shoulder_side
	var height := lerpf(normal_height_offset, aim_height_offset, _aim_blend)
	var distance := lerpf(normal_distance, aim_distance, _aim_blend)
	camera.fov = lerpf(normal_fov, aim_fov, _aim_blend)

	var pivot := _pitch_node.global_transform
	# Sweep 1: pivot -> shoulder point.
	var side_offset := pivot.basis * Vector3(shoulder, height, 0.0)
	var side_fraction := _sweep(pivot.origin, side_offset)
	var arm_origin := Vector3(shoulder, height, 0.0) * side_fraction

	# Sweep 2: shoulder point -> camera (backwards, +Z in pitch space).
	var back := pivot.basis.z * distance
	var allowed := distance * _sweep(pivot * arm_origin, back)
	if allowed < _current_distance or delta <= 0.0:
		_current_distance = allowed  # snap in immediately: never clip
	else:
		_current_distance = minf(_current_distance + arm_return_speed * delta, allowed)

	spring_arm.position = arm_origin
	camera.position = Vector3(0.0, 0.0, _current_distance)
	_apply_shake(delta)


func _apply_shake(delta: float) -> void:
	_trauma = maxf(_trauma - shake_decay * delta, 0.0)
	if _trauma <= 0.0:
		camera.rotation = Vector3.ZERO
		return
	_shake_time += delta * shake_frequency
	var amount := _trauma * _trauma
	var n := func(channel: int) -> float:
		return _shake_noise.get_noise_2d(_shake_time, channel * 100.0)
	camera.rotation = (
		Vector3(
			deg_to_rad(shake_max_degrees.x) * n.call(0),
			deg_to_rad(shake_max_degrees.y) * n.call(1),
			deg_to_rad(shake_max_degrees.z) * n.call(2)
		)
		* amount
	)
	camera.position += Vector3(n.call(3), n.call(4), 0.0) * shake_max_offset * amount


## Returns the free fraction [0, 1] of [param motion] starting at [param from],
## shortened by [member collision_margin].
func _sweep(from: Vector3, motion: Vector3) -> float:
	var length := motion.length()
	if length < 0.001 or not is_inside_tree():
		return 1.0
	_probe.transform = Transform3D(Basis(), from)
	_probe.motion = motion
	var result := get_world_3d().direct_space_state.cast_motion(_probe)
	var safe: float = result[0] if result.size() > 0 else 1.0
	if safe >= 1.0:
		return 1.0
	return clampf((safe * length - collision_margin) / length, 0.0, 1.0)
