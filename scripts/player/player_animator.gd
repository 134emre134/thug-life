class_name PlayerAnimator
extends Node
## Feeds movement and combat state into an AnimationTree. Used by the player
## and by NPCs (same tree, res://assets/animations/humanoid_tree.tres).
##
## Expected tree:
##   locomotion   : BlendSpace1D, blend position = horizontal speed (m/s)
##   strafe       : BlendSpace2D, blend position = local velocity (x = right, y = forward, m/s)
##   aim_blend    : Blend2, 0 = locomotion, 1 = strafe (aiming and guarding)
##   air_blend    : Blend2, 0 = grounded, 1 = in-air pose
##   guard_clip   : Transition, one input per guard pose (upper body)
##   guard_blend  : Blend2 filtered to the upper body, 1 = guard pose
##   combat_clip  : Transition, one input per combat clip (input name = clip name)
##   combat_speed : TimeScale, stretches the clip to the duration combat asks for
##   combat_blend : Blend2, 0 = everything above, 1 = combat clip (full body)
## Blend space points are placed at the speed each clip was authored for,
## which keeps feet from sliding. When swapping in a new model (e.g. Mixamo),
## keep these parameter names and re-place the points at the new clips' speeds.
## Combat clip animations are looked up as "<combat_library>/<clip>".

const PARAM_LOCOMOTION := &"parameters/locomotion/blend_position"
const PARAM_STRAFE := &"parameters/strafe/blend_position"
const PARAM_AIM := &"parameters/aim_blend/blend_amount"
const PARAM_AIR := &"parameters/air_blend/blend_amount"
const PARAM_GUARD_CLIP := &"parameters/guard_clip/transition_request"
const PARAM_GUARD := &"parameters/guard_blend/blend_amount"
const PARAM_COMBAT_CLIP := &"parameters/combat_clip/transition_request"
const PARAM_COMBAT_SPEED := &"parameters/combat_speed/scale"
const PARAM_COMBAT := &"parameters/combat_blend/blend_amount"

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

@export_group("Combat layer")
## AnimationLibrary key holding the combat clips.
@export var combat_library: StringName = &"combat"
## Blend amount the combat layer starts at when a clip starts (snappy but not a pop).
@export_range(0.0, 1.0) var combat_blend_in_start: float = 0.4
## Blend per second toward the combat clip / back to locomotion.
@export var combat_blend_in_speed: float = 14.0
@export var combat_blend_out_speed: float = 6.0
@export var guard_blend_speed: float = 10.0

## Clip currently requested on the combat layer (empty = none).
var combat_clip: StringName = &""

var _speed: float = 0.0
var _strafe := Vector2.ZERO
var _aim: float = 0.0
var _air: float = 0.0
var _air_time: float = 0.0
var _guard: float = 0.0
var _guard_clip: StringName = &""
var _combat: float = 0.0
var _combat_target: float = 0.0
var _clip_elapsed: float = 0.0
var _clip_duration: float = 0.0
var _clip_switch_at: float = -1.0
var _clip_second_speed: float = 1.0
var _clip_hold: bool = false
var _combat_inputs: PackedStringArray = []
var _guard_inputs: PackedStringArray = []
var _warned: Dictionary = {}


func _ready() -> void:
	if animation_tree == null or body == null or model == null:
		push_warning(
			"PlayerAnimator: animation_tree, body or model not assigned; animation is off."
		)
		return
	_combat_inputs = _transition_inputs(&"combat_clip")
	_guard_inputs = _transition_inputs(&"guard_clip")


## [param strafing]: use the strafe blend space (aiming or guarding).
## [param guard_clip]: guard pose to show on the upper body (empty = none).
func update(delta: float, strafing: bool, guard_clip: StringName = &"") -> void:
	if animation_tree == null or body == null or model == null:
		return
	var velocity := body.get_real_velocity()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var local := model.global_basis.inverse() * horizontal
	var t := 1.0 - exp(-blend_smoothing * delta)

	_speed = lerpf(_speed, horizontal.length(), t)
	_strafe = _strafe.lerp(Vector2(local.x, -local.z), t)
	_aim = move_toward(_aim, 1.0 if strafing else 0.0, aim_blend_speed * delta)
	_air_time = 0.0 if body.is_on_floor() else _air_time + delta
	_air = move_toward(_air, 1.0 if _air_time > air_delay else 0.0, air_blend_speed * delta)

	animation_tree.set(PARAM_LOCOMOTION, _speed)
	animation_tree.set(PARAM_STRAFE, _strafe)
	animation_tree.set(PARAM_AIM, _aim)
	animation_tree.set(PARAM_AIR, _air)
	_update_guard(delta, guard_clip)
	_update_combat(delta)


## Plays [param clip] on the combat layer, stretched to [param duration]
## seconds. With [param hit_time] > 0, clip time [param hit_time] (authored
## seconds) lines up with [param hit_at] seconds and the rest of the clip fills
## the remaining time. [param hold] keeps the last frame until
## [method stop_combat_clip]; otherwise the layer fades out at the end.
func play_combat_clip(
	clip: StringName,
	duration: float,
	hit_time: float = 0.0,
	hit_at: float = 0.0,
	hold: bool = false
) -> void:
	if animation_tree == null or not _has_clip(clip, _combat_inputs):
		return
	var length := get_clip_length(clip)
	if length <= 0.0 or duration <= 0.0:
		return
	_clip_duration = duration
	_clip_elapsed = 0.0
	_clip_hold = hold
	var first_speed := length / duration
	_clip_switch_at = -1.0
	if hit_time > 0.0 and hit_time < length and hit_at > 0.0 and hit_at < duration:
		first_speed = hit_time / hit_at
		_clip_switch_at = hit_at
		_clip_second_speed = (length - hit_time) / (duration - hit_at)
	combat_clip = clip
	animation_tree.set(PARAM_COMBAT_CLIP, String(clip))
	animation_tree.set(PARAM_COMBAT_SPEED, first_speed)
	_combat_target = 1.0
	_combat = maxf(_combat, combat_blend_in_start)
	animation_tree.set(PARAM_COMBAT, _combat)


func stop_combat_clip() -> void:
	combat_clip = &""
	_combat_target = 0.0


## Clip names available on the combat layer.
func get_combat_clips() -> PackedStringArray:
	return _combat_inputs


## Authored length of a combat clip in seconds (0 if missing).
func get_clip_length(clip: StringName) -> float:
	var path := StringName("%s/%s" % [combat_library, clip])
	if animation_tree == null or not animation_tree.has_animation(path):
		return 0.0
	return animation_tree.get_animation(path).length


func _update_guard(delta: float, guard_clip: StringName) -> void:
	var guarding := guard_clip != &"" and _has_clip(guard_clip, _guard_inputs)
	if guarding and guard_clip != _guard_clip:
		_guard_clip = guard_clip
		animation_tree.set(PARAM_GUARD_CLIP, String(guard_clip))
	_guard = move_toward(_guard, 1.0 if guarding else 0.0, guard_blend_speed * delta)
	animation_tree.set(PARAM_GUARD, _guard)


func _update_combat(delta: float) -> void:
	if _combat_target > 0.0:
		_clip_elapsed += delta
		if _clip_switch_at >= 0.0 and _clip_elapsed >= _clip_switch_at:
			_clip_switch_at = -1.0
			animation_tree.set(PARAM_COMBAT_SPEED, _clip_second_speed)
		if not _clip_hold and _clip_elapsed >= _clip_duration:
			stop_combat_clip()
	var rate := combat_blend_in_speed if _combat_target > _combat else combat_blend_out_speed
	_combat = move_toward(_combat, _combat_target, rate * delta)
	animation_tree.set(PARAM_COMBAT, _combat)


func _transition_inputs(node_name: StringName) -> PackedStringArray:
	var names := PackedStringArray()
	var root := animation_tree.tree_root as AnimationNodeBlendTree
	if root == null or not root.has_node(node_name):
		return names
	var transition := root.get_node(node_name) as AnimationNodeTransition
	if transition == null:
		return names
	for i in transition.get_input_count():
		names.append(transition.get_input_name(i))
	return names


func _has_clip(clip: StringName, inputs: PackedStringArray) -> bool:
	if inputs.has(String(clip)):
		return true
	if not _warned.has(clip):
		_warned[clip] = true
		push_warning("PlayerAnimator: no clip '%s' in the AnimationTree." % clip)
	return false
