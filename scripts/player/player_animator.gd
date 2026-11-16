class_name PlayerAnimator
extends Node
## Feeds movement state into an AnimationTree.
##
## Expected tree (see player.tscn):
##   locomotion : BlendSpace1D, blend position = horizontal speed (m/s)
##   strafe     : BlendSpace2D, blend position = local velocity (x = right, y = forward, m/s)
##   aim_blend  : Blend2, 0 = locomotion, 1 = strafe
##   air_blend  : Blend2, 0 = grounded, 1 = in-air pose
## Blend space points are placed at the speed each clip was authored for,
## which keeps feet from sliding. When swapping in a new model (e.g. Mixamo),
## keep these parameter names and re-place the points at the new clips' speeds.

const PARAM_LOCOMOTION := &"parameters/locomotion/blend_position"
const PARAM_STRAFE := &"parameters/strafe/blend_position"
const PARAM_AIM := &"parameters/aim_blend/blend_amount"
const PARAM_AIR := &"parameters/air_blend/blend_amount"

@export var animation_tree: AnimationTree
@export var body: CharacterBody3D
## Node whose orientation defines "forward" for strafing.
@export var model: Node3D
## Smoothing of blend parameters (higher = snappier).
@export var blend_smoothing: float = 12.0
@export var aim_blend_speed: float = 8.0
@export var air_blend_speed: float = 6.0
## Seconds off the floor before the in-air pose blends in (ignores small steps).
@export var air_delay: float = 0.15

var _speed: float = 0.0
var _strafe := Vector2.ZERO
var _aim: float = 0.0
var _air: float = 0.0
var _air_time: float = 0.0


func update(delta: float, aiming: bool) -> void:
	if animation_tree == null or body == null or model == null:
		return
	var velocity := body.get_real_velocity()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var local := model.global_basis.inverse() * horizontal
	var t := 1.0 - exp(-blend_smoothing * delta)

	_speed = lerpf(_speed, horizontal.length(), t)
	_strafe = _strafe.lerp(Vector2(local.x, -local.z), t)
	_aim = move_toward(_aim, 1.0 if aiming else 0.0, aim_blend_speed * delta)
	_air_time = 0.0 if body.is_on_floor() else _air_time + delta
	_air = move_toward(_air, 1.0 if _air_time > air_delay else 0.0, air_blend_speed * delta)

	animation_tree.set(PARAM_LOCOMOTION, _speed)
	animation_tree.set(PARAM_STRAFE, _strafe)
	animation_tree.set(PARAM_AIM, _aim)
	animation_tree.set(PARAM_AIR, _air)
