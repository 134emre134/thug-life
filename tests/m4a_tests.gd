extends Node
## Headless M4a checks (animation pass, clip-driven timing, reactions, jumps,
## crouch, stomp, inventory pause). Loads the real arena and the real district
## and drives the real player through the InputMap; checks the GDD §19 M4a
## "Done when" criteria (feel and readability still need a human playtest).
##
## Run: godot --headless --fixed-fps 60 res://tests/m4a_tests.tscn
## Exit code 0 = all passed.

const ARENA := preload("res://scenes/levels/combat_gym.tscn")
const DISTRICT := preload("res://scenes/levels/district.tscn")
const TREE_BUILDER := preload("res://scripts/tools/build_humanoid_tree.gd")
const FISTS := preload("res://data/items/fists.tres")
const BAT := preload("res://data/items/bat.tres")
const KNIFE := preload("res://data/items/knife.tres")
const THUG_FISTS := preload("res://data/items/thug_fists.tres")
const STOMP := preload("res://data/attacks/stomp.tres")
const PUNCH_1 := preload("res://data/attacks/punch_1.tres")
const CLIP_DIR := "res://assets/animations/mixamo/"
const MODE_ONE_VS_THREE := 0
const MODE_ONE_VS_ONE := 1
const MODE_DUMMY := 2
## Allowed difference between the tree's playback position and the contact
## marker when the hit window opens (clip seconds): two frames at full speed.
const CONTACT_TOLERANCE := 2.0 / 60.0
## Durations of the M2 placeholder attacks, which the user found too fast.
const M2_PUNCH_1_TOTAL := 0.42
const M2_PUNCH_HEAVY_TOTAL := 1.04
## Scaffold in the district gym yard: deck from 1.3 m up, x 41..46, z -35..-33.
const SCAFFOLD_WEST := Vector3(39.3, 0, -34.0)
const SCAFFOLD_UNDER := Vector3(43.5, 0, -34.0)

var arena: Node3D
var district: District
var player: Player

var _checks: int = 0
var _failures: PackedStringArray = []
var _current: String = ""


func _ready() -> void:
	var tests: Array[StringName] = [
		&"test_clip_pass",
		&"test_debug_key_plays_all_clips",
		&"test_attack_timing_data",
		&"test_contact_frames",
		&"test_reaction_clips",
		&"test_get_up_side",
		&"test_jump_fall_land",
		&"test_crouch",
		&"test_crouch_hold_and_combat",
		&"test_stomp",
		&"test_inventory_pause",
	]
	for test in tests:
		_current = test
		print("== %s" % test)
		await call(test)
		await _teardown()
	var passed := _failures.is_empty()
	print("")
	print("%d checks, %d failed" % [_checks, _failures.size()])
	for failure in _failures:
		print("  FAIL %s" % failure)
	print("ALL PASSED" if passed else "FAILURES")
	get_tree().quit(0 if passed else 1)


# --- M4a.1 Animation pass ------------------------------------------------------


func test_clip_pass() -> void:
	await _load_arena(MODE_DUMMY)
	var tree := player.get_node(^"AnimationTree") as AnimationTree
	var root := tree.tree_root as AnimationNodeBlendTree
	var inputs := player.animator.get_combat_clips()
	# Every gameplay clip is on the combat layer and plays a real animation.
	for clip: String in TREE_BUILDER.COMBAT_CLIPS:
		_check(inputs.has(clip), "combat layer has %s" % clip)
	# Real clips replaced the placeholders wherever one fits.
	var expected_real := {
		&"punch_jab": PUNCH_1.clip,
		&"knife_stab_straight": KNIFE.light_combo[0].clip,
		&"knife_stab_hook": KNIFE.heavy_attack.clip,
		&"punch_uppercut": FISTS.heavy_attack.clip,
	}
	for clip: StringName in expected_real:
		_check(expected_real[clip] == clip, "%s uses its real clip" % clip)
		var node := root.get_node(StringName("clip_%s" % clip)) as AnimationNodeAnimation
		_check(not String(node.animation).begins_with("combat/"), "%s is not a placeholder" % clip)
	for clip in [
		&"hit_react_face",
		&"hit_react_body",
		&"hit_react_stomach",
		&"hit_react_uppercut",
		&"hit_react_head",
		&"knockdown_fall",
		&"getup_from_back",
		&"getup_from_front",
	]:
		var node := root.get_node(StringName("clip_%s" % clip)) as AnimationNodeAnimation
		_check(String(node.animation) == "%s/%s" % [clip, clip], "%s is a real clip" % clip)
	var combat := player.combat
	_check(combat.flinch_clips.has(&"hit_react_face"), "flinch uses hit_react_face")
	_check(combat.knockdown_clip == &"knockdown_fall", "knockdown uses knockdown_fall")
	_check(combat.get_up_clip == &"getup_from_back", "get-up uses getup_from_back")
	# Every non-firearm clip file is on the combat layer (F4 plays all clips),
	# firearm clips are left for M4b.
	var missing: PackedStringArray = []
	var firearm_wired: PackedStringArray = []
	for file in DirAccess.get_files_at(CLIP_DIR):
		if not file.ends_with(".fbx"):
			continue
		var clip := file.get_basename()
		var firearm := clip.begins_with("rifle_") or clip.begins_with("grenade_")
		if firearm and inputs.has(clip):
			firearm_wired.append(clip)
		elif not firearm and not inputs.has(clip):
			missing.append(clip)
	_check(missing.is_empty(), "every non-firearm clip is on the combat layer %s" % [missing])
	_check(firearm_wired.is_empty(), "firearm clips are not wired (M4b) %s" % [firearm_wired])
	# File names are snake_case.
	var bad_names: PackedStringArray = []
	for file in DirAccess.get_files_at(CLIP_DIR):
		if file.ends_with(".fbx") and file.get_basename() != file.get_basename().to_snake_case():
			bad_names.append(file)
	_check(bad_names.is_empty(), "clip files are snake_case %s" % [bad_names])
	# Every animation node of the tree resolves, on the player and on a thug.
	var thug := _enemies()[0]
	var thug_tree := thug.get_node(^"AnimationTree") as AnimationTree
	for character_tree: AnimationTree in [tree, thug_tree]:
		var unresolved := _unresolved_animations(character_tree)
		_check(
			unresolved.is_empty(),
			"%s: every tree animation resolves %s" % [character_tree.get_parent().name, unresolved]
		)
	# Retargeted onto the humanoid skeleton (bone map for the mixamorig12_ prefix).
	var jab := tree.get_animation(&"punch_jab/punch_jab")
	_check(
		String(jab.track_get_path(0)).begins_with("%GeneralSkeleton:"),
		"new clips are retargeted (%s)" % jab.track_get_path(0)
	)
	# Air layer: jump start (standing / running), fall loop, landings.
	var air := root.get_node(&"air_clip") as AnimationNodeTransition
	var air_inputs := PackedStringArray()
	for i in air.get_input_count():
		air_inputs.append(air.get_input_name(i))
	_check(
		air_inputs == PackedStringArray(["jump_standing", "jump_running", "fall"]),
		"air layer: %s" % [air_inputs]
	)
	_check(root.has_node(&"land_shot") and root.has_node(&"land_clip"), "landing one-shot")
	# Locomotion still meets M1.7: points at the clips' ground speeds.
	var locomotion := root.get_node(&"locomotion") as AnimationNodeBlendSpace1D
	var points: Array[float] = []
	for i in locomotion.get_blend_point_count():
		points.append(snappedf(locomotion.get_blend_point_position(i), 0.01))
	_check(points == [0.0, 1.53, 3.91, 5.63], "locomotion points unchanged %s" % [points])
	var crouch := root.get_node(&"crouch") as AnimationNodeBlendSpace1D
	var crouch_walk := crouch.get_blend_point_position(1)
	_check(is_equal_approx(crouch_walk, 1.28), "crouch walk point at its ground speed")
	var crouch_speed := player.movement.crouch_speed
	_check(
		crouch_speed <= crouch_walk * player.animator.max_clip_speed_scale,
		"crouch speed %.2f is covered by the crouch walk clip (no sliding)" % crouch_speed
	)


func test_debug_key_plays_all_clips() -> void:
	await _load_arena(MODE_DUMMY)
	var tree := player.get_node(^"AnimationTree") as AnimationTree
	var clips := player.animator.get_combat_clips()
	var played := {}
	var moved := 0
	for i in clips.size():
		var before := _pose(player)
		_press_event(&"debug_combat_clip")
		await _frames(6)
		var clip := player.animator.combat_clip
		played[clip] = true
		var state := String(tree.get(&"parameters/combat_clip/current_state"))
		if state == String(clip) and _pose_change(before, _pose(player)) > 0.001:
			moved += 1
	var missed := PackedStringArray()
	for clip in clips:
		if not played.has(StringName(clip)):
			missed.append(clip)
	_check(
		played.size() == clips.size(),
		"F4 played %d/%d clips %s" % [played.size(), clips.size(), missed]
	)
	_check(moved == clips.size(), "each clip plays on the character (%d)" % moved)


# --- M4a.2 Clip-driven timing ---------------------------------------------------


func test_attack_timing_data() -> void:
	await _load_arena(MODE_DUMMY)
	var attacks: Array[AttackData] = [STOMP]
	for weapon: WeaponData in [FISTS, BAT, KNIFE, THUG_FISTS]:
		attacks.append_array(weapon.light_combo)
		attacks.append(weapon.heavy_attack)
	for attack in attacks:
		var timing := player.combat.get_attack_timing(attack)
		var clip_end := player.animator.get_clip_end(attack.clip)
		_check(timing.from_clip, "%s: timing from the clip markers" % attack.id)
		_check(attack.speed <= 1.0, "%s: speed %.2f <= 1" % [attack.id, attack.speed])
		_check(
			timing.get_total() >= clip_end - 0.001,
			(
				"%s: no faster than its clip (%.2f s for a %.2f s clip)"
				% [attack.id, timing.get_total(), clip_end]
			)
		)
	# Slower than the M2 attacks (user request).
	var jab := player.combat.get_attack_timing(PUNCH_1)
	_check(
		jab.get_total() > M2_PUNCH_1_TOTAL * 1.4,
		"jab is slower than in M2 (%.2f s vs %.2f s)" % [jab.get_total(), M2_PUNCH_1_TOTAL]
	)
	var heavy := player.combat.get_attack_timing(FISTS.heavy_attack)
	_check(
		heavy.get_total() > M2_PUNCH_HEAVY_TOTAL,
		"heavy is slower than in M2 (%.2f s)" % heavy.get_total()
	)
	for attack: AttackData in THUG_FISTS.light_combo + [THUG_FISTS.heavy_attack]:
		var windup := player.combat.get_attack_timing(attack).windup
		_check(windup >= 0.4, "thug %s telegraphs for %.2f s" % [attack.id, windup])


func test_contact_frames() -> void:
	await _load_arena(MODE_ONE_VS_ONE)
	var contacts: Array = []
	_record_contacts(player, contacts)
	var thug := _enemies()[0]
	_record_contacts(thug, contacts)
	player.health.max_health = 100000.0
	player.health.revive()
	thug.health.max_health = 100000.0
	thug.health.revive()
	thug.ai.enabled = false
	_place(thug, player.global_position + Vector3(0, 0, -1.4))
	# Player: fists combo + heavy, bat combo + heavy, knife combo + heavy.
	for weapon: WeaponData in [null, BAT, KNIFE]:
		if weapon != null:
			player.receive_item(weapon)
			await _frames(2)
		var combo := (weapon if weapon != null else FISTS).light_combo.size()
		for i in combo:
			await _tap(&"attack_light")
			await _until(
				func() -> bool: return player.combat.phase == MeleeCombat.Phase.RECOVERY, 3.0
			)
		await _until(func() -> bool: return player.combat.state == MeleeCombat.State.IDLE, 3.0)
		await _seconds(0.5)
		await _tap(&"attack_heavy")
		await _until(func() -> bool: return player.combat.state == MeleeCombat.State.IDLE, 4.0)
		await _until(func() -> bool: return thug.combat.state == MeleeCombat.State.IDLE, 5.0)
		_place(thug, player.global_position + Vector3(0, 0, -1.4))
	# Thug: let it fight for a while.
	thug.ai.enabled = true
	await _seconds(8.0)
	var clips := {}
	var worst := 0.0
	var worst_clip := &""
	for contact: Array in contacts:
		clips[contact[0]] = true
		var error := absf(float(contact[1]) - float(contact[2]))
		if error > worst:
			worst = error
			worst_clip = contact[0]
	_check(contacts.size() >= 12, "contact moments measured (%d)" % contacts.size())
	_check(clips.size() >= 9, "distinct attack clips measured (%d)" % clips.size())
	_check(
		worst <= CONTACT_TOLERANCE,
		(
			"every hit window opens on the clip's contact frame (worst %.3f s, %s)"
			% [worst, worst_clip]
		)
	)


# --- M4a.3 Reactions on the new clips --------------------------------------------


func test_reaction_clips() -> void:
	await _load_arena(MODE_DUMMY)
	var dummy := _enemies()[0]
	_place(dummy, player.global_position + Vector3(0, 0, -1.4))
	var clips: Array[StringName] = []
	dummy.combat.clip_requested.connect(
		func(clip: StringName, _speed: float, _hold: bool) -> void: clips.append(clip)
	)
	await _tap(&"attack_light")
	await _until(func() -> bool: return not clips.is_empty(), 2.0)
	_check(
		not clips.is_empty() and dummy.combat.flinch_clips.has(clips[0]),
		"a jab plays a flinch clip (%s)" % [clips]
	)
	await _until(func() -> bool: return player.combat.state == MeleeCombat.State.IDLE, 3.0)
	await _seconds(0.8)
	clips.clear()
	player.receive_item(BAT)
	await _frames(2)
	await _tap(&"attack_heavy")
	await _until(func() -> bool: return clips.size() >= 2, 6.0)
	_check(clips.size() >= 1 and clips[0] == &"knockdown_fall", "bat heavy: knockdown clip")
	_check(clips.size() >= 2 and clips[1] == &"getup_from_back", "then the get-up clip")
	var reaction := dummy.combat.get_reaction_time(
		&"hit_react_face", dummy.combat.flinch_speed, MeleeCombat.MARKER_RECOVER
	)
	_check(reaction > 0.3 and reaction < 0.8, "flinch lock from the clip (%.2f s)" % reaction)


func test_get_up_side() -> void:
	await _load_arena(MODE_ONE_VS_THREE)
	_park_enemies()
	var results: Array = []
	var x := -6.0
	for npc in _enemies():
		npc.health.knockout_recovery_time = 2.5
		_place(npc, Vector3(x, 0, -6))
		x += 4.0
		npc.combat.last_hit_impulse = Vector3(0, 0, 200 if x > 0 else -200)
		npc.health.take_damage(1000.0, player)
		var record := func(clip: StringName, _speed: float, _hold: bool) -> void:
			# Emitted while the ragdoll still lies as it fell.
			if String(clip).begins_with("getup_from"):
				results.append([npc.ragdoll.is_face_down(), clip])
		npc.combat.clip_requested.connect(record)
	await _seconds(3.5)
	_check(results.size() == 3, "all three got up (%d)" % results.size())
	var matched := true
	for result: Array in results:
		var expected := &"getup_from_front" if result[0] else &"getup_from_back"
		matched = matched and result[1] == expected
	_check(matched, "get-up clip matches how the ragdoll lies %s" % [results])


# --- Jump, fall, land (user request) ---------------------------------------------


func test_jump_fall_land() -> void:
	await _load_district()
	_freeze_npcs()
	var start := Vector3(-24, 0, -2)
	_place(player, start)
	await _seconds(0.5)
	var animator := player.animator
	_check(animator.air_clip == &"", "on the ground: no air clip")
	await _tap(&"jump")
	await _frames(6)
	_check(animator.air_clip == &"jump_standing", "standing jump clip (%s)" % animator.air_clip)
	await _until(func() -> bool: return player.is_on_floor(), 3.0)
	await _frames(3)
	_check(
		animator.last_land_clip == &"land_standing",
		"standing landing (%s)" % animator.last_land_clip
	)
	# Running jump.
	player.camera_rig.yaw = -PI / 2.0  # look east, along Harbour Road
	Input.action_press(&"move_forward")
	await _seconds(1.0)
	await _tap(&"jump")
	await _frames(6)
	_check(animator.air_clip == &"jump_running", "running jump clip (%s)" % animator.air_clip)
	await _until(func() -> bool: return player.is_on_floor(), 3.0)
	await _frames(3)
	_check(
		animator.last_land_clip == &"land_running", "running landing (%s)" % animator.last_land_clip
	)
	Input.action_release(&"move_forward")
	await _seconds(0.6)
	# A long fall: the fall loop takes over, then a heavy landing.
	_place(player, player.global_position + Vector3(0, 8, 0))
	await _seconds(0.5)
	_check(animator.air_clip == &"fall", "falling loop (%s)" % animator.air_clip)
	await _until(func() -> bool: return player.is_on_floor(), 3.0)
	await _frames(3)
	_check(animator.last_land_clip == &"land_heavy", "heavy landing (%s)" % animator.last_land_clip)


# --- M4a.4 Crouch ------------------------------------------------------------------


func test_crouch() -> void:
	await _load_district()
	_freeze_npcs()
	var movement := player.movement
	_place(player, SCAFFOLD_WEST)
	player.camera_rig.yaw = -PI / 2.0  # look east, into the scaffold
	await _seconds(0.3)
	# Standing, the scaffold blocks the way.
	Input.action_press(&"move_forward")
	await _seconds(1.5)
	Input.action_release(&"move_forward")
	_check(player.global_position.x < 41.0, "standing: blocked by the 1.3 m deck")
	# Crouched, the player fits under it.
	_place(player, SCAFFOLD_WEST)
	await _frames(3)
	await _tap(&"crouch")
	await _frames(3)
	_check(movement.is_crouched, "C crouches")
	var capsule := movement.collision_shape.shape as CapsuleShape3D
	_check(capsule.height < 1.3, "crouched capsule fits under 1.3 m (%.2f)" % capsule.height)
	Input.action_press(&"move_forward")
	var speed := 0.0
	for i in 240:
		await _frames(1)
		speed = maxf(speed, movement.get_horizontal_speed())
		if player.global_position.x >= SCAFFOLD_UNDER.x:
			break
	Input.action_release(&"move_forward")
	_check(player.global_position.x >= SCAFFOLD_UNDER.x - 0.1, "crouch-walked under the deck")
	_check(speed <= movement.crouch_speed + 0.05, "crouch speed (%.2f m/s)" % speed)
	await _seconds(0.5)
	_check(player.animator.get(&"_crouch") > 0.9, "crouch locomotion blended in")
	# Standing up under the deck is blocked.
	await _tap(&"crouch")
	await _seconds(0.5)
	_check(not movement.can_stand(), "no room to stand under the deck")
	_check(movement.is_crouched, "standing up under a ceiling is blocked")
	# Out in the open (wish to stand is still on), the player stands up by itself.
	player.camera_rig.yaw = PI / 2.0  # look west, back out
	Input.action_press(&"move_forward")
	await _until(func() -> bool: return not movement.is_crouched, 6.0)
	Input.action_release(&"move_forward")
	_check(not movement.is_crouched, "stands up once clear")
	_check(player.global_position.x < 41.0, "...only after leaving the deck")
	_check(
		is_equal_approx(capsule.height, 1.8), "standing capsule restored (%.2f)" % capsule.height
	)


func test_crouch_hold_and_combat() -> void:
	await _load_district()
	_freeze_npcs()
	var movement := player.movement
	_place(player, Vector3(-24, 0, -2))
	await _seconds(0.3)
	# Hold mode.
	player.crouch_toggle = false
	Input.action_press(&"crouch")
	await _frames(3)
	_check(movement.is_crouched, "hold mode: crouched while held")
	Input.action_release(&"crouch")
	await _frames(3)
	_check(not movement.is_crouched, "hold mode: up on release")
	player.crouch_toggle = true
	# An attack stands up first, then the buffered attack follows.
	await _tap(&"crouch")
	await _frames(3)
	_check(movement.is_crouched, "toggle: crouched")
	var started: Array[StringName] = []
	player.combat.attack_started.connect(func(a: AttackData) -> void: started.append(a.id))
	await _tap(&"attack_light")
	await _seconds(0.3)
	_check(not movement.is_crouched, "attacking stands up")
	_check(started == [&"punch_1"], "the attack still happens: %s" % [started])
	await _seconds(1.0)
	# Sprinting stands up as well.
	await _tap(&"crouch")
	await _frames(3)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(5)
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	_check(not movement.is_crouched, "sprinting stands up")


# --- M4a.5 Stomp --------------------------------------------------------------------


func test_stomp() -> void:
	await _load_arena(MODE_ONE_VS_THREE)
	_park_enemies()
	var enemies := _enemies()
	var target := enemies[0]
	var other := enemies[1]
	var standing := enemies[2]
	_place(standing, Vector3(14, 0, 14))
	_place(target, Vector3(-3, 0, -4))
	_place(other, Vector3(3, 0, -4))
	for npc in [target, other]:
		npc.health.knockout_recovery_time = 0.0  # stay down
		npc.combat.last_hit_impulse = Vector3.ZERO
		npc.health.take_damage(1000.0, player)
	await _seconds(1.5)
	_check(target.health.is_knocked_out() and other.health.is_knocked_out(), "two bodies down")
	var started: Array[StringName] = []
	player.combat.attack_started.connect(func(a: AttackData) -> void: started.append(a.id))
	var victims: Array[Node3D] = []
	player.combat.hit_landed.connect(
		func(_a: Node3D, victim: Node3D, _attack: AttackData) -> void: victims.append(victim)
	)
	_approach_body(target)
	await _frames(2)
	var before := target.health.downed_health_left
	await _attack(&"attack_light")
	_check(started == [&"stomp"], "attack next to a downed body stomps: %s" % [started])
	_check(victims == [target as Node3D], "the stomp hits the intended body")
	_check(
		is_equal_approx(before - target.health.downed_health_left, STOMP.get_downed_damage()),
		"stomp deals its downed damage (%.0f)" % (before - target.health.downed_health_left)
	)
	_check(
		is_equal_approx(other.health.downed_health_left, other.health.downed_health),
		"the other body is untouched"
	)
	var stomps := 1
	while not target.health.is_dead() and stomps < 6:
		_approach_body(target)
		await _frames(2)
		await _attack(&"attack_heavy")
		stomps += 1
	_check(target.health.is_dead(), "stomps kill past the downed threshold (%d stomps)" % stomps)
	_check(stomps <= 3, "a few stomps are enough (%d)" % stomps)
	# A dead body isn't stomped.
	started.clear()
	_approach_body(target)
	await _frames(2)
	await _tap(&"attack_light")
	await _seconds(0.2)
	_check(started == [&"punch_1"], "no stomp on a dead body: %s" % [started])
	await _until(func() -> bool: return player.combat.state == MeleeCombat.State.IDLE, 3.0)
	await _seconds(0.5)
	# A standing enemy close in front takes priority over a downed body.
	_approach_body(other)
	var forward := -player.camera_rig.get_yaw_basis().z
	_place(standing, player.global_position + forward * 1.3)
	await _frames(3)
	started.clear()
	await _tap(&"attack_light")
	await _seconds(0.2)
	_check(started == [&"punch_1"], "a standing enemy close by is punched instead: %s" % [started])


# --- M4a.6 Inventory pause ------------------------------------------------------------


func test_inventory_pause() -> void:
	await _load_district()
	await _seconds(1.0)
	var hud := district.get_node(^"HUD")
	var npcs := _npcs()
	_check(npcs.size() > 5, "district has NPCs (%d)" % npcs.size())
	_press_event(&"toggle_inventory")
	await _frames(3)
	_check(get_tree().paused, "the inventory overlay pauses the game")
	_check(hud.call(&"is_inventory_open"), "overlay shown")
	var positions := npcs.map(func(n: NpcCharacter) -> Vector3: return n.global_position)
	var player_at := player.global_position
	Input.action_press(&"move_forward")
	await _seconds(1.0)
	Input.action_release(&"move_forward")
	var frozen := true
	for i in npcs.size():
		frozen = frozen and npcs[i].global_position.is_equal_approx(positions[i])
	_check(frozen, "enemies and civilians are frozen")
	_check(player.global_position.is_equal_approx(player_at), "the player is frozen too")
	_press_event(&"toggle_inventory")
	await _frames(3)
	_check(not get_tree().paused, "closing the overlay resumes")
	_check(not hud.call(&"is_inventory_open"), "overlay hidden")
	await _seconds(1.5)
	var moved := 0
	for i in npcs.size():
		if is_instance_valid(npcs[i]) and npcs[i].global_position.distance_to(positions[i]) > 0.3:
			moved += 1
	_check(moved > 0, "NPCs move again after closing (%d)" % moved)
	# Searching a body stays real-time.
	var civilian := _civilians()[0]
	civilian.ai.enabled = false
	_place(civilian, Vector3(-24, 0, -2))
	_place(player, Vector3(-24, 0, -0.5))
	civilian.health.take_damage(1000.0, player)
	await _seconds(1.5)
	_approach_body(civilian)
	await _seconds(0.3)
	Input.action_press(&"interact")
	await _seconds(0.5)
	var progressing := player.interaction.is_holding() and not get_tree().paused
	Input.action_release(&"interact")
	_check(progressing, "searching a body runs in real time (no pause)")


# --- Helpers --------------------------------------------------------------------------


func _record_contacts(character: Node3D, contacts: Array) -> void:
	var combat := character.get(&"combat") as MeleeCombat
	var animator := character.get(&"animator") as PlayerAnimator
	var tree := character.get_node(^"AnimationTree") as AnimationTree
	combat.phase_changed.connect(
		func(phase: MeleeCombat.Phase) -> void:
			if phase != MeleeCombat.Phase.ACTIVE or combat.attack == null:
				return
			var clip := combat.attack.clip
			var marker := animator.get_clip_marker(clip, MeleeCombat.MARKER_HIT)
			# The tree advances after physics: read its position on the next frame,
			# minus that frame's advance.
			var read := func() -> void:
				var position: float = tree.get(
					StringName("parameters/clip_%s/current_position" % clip)
				)
				var step := combat.timing.speed / 60.0 * Engine.time_scale
				contacts.append([clip, position - step, marker])
			read.call_deferred()
	)


func _unresolved_animations(tree: AnimationTree) -> PackedStringArray:
	var missing := PackedStringArray()
	var root := tree.tree_root as AnimationNodeBlendTree
	var nodes: Array[AnimationNode] = []
	for node_name in root.get_node_list():
		nodes.append(root.get_node(node_name))
	while not nodes.is_empty():
		var node: AnimationNode = nodes.pop_back()
		if node is AnimationNodeAnimation:
			var animation := (node as AnimationNodeAnimation).animation
			if not tree.has_animation(animation):
				missing.append(String(animation))
		elif node is AnimationNodeBlendSpace1D:
			var space := node as AnimationNodeBlendSpace1D
			for i in space.get_blend_point_count():
				nodes.append(space.get_blend_point_node(i))
		elif node is AnimationNodeBlendSpace2D:
			var space := node as AnimationNodeBlendSpace2D
			for i in space.get_blend_point_count():
				nodes.append(space.get_blend_point_node(i))
	return missing


func _load_arena(mode: int) -> void:
	arena = ARENA.instantiate()
	arena.set(&"mode", mode)
	add_child(arena)
	player = arena.get_node(^"Player") as Player
	player.require_mouse_capture = false
	await arena.fight_started
	await _frames(2)


func _load_district() -> void:
	district = DISTRICT.instantiate() as District
	add_child(district)
	player = district.get_node(^"Player") as Player
	player.require_mouse_capture = false
	player.capture_mouse_on_start = false
	for i in 240:
		await get_tree().physics_frame
		if not _civilians().is_empty():
			break
	await _seconds(0.3)


func _teardown() -> void:
	for action: StringName in [
		&"move_forward",
		&"move_back",
		&"sprint",
		&"interact",
		&"attack_light",
		&"attack_heavy",
		&"guard",
		&"crouch",
		&"jump",
	]:
		Input.action_release(action)
	get_tree().paused = false
	HitStop.cancel()
	for level: Node in [arena, district]:
		if is_instance_valid(level):
			remove_child(level)
			level.queue_free()
	arena = null
	district = null
	await _frames(3)
	Engine.time_scale = 1.0


func _enemies() -> Array[NpcCharacter]:
	var result: Array[NpcCharacter] = []
	for node in arena.get_node(^"Enemies").get_children():
		if node is NpcCharacter and not node.is_queued_for_deletion():
			result.append(node)
	return result


func _npcs() -> Array[NpcCharacter]:
	var result: Array[NpcCharacter] = []
	for node in get_tree().get_nodes_in_group(&"npcs"):
		if node is NpcCharacter and not node.is_queued_for_deletion():
			result.append(node)
	return result


func _civilians() -> Array[NpcCharacter]:
	var result: Array[NpcCharacter] = []
	for npc in _npcs():
		if npc.ai is CivilianAI:
			result.append(npc)
	return result


func _freeze_npcs() -> void:
	for npc in _npcs():
		npc.ai.enabled = false


func _park_enemies() -> void:
	var x := -18.0
	for npc in _enemies():
		npc.ai.enabled = false
		_place(npc, Vector3(x, 0, -18))
		x += 3.0


func _place(node: Node3D, at: Vector3) -> void:
	node.global_position = at
	if node is CharacterBody3D:
		(node as CharacterBody3D).velocity = Vector3.ZERO
	node.reset_physics_interpolation()


## Puts the player 1.1 m from the downed body, looking at it.
func _approach_body(npc: NpcCharacter) -> void:
	var body := npc.ragdoll.get_root_body().global_position
	body.y = player.global_position.y
	var from := player.global_position - body
	from.y = 0.0
	from = from.normalized() if from.length() > 0.1 else Vector3.BACK
	_place(player, body + from * 1.1)
	player.camera_rig.yaw = atan2(from.x, from.z)


## Rotations of the main bones (to see that a clip moves the character).
func _pose(character: Node3D) -> Array[Quaternion]:
	var skeleton := character.get_node(^"Model/Character/GeneralSkeleton") as Skeleton3D
	var result: Array[Quaternion] = []
	for bone in [
		"Hips",
		"Spine",
		"Chest",
		"Head",
		"LeftUpperArm",
		"RightUpperArm",
		"LeftLowerArm",
		"RightLowerArm",
		"LeftUpperLeg",
		"RightUpperLeg",
	]:
		result.append(skeleton.get_bone_pose_rotation(skeleton.find_bone(bone)))
	return result


func _pose_change(a: Array[Quaternion], b: Array[Quaternion]) -> float:
	var total := 0.0
	for i in a.size():
		total += a[i].angle_to(b[i])
	return total


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _frames(ceili(seconds * 60.0))


## Waits until [param condition] holds, at most [param timeout] seconds.
func _until(condition: Callable, timeout: float) -> void:
	for i in ceili(timeout * 60.0):
		if condition.call():
			return
		await _frames(1)


## Taps an attack and waits until the player is idle again.
func _attack(action: StringName) -> void:
	await _tap(action)
	await _frames(3)
	await _until(func() -> bool: return player.combat.state == MeleeCombat.State.IDLE, 3.0)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)


## For actions read in _unhandled_input.
func _press_event(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event.call_deferred(release)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % message)
	else:
		print("  FAIL %s" % message)
		_failures.append("%s: %s" % [_current, message])
