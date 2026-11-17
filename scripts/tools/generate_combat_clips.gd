extends SceneTree
## Generates placeholder combat clips for the humanoid character skeleton
## (res://assets/animations/combat_placeholder.tres) for moves that have no
## real (Mixamo) clip yet: right cross, hook, bat swings, guard poses, dodge and
## stomp. Clips that got a real clip in M4a (jab, uppercut, hit reactions,
## knockdown, get-up) are no longer generated. See assets/animations/CLIPS.md.
##
## Run (after the model is imported):
##   godot --headless --script res://scripts/tools/generate_combat_clips.gd
##
## Poses are authored as targets in character space: fist positions, a bat
## grip point and bat direction, foot positions and hip / spine / head angles.
## Two-bone IK turns them into bone rotations, so both hands really hold the
## bat. Character space here is the skeleton's: the model faces +Z; positions
## are written as cs(right, up, forward). Attack clips get animation markers
## ([constant MARKERS]: "hit" / "hit_end" = the contact window) that combat
## timing is read from (M4a.2), the same as the real clips' markers.

const MODEL := "res://assets/models/player.fbx"
const OUTPUT := "res://assets/animations/combat_placeholder.tres"
const SKELETON_PATH := "%GeneralSkeleton"

## Fist centre relative to the hand bone (wrist), in hand space.
const FIST_OFFSET := Vector3(0.0, 0.08, 0.03)
## Default distance of the left hand from the right hand along the bat (knob side).
const LEFT_GRIP := -0.11
## Finger curl for a fist (radians per joint), and the thumb's.
const FINGER_CURL := 1.2
const THUMB_CURL := 0.5
## Finger joints bend around this local axis (verified on the model render).
const FINGER_AXIS := Vector3.RIGHT

## Contact window (seconds, clip time) per attack clip, matching the key poses.
const MARKERS := {
	"punch_cross": {"hit": 0.12, "hit_end": 0.2},
	"punch_hook": {"hit": 0.16, "hit_end": 0.26},
	"bat_1": {"hit": 0.18, "hit_end": 0.28},
	"bat_2": {"hit": 0.2, "hit_end": 0.3},
	"bat_3": {"hit": 0.26, "hit_end": 0.38},
	"bat_heavy": {"hit": 0.55, "hit_end": 0.69},
	"stomp": {"hit": 0.5, "hit_end": 0.6},
}

const FINGERS := ["Index", "Middle", "Ring", "Little"]
const PHALANGES := ["Proximal", "Intermediate", "Distal"]
const THUMB := ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal"]

var _skeleton: Skeleton3D
var _motion_scale: float = 1.0
var _bones: PackedStringArray = []


func _initialize() -> void:
	var model := (load(MODEL) as PackedScene).instantiate()
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	_motion_scale = _skeleton.motion_scale
	_bones = _animated_bones()
	var library := AnimationLibrary.new()
	for clip in _clips():
		var markers: Dictionary = MARKERS.get(clip.resource_name, {})
		for marker: String in markers:
			clip.add_marker(StringName(marker), markers[marker])
		library.add_animation(clip.resource_name, clip)
	var error := ResourceSaver.save(library, OUTPUT)
	print("Saved %d clips to %s (error %d)" % [library.get_animation_list().size(), OUTPUT, error])
	model.free()
	quit(error)


# --- Pose definitions -----------------------------------------------------------


## Character-space position: right, up, forward (the model faces +Z, its right is -X).
static func cs(right: float, up: float, forward: float) -> Vector3:
	return Vector3(-right, up, forward)


static func dir(right: float, up: float, forward: float) -> Vector3:
	return cs(right, up, forward).normalized()


## Fighting stance: fists up, left foot forward, knees a little bent.
static func stance() -> Dictionary:
	return {
		"hips_pos": cs(0.0, 0.93, 0.0),
		"hips_rot": Vector3.ZERO,
		"spine": Vector3(0.08, 0.0, 0.0),
		"head": Vector3(0.05, 0.0, 0.0),
		"lhand": cs(-0.12, 1.42, 0.28),
		"rhand": cs(0.12, 1.38, 0.22),
		"lfoot": cs(-0.14, 0.14, 0.14),
		"rfoot": cs(0.16, 0.14, -0.16),
	}


## Ready stance with the bat over the right shoulder.
static func bat_stance() -> Dictionary:
	return _with(stance(), {"grip": cs(0.2, 1.22, 0.18), "bat": dir(0.2, 0.9, -0.35)})


static func _with(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var pose := base.duplicate()
	pose.merge(overrides, true)
	if overrides.has("grip"):
		pose.erase("lhand")
		pose.erase("rhand")
	if overrides.has("lhand") or overrides.has("rhand"):
		pose.erase("grip")
	return pose


func _clips() -> Array[Animation]:
	var s := stance()
	var b := bat_stance()
	var clips: Array[Animation] = []
	# --- Unarmed ---------------------------------------------------------------
	(
		clips
		. append(
			_clip(
				"punch_cross",
				0.46,
				[
					[0.0, s],
					[
						0.07,
						_with(s, {"rhand": cs(0.16, 1.36, 0.12), "spine": Vector3(0.08, -0.25, 0)})
					],
					[
						0.12,
						_with(
							s,
							{
								"rhand": cs(0.02, 1.46, 0.7),
								"spine": Vector3(0.14, 0.5, 0),
								"hips_rot": Vector3(0, 0.25, 0),
								"rfoot": cs(0.16, 0.14, -0.1),
							}
						)
					],
					[
						0.2,
						_with(s, {"rhand": cs(0.04, 1.45, 0.62), "spine": Vector3(0.12, 0.45, 0)})
					],
					[0.46, s],
				]
			)
		)
	)
	(
		clips
		. append(
			_clip(
				"punch_hook",
				0.64,
				[
					[0.0, s],
					[
						0.1,
						_with(
							s,
							{
								"rhand": cs(0.45, 1.4, 0.2),
								"rpole": dir(1, 0.2, -0.3),
								"spine": Vector3(0.08, -0.55, 0),
								"hips_pos": cs(0, 0.9, 0),
							}
						)
					],
					[
						0.16,
						_with(
							s,
							{
								"rhand": cs(-0.05, 1.45, 0.52),
								"rpole": dir(1, 0.6, 0),
								"spine": Vector3(0.12, 0.6, 0),
								"hips_rot": Vector3(0, 0.25, 0),
							}
						)
					],
					[
						0.26,
						_with(
							s,
							{
								"rhand": cs(-0.3, 1.42, 0.35),
								"rpole": dir(1, 0.6, 0),
								"spine": Vector3(0.1, 0.75, 0),
								"hips_rot": Vector3(0, 0.3, 0),
							}
						)
					],
					[0.64, s],
				]
			)
		)
	)
	# --- Bat (two-handed) ---------------------------------------------------------
	(
		clips
		. append(
			_clip(
				"bat_1",
				0.6,
				[
					[0.0, b],
					[
						0.12,
						_with(
							b,
							{
								"grip": cs(0.35, 1.32, -0.02),
								"bat": dir(0.4, 0.75, -0.5),
								"spine": Vector3(0.05, -0.6, 0),
							}
						)
					],
					[
						0.18,
						_with(
							b,
							{
								"grip": cs(0.0, 1.15, 0.42),
								"bat": dir(-0.9, 0.08, 0.45),
								"spine": Vector3(0.12, 0.05, 0),
							}
						)
					],
					[
						0.28,
						_with(
							b,
							{
								"grip": cs(-0.3, 1.2, 0.22),
								"bat": dir(-0.45, 0.3, -0.8),
								"spine": Vector3(0.1, 0.7, 0),
								"hips_rot": Vector3(0, 0.25, 0),
							}
						)
					],
					[0.6, b],
				]
			)
		)
	)
	var backhand_start := _with(
		b,
		{"grip": cs(-0.28, 1.22, 0.2), "bat": dir(-0.45, 0.4, -0.7), "spine": Vector3(0.1, 0.55, 0)}
	)
	(
		clips
		. append(
			_clip(
				"bat_2",
				0.64,
				[
					[0.0, backhand_start],
					[
						0.14,
						_with(
							b,
							{
								"grip": cs(-0.35, 1.25, 0.12),
								"bat": dir(-0.5, 0.5, -0.7),
								"spine": Vector3(0.05, 0.7, 0),
							}
						)
					],
					[
						0.2,
						_with(
							b,
							{
								"grip": cs(0.05, 1.15, 0.42),
								"bat": dir(0.9, 0.08, 0.45),
								"spine": Vector3(0.12, -0.1, 0),
							}
						)
					],
					[
						0.3,
						_with(
							b,
							{
								"grip": cs(0.32, 1.22, 0.15),
								"bat": dir(0.5, 0.45, -0.7),
								"spine": Vector3(0.08, -0.6, 0),
							}
						)
					],
					[0.64, b],
				]
			)
		)
	)
	(
		clips
		. append(
			_clip(
				"bat_3",
				0.88,
				[
					[0.0, b],
					[
						0.2,
						_with(
							b,
							{
								"grip": cs(0.08, 1.62, -0.02),
								"bat": dir(0.0, 0.55, -0.85),
								"spine": Vector3(-0.15, 0, 0),
								"hips_pos": cs(0, 0.95, 0),
							}
						)
					],
					[
						0.26,
						_with(
							b,
							{
								"grip": cs(0.0, 1.05, 0.42),
								"bat": dir(0.0, -0.25, 1.0),
								"spine": Vector3(0.4, 0, 0),
								"hips_pos": cs(0, 0.86, 0.08),
								"lfoot": cs(-0.14, 0.14, 0.3),
							}
						)
					],
					[
						0.36,
						_with(
							b,
							{
								"grip": cs(0.0, 0.92, 0.38),
								"bat": dir(0.0, -0.75, 0.65),
								"spine": Vector3(0.45, 0, 0),
								"hips_pos": cs(0, 0.86, 0.08),
								"lfoot": cs(-0.14, 0.14, 0.3),
							}
						)
					],
					[0.88, b],
				]
			)
		)
	)
	var bat_heavy_windup := _with(
		b,
		{
			"grip": cs(0.42, 1.3, -0.12),
			"bat": dir(0.45, 0.5, -0.75),
			"spine": Vector3(0.05, -0.9, 0),
			"hips_pos": cs(0, 0.88, 0),
			"hips_rot": Vector3(0, -0.25, 0),
		}
	)
	(
		clips
		. append(
			_clip(
				"bat_heavy",
				1.29,
				[
					[0.0, b],
					[0.4, bat_heavy_windup],
					[0.5, bat_heavy_windup],
					[
						0.55,
						_with(
							b,
							{
								"grip": cs(0.0, 1.15, 0.45),
								"bat": dir(-0.9, 0.05, 0.4),
								"spine": Vector3(0.12, 0.1, 0),
								"hips_pos": cs(0, 0.9, 0.1),
							}
						)
					],
					[
						0.7,
						_with(
							b,
							{
								"grip": cs(-0.38, 1.25, 0.12),
								"bat": dir(-0.3, 0.3, -0.9),
								"spine": Vector3(0.1, 0.95, 0),
								"hips_pos": cs(0, 0.9, 0.12),
								"hips_rot": Vector3(0, 0.35, 0),
							}
						)
					],
					[1.29, b],
				]
			)
		)
	)
	# --- Upper-body poses (guard, weapon ready; looped) ---------------------------------
	(
		clips
		. append(
			_pose_clip(
				"guard",
				_with(
					s,
					{
						"lhand": cs(-0.09, 1.56, 0.24),
						"rhand": cs(0.09, 1.53, 0.21),
						"lpole": dir(-0.3, -1, 0),
						"rpole": dir(0.3, -1, 0),
						"spine": Vector3(0.12, 0, 0),
						"head": Vector3(0.15, 0, 0),
					}
				)
			)
		)
	)
	(
		clips
		. append(
			_pose_clip(
				"bat_guard",
				_with(
					b,
					{
						"grip": cs(0.24, 1.48, 0.3),
						"bat": dir(-1.0, 0.12, 0.0),
						"lgrip": 0.42,
						"spine": Vector3(0.1, 0, 0),
						"head": Vector3(0.12, 0, 0),
					}
				)
			)
		)
	)
	clips.append(_pose_clip("bat_ready", b))
	# --- Dodge (direction-neutral duck) ------------------------------------------------
	var duck := _with(
		s,
		{
			"hips_pos": cs(0, 0.78, 0),
			"spine": Vector3(0.2, 0, 0),
			"head": Vector3(0.2, 0, 0),
			"lhand": cs(-0.1, 1.38, 0.22),
			"rhand": cs(0.1, 1.35, 0.2),
			"lfoot": cs(-0.2, 0.14, 0.12),
			"rfoot": cs(0.2, 0.14, -0.12),
		}
	)
	clips.append(_clip("dodge", 0.35, [[0.0, s], [0.08, duck], [0.22, duck], [0.35, s]]))
	# --- Stomp on a downed body (right foot) ------------------------------------------
	var knee_up := _with(
		s,
		{
			"hips_pos": cs(0, 0.95, -0.05),
			"spine": Vector3(0.35, 0, 0),
			"head": Vector3(0.45, 0, 0),
			"rfoot": cs(0.14, 0.62, 0.32),
			"knee": dir(0, 0.2, 1),
			"lhand": cs(-0.25, 1.25, 0.15),
			"rhand": cs(0.3, 1.2, 0.0),
		}
	)
	var stomp_down := _with(
		s,
		{
			"hips_pos": cs(0, 0.86, 0.02),
			"spine": Vector3(0.45, 0, 0),
			"head": Vector3(0.5, 0, 0),
			"rfoot": cs(0.12, 0.12, 0.5),
			"lfoot": cs(-0.14, 0.14, -0.1),
			"knee": dir(0, 0.2, 1),
			"lhand": cs(-0.3, 1.15, 0.1),
			"rhand": cs(0.32, 1.1, -0.05),
		}
	)
	clips.append(
		_clip(
			"stomp",
			0.95,
			[
				[0.0, s],
				[0.32, knee_up],
				[0.42, knee_up],
				[0.5, stomp_down],
				[0.62, stomp_down],
				[0.95, s]
			]
		)
	)
	return clips


# --- Clip building -----------------------------------------------------------------


func _clip(clip_name: String, length: float, keys: Array) -> Animation:
	var animation := Animation.new()
	animation.resource_name = clip_name
	animation.length = length
	animation.loop_mode = Animation.LOOP_NONE
	var hips_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(hips_track, NodePath("%s:Hips" % SKELETON_PATH))
	var rotation_tracks := {}
	for bone in _bones:
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath("%s:%s" % [SKELETON_PATH, bone]))
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		rotation_tracks[bone] = track
	animation.track_set_interpolation_type(hips_track, Animation.INTERPOLATION_CUBIC)
	for key: Array in keys:
		var time: float = key[0]
		var solved := _solve(key[1])
		var hips: Transform3D = solved["Hips"]
		animation.position_track_insert_key(hips_track, time, hips.origin / _motion_scale)
		for bone in _bones:
			var local: Transform3D = solved[bone]
			var rotation := local.basis.get_rotation_quaternion()
			animation.rotation_track_insert_key(rotation_tracks[bone], time, rotation)
	return animation


func _pose_clip(clip_name: String, pose: Dictionary) -> Animation:
	var animation := _clip(clip_name, 0.5, [[0.0, pose], [0.5, pose]])
	animation.loop_mode = Animation.LOOP_LINEAR
	return animation


## Bones that get a rotation track: every bone with a humanoid name except the
## leaf "end" bones (they never move).
func _animated_bones() -> PackedStringArray:
	var names := PackedStringArray()
	var profile := SkeletonProfileHumanoid.new()
	for i in profile.bone_size:
		var bone := String(profile.get_bone_name(i))
		if _skeleton.find_bone(bone) >= 0:
			names.append(bone)
	return names


# --- Solver --------------------------------------------------------------------------


## Bone name -> local pose transform for one pose (only animated bones and Hips).
func _solve(pose: Dictionary) -> Dictionary:
	var local := {}
	var global := {}
	# Rest pose first; the steps below overwrite what they control.
	for bone in _bones:
		local[bone] = _rest_local(bone)
	var hips_basis := Basis.from_euler(pose.get("hips_rot", Vector3.ZERO))
	local["Hips"] = Transform3D(hips_basis * _rest_local("Hips").basis, pose["hips_pos"])
	_rotate_local(local, "Spine", pose.get("spine", Vector3.ZERO) / 3.0)
	_rotate_local(local, "Chest", pose.get("spine", Vector3.ZERO) / 3.0)
	_rotate_local(local, "UpperChest", pose.get("spine", Vector3.ZERO) / 3.0)
	_rotate_local(local, "Neck", pose.get("head", Vector3.ZERO) * 0.4)
	_rotate_local(local, "Head", pose.get("head", Vector3.ZERO) * 0.6)
	_curl_fists(local)
	_update_globals(local, global)

	if pose.has("grip"):
		_solve_bat(pose, local, global)
	else:
		_solve_arm("Left", pose["lhand"], pose.get("lpole", dir(-0.6, -1, -0.3)), local, global)
		_solve_arm("Right", pose["rhand"], pose.get("rpole", dir(0.6, -1, -0.3)), local, global)
	var knee: Vector3 = pose.get("knee", dir(0, 0, 1))
	_solve_leg("Left", pose["lfoot"], (knee + cs(-0.15, 0, 0)).normalized(), local, global)
	_solve_leg("Right", pose["rfoot"], (knee + cs(0.15, 0, 0)).normalized(), local, global)
	return local


func _solve_bat(pose: Dictionary, local: Dictionary, global: Dictionary) -> void:
	var grip: Vector3 = pose["grip"]
	var bat: Vector3 = pose["bat"]
	var left_grip: Vector3 = grip + bat * float(pose.get("lgrip", LEFT_GRIP))
	# Hand orientation depends on the forearm, the wrist on the hand: iterate.
	for i in 3:
		for side in ["Right", "Left"]:
			var target: Vector3 = grip if side == "Right" else left_grip
			var hand_basis := _bat_hand_basis(side, bat, global)
			var wrist := target - hand_basis * FIST_OFFSET
			var pole := dir(0.6, -1, -0.3) if side == "Right" else dir(-0.6, -1, -0.3)
			_solve_arm(side, wrist, pole, local, global, false)
			hand_basis = _bat_hand_basis(side, bat, global)
			var lower: Transform3D = global[side + "LowerArm"]
			local[side + "Hand"] = Transform3D(
				lower.basis.inverse() * hand_basis, _rest_local(side + "Hand").origin
			)
			_update_globals(local, global)


## Hand basis for a fist around the bat: the bat runs out of the thumb side
## (+X for the right hand, -X for the left), the fingers continue the forearm.
func _bat_hand_basis(side: String, bat: Vector3, global: Dictionary) -> Basis:
	var lower: Transform3D = global[side + "LowerArm"]
	var hand: Transform3D = global[side + "Hand"]
	var forearm := (hand.origin - lower.origin).normalized()
	var x := bat if side == "Right" else -bat
	var y := (forearm - x * forearm.dot(x)).normalized()
	if y.length_squared() < 0.001:
		y = Vector3.DOWN
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _solve_arm(
	side: String,
	target: Vector3,
	pole: Vector3,
	local: Dictionary,
	global: Dictionary,
	is_fist_target: bool = true
) -> void:
	var wrist := target
	if is_fist_target:
		# Fist target -> wrist, assuming the hand continues the forearm.
		var shoulder: Vector3 = global[side + "UpperArm"].origin
		wrist = target - (target - shoulder).normalized() * FIST_OFFSET.y
	_two_bone(side + "UpperArm", side + "LowerArm", side + "Hand", wrist, pole, local, global)


func _solve_leg(
	side: String, ankle: Vector3, pole: Vector3, local: Dictionary, global: Dictionary
) -> void:
	_two_bone(side + "UpperLeg", side + "LowerLeg", side + "Foot", ankle, pole, local, global)
	# Feet follow the hips' orientation (level when standing, toes up when lying).
	var hips: Transform3D = global["Hips"]
	var foot_rest := _rest_global(side + "Foot").basis
	var lower: Transform3D = global[side + "LowerLeg"]
	var foot_global := hips.basis * _rest_global("Hips").basis.inverse() * foot_rest
	local[side + "Foot"] = Transform3D(
		lower.basis.inverse() * foot_global, _rest_local(side + "Foot").origin
	)
	_update_globals(local, global)


## Analytic two-bone IK: rotates [param upper] and [param lower] so the end
## bone's origin reaches [param target], bending toward [param pole].
func _two_bone(
	upper: String,
	lower: String,
	end: String,
	target: Vector3,
	pole: Vector3,
	local: Dictionary,
	global: Dictionary
) -> void:
	var start: Vector3 = global[upper].origin
	var upper_length := _rest_local(lower).origin.length()
	var lower_length := _rest_local(end).origin.length()
	var to_target := target - start
	var distance := clampf(
		to_target.length(),
		absf(upper_length - lower_length) + 0.01,
		(upper_length + lower_length) * 0.999
	)
	var direction := to_target.normalized()
	var bend := pole - direction * pole.dot(direction)
	if bend.length_squared() < 0.0001:
		bend = Vector3.DOWN - direction * direction.y  # pole along the limb: bend down
	bend = bend.normalized()
	var cos_a := (
		(upper_length * upper_length + distance * distance - lower_length * lower_length)
		/ (2.0 * upper_length * distance)
	)
	var angle := acos(clampf(cos_a, -1.0, 1.0))
	var elbow := start + (direction * cos(angle) + bend * sin(angle)) * upper_length
	var reach := start + direction * distance
	_aim_bone(upper, elbow - start, local, global)
	_aim_bone(lower, reach - elbow, local, global)


## Rotates [param bone] (shortest arc from its current direction) so its +Y
## axis (toward its child) points along [param direction].
func _aim_bone(bone: String, direction: Vector3, local: Dictionary, global: Dictionary) -> void:
	var parent_global: Transform3D = global[_parent(bone)]
	var current := parent_global.basis * _rest_local(bone).basis
	var arc := Quaternion(current.y.normalized(), direction.normalized())
	var target := Basis(arc) * current
	local[bone] = Transform3D(parent_global.basis.inverse() * target, _rest_local(bone).origin)
	_update_globals(local, global)


func _rotate_local(local: Dictionary, bone: String, euler: Vector3) -> void:
	var rest := _rest_local(bone)
	local[bone] = Transform3D(rest.basis * Basis.from_euler(euler), rest.origin)


func _curl_fists(local: Dictionary) -> void:
	for side in ["Left", "Right"]:
		for finger in FINGERS:
			for phalanx in PHALANGES:
				_curl(local, side + finger + phalanx, FINGER_CURL)
		for phalanx in THUMB:
			_curl(local, side + phalanx, THUMB_CURL)


func _curl(local: Dictionary, bone: String, angle: float) -> void:
	if not local.has(bone):
		return
	var rest := _rest_local(bone)
	local[bone] = Transform3D(rest.basis * Basis(FINGER_AXIS, angle), rest.origin)


func _update_globals(local: Dictionary, global: Dictionary) -> void:
	for i in _skeleton.get_bone_count():
		var bone := _skeleton.get_bone_name(i)
		var transform: Transform3D = local.get(bone, _skeleton.get_bone_rest(i))
		var parent := _skeleton.get_bone_parent(i)
		global[bone] = (
			transform if parent < 0 else global[_skeleton.get_bone_name(parent)] * transform
		)


func _parent(bone: String) -> String:
	return _skeleton.get_bone_name(_skeleton.get_bone_parent(_skeleton.find_bone(bone)))


func _rest_local(bone: String) -> Transform3D:
	return _skeleton.get_bone_rest(_skeleton.find_bone(bone))


func _rest_global(bone: String) -> Transform3D:
	return _skeleton.get_bone_global_rest(_skeleton.find_bone(bone))
