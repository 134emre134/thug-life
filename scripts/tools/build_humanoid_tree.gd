extends SceneTree
## Builds the shared AnimationTree (res://assets/animations/humanoid_tree.tres)
## used by the player and every NPC (M4a.1). The node names are a contract with
## [PlayerAnimator]; the tables below say which animation each node plays.
##
## Run: godot --headless --script res://scripts/tools/build_humanoid_tree.gd
## Re-run after adding a clip to a table (edits made in the editor are lost
## when the tree is rebuilt). Every clip in assets/animations/mixamo/ that is
## not a firearm clip (rifle_*, grenade_*: M4b) also becomes an input of
## combat_clip, so the F4 debug key can play all of them. The clip libraries
## must be listed in the AnimationTree "libraries" of player.tscn and thug.tscn.
##
## Layout (bottom to top):
##   locomotion (1D) -> locomotion_speed --+
##   strafe (2D) -> strafe_speed ---------- aim_blend --+
##   crouch (1D) -> crouch_speed ----------------------- crouch_blend
##   crouch_clip (stand_to_crouch / crouch_to_stand) -> crouch_shot (one-shot)
##   land_clip (standing / running / heavy) -> land_shot (one-shot)
##   air_clip (jump_standing / jump_running / fall) -> air_blend
##   guard_clip (upper-body poses) -> guard_blend (filtered: Spine and up)
##   combat_clip (all combat clips) -> combat_speed -> combat_blend -> output

const OUTPUT := "res://assets/animations/humanoid_tree.tres"
const CLIP_DIR := "res://assets/animations/mixamo/"
const PLACEHOLDERS := "res://assets/animations/combat_placeholder.tres"
## Clips of these families are left for M4b (firearms).
const FIREARM_PREFIXES: PackedStringArray = ["rifle_", "grenade_"]

## Blend points at each clip's measured ground speed (m/s), see CLIPS.md.
const LOCOMOTION := [
	["idle/idle", 0.0], ["walk/walk", 1.53], ["run/run", 3.91], ["sprint/sprint", 5.63]
]
const STRAFE := [
	["aim_idle/aim_idle", Vector2(0, 0)],
	["aim_forward/aim_forward", Vector2(0, 2.26)],
	["aim_backward/aim_backward", Vector2(0, -1.32)],
	["aim_right/aim_right", Vector2(2.18, 0)],
	["aim_left/aim_left", Vector2(-2.06, 0)],
]
const CROUCH := [["crouch_idle/crouch_idle", 0.0], ["crouch_walk/crouch_walk", 1.28]]
const CROUCH_CLIPS := {
	"stand_to_crouch": "stand_to_crouch/stand_to_crouch",
	"crouch_to_stand": "crouch_to_stand/crouch_to_stand",
}
const AIR_CLIPS := {
	"jump_standing": "jump_standing/jump_standing_air",
	"jump_running": "jump_running/jump_running_air",
	"fall": "fall/fall",
}
const LAND_CLIPS := {
	"land_standing": "jump_standing/jump_standing_land",
	"land_running": "jump_running/jump_running_land",
	"land_heavy": "jump_drop_down/jump_drop_down_land",
}
## Upper-body poses (guard_clip inputs; WeaponData.guard_clip / ready_clip).
const GUARD_CLIPS := {
	"guard": "combat/guard",
	"bat_guard": "combat/bat_guard",
	"bat_ready": "combat/bat_ready",
	"knife_ready": "knife_idle/knife_idle",
}
## Combat layer inputs used by gameplay (AttackData.clip, MeleeCombat clips).
## Placeholders live in the "combat" library; real clips in their own.
const COMBAT_CLIPS := {
	"punch_jab": "punch_jab/punch_jab",
	"punch_cross": "combat/punch_cross",
	"punch_hook": "combat/punch_hook",
	"punch_uppercut": "punch_uppercut/punch_uppercut",
	"bat_1": "combat/bat_1",
	"bat_2": "combat/bat_2",
	"bat_3": "combat/bat_3",
	"bat_heavy": "combat/bat_heavy",
	"knife_stab_straight": "knife_stab_straight/knife_stab_straight",
	"knife_stab_hook": "knife_stab_hook/knife_stab_hook",
	"stomp": "combat/stomp",
	"dodge": "combat/dodge",
	"hit_react_face": "hit_react_face/hit_react_face",
	"hit_react_body": "hit_react_body/hit_react_body",
	"hit_react_stomach": "hit_react_stomach/hit_react_stomach",
	"hit_react_uppercut": "hit_react_uppercut/hit_react_uppercut",
	"hit_react_head": "hit_react_head/hit_react_head",
	"knockdown_fall": "knockdown_fall/knockdown_fall",
	"getup_from_back": "getup_from_back/getup_from_back",
	"getup_from_front": "getup_from_front/getup_from_front",
}
## Bones the guard pose doesn't touch (the legs keep moving).
const LOWER_BODY: PackedStringArray = [
	"Root",
	"Hips",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"LeftToes",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
	"RightToes",
]
const SKELETON := "%GeneralSkeleton"

var _tree := AnimationNodeBlendTree.new()


func _initialize() -> void:
	_add(&"locomotion", _blend_space_1d(LOCOMOTION, 8.0), -900, 0)
	_add(&"locomotion_speed", AnimationNodeTimeScale.new(), -650, 0)
	_add(&"strafe", _blend_space_2d(), -900, 200)
	_add(&"strafe_speed", AnimationNodeTimeScale.new(), -650, 200)
	_add(&"aim_blend", AnimationNodeBlend2.new(), -420, 60)
	_add(&"crouch", _blend_space_1d(CROUCH, 3.0), -900, 400)
	_add(&"crouch_speed", AnimationNodeTimeScale.new(), -650, 400)
	_add(&"crouch_blend", AnimationNodeBlend2.new(), -200, 60)
	_add(&"crouch_clip", _transition(CROUCH_CLIPS.keys(), 0.0), -200, 400)
	_add(&"crouch_shot", _one_shot(0.12, 0.2), 20, 60)
	_add(&"land_clip", _transition(LAND_CLIPS.keys(), 0.0), 20, 400)
	_add(&"land_shot", _one_shot(0.06, 0.25), 240, 60)
	_add(&"air_clip", _transition(AIR_CLIPS.keys(), 0.15), 240, 400)
	_add(&"air_blend", AnimationNodeBlend2.new(), 460, 60)
	_add(&"guard_clip", _transition(GUARD_CLIPS.keys(), 0.15), 460, 400)
	_add(&"guard_blend", _guard_blend(), 680, 60)
	var combat := _combat_inputs()
	_add(&"combat_clip", _transition(combat.keys(), 0.06, true), 680, 400)
	_add(&"combat_speed", AnimationNodeTimeScale.new(), 900, 400)
	_add(&"combat_blend", AnimationNodeBlend2.new(), 1120, 60)
	_tree.set_node_position(&"output", Vector2(1340, 60))

	_add_clip_nodes(CROUCH_CLIPS, &"crouch_", &"crouch_clip")
	_add_clip_nodes(LAND_CLIPS, &"land_", &"land_clip")
	_add_clip_nodes(AIR_CLIPS, &"air_", &"air_clip")
	_add_clip_nodes(GUARD_CLIPS, &"clip_", &"guard_clip")
	_add_clip_nodes(combat, &"clip_", &"combat_clip")

	_tree.connect_node(&"locomotion_speed", 0, &"locomotion")
	_tree.connect_node(&"strafe_speed", 0, &"strafe")
	_tree.connect_node(&"crouch_speed", 0, &"crouch")
	_tree.connect_node(&"aim_blend", 0, &"locomotion_speed")
	_tree.connect_node(&"aim_blend", 1, &"strafe_speed")
	_tree.connect_node(&"crouch_blend", 0, &"aim_blend")
	_tree.connect_node(&"crouch_blend", 1, &"crouch_speed")
	_tree.connect_node(&"crouch_shot", 0, &"crouch_blend")
	_tree.connect_node(&"crouch_shot", 1, &"crouch_clip")
	_tree.connect_node(&"land_shot", 0, &"crouch_shot")
	_tree.connect_node(&"land_shot", 1, &"land_clip")
	_tree.connect_node(&"air_blend", 0, &"land_shot")
	_tree.connect_node(&"air_blend", 1, &"air_clip")
	_tree.connect_node(&"guard_blend", 0, &"air_blend")
	_tree.connect_node(&"guard_blend", 1, &"guard_clip")
	_tree.connect_node(&"combat_speed", 0, &"combat_clip")
	_tree.connect_node(&"combat_blend", 0, &"guard_blend")
	_tree.connect_node(&"combat_blend", 1, &"combat_speed")
	_tree.connect_node(&"output", 0, &"combat_blend")

	var error := ResourceSaver.save(_tree, OUTPUT)
	print("Saved %s with %d combat clips (error %d)" % [OUTPUT, combat.size(), error])
	quit(error)


## Gameplay clips first, then every other non-firearm clip (debug, F4).
func _combat_inputs() -> Dictionary:
	var inputs := COMBAT_CLIPS.duplicate()
	var files := Array(DirAccess.get_files_at(CLIP_DIR))
	files.sort()
	for file: String in files:
		if not file.ends_with(".fbx"):
			continue
		var clip := file.get_basename()
		var firearm := false
		for prefix in FIREARM_PREFIXES:
			firearm = firearm or clip.begins_with(prefix)
		if firearm or inputs.has(clip):
			continue
		inputs[clip] = "%s/%s" % [clip, clip]
	return inputs


func _add(node_name: StringName, node: AnimationNode, x: float, y: float) -> void:
	_tree.add_node(node_name, node, Vector2(x, y))


func _add_clip_nodes(clips: Dictionary, prefix: StringName, transition: StringName) -> void:
	var position := _tree.get_node_position(transition) - Vector2(240, 0)
	var index := 0
	for clip: String in clips:
		var node := AnimationNodeAnimation.new()
		node.animation = StringName(clips[clip])
		_check_animation(clips[clip])
		var node_name := StringName("%s%s" % [prefix, clip])
		_tree.add_node(node_name, node, position + Vector2(0, 80 * index))
		_tree.connect_node(transition, index, node_name)
		index += 1


func _transition(inputs: Array, xfade: float, to_self: bool = false) -> AnimationNodeTransition:
	var transition := AnimationNodeTransition.new()
	transition.xfade_time = xfade
	transition.allow_transition_to_self = to_self
	transition.input_count = inputs.size()
	for i in inputs.size():
		transition.set_input_name(i, String(inputs[i]))
		transition.set_input_reset(i, true)
	return transition


func _one_shot(fade_in: float, fade_out: float) -> AnimationNodeOneShot:
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = fade_in
	shot.fadeout_time = fade_out
	return shot


func _blend_space_1d(points: Array, max_space: float) -> AnimationNodeBlendSpace1D:
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = max_space
	space.value_label = "speed (m/s)"
	for point: Array in points:
		var node := AnimationNodeAnimation.new()
		node.animation = StringName(point[0])
		_check_animation(point[0])
		space.add_blend_point(node, point[1], -1, StringName(str(space.get_blend_point_count())))
	return space


func _blend_space_2d() -> AnimationNodeBlendSpace2D:
	var space := AnimationNodeBlendSpace2D.new()
	space.min_space = Vector2(-3, -3)
	space.max_space = Vector2(3, 3)
	space.x_label = "right (m/s)"
	space.y_label = "forward (m/s)"
	for point: Array in STRAFE:
		var node := AnimationNodeAnimation.new()
		node.animation = StringName(point[0])
		_check_animation(point[0])
		space.add_blend_point(node, point[1], -1, StringName(str(space.get_blend_point_count())))
	return space


func _guard_blend() -> AnimationNodeBlend2:
	var blend := AnimationNodeBlend2.new()
	blend.filter_enabled = true
	var profile := SkeletonProfileHumanoid.new()
	for i in profile.bone_size:
		var bone := String(profile.get_bone_name(i))
		if not LOWER_BODY.has(bone):
			blend.set_filter_path(NodePath("%s:%s" % [SKELETON, bone]), true)
	return blend


## Warns about table entries that point at a missing animation.
func _check_animation(path: String) -> void:
	var library_name := path.get_slice("/", 0)
	var animation := path.get_slice("/", 1)
	var file := PLACEHOLDERS if library_name == "combat" else "%s%s.fbx" % [CLIP_DIR, library_name]
	var library := load(file) as AnimationLibrary
	if library == null or not library.has_animation(animation):
		push_warning("build_humanoid_tree: missing animation %s" % path)
