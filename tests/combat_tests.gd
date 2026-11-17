extends Node
## Headless M2 checks. Drives the real arena and the real player through the
## InputMap, steps physics and checks the M2 "Done when" criteria that can be
## checked without eyes and ears.
##
## Run: godot --headless --fixed-fps 60 res://tests/combat_tests.tscn
## Exit code 0 = all passed.

const ARENA := preload("res://scenes/levels/combat_gym.tscn")
const TEST_GYM := preload("res://scenes/levels/test_gym.tscn")
const BAT := preload("res://data/items/bat.tres")
const FISTS := preload("res://data/items/fists.tres")
const THUG_JAB := preload("res://data/attacks/thug_jab.tres")
const THUG_HEAVY := preload("res://data/attacks/thug_heavy.tres")
const PUNCH_HEAVY := preload("res://data/attacks/punch_heavy.tres")
const MODE_ONE_VS_THREE := 0
const MODE_ONE_VS_ONE := 1
const MODE_DUMMY := 2

var arena: Node3D
var player: Player

var _checks: int = 0
var _failures: PackedStringArray = []
var _current: String = ""


func _ready() -> void:
	var tests: Array[StringName] = [
		&"test_arena_setup",
		&"test_clips_play",
		&"test_guard_pose_layer",
		&"test_light_combo",
		&"test_input_buffering",
		&"test_heavy_hold",
		&"test_guard_block_and_break",
		&"test_dodge",
		&"test_dodge_cancels_recovery",
		&"test_soft_targeting",
		&"test_bat",
		&"test_knockdown_and_get_up",
		&"test_knockout_drop_and_ragdoll",
		&"test_ai_one_vs_three",
		&"test_navigation_around_alley",
		&"test_player_knockout_and_restart",
		&"test_m1_locomotion_regression",
	]
	for test in tests:
		_current = test
		print("== %s" % test)
		await call(test)
		await _teardown()
	Input.action_release(&"guard")
	var passed := _failures.is_empty()
	print("")
	print("%d checks, %d failed" % [_checks, _failures.size()])
	for failure in _failures:
		print("  FAIL %s" % failure)
	print("ALL PASSED" if passed else "FAILURES")
	get_tree().quit(0 if passed else 1)


# --- Tests -------------------------------------------------------------------


func test_arena_setup() -> void:
	await _load_arena(MODE_ONE_VS_THREE)
	var region := arena.get_node(^"NavigationRegion3D") as NavigationRegion3D
	_check(region.navigation_mesh.get_polygon_count() > 0, "navigation mesh baked")
	_check(_enemies().size() == 3, "3 thugs spawned")
	_check(_pickups().size() == 3, "2 bats and a knife in the arena")
	_check(get_tree().get_first_node_in_group(&"combat_director") != null, "director present")
	_check(player.health.health == 150.0, "player at full health")
	_check(Engine.time_scale == 1.0, "time scale normal")
	for weapon: WeaponData in [FISTS, BAT, preload("res://data/items/thug_fists.tres")]:
		var attacks: Array[AttackData] = weapon.light_combo.duplicate()
		attacks.append(weapon.heavy_attack)
		for attack in attacks:
			_check(attack.damage_type == AttackData.DamageType.BLUNT, "%s is blunt" % attack.id)


func test_clips_play() -> void:
	await _load_arena(MODE_DUMMY)
	_park_enemies()
	var clips := player.animator.get_combat_clips()
	_check(clips.size() >= 13, "combat clips in the tree (%d)" % clips.size())
	var tree := player.get_node(^"AnimationTree") as AnimationTree
	for clip in clips:
		_check(player.animator.get_clip_length(clip) > 0.0, "clip %s has an animation" % clip)
		player.animator.play_combat_clip(clip, player.animator.get_clip_length(clip))
		var moved := false
		var start_hand := _bone(player, "RightHand").origin
		var start_hips := _bone(player, "Hips").origin
		for i in 20:
			await _frames(1)
			if (
				_bone(player, "RightHand").origin.distance_to(start_hand) > 0.1
				or _bone(player, "Hips").origin.distance_to(start_hips) > 0.05
			):
				moved = true
		var state := String(tree.get(&"parameters/combat_clip/current_state"))
		_check(state == clip, "clip %s is playing (state %s)" % [clip, state])
		_check(moved, "clip %s moves the model" % clip)
		await _seconds(player.animator.get_clip_length(clip) + 0.3)
	_check(player.animator.combat_clip == &"", "combat layer released after clips")
	var blend: float = tree.get(&"parameters/combat_blend/blend_amount")
	_check(blend < 0.05, "combat layer blended out (%.2f)" % blend)
	# Debug key cycles through the clips.
	_press_event(&"debug_combat_clip")
	await _frames(3)
	_check(player.animator.combat_clip == StringName(clips[0]), "debug key plays the first clip")


func test_guard_pose_layer() -> void:
	await _load_arena(MODE_DUMMY)
	_park_enemies()
	Input.action_press(&"guard")
	Input.action_press(&"move_left")
	await _seconds(0.6)
	_check(player.combat.is_guarding(), "guard state while held")
	var fist := _bone(player, "LeftHand").origin.y
	var chest := _bone(player, "UpperChest").origin.y
	_check(fist > chest + 0.1, "guard pose: fists above the chest (%.2f m)" % (fist - chest))
	var strafe_speed := player.movement.get_horizontal_speed()
	_check(
		absf(strafe_speed - player.movement.strafe_speed) < 0.3,
		"guard strafes (%.2f)" % strafe_speed
	)
	var leg_start := _bone_rotation(player, "LeftLowerLeg")
	var leg_moved := 0.0
	for i in 30:
		await _frames(1)
		leg_moved = maxf(leg_moved, leg_start.angle_to(_bone_rotation(player, "LeftLowerLeg")))
	_check(leg_moved > 0.1, "legs keep stepping under the guard (%.2f)" % leg_moved)
	Input.action_release(&"move_left")
	Input.action_release(&"guard")
	await _seconds(0.3)
	_check(not player.combat.is_guarding(), "guard released")


func test_light_combo() -> void:
	await _load_arena(MODE_DUMMY)
	var dummy := _enemies()[0]
	_place(dummy, player.global_position + Vector3(0, 0, -1.6))
	var started: Array[StringName] = []
	player.combat.attack_started.connect(func(a: AttackData) -> void: started.append(a.id))
	var landed: Array = []
	player.combat.hit_landed.connect(
		func(att: Node3D, vic: Node3D, a: AttackData) -> void: landed.append([att, vic, a.id])
	)
	var states: Array[int] = []
	dummy.combat.state_changed.connect(func(s: int) -> void: states.append(s))
	var saw_hit_stop := false
	var saw_shake := false
	for i in 3:
		await _tap(&"attack_light")
		for f in 14:
			await _frames(1)
			saw_hit_stop = saw_hit_stop or Engine.time_scale < 1.0
			saw_shake = saw_shake or player.camera_rig.get_trauma() > 0.0
	await _seconds(1.0)
	_check(started == [&"punch_1", &"punch_2", &"punch_3"], "full combo started: %s" % [started])
	_check(landed.size() == 3, "3 hits landed (%d)" % landed.size())
	if landed.size() > 0:
		_check(
			landed[0][0] == player and landed[0][1] == dummy, "hit_landed(attacker, victim, attack)"
		)
	_check(
		is_equal_approx(dummy.health.health, 400.0 - 30.0),
		"damage 8+8+14 (%s)" % dummy.health.health
	)
	_check(states.has(MeleeCombat.State.REACTION), "dummy reacted")
	_check(saw_hit_stop, "hit stop happened")
	_check(Engine.time_scale == 1.0, "time scale restored")
	_check(saw_shake, "camera shook")
	_check(player.combat.state == MeleeCombat.State.IDLE, "player back to idle")


func test_input_buffering() -> void:
	await _load_arena(MODE_DUMMY)
	var dummy := _enemies()[0]
	_place(dummy, player.global_position + Vector3(0, 0, -1.6))
	var started: Array[StringName] = []
	player.combat.attack_started.connect(func(a: AttackData) -> void: started.append(a.id))
	# Second tap lands during the first punch's windup: it must not be dropped.
	await _tap(&"attack_light")
	await _frames(2)
	_check(player.combat.phase == MeleeCombat.Phase.WINDUP, "first punch in windup")
	await _tap(&"attack_light")
	await _seconds(1.2)
	_check(started == [&"punch_1", &"punch_2"], "buffered tap chained: %s" % [started])
	# After the combo window, the combo starts over.
	started.clear()
	await _seconds(0.5)
	await _tap(&"attack_light")
	await _seconds(0.6)
	_check(started == [&"punch_1"], "combo resets after a pause: %s" % [started])


func test_heavy_hold() -> void:
	await _load_arena(MODE_DUMMY)
	var dummy := _enemies()[0]
	_place(dummy, player.global_position + Vector3(0, 0, -1.8))
	var started: Array[StringName] = []
	player.combat.attack_started.connect(func(a: AttackData) -> void: started.append(a.id))
	Input.action_press(&"attack_light")
	await _seconds(0.5)
	Input.action_release(&"attack_light")
	await _seconds(1.5)
	_check(started == [&"punch_heavy"], "hold = heavy only: %s" % [started])
	_check(
		is_equal_approx(dummy.health.health, 380.0), "heavy damage 20 (%s)" % dummy.health.health
	)
	started.clear()
	await _tap(&"attack_heavy")
	await _seconds(1.5)
	_check(started == [&"punch_heavy"], "heavy action: %s" % [started])


func test_guard_block_and_break() -> void:
	await _load_arena(MODE_DUMMY)
	var dummy := _enemies()[0]
	_place(dummy, player.global_position + Vector3(0, 0, -1.4))
	dummy.set_physics_process(false)  # driven by hand below
	var results: Array[int] = []
	player.combat.hit_taken.connect(
		func(_a: Node3D, _b: AttackData, r: int) -> void: results.append(r)
	)
	Input.action_press(&"guard")
	await _frames(5)
	_check(player.combat.is_guarding(), "player guarding")
	await _drive_npc_attack(dummy, false)
	_check(results == [HurtboxComponent.HitResult.BLOCKED], "light attack blocked: %s" % [results])
	_check(player.health.health == 150.0, "no damage through guard")
	results.clear()
	await _drive_npc_attack(dummy, true)
	_check(
		results == [HurtboxComponent.HitResult.GUARD_BROKEN], "heavy breaks guard: %s" % [results]
	)
	_check(
		is_equal_approx(player.health.health, 150.0 - THUG_HEAVY.damage * 0.5),
		"guard break damage (%s)" % player.health.health
	)
	Input.action_release(&"guard")
	await _seconds(1.2)
	# Guard only covers the front.
	_place(player, Vector3(0, 0, 8))
	_place(dummy, Vector3(0, 0, 6.6))
	Input.action_press(&"guard")
	await _frames(5)
	player.camera_rig.yaw = PI
	await _seconds(0.5)
	_check(player.get_facing().z > 0.9, "player turned away while guarding")
	results.clear()
	await _drive_npc_attack(dummy, false)
	_check(results == [HurtboxComponent.HitResult.HIT], "hit from behind lands: %s" % [results])
	Input.action_release(&"guard")


func test_dodge() -> void:
	await _load_arena(MODE_DUMMY)
	var dummy := _enemies()[0]
	_place(dummy, player.global_position + Vector3(0, 0, -1.3))
	dummy.set_physics_process(false)
	var results: Array[int] = []
	player.combat.hit_taken.connect(
		func(_a: Node3D, _b: AttackData, r: int) -> void: results.append(r)
	)
	var start := player.global_position
	Input.action_press(&"guard")
	await _frames(3)
	# Dodge just before the thug's active phase (windup 0.5 s).
	var dodge_at := int((THUG_JAB.windup - 0.12) * 60.0)
	var saw_dodge := false
	var intent := _npc_intent(dummy, false)
	for frame in 70:
		if frame == dodge_at:
			Input.action_press(&"dodge")
		if frame == dodge_at + 2:
			Input.action_release(&"dodge")
		_step_npc(dummy, intent)
		intent = _npc_intent(dummy, false, false)
		await _frames(1)
		saw_dodge = saw_dodge or player.combat.state == MeleeCombat.State.DODGE
	Input.action_release(&"guard")
	_check(saw_dodge, "dodge while guarding")
	_check(player.health.health == 150.0, "no damage when dodging (%s)" % player.health.health)
	var moved := player.global_position.distance_to(start)
	_check(absf(moved - player.combat.dodge_distance) < 0.4, "dodge distance (%.2f m)" % moved)
	_check(player.global_position.z > start.z, "dodged backwards without input")
	_check(player.is_on_floor(), "on the floor after dodging")


func test_dodge_cancels_recovery() -> void:
	await _load_arena(MODE_DUMMY)
	_park_enemies()
	await _tap(&"attack_light")
	var reached_recovery := false
	for i in 30:
		await _frames(1)
		if player.combat.phase == MeleeCombat.Phase.RECOVERY:
			reached_recovery = true
			break
	_check(reached_recovery, "attack reached recovery")
	Input.action_press(&"guard")
	Input.action_press(&"dodge")
	await _frames(2)
	Input.action_release(&"dodge")
	Input.action_release(&"guard")
	_check(player.combat.state == MeleeCombat.State.DODGE, "dodge cancelled the recovery")


func test_soft_targeting() -> void:
	await _load_arena(MODE_ONE_VS_THREE)
	var thugs := _enemies()
	for thug in thugs:
		thug.ai.enabled = false
	var origin := player.global_position
	var yaws := [0.6, 0.0, -0.6]
	for i in 3:
		var dir := Vector3(-sin(yaws[i]), 0, -cos(yaws[i]))
		_place(thugs[i], origin + dir * 2.2)
	await _frames(5)
	for i in 3:
		for thug in thugs:
			thug.health.revive()
		player.camera_rig.yaw = yaws[i]
		await _frames(3)
		_check(player.combat.current_target == thugs[i].combat, "target %d chosen by camera" % i)
		await _tap(&"attack_light")
		await _seconds(0.7)
		for j in 3:
			var hit := thugs[j].health.health < thugs[j].health.max_health
			_check(hit == (i == j), "aimed at %d: thug %d hit=%s" % [i, j, hit])
		_place(player, origin)
		for j in 3:
			_place(thugs[j], origin + Vector3(-sin(yaws[j]), 0, -cos(yaws[j])) * 2.2)
		await _seconds(0.6)
	# No target in view: attack goes where the camera looks.
	player.camera_rig.yaw = PI
	await _frames(3)
	_check(player.combat.current_target == null, "no target behind the camera")


func test_bat() -> void:
	await _load_arena(MODE_DUMMY)
	var dummy := _enemies()[0]
	_place(dummy, player.global_position + Vector3(0, 0, -6))
	var bat := _pickups().filter(func(p: Node) -> bool: return p.weapon == BAT)[0] as RigidBody3D
	bat.global_transform = Transform3D(
		Basis(Vector3.RIGHT, PI / 2), player.global_position + Vector3(0, 0.1, -0.9)
	)
	bat.linear_velocity = Vector3.ZERO
	await _seconds(0.3)
	_check(player.interaction.current_target != null, "bat is the interaction target")
	_press_event(&"interact")
	await _frames(3)
	_check(player.combat.weapon == BAT, "bat equipped")
	var socket := player.get_node(^"Model/Character/GeneralSkeleton/RightHandAttachment/Grip")
	_check(socket.get_child_count() == 1, "bat visible in hand")
	await _seconds(0.5)
	var hands := _bone(player, "LeftHand").origin.distance_to(_bone(player, "RightHand").origin)
	_check(hands < 0.2, "both hands on the bat while idle (%.2f m apart)" % hands)
	_check(not is_instance_valid(bat) or bat.is_queued_for_deletion(), "pickup removed")
	_place(dummy, player.global_position + Vector3(0, 0, -2.0))
	var timeline: Array = []
	player.combat.phase_changed.connect(
		func(p: int) -> void: timeline.append([p, Time.get_ticks_msec()])
	)
	await _tap(&"attack_light")
	await _seconds(0.08)
	var hitbox := player.get_node(^"Model/Hitbox") as HitboxComponent
	_check(is_equal_approx(hitbox.position.z, -1.25), "bat reach (%.2f)" % hitbox.position.z)
	await _seconds(1.0)
	_check(
		is_equal_approx(dummy.health.health, 400.0 - 14.0),
		"bat damage 14 (%s)" % dummy.health.health
	)
	# Drop with the drop key.
	var before := _pickups().size()
	_press_event(&"drop_weapon")
	await _frames(3)
	_check(player.combat.weapon == null, "bat dropped")
	_check(_pickups().size() == before + 1, "dropped bat is a pickup again")
	_check(socket.get_child_count() == 0, "hand empty")
	var dropped := _pickups()[-1] as WeaponPickup
	_check(dropped.weapon == BAT, "dropped pickup carries the bat data")


func test_knockdown_and_get_up() -> void:
	await _load_arena(MODE_DUMMY)
	var dummy := _enemies()[0]
	_place(dummy, player.global_position + Vector3(0, 0, -1.8))
	player.receive_item(BAT)
	await _frames(2)
	var states: Array[int] = []
	dummy.combat.state_changed.connect(func(s: int) -> void: states.append(s))
	Input.action_press(&"attack_light")
	await _seconds(0.5)
	Input.action_release(&"attack_light")
	await _seconds(0.75)
	_check(dummy.combat.state == MeleeCombat.State.KNOCKDOWN, "bat heavy knocks down")
	var health := dummy.health.health
	await _tap(&"attack_light")
	await _seconds(0.6)
	_check(dummy.health.health == health, "no hits while down")
	await _seconds(2.5)
	_check(dummy.combat.state == MeleeCombat.State.IDLE, "got up again")
	_check(states.has(MeleeCombat.State.KNOCKDOWN), "knockdown state seen")


func test_knockout_drop_and_ragdoll() -> void:
	await _load_arena(MODE_DUMMY)
	var dummy := _enemies()[0]
	_place(dummy, player.global_position + Vector3(0, 0, -1.6))
	dummy.inventory.add_item(BAT)
	await _frames(2)
	var ko: Array = []
	dummy.health.knocked_out.connect(func(v: Node3D, by: Node3D) -> void: ko.append([v, by]))
	dummy.health.health = 5.0
	var before := _pickups().size()
	await _tap(&"attack_light")
	await _seconds(0.6)
	_check(ko.size() == 1, "knocked_out emitted once")
	if ko.size() == 1:
		_check(ko[0][0] == dummy and ko[0][1] == player, "knocked_out(victim, by)")
	_check(dummy.combat.is_knocked_out(), "dummy knocked out")
	_check(dummy.health.state == HealthComponent.State.KNOCKED_OUT, "health state is KNOCKED_OUT")
	_check(dummy.ragdoll.is_active, "ragdoll active")
	var skeleton := dummy.get_node(^"Model/Character/GeneralSkeleton")
	var bodies := skeleton.find_children("*", "PhysicalBone3D", true, false)
	_check(bodies.size() == dummy.ragdoll.bones.size(), "physical bones (%d)" % bodies.size())
	_check(dummy.combat.weapon == null, "weapon dropped on knockout")
	_check(_pickups().size() == before + 1, "dropped bat in the world")
	_check(player.combat.current_target == null, "knocked-out enemy isn't a target")
	var root := dummy.ragdoll.get_root_body()
	await _seconds(2.0)
	var y := root.global_position.y
	_check(y < 0.4 and y > -0.2, "ragdoll pelvis on the floor (%.2f m, standing 0.9)" % y)


func test_ai_one_vs_three() -> void:
	await _load_arena(MODE_ONE_VS_THREE)
	player.health.max_health = 100000.0
	player.health.revive()
	var thugs := _enemies()
	var director := get_tree().get_first_node_in_group(&"combat_director") as CombatDirector
	var max_attacking := 0
	var max_tokens := 0
	var attackers := {}
	var windups: Array[float] = []
	var windup_start := {}
	var min_windup := INF
	for attack: AttackData in [THUG_JAB, THUG_HEAVY, preload("res://data/attacks/thug_hook.tres")]:
		min_windup = minf(min_windup, attack.windup)
	var closest := {}
	for thug in thugs:
		thug.combat.phase_changed.connect(
			func(p: int) -> void:
				if p == MeleeCombat.Phase.WINDUP:
					windup_start[thug] = Engine.get_physics_frames()
				elif p == MeleeCombat.Phase.ACTIVE and windup_start.has(thug):
					windups.append((Engine.get_physics_frames() - windup_start[thug]) / 60.0)
		)
		thug.combat.attack_started.connect(func(_a: AttackData) -> void: attackers[thug] = true)
		closest[thug] = INF
	var telegraphed := true
	for frame in 25 * 60:
		await _frames(1)
		var attacking := 0
		for thug in thugs:
			if thug.combat.state == MeleeCombat.State.ATTACK:
				attacking += 1
				if thug.combat.phase == MeleeCombat.Phase.WINDUP:
					telegraphed = telegraphed and _has_overlay(thug)
			closest[thug] = minf(
				closest[thug], thug.global_position.distance_to(player.global_position)
			)
		max_attacking = maxi(max_attacking, attacking)
		max_tokens = maxi(max_tokens, director.get_attacker_count())
	_check(max_attacking <= 2, "never more than 2 attacking (%d)" % max_attacking)
	_check(max_tokens <= 2, "never more than 2 tokens (%d)" % max_tokens)
	_check(attackers.size() >= 2, "several thugs took turns (%d)" % attackers.size())
	_check(player.health.health < player.health.max_health, "thugs landed hits")
	_check(telegraphed, "every windup is telegraphed (red overlay)")
	_check(not windups.is_empty(), "thug windups measured (%d)" % windups.size())
	var shortest: float = windups.min() if not windups.is_empty() else 0.0
	_check(
		shortest >= min_windup - 1.0 / 60.0,
		(
			"every attack can be seen coming: shortest windup %.2f s (min %.2f)"
			% [shortest, min_windup]
		)
	)
	for thug in thugs:
		_check(closest[thug] < 2.0, "%s reached the player (%.1f m)" % [thug.name, closest[thug]])
	# Knock them all out: tokens are returned, nobody attacks.
	for thug in thugs:
		thug.health.take_damage(1000.0, player)
	await _frames(5)
	_check(director.get_attacker_count() == 0, "tokens returned on knockout")


func test_navigation_around_alley() -> void:
	await _load_arena(MODE_ONE_VS_ONE)
	var thug := _enemies()[0]
	_place(thug, Vector3(14, 0, -8))
	_place(player, Vector3(9, 0, -8))
	player.health.max_health = 100000.0
	player.health.revive()
	var map := thug.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, Vector3(14, 0, -8), Vector3(9, 0, -8), true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	_check(
		path.size() > 2 and length > 7.5,
		"path detours around the alley wall (%.1f m, straight 5)" % length
	)
	var reached := false
	for frame in 15 * 60:
		await _frames(1)
		if thug.global_position.distance_to(player.global_position) < 3.5:
			reached = true
			break
	_check(reached, "thug navigated out of the alley to the player")


func test_player_knockout_and_restart() -> void:
	await _load_arena(MODE_ONE_VS_THREE)
	var thug := _enemies()[0]
	player.health.take_damage(1000.0, thug)
	await _frames(3)
	_check(player.combat.is_knocked_out(), "player knocked out")
	_check(player.ragdoll.is_active, "player ragdoll")
	_check(player.collision_layer == 0, "player body out of the way")
	await _seconds(1.0)
	for t in _enemies():
		_check(t.ai.target == null, "thugs stop targeting a knocked-out player")
	for t in _enemies():
		t.health.take_damage(1000.0, player)
	await _frames(2)
	arena.start_fight()
	await _frames(3)
	_check(not player.combat.is_knocked_out(), "player revived")
	_check(not player.ragdoll.is_active, "player ragdoll removed")
	var player_skeleton := player.get_node(^"Model/Character/GeneralSkeleton")
	_check(
		player_skeleton.find_children("*", "PhysicalBone3D", true, false).is_empty(),
		"physical bones freed"
	)
	_check(player.health.health == player.health.max_health, "player health full")
	_check(_enemies().size() == 3, "3 fresh thugs")
	var alive := 0
	for t in _enemies():
		if not t.combat.is_knocked_out():
			alive += 1
	_check(alive == 3, "all fresh thugs standing")
	_check(_pickups().size() == 3, "weapons reset")
	arena.set(&"mode", MODE_ONE_VS_ONE)
	_press_event(&"next_fight_mode")
	await _frames(3)
	_check(arena.mode == MODE_DUMMY, "next mode cycles")
	_check(_enemies().size() == 1 and not _enemies()[0].ai.enabled, "dummy mode spawns a dummy")


func test_m1_locomotion_regression() -> void:
	var gym := TEST_GYM.instantiate()
	add_child(gym)
	arena = gym
	player = gym.get_node(^"Player") as Player
	player.require_mouse_capture = false
	await _frames(5)
	Input.action_press(&"move_forward")
	await _seconds(0.6)
	var speed := player.movement.get_horizontal_speed()
	_check(absf(speed - player.movement.run_speed) < 0.3, "M1 run speed (%.2f)" % speed)
	Input.action_release(&"move_forward")
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"jump")
	await _frames(10)
	_check(not player.is_on_floor(), "M1 jump")
	await _seconds(1.5)
	var started: Array[StringName] = []
	player.combat.attack_started.connect(func(a: AttackData) -> void: started.append(a.id))
	await _tap(&"attack_light")
	await _frames(3)
	_check(started == [&"punch_1"], "punching works in the M1 gym too: %s" % [started])


# --- Helpers -----------------------------------------------------------------


func _load_arena(mode: int) -> void:
	arena = ARENA.instantiate()
	arena.set(&"mode", mode)
	add_child(arena)
	player = arena.get_node(^"Player") as Player
	player.require_mouse_capture = false
	await arena.fight_started
	await _frames(2)


func _teardown() -> void:
	for action in [
		&"attack_light", &"attack_heavy", &"guard", &"dodge", &"move_left", &"move_forward"
	]:
		Input.action_release(action)
	if is_instance_valid(arena):
		remove_child(arena)
		arena.queue_free()
	await _frames(2)
	Engine.time_scale = 1.0


func _enemies() -> Array[NpcCharacter]:
	var result: Array[NpcCharacter] = []
	for node in arena.get_node(^"Enemies").get_children():
		if node is NpcCharacter and not node.is_queued_for_deletion():
			result.append(node)
	return result


func _pickups() -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().get_nodes_in_group(&"weapon_pickups"):
		if not node.is_queued_for_deletion():
			result.append(node)
	return result


func _park_enemies() -> void:
	for npc in _enemies():
		npc.ai.enabled = false
		_place(npc, Vector3(-18, 0, -18))


func _place(node: Node3D, at: Vector3) -> void:
	node.global_position = at
	if node is CharacterBody3D:
		(node as CharacterBody3D).velocity = Vector3.ZERO
	node.reset_physics_interpolation()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _frames(ceili(seconds * 60.0))


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)


## For actions the player reads in _unhandled_input.
func _press_event(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event.call_deferred(release)


func _npc_intent(npc: NpcCharacter, heavy: bool, press: bool = true) -> MeleeCombat.Intent:
	var intent := MeleeCombat.Intent.new()
	var to_player := player.global_position - npc.global_position
	to_player.y = 0.0
	intent.look_direction = to_player.normalized()
	intent.target = player.combat
	intent.light = press and not heavy
	intent.heavy = press and heavy
	return intent


func _step_npc(npc: NpcCharacter, intent: MeleeCombat.Intent) -> void:
	var delta := 1.0 / 60.0
	npc.combat.physics_update(delta, intent)
	var move := PlayerMovement.Intent.new()
	npc.combat.apply_to_movement(move)
	npc.movement.physics_update(delta, move)


## Runs one attack of a hand-driven NPC to the end.
func _drive_npc_attack(npc: NpcCharacter, heavy: bool) -> void:
	_step_npc(npc, _npc_intent(npc, heavy))
	for frame in 150:
		await _frames(1)
		_step_npc(npc, _npc_intent(npc, heavy, false))
		if npc.combat.state == MeleeCombat.State.IDLE:
			break


func _has_overlay(npc: NpcCharacter) -> bool:
	var mesh := npc.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	return mesh.material_overlay != null


## Global transform of a bone of a character's model.
func _bone(character: Node3D, bone: String) -> Transform3D:
	var skeleton := character.get_node(^"Model/Character/GeneralSkeleton") as Skeleton3D
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))


func _bone_rotation(character: Node3D, bone: String) -> Quaternion:
	var skeleton := character.get_node(^"Model/Character/GeneralSkeleton") as Skeleton3D
	return skeleton.get_bone_pose_rotation(skeleton.find_bone(bone))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % message)
	else:
		print("  FAIL %s" % message)
		_failures.append("%s: %s" % [_current, message])
