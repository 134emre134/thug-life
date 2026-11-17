class_name PlayerMovement
extends Node
## Ground locomotion for a CharacterBody3D: walk / run / sprint with
## acceleration, slopes, stair stepping, jumping, rigid body pushing and
## knockback. Driven each physics tick through [method physics_update] with an
## [PlayerMovement.Intent], so it does not read input or know about cameras.

signal jumped
signal landed(fall_speed: float)

enum Gait { IDLE, WALK, RUN, SPRINT, STRAFE }


## What the controller wants to do this tick.
class Intent:
	## World-space desired direction, length 0..1 (analog).
	var move_direction := Vector3.ZERO
	var walk := false
	var sprint := false
	var jump := false
	## Strafe mode (aiming): face [member face_yaw] instead of the move direction.
	var strafe := false
	var face_yaw := 0.0
	## Drive the horizontal velocity directly (lunges, dodges) instead of
	## accelerating toward [member move_direction].
	var use_velocity_override := false
	var velocity_override := Vector3.ZERO


@export var body: CharacterBody3D
## Visual node that turns toward the movement / aim direction.
@export var model: Node3D

@export_group("Speeds (m/s)")
@export var walk_speed: float = 2.0
@export var run_speed: float = 4.5
@export var sprint_speed: float = 7.0
@export var strafe_speed: float = 2.5
## Sprint only applies when moving roughly forward relative to the input.
@export_range(0.0, 1.0) var min_sprint_input: float = 0.5

@export_group("Acceleration (m/s²)")
@export var acceleration: float = 22.0
@export var deceleration: float = 30.0
@export var air_acceleration: float = 5.0

@export_group("Turning")
## Exponential turn rate toward the move direction (higher = snappier).
@export var turn_speed: float = 12.0
@export var strafe_turn_speed: float = 25.0

@export_group("Jump & gravity")
@export var jump_velocity: float = 4.8
@export var gravity_scale: float = 1.0
## Extra gravity while falling, for a less floaty arc.
@export var fall_gravity_scale: float = 1.6
@export var terminal_velocity: float = 40.0
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12

@export_group("Slopes & steps")
@export_range(0.0, 89.0) var max_slope_degrees: float = 46.0
## Max height climbed automatically (stairs, curbs).
@export var step_height: float = 0.35
## How far ahead to look for a step.
@export var step_probe_distance: float = 0.12
## Snap distance that keeps the body glued to stairs / ramps going down.
@export var floor_snap_length: float = 0.45

@export_group("Physics interaction")
## Max force (N) the player applies when walking into rigid bodies.
@export var push_force: float = 700.0
## Player mass used to convert knockback impulses into velocity.
@export var mass: float = 80.0
## Seconds of reduced control after a knockback.
@export var knockback_control_lock: float = 0.35
## Fraction of normal acceleration available during the lock.
@export_range(0.0, 1.0) var knockback_control_factor: float = 0.1

var gait: Gait = Gait.IDLE

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _knockback_timer := 0.0
var _was_on_floor := true


func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody3D
	assert(body != null, "PlayerMovement needs a CharacterBody3D")
	if model == null:
		push_warning("PlayerMovement: no model assigned, the character will not turn.")
	body.floor_max_angle = deg_to_rad(max_slope_degrees)
	body.floor_snap_length = floor_snap_length
	body.floor_constant_speed = true
	body.floor_stop_on_slope = true
	body.floor_block_on_wall = true


func physics_update(delta: float, intent: Intent) -> void:
	var on_floor := body.is_on_floor()
	_update_timers(delta, on_floor, intent.jump)

	var velocity := body.velocity
	velocity = _apply_gravity(velocity, delta, on_floor)
	velocity = _apply_horizontal(velocity, delta, intent, on_floor)

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		jumped.emit()

	body.velocity = velocity
	if on_floor and velocity.y <= 0.0:
		_try_step_up(delta)

	var pre_slide_velocity := body.velocity
	body.move_and_slide()
	_push_rigid_bodies(pre_slide_velocity, delta)
	_update_facing(delta, intent)

	var now_on_floor := body.is_on_floor()
	if now_on_floor and not _was_on_floor:
		landed.emit(-pre_slide_velocity.y)
	_was_on_floor = now_on_floor


## Adds an impulse (N·s) to the body and briefly reduces control.
func apply_knockback(impulse: Vector3) -> void:
	body.velocity += impulse / mass
	_knockback_timer = knockback_control_lock
	_coyote_timer = 0.0


func get_horizontal_speed() -> float:
	return Vector2(body.velocity.x, body.velocity.z).length()


func is_knocked_back() -> bool:
	return _knockback_timer > 0.0


func _update_timers(delta: float, on_floor: bool, jump_pressed: bool) -> void:
	_coyote_timer = coyote_time if on_floor else maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = jump_buffer_time if jump_pressed else maxf(_jump_buffer_timer - delta, 0.0)
	_knockback_timer = maxf(_knockback_timer - delta, 0.0)


func _apply_gravity(velocity: Vector3, delta: float, on_floor: bool) -> Vector3:
	if on_floor and velocity.y <= 0.0:
		return velocity
	var scale := fall_gravity_scale if velocity.y < 0.0 else gravity_scale
	velocity.y = maxf(velocity.y - _gravity * scale * delta, -terminal_velocity)
	return velocity


func _apply_horizontal(velocity: Vector3, delta: float, intent: Intent, on_floor: bool) -> Vector3:
	if intent.use_velocity_override:
		gait = Gait.IDLE if intent.velocity_override.length_squared() < 0.01 else Gait.RUN
		velocity.x = intent.velocity_override.x
		velocity.z = intent.velocity_override.z
		return velocity

	var input_strength := clampf(intent.move_direction.length(), 0.0, 1.0)
	var direction := intent.move_direction.normalized() if input_strength > 0.01 else Vector3.ZERO

	var target_speed := run_speed
	if input_strength <= 0.01:
		gait = Gait.IDLE
	elif intent.strafe:
		gait = Gait.STRAFE
		target_speed = strafe_speed
	elif intent.sprint and input_strength >= min_sprint_input:
		gait = Gait.SPRINT
		target_speed = sprint_speed
	elif intent.walk:
		gait = Gait.WALK
		target_speed = walk_speed
	else:
		gait = Gait.RUN

	var target := direction * target_speed * input_strength
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	var rate: float
	if not on_floor:
		rate = air_acceleration
	elif target.length() > horizontal.length() or horizontal.dot(target) < 0.0:
		rate = acceleration  # speeding up or reversing
	else:
		rate = deceleration
	if _knockback_timer > 0.0:
		rate *= knockback_control_factor

	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	return velocity


## Lifts the body onto steps up to [member step_height] that block movement.
## Slopes are left to move_and_slide; rigid bodies are pushed, not climbed.
func _try_step_up(delta: float) -> void:
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if horizontal.length_squared() < 0.01:
		return
	var probe := horizontal.normalized() * maxf(horizontal.length() * delta, step_probe_distance)
	var from := body.global_transform
	var hit := KinematicCollision3D.new()

	# 1. Something must block us, and it must be a wall (not a walkable slope).
	if not body.test_move(from, probe, hit):
		return
	if hit.get_normal().angle_to(Vector3.UP) <= body.floor_max_angle:
		return
	if hit.get_collider() is RigidBody3D:
		return

	# 2. Move up (limited by ceilings), then forward must be free.
	var up := Vector3.UP * step_height
	if body.test_move(from, up, hit):
		up = hit.get_travel()
	if up.y < 0.05:
		return
	var raised := from.translated(up)
	if body.test_move(raised, probe):
		return

	# 3. Come back down onto a walkable surface.
	var ahead := raised.translated(probe)
	if not body.test_move(ahead, Vector3.DOWN * (up.y + 0.05), hit):
		return
	if hit.get_normal().angle_to(Vector3.UP) > body.floor_max_angle:
		return
	var rise := up.y + hit.get_travel().y
	if rise <= 0.01:
		return
	body.global_position.y += rise


func _push_rigid_bodies(pre_slide_velocity: Vector3, delta: float) -> void:
	for i in body.get_slide_collision_count():
		var collision := body.get_slide_collision(i)
		var rigid := collision.get_collider() as RigidBody3D
		if rigid == null or rigid.freeze:
			continue
		var direction := -collision.get_normal()
		direction.y = 0.0
		if direction.length_squared() < 0.0001:
			continue  # standing on it
		direction = direction.normalized()
		var speed_into := pre_slide_velocity.dot(direction)
		var relative := speed_into - rigid.linear_velocity.dot(direction)
		if relative <= 0.0:
			continue
		# Never push harder than needed to match our speed, never above push_force.
		var impulse := minf(push_force * delta, rigid.mass * relative)
		rigid.apply_impulse(direction * impulse, collision.get_position() - rigid.global_position)


func _update_facing(delta: float, intent: Intent) -> void:
	if model == null:
		return
	var target_yaw: float
	var speed: float
	if intent.strafe:
		target_yaw = intent.face_yaw
		speed = strafe_turn_speed
	else:
		var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
		if intent.move_direction.length_squared() < 0.0001 or horizontal.length_squared() < 0.04:
			return
		target_yaw = atan2(-horizontal.x, -horizontal.z)
		speed = turn_speed
	model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 1.0 - exp(-speed * delta))
