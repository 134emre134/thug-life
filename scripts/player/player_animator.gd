class_name PlayerAnimator
extends Node
## Feeds movement and combat state into an AnimationTree. Used by the player
## and by NPCs (same tree, res://assets/animations/humanoid_tree.tres, built
## by scripts/tools/build_humanoid_tree.gd).
##
## Expected tree:
##   locomotion   : BlendSpace1D, blend position = horizontal speed (m/s)
##   locomotion_speed : TimeScale on locomotion
##   strafe       : BlendSpace2D, blend position = local velocity (x = right, y = forward, m/s)
##   strafe_speed : TimeScale on strafe
##   rifle_strafe : BlendSpace2D like strafe, with the rifle clips (aiming a firearm)
##   rifle_strafe_speed : TimeScale on rifle_strafe
##   rifle_blend  : Blend2, 0 = strafe, 1 = rifle_strafe
##   aim_blend    : Blend2, 0 = locomotion, 1 = strafe (aiming and guarding)
##   crouch       : BlendSpace1D, crouched locomotion (speed, m/s)
##   crouch_speed : TimeScale on crouch
##   crouch_blend : Blend2, 0 = standing, 1 = crouched
##   crouch_clip / crouch_shot : Transition + OneShot, stand-to-crouch and back
##   land_clip / land_shot : Transition + OneShot, landing after a jump or fall
##   air_clip     : Transition, jump_standing / jump_running / fall (loop)
##   air_blend    : Blend2, 0 = grounded, 1 = in the air
##   guard_clip   : Transition, one input per guard pose (upper body)
##   guard_blend  : Blend2 filtered to the upper body, 1 = guard pose
##   upper_clip / upper_speed / upper_shot : Transition + TimeScale + OneShot
##                  filtered to the upper body (firing and reloading, M4b)
##   combat_clip  : Transition, one input per combat clip (input name = clip name)
##   combat_speed : TimeScale, the playback speed combat asks for
##   combat_blend : Blend2, 0 = everything above, 1 = combat clip (full body)
## Blend space points are placed at the ground speed of each clip, which keeps
## feet from sliding. Moving faster than the outermost point speeds the clips
## up (TimeScale) instead of sliding. When swapping clips, keep these parameter
## names and re-place the points at the new clips' speeds.
## A combat clip's animation is whatever the "clip_<name>" node in the tree
## plays. Its animation markers ("hit", "hit_end", "end", "recover", "down")
## drive combat timing ([method get_clip_marker], [MeleeCombat]).

const PARAM_LOCOMOTION := &"parameters/locomotion/blend_position"
const PARAM_STRAFE := &"parameters/strafe/blend_position"
const PARAM_AIM := &"parameters/aim_blend/blend_amount"
const PARAM_CROUCH := &"parameters/crouch/blend_position"
const PARAM_CROUCH_SPEED := &"parameters/crouch_speed/scale"
const PARAM_CROUCH_BLEND := &"parameters/crouch_blend/blend_amount"
const PARAM_CROUCH_CLIP := &"parameters/crouch_clip/transition_request"
const PARAM_CROUCH_SHOT := &"parameters/crouch_shot/request"
const PARAM_LAND_CLIP := &"parameters/land_clip/transition_request"
const PARAM_LAND_SHOT := &"parameters/land_shot/request"
const PARAM_AIR_CLIP := &"parameters/air_clip/transition_request"
const PARAM_AIR := &"parameters/air_blend/blend_amount"
const PARAM_GUARD_CLIP := &"parameters/guard_clip/transition_request"
const PARAM_GUARD := &"parameters/guard_blend/blend_amount"
const PARAM_COMBAT_CLIP := &"parameters/combat_clip/transition_request"
const PARAM_COMBAT_SPEED := &"parameters/combat_speed/scale"
const PARAM_COMBAT := &"parameters/combat_blend/blend_amount"
const PARAM_LOCOMOTION_SPEED := &"parameters/locomotion_speed/scale"
const PARAM_STRAFE_SPEED := &"parameters/strafe_speed/scale"
const PARAM_RIFLE_STRAFE := &"parameters/rifle_strafe/blend_position"
const PARAM_RIFLE_STRAFE_SPEED := &"parameters/rifle_strafe_speed/scale"
const PARAM_RIFLE := &"parameters/rifle_blend/blend_amount"
const PARAM_UPPER_CLIP := &"parameters/upper_clip/transition_request"
const PARAM_UPPER_SPEED := &"parameters/upper_speed/scale"
const PARAM_UPPER_SHOT := &"parameters/upper_shot/request"
## Marker that cuts a clip short (the tail after it is not played).
const MARKER_END := &"end"

@export var animation_tree: AnimationTree
@export var body: CharacterBody3D
## Node whose orientation defines "forward" for strafing.
@export var model: Node3D
## Smoothing of blend parameters (higher = snappier).
@export var blend_smoothing: float = 12.0
@export var aim_blend_speed: float = 8.0

## Max playback speed-up when moving faster than the fastest clip.
@export var max_clip_speed_scale: float = 1.5

@export_group("Air (jump, fall, land)")
## Blend per second into the air layer after a jump / back to the ground.
@export var air_blend_in_speed: float = 12.0
@export var air_blend_out_speed: float = 10.0
## Seconds off the floor before a fall (no jump) blends in (ignores small steps).
@export var air_delay: float = 0.15
## A jump with at least this horizontal speed (m/s) uses the running jump.
@export var running_jump_speed: float = 2.5
## After a jump clip has played this long past its end, the fall loop takes over.
@export var fall_after_jump_delay: float = 0.15
## Landings play only after at least this much time in the air.
@export var min_land_air_time: float = 0.25
## Falling faster than this (m/s) lands heavily (when not moving much).
@export var heavy_land_speed: float = 7.5
## At or above this horizontal speed (m/s) a landing uses the running clip.
@export var running_land_speed: float = 1.5

@export_group("Crouch")
## Blend per second between standing and crouched locomotion.
@export var crouch_blend_speed: float = 5.0
## The stand-to-crouch / crouch-to-stand clips only play below this speed
## (m/s); moving cancels them and the layers just blend.
@export var crouch_transition_max_speed: float = 0.6

@export_group("Combat layer")
## Blend amount the combat layer starts at when a clip starts (snappy but not a pop).
@export_range(0.0, 1.0) var combat_blend_in_start: float = 0.4
## Blend per second toward the combat clip / back to locomotion.
@export var combat_blend_in_speed: float = 14.0
@export var combat_blend_out_speed: float = 6.0
@export var guard_blend_speed: float = 10.0

@export_group("Firearm")
## Blend per second between the unarmed and the rifle strafe clips.
@export var rifle_blend_speed: float = 8.0

## Clip currently requested on the combat layer (empty = none).
var combat_clip: StringName = &""
## Playback speed of [member combat_clip].
var combat_clip_speed: float = 1.0
## Current air clip ("jump_standing", "jump_running", "fall"; empty on the ground).
var air_clip: StringName = &""
## Last landing clip played (empty = none yet).
var last_land_clip: StringName = &""
## Clip playing on the upper-body one-shot layer (empty = none).
var upper_clip: StringName = &""

var _speed: float = 0.0
var _strafe := Vector2.ZERO
var _aim: float = 0.0
var _air: float = 0.0
var _air_time: float = 0.0
var _jumping: bool = false
var _running_jump: bool = false
var _fall_speed: float = 0.0
var _was_on_floor: bool = true
var _crouch: float = 0.0
var _crouched: bool = false
var _crouch_shot_active: bool = false
var _guard: float = 0.0
var _guard_clip: StringName = &""
var _combat: float = 0.0
var _combat_target: float = 0.0
var _clip_elapsed: float = 0.0
var _clip_duration: float = 0.0
var _clip_hold: bool = false
var _combat_inputs: PackedStringArray = []
var _guard_inputs: PackedStringArray = []
var _locomotion_max_speed: float = 0.0
var _crouch_max_speed: float = 0.0
var _strafe_points: PackedVector2Array = []
var _rifle_strafe_points: PackedVector2Array = []
var _rifle: float = 0.0
var _upper_inputs: PackedStringArray = []
var _upper_elapsed: float = 0.0
var _upper_duration: float = 0.0
var _warned: Dictionary = {}


func _ready() -> void:
	if animation_tree == null or body == null or model == null:
		push_warning(
			"PlayerAnimator: animation_tree, body or model not assigned; animation is off."
		)
		return
	_combat_inputs = _transition_inputs(&"combat_clip")
	_guard_inputs = _transition_inputs(&"guard_clip")
	_upper_inputs = _transition_inputs(&"upper_clip")
	_read_blend_points()


## [param strafing]: use the strafe blend space (aiming or guarding).
## [param upper_body_clip]: pose to show on the upper body, e.g. guard (empty = none).
## [param crouched]: use the crouched locomotion.
## [param firearm]: aiming uses the rifle strafe clips.
func update(
	delta: float,
	strafing: bool,
	upper_body_clip: StringName = &"",
	crouched: bool = false,
	firearm: bool = false
) -> void:
	if animation_tree == null or body == null or model == null:
		return
	var velocity := body.get_real_velocity()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var local := model.global_basis.inverse() * horizontal
	var t := 1.0 - exp(-blend_smoothing * delta)

	_speed = lerpf(_speed, horizontal.length(), t)
	_strafe = _strafe.lerp(Vector2(local.x, -local.z), t)
	_aim = move_toward(_aim, 1.0 if strafing else 0.0, aim_blend_speed * delta)

	animation_tree.set(PARAM_LOCOMOTION, _speed)
	_rifle = move_toward(_rifle, 1.0 if firearm else 0.0, rifle_blend_speed * delta)

	animation_tree.set(PARAM_STRAFE, _strafe)
	animation_tree.set(PARAM_RIFLE_STRAFE, _strafe)
	animation_tree.set(PARAM_RIFLE, _rifle)
	animation_tree.set(PARAM_AIM, _aim)
	animation_tree.set(PARAM_LOCOMOTION_SPEED, _scale_beyond(_speed, _locomotion_max_speed))
	animation_tree.set(PARAM_STRAFE_SPEED, _strafe_scale(_strafe, _strafe_points))
	animation_tree.set(PARAM_RIFLE_STRAFE_SPEED, _strafe_scale(_strafe, _rifle_strafe_points))
	_update_upper(delta)
	_update_crouch(delta, crouched)
	_update_air(delta, velocity)
	_update_guard(delta, upper_body_clip)
	_update_combat(delta)


## A jump started (connect [signal PlayerMovement.jumped]): the jump clip
## plays right away, running or standing depending on the speed.
func notify_jump() -> void:
	if animation_tree == null or body == null:
		return
	var velocity := body.get_real_velocity()
	_running_jump = Vector2(velocity.x, velocity.z).length() >= running_jump_speed
	_jumping = true
	_air_time = 0.0
	_fall_speed = 0.0
	_set_air_clip(&"jump_running" if _running_jump else &"jump_standing")


## Plays [param clip] on the combat layer at [param speed] (1 = authored
## speed) up to its "end" marker (or its end). [param hold] keeps the last
## frame until [method stop_combat_clip]; otherwise the layer fades out at the end.
func play_combat_clip(clip: StringName, speed: float = 1.0, hold: bool = false) -> void:
	if animation_tree == null or not _has_clip(clip, _combat_inputs):
		return
	var length := get_clip_end(clip)
	if length <= 0.0 or speed <= 0.0:
		return
	_clip_duration = length / speed
	_clip_elapsed = 0.0
	_clip_hold = hold
	combat_clip = clip
	combat_clip_speed = speed
	animation_tree.set(PARAM_COMBAT_CLIP, String(clip))
	animation_tree.set(PARAM_COMBAT_SPEED, speed)
	_combat_target = 1.0
	_combat = maxf(_combat, combat_blend_in_start)
	animation_tree.set(PARAM_COMBAT, _combat)


func stop_combat_clip() -> void:
	combat_clip = &""
	_combat_target = 0.0


## Plays [param clip] once on the upper body (firing, reloading) at
## [param speed], up to its "end" marker; the legs keep walking.
func play_upper_clip(clip: StringName, speed: float = 1.0) -> void:
	if animation_tree == null or not _has_clip(clip, _upper_inputs):
		return
	var length := get_clip_end(clip)
	if length <= 0.0 or speed <= 0.0:
		return
	upper_clip = clip
	_upper_elapsed = 0.0
	_upper_duration = length / speed
	animation_tree.set(PARAM_UPPER_CLIP, String(clip))
	animation_tree.set(PARAM_UPPER_SPEED, speed)
	animation_tree.set(PARAM_UPPER_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func stop_upper_clip() -> void:
	if animation_tree == null or upper_clip == &"":
		return
	upper_clip = &""
	animation_tree.set(PARAM_UPPER_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


## Clip names available on the combat layer.
func get_combat_clips() -> PackedStringArray:
	return _combat_inputs


## Authored length of a combat clip in seconds (0 if missing).
func get_clip_length(clip: StringName) -> float:
	var animation := _clip_animation(clip)
	return animation.length if animation != null else 0.0


## Where a combat clip stops playing: its "end" marker, else its length.
func get_clip_end(clip: StringName) -> float:
	var animation := _clip_animation(clip)
	if animation == null:
		return 0.0
	if animation.has_marker(MARKER_END):
		return animation.get_marker_time(MARKER_END)
	return animation.length


## Time of the animation marker [param marker] in a combat clip (authored
## seconds), or -1 if the clip or the marker doesn't exist.
func get_clip_marker(clip: StringName, marker: StringName) -> float:
	var animation := _clip_animation(clip)
	if animation == null or not animation.has_marker(marker):
		return -1.0
	return animation.get_marker_time(marker)


## Clip time (authored seconds) the combat layer is at, or -1 when no clip plays.
func get_combat_clip_time() -> float:
	if combat_clip == &"":
		return -1.0
	return minf(_clip_elapsed, _clip_duration) * combat_clip_speed


func _clip_animation(clip: StringName) -> Animation:
	if animation_tree == null:
		return null
	var root := animation_tree.tree_root as AnimationNodeBlendTree
	var node_name := StringName("clip_%s" % clip)
	if root != null and not root.has_node(node_name):
		node_name = StringName("upper_%s" % clip)
	if root == null or not root.has_node(node_name):
		return null
	var node := root.get_node(node_name) as AnimationNodeAnimation
	if node == null or not animation_tree.has_animation(node.animation):
		return null
	return animation_tree.get_animation(node.animation)


func _update_crouch(delta: float, crouched: bool) -> void:
	if crouched != _crouched:
		_crouched = crouched
		if _speed < crouch_transition_max_speed and _combat_target <= 0.0:
			var clip := "stand_to_crouch" if crouched else "crouch_to_stand"
			animation_tree.set(PARAM_CROUCH_CLIP, clip)
			animation_tree.set(PARAM_CROUCH_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			_crouch_shot_active = true
	if _crouch_shot_active and _speed >= crouch_transition_max_speed:
		animation_tree.set(PARAM_CROUCH_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		_crouch_shot_active = false
	_crouch = move_toward(_crouch, 1.0 if crouched else 0.0, crouch_blend_speed * delta)
	animation_tree.set(PARAM_CROUCH_BLEND, _crouch)
	animation_tree.set(PARAM_CROUCH, _speed)
	animation_tree.set(PARAM_CROUCH_SPEED, _scale_beyond(_speed, _crouch_max_speed))


func _update_air(delta: float, velocity: Vector3) -> void:
	var on_floor := body.is_on_floor()
	if on_floor:
		if not _was_on_floor and _air_time >= min_land_air_time:
			_land(velocity)
		_air_time = 0.0
		_jumping = false
		_fall_speed = 0.0
		air_clip = &""
	else:
		_air_time += delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
		if _jumping:
			var jump_length := _air_animation_length(air_clip)
			if _air_time > jump_length + fall_after_jump_delay and air_clip != &"fall":
				_set_air_clip(&"fall")
		elif _air_time > air_delay and air_clip != &"fall":
			_set_air_clip(&"fall")
	_was_on_floor = on_floor
	var airborne := not on_floor and (_jumping or _air_time > air_delay)
	var rate := air_blend_in_speed if airborne else air_blend_out_speed
	_air = move_toward(_air, 1.0 if airborne else 0.0, rate * delta)
	animation_tree.set(PARAM_AIR, _air)


func _land(velocity: Vector3) -> void:
	var horizontal := Vector2(velocity.x, velocity.z).length()
	var clip := &"land_standing"
	if horizontal >= running_land_speed:
		clip = &"land_running"
	elif _fall_speed >= heavy_land_speed:
		clip = &"land_heavy"
	last_land_clip = clip
	animation_tree.set(PARAM_LAND_CLIP, String(clip))
	animation_tree.set(PARAM_LAND_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _set_air_clip(clip: StringName) -> void:
	air_clip = clip
	animation_tree.set(PARAM_AIR_CLIP, String(clip))


func _air_animation_length(clip: StringName) -> float:
	var root := animation_tree.tree_root as AnimationNodeBlendTree
	var node_name := StringName("air_%s" % clip)
	if root == null or not root.has_node(node_name):
		return 0.0
	var node := root.get_node(node_name) as AnimationNodeAnimation
	if node == null or not animation_tree.has_animation(node.animation):
		return 0.0
	return animation_tree.get_animation(node.animation).length


## Playback scale of a 1D blend space at [param speed] (m/s) whose fastest
## point is at [param max_speed].
func _scale_beyond(speed: float, max_speed: float) -> float:
	if max_speed <= 0.0 or speed <= max_speed:
		return 1.0
	return minf(speed / max_speed, max_clip_speed_scale)


## Playback scale of the strafe clips: how far [param velocity] lies beyond the
## outline of the blend [param points] in its direction.
func _strafe_scale(velocity: Vector2, points: PackedVector2Array) -> float:
	var speed := velocity.length()
	if speed < 0.01 or points.size() < 3:
		return 1.0
	var direction := velocity / speed
	var reach := INF
	var count := points.size()
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		# Ray (origin, direction) against the segment a-b.
		var edge := b - a
		var denominator := direction.cross(edge)
		if absf(denominator) < 0.0001:
			continue
		var t := a.cross(edge) / denominator
		var u := a.cross(direction) / denominator
		if t > 0.0 and u >= 0.0 and u <= 1.0:
			reach = minf(reach, t)
	if reach == INF or speed <= reach:
		return 1.0
	return minf(speed / reach, max_clip_speed_scale)


## Reads the outer blend points (clip ground speeds) from the tree.
func _read_blend_points() -> void:
	var root := animation_tree.tree_root as AnimationNodeBlendTree
	if root == null:
		return
	_locomotion_max_speed = _max_point(root, &"locomotion")
	_crouch_max_speed = _max_point(root, &"crouch")
	_strafe_points = _outline(root, &"strafe")
	_rifle_strafe_points = _outline(root, &"rifle_strafe")


## The outermost blend points of a 2D blend space, sorted by angle.
func _outline(root: AnimationNodeBlendTree, node_name: StringName) -> PackedVector2Array:
	if not root.has_node(node_name):
		return PackedVector2Array()
	var space := root.get_node(node_name) as AnimationNodeBlendSpace2D
	if space == null:
		return PackedVector2Array()
	# Per direction keep only the furthest point (inner points are slower clips).
	var furthest := {}
	for i in space.get_blend_point_count():
		var point := space.get_blend_point_position(i)
		if point.length() <= 0.01:
			continue
		var key := snappedf(point.angle(), 0.01)
		if not furthest.has(key) or (furthest[key] as Vector2).length() < point.length():
			furthest[key] = point
	var outer: Array[Vector2] = []
	for point: Vector2 in furthest.values():
		outer.append(point)
	outer.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.angle() < b.angle())
	return PackedVector2Array(outer)


func _max_point(root: AnimationNodeBlendTree, node_name: StringName) -> float:
	if not root.has_node(node_name):
		return 0.0
	var space := root.get_node(node_name) as AnimationNodeBlendSpace1D
	var result := 0.0
	if space != null:
		for i in space.get_blend_point_count():
			result = maxf(result, space.get_blend_point_position(i))
	return result


func _update_guard(delta: float, guard_clip: StringName) -> void:
	var guarding := guard_clip != &"" and _has_clip(guard_clip, _guard_inputs)
	if guarding and guard_clip != _guard_clip:
		_guard_clip = guard_clip
		animation_tree.set(PARAM_GUARD_CLIP, String(guard_clip))
	_guard = move_toward(_guard, 1.0 if guarding else 0.0, guard_blend_speed * delta)
	animation_tree.set(PARAM_GUARD, _guard)


func _update_upper(delta: float) -> void:
	if upper_clip == &"":
		return
	_upper_elapsed += delta
	if _upper_elapsed >= _upper_duration:
		stop_upper_clip()


func _update_combat(delta: float) -> void:
	if _combat_target > 0.0:
		_clip_elapsed += delta
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
