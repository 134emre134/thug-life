extends "res://tests/m4b_test_base.gd"
## Headless M4b checks (firearm and ammo, weapon switching, cover, ranged
## enemy, mixed fight, balance). Loads the real arena and the real district
## and drives the real player through the InputMap; checks the GDD §19 M4b
## "Done when" criteria (feel and readability still need a human playtest).
##
## Run: godot --headless --fixed-fps 60 res://tests/m4b_tests.tscn
## Exit code 0 = all passed.

const BAT := preload("res://data/items/bat.tres")
const RIFLE_THUG := preload("res://scenes/npc/rifle_thug.tscn")
const THUG_SHOT := preload("res://data/attacks/thug_rifle_shot.tres")
const RIFLE_THUG_LOOT := preload("res://data/loot/rifle_thug.tres")
const MODE_ONE_VS_ONE := 1
const MODE_DUMMY := 2
const MODE_MIXED := 3
## Arena layout (combat_gym.tscn).
const ARENA_DUMMY := Vector3(0, 0, -6)
const ARENA_PILLAR := Vector3(-8, 0, 6)
const ARENA_LOW_COVER := Vector3(-6, 0, -4)  # 2.4 x 0.9 x 0.6, long side along x
const ARENA_ALLEY_WALL_END := Vector3(11.8, 0, 7)  # west face of AlleyWallW, south end


func _ready() -> void:
	var tests: Array[StringName] = [
		&"test_firearm_data",
		&"test_pickup_and_shots_hit_crosshair",
		&"test_shot_behind_cover_edge",
		&"test_shot_hits_knocked_down",
		&"test_ammo_and_reload",
		&"test_weapon_switching",
		&"test_switching_mid_fight",
		&"test_cover_low",
		&"test_cover_high_peek",
		&"test_ranged_thug",
		&"test_shooter_limit",
		&"test_melee_beats_rifle_thug",
		&"test_mixed_fight",
		&"test_district_firearms",
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


# --- M4b.1 Firearm and ammo -----------------------------------------------------


func test_firearm_data() -> void:
	_check(RIFLE is FirearmData, "the rifle is FirearmData (a WeaponData)")
	_check(RIFLE.get_slot() == ItemData.Slot.FIREARM, "the rifle goes in the firearm slot")
	var shot := RIFLE.fire_attack
	_check(shot != null and shot.damage_type == AttackData.DamageType.FIREARM, "firearm damage")
	_check(not shot.can_be_blocked, "shots can't be blocked by a guard")
	_check(RIFLE.ammo_item == MAGAZINE, "ammo is the rifle magazine")
	_check(MAGAZINE.get_slot() == ItemData.Slot.POCKET, "the magazine is a pocket item")
	_check(RIFLE.light_combo.is_empty() and RIFLE.heavy_attack == null, "no melee with the rifle")
	_check(RIFLE.ready_clip == &"rifle_ready", "rifle ready pose")
	var magazines := 0.0
	for entry in RIFLE_THUG_LOOT.entries:
		if entry.item == MAGAZINE:
			magazines += entry.chance
	_check(magazines >= 0.8, "rifle thugs carry magazines (%.1f on average)" % magazines)
	await _load_arena(MODE_DUMMY)
	var tree := player.get_node(^"AnimationTree") as AnimationTree
	var root := tree.tree_root as AnimationNodeBlendTree
	for node in [&"rifle_strafe", &"rifle_blend", &"upper_clip", &"upper_shot"]:
		_check(root.has_node(node), "animation tree has %s" % node)
	for clip in [&"rifle_fire", &"rifle_reload", &"rifle_ready", &"rifle_hit_react"]:
		var found := root.has_node(StringName("upper_%s" % clip))
		found = found or root.has_node(StringName("clip_%s" % clip))
		_check(found, "%s is wired" % clip)
	_check(player.animator.get_clip_marker(&"rifle_reload", &"reload") > 0.0, "reload marker")
	_check(player.inventory.firearm_slot_active, "firearm slot unlocked")


func test_pickup_and_shots_hit_crosshair() -> void:
	await _load_arena(MODE_DUMMY)
	var dummy := _enemies()[0]
	var pickup := _rifle_pickup()
	_check(pickup != null, "a rifle lies in the arena")
	if pickup == null:
		return
	_place(player, pickup.global_position + Vector3(0, 0, -1.0))
	player.camera_rig.yaw = PI  # look south, at the rifle
	player.camera_rig.pitch = -0.4
	await _seconds(0.3)
	_press_event(&"interact")
	await _frames(5)
	var inventory := player.inventory
	_check(inventory.firearm == RIFLE and inventory.firearm_drawn, "rifle picked up and in hand")
	_check(inventory.firearm_rounds == RIFLE.magazine_size, "full magazine")
	_check(player.combat.held_visual != null, "rifle visual in the hand")
	var hud := arena.get_node(^"HUD")
	var ammo := hud.get_node(^"HealthBar/Ammo") as Label
	_check(ammo.text.begins_with("8 / 8"), "ammo on the HUD (%s)" % ammo.text)

	# Far (14 m) and close (3 m): the shot hits the dummy under the crosshair.
	var shot_signals: Array = []
	player.combat.shot_fired.connect(
		func(shooter: Node3D, weapon: WeaponData) -> void: shot_signals.append([shooter, weapon])
	)
	var landed: Array = []
	player.combat.hit_landed.connect(
		func(_a: Node3D, victim: Node3D, attack: AttackData) -> void:
			landed.append([victim, attack])
	)
	for distance in [14.0, 3.0]:
		_place(player, ARENA_DUMMY + Vector3(0, 0, distance))
		await _frames(2)
		var health := dummy.health.health
		await _aim_at(ARENA_DUMMY + Vector3.UP * 1.2)
		var on_target := _crosshair_on(dummy)
		_check(on_target, "%.0f m: crosshair on the dummy" % distance)
		await _fire()
		_check(player.ranged.last_hit == dummy, "%.0f m: the shot hit the dummy" % distance)
		_check(
			is_equal_approx(dummy.health.health, health - RIFLE.fire_attack.damage),
			"%.0f m: firearm damage (%.0f -> %.0f)" % [distance, health, dummy.health.health]
		)
		Input.action_release(&"aim")
		await _frames(10)
	# Crosshair beside the dummy: no hit.
	_place(player, ARENA_DUMMY + Vector3(0, 0, 8))
	var before := dummy.health.health
	await _aim_at(ARENA_DUMMY + Vector3(1.6, 1.2, 0))
	# On a wall the shot lands on the crosshair point (before the recoil kick).
	var aim_point := player.aim.aim_point
	await _fire()
	_check(dummy.health.health == before, "crosshair beside the dummy: miss")
	_check(
		player.ranged.last_shot_end.distance_to(aim_point) < 0.25,
		(
			"shot ends at the crosshair point (%.2f m off)"
			% player.ranged.last_shot_end.distance_to(aim_point)
		)
	)
	Input.action_release(&"aim")
	_check(shot_signals.size() == player.ranged.shots_fired, "shot_fired for every shot")
	_check(
		(
			not shot_signals.is_empty()
			and shot_signals[0][0] == player
			and shot_signals[0][1] == RIFLE
		),
		"shot_fired(shooter, weapon)"
	)
	_check(landed.size() == 2 and landed[0][0] == dummy, "landed shots reported as hit_landed")
	_check(inventory.firearm_rounds == RIFLE.magazine_size - 3, "three rounds used")
	_check(player.is_in_group(&"player") and player.combat.is_in_group(&"combatants"), "groups")


## M1.4 "behind cover edges": the crosshair sees past a pillar the chest
## doesn't; the shot stops at the pillar and the HUD marks the line of fire.
func test_shot_behind_cover_edge() -> void:
	await _load_arena(MODE_DUMMY)
	_park_enemies()
	player.receive_item(RIFLE)
	_place(player, ARENA_PILLAR + Vector3(0, 0, 1.1))
	player.camera_rig.yaw = 0.0
	player.camera_rig.pitch = -0.05
	Input.action_press(&"aim")
	await _seconds(0.5)
	_check(player.aim.is_obstructed, "line of fire blocked by the pillar")
	var marker := arena.get_node(^"HUD/BlockedMarker") as Control
	await _frames(2)
	_check(marker.visible, "HUD shows the blocked marker")
	await _fire()
	var end := player.ranged.last_shot_end
	_check(
		end.distance_to(player.aim.obstructed_point) < 0.3,
		(
			"shot stops where the line of fire is blocked (%.2f m)"
			% end.distance_to(player.aim.obstructed_point)
		)
	)
	_check(end.z > ARENA_PILLAR.z, "the shot hit the pillar, not the crosshair point")
	Input.action_release(&"aim")


## No knockdown i-frames (M4a): a shot at a knocked-down (not knocked-out)
## target lands, deals damage and starts no new reaction.
func test_shot_hits_knocked_down() -> void:
	await _load_arena(MODE_DUMMY)
	var dummy := _enemies()[0]
	player.receive_item(RIFLE)
	_place(player, ARENA_DUMMY + Vector3(0, 0, 6))
	await _aim_at(ARENA_DUMMY + Vector3.UP * 1.0)
	var knockdown := BAT.heavy_attack
	dummy.hurtbox.receive_hit(player, knockdown, Vector3.FORWARD)
	await _frames(20)
	_check(dummy.combat.state == MeleeCombat.State.KNOCKDOWN, "dummy knocked down")
	var health := dummy.health.health
	await _aim_at(dummy.global_position + Vector3.UP * 0.4)
	_check(dummy.combat.state == MeleeCombat.State.KNOCKDOWN, "still down")
	await _fire()
	_check(
		dummy.health.health < health,
		"the shot lands (%.0f -> %.0f)" % [health, dummy.health.health]
	)
	_check(dummy.combat.state == MeleeCombat.State.KNOCKDOWN, "no new reaction")
	Input.action_release(&"aim")


func test_ammo_and_reload() -> void:
	await _load_arena(MODE_DUMMY)
	_park_enemies()
	var inventory := player.inventory
	player.receive_item(RIFLE)
	_place(player, Vector3(0, 0, 8))
	await _aim_at(Vector3(0, 1.5, -22))
	for i in RIFLE.magazine_size:
		await _fire(false)
	_check(inventory.firearm_rounds == 0, "magazine used up (%d)" % inventory.firearm_rounds)
	_check(player.ranged.shots_fired == RIFLE.magazine_size, "8 shots")
	var dry := [0]
	player.ranged.dry_fired.connect(func() -> void: dry[0] += 1)
	await _fire(false)
	_check(player.ranged.shots_fired == RIFLE.magazine_size, "empty: no shot")
	_check(dry[0] == 1, "empty: dry click")
	_check(not player.ranged.is_reloading, "no magazine: no reload")
	Input.action_release(&"aim")

	# Pick up both magazine pickups (real interaction).
	for pickup in _magazine_pickups():
		_place(player, pickup.global_position + Vector3(0, 0, -0.8))
		player.camera_rig.yaw = PI
		player.camera_rig.pitch = -0.5
		await _seconds(0.3)
		_press_event(&"interact")
		await _frames(5)
	_check(inventory.pockets.count(MAGAZINE) == 2, "two magazines in the pockets")
	var hud_ammo := arena.get_node(^"HUD/HealthBar/Ammo") as Label
	_check(hud_ammo.text == "0 / 8  +2", "HUD: rounds and spare magazines (%s)" % hud_ammo.text)

	# Reload with R: the magazine goes in at the clip's marker.
	_press(&"reload")
	await _frames(2)
	_check(player.ranged.is_reloading, "R reloads")
	var load_at := RIFLE.reload_speed
	load_at = player.animator.get_clip_marker(&"rifle_reload", &"reload") / load_at
	await _seconds(load_at - 0.2)
	_check(inventory.firearm_rounds == 0, "not loaded before the marker")
	await _seconds(0.3)
	_check(inventory.firearm_rounds == RIFLE.magazine_size, "loaded at the marker")
	_check(inventory.pockets.count(MAGAZINE) == 1, "one magazine used")
	await _until(func() -> bool: return not player.ranged.is_reloading, 2.0)
	_check(not player.ranged.is_reloading, "reload finished")
	_check(player.animator.upper_clip == &"", "reload clip done")

	# An interrupted reload costs nothing.
	inventory.set_firearm_rounds(3)
	_press(&"reload")
	await _seconds(0.4)
	_hit_player(FISTS.light_combo[0])
	await _frames(3)
	_check(not player.ranged.is_reloading, "a hit cancels the reload")
	_check(inventory.firearm_rounds == 3, "cancelled reload: rounds unchanged")
	_check(inventory.pockets.count(MAGAZINE) == 1, "cancelled reload: magazine kept")

	# Firing an empty magazine with a magazine carried reloads by itself.
	await _until(func() -> bool: return player.combat.is_free(), 2.0)
	inventory.set_firearm_rounds(0)
	await _aim_at(Vector3(0, 1.5, -22))
	await _fire(false)
	_check(player.ranged.is_reloading, "empty magazine + fire: auto reload")
	Input.action_release(&"aim")


# --- M4b.2 Weapon switching -----------------------------------------------------


func test_weapon_switching() -> void:
	await _load_arena(MODE_DUMMY)
	_park_enemies()
	var inventory := player.inventory
	player.receive_item(BAT)
	player.receive_item(RIFLE)
	_check(inventory.get_hand() == InventoryComponent.Hand.FIREARM, "new rifle in hand")
	_check(inventory.melee == BAT and not inventory.melee_drawn, "bat holstered")
	var expected := {
		&"weapon_unarmed": InventoryComponent.Hand.NONE,
		&"weapon_melee": InventoryComponent.Hand.MELEE,
		&"weapon_firearm": InventoryComponent.Hand.FIREARM,
	}
	for action: StringName in expected:
		_press_event(action)
		await _frames(2)
		_check(inventory.get_hand() == expected[action], "%s" % action)
	_check(player.combat.weapon == RIFLE, "combat holds the rifle")
	# Wheel: firearm -> unarmed -> melee; back: melee -> unarmed.
	_press_event(&"weapon_next")
	await _frames(2)
	_check(inventory.get_hand() == InventoryComponent.Hand.NONE, "wheel up: unarmed")
	_check(player.combat.weapon == null, "fists")
	_press_event(&"weapon_next")
	await _frames(2)
	_check(player.combat.weapon == BAT, "wheel up: bat")
	_press_event(&"weapon_prev")
	await _frames(2)
	_check(inventory.get_hand() == InventoryComponent.Hand.NONE, "wheel down: unarmed")
	# H holsters and draws the last weapon again.
	_press_event(&"weapon_firearm")
	await _frames(2)
	_press_event(&"holster_weapon")
	await _frames(2)
	_check(inventory.get_hand() == InventoryComponent.Hand.NONE, "H holsters the rifle")
	_press_event(&"holster_weapon")
	await _frames(2)
	_check(inventory.get_hand() == InventoryComponent.Hand.FIREARM, "H draws the rifle again")
	# HUD and overlay.
	var label := arena.get_node(^"HUD/HealthBar/Weapon") as Label
	_check(label.text == "Rifle (Baseball bat holstered)", "HUD weapon (%s)" % label.text)
	var hud := arena.get_node(^"HUD")
	hud.call(&"set_inventory_open", true)
	var text := (arena.get_node(^"HUD/InventoryPanel/Text") as Label).text
	_check(text.contains("Firearm: Rifle (in hand, 8/8)"), "overlay shows the firearm slot")
	hud.call(&"set_inventory_open", false)
	# G drops the rifle with its rounds; picking it up keeps them.
	inventory.set_firearm_rounds(5)
	_press_event(&"drop_weapon")
	await _frames(3)
	_check(inventory.firearm == null, "G drops the rifle in hand")
	_check(inventory.melee == BAT, "the holstered bat stays")
	var pickup := _rifle_pickup(true)
	_check(pickup != null and pickup.get(&"rounds") == 5, "the pickup keeps 5 rounds")
	if pickup != null:
		pickup.call(&"_on_interacted", player)
		_check(inventory.firearm_rounds == 5, "picked up again with 5 rounds")


func test_switching_mid_fight() -> void:
	await _load_arena(MODE_ONE_VS_ONE)
	var thug := _enemies()[0]
	thug.ai.enabled = false
	var inventory := player.inventory
	player.receive_item(RIFLE)
	player.receive_item(BAT)
	_place(player, thug.global_position + Vector3(0, 0, 3))
	player.camera_rig.yaw = 0.0
	await _frames(3)
	# RMB held with the bat: guard. Switch to the rifle: aim, no guard.
	_press_rmb(true)
	await _frames(6)
	_check(player.combat.is_guarding(), "RMB with the bat: guard")
	_press_event(&"weapon_firearm")
	await _seconds(0.3)
	_check(not player.combat.is_guarding(), "switched to the rifle: guard released")
	_check(player.aim.is_aiming and player.ranged.is_aiming, "still holding RMB: aiming")
	_check(player.camera_rig.get(&"_aim_goal") == 1.0, "camera in aim framing")
	_press_event(&"weapon_melee")
	await _seconds(0.3)
	_check(not player.aim.is_aiming, "back to the bat: aim off")
	_check(player.combat.is_guarding(), "back to the bat: guarding again")
	_press_rmb(false)
	await _frames(4)
	# A switch during an attack waits for it, the attack isn't cut short.
	_tap(&"attack_light")
	await _frames(4)
	_check(player.combat.state == MeleeCombat.State.ATTACK, "bat attack started")
	var serial := player.combat.attack_serial
	_press_event(&"weapon_firearm")
	await _frames(2)
	_check(inventory.get_hand() == InventoryComponent.Hand.MELEE, "switch waits for the swing")
	await _until(func() -> bool: return player.combat.phase != MeleeCombat.Phase.WINDUP, 3.0)
	await _until(func() -> bool: return player.combat.phase != MeleeCombat.Phase.ACTIVE, 3.0)
	await _frames(1)
	_check(player.combat.attack_serial == serial, "the swing wasn't cut short")
	await _until(func() -> bool: return player.combat.is_free(), 3.0)
	await _frames(2)
	_check(inventory.get_hand() == InventoryComponent.Hand.FIREARM, "then the rifle is drawn")
	# A hit reaction mid-switch: the switch waits until the reaction ends.
	_press_event(&"weapon_melee")
	_hit_player(FISTS.heavy_attack)
	await _frames(2)
	_check(player.combat.is_busy_reacting(), "player reacting to a hit")
	await _until(func() -> bool: return player.combat.is_free(), 3.0)
	await _frames(2)
	_check(inventory.get_hand() == InventoryComponent.Hand.MELEE, "switch after the reaction")
	# Switching cancels a reload without using the magazine.
	_press_event(&"weapon_firearm")
	await _frames(2)
	inventory.add_item(MAGAZINE)
	inventory.set_firearm_rounds(2)
	_press(&"reload")
	await _seconds(0.3)
	_check(player.ranged.is_reloading, "reloading")
	_press_event(&"weapon_unarmed")
	await _frames(3)
	_check(not player.ranged.is_reloading, "switching cancels the reload")
	_check(inventory.pockets.count(MAGAZINE) == 1 and inventory.firearm_rounds == 2, "nothing used")
	# Live fight: switch back and forth while the thug attacks; nothing sticks.
	thug.ai.enabled = true
	var stuck := 0
	for i in 8:
		_press_event(&"weapon_melee" if i % 2 == 0 else &"weapon_firearm")
		await _seconds(0.7)
		var held := player.combat.weapon
		if held != inventory.get_held_weapon():
			stuck += 1
	_check(stuck == 0, "combat and inventory agree on the weapon after every switch")
	_check(not player.combat.is_down(), "player still standing")


# --- M4b.3 Cover ----------------------------------------------------------------


func test_cover_low() -> void:
	await _load_arena(MODE_DUMMY)
	_park_enemies()
	player.receive_item(RIFLE)
	var cover := player.cover
	# South of the low cover, looking north at it.
	_place(player, ARENA_LOW_COVER + Vector3(0, 0, 1.4))
	player.camera_rig.yaw = 0.0
	player.camera_rig.pitch = -0.2
	await _frames(3)
	_press(&"cover")
	await _seconds(0.7)
	_check(cover.is_in_cover(), "F takes cover")
	_check(cover.height == CoverComponent.Height.LOW, "low cover")
	_check(player.movement.is_crouched, "crouched behind low cover")
	var wall_distance := cover.get_wall_distance()
	var expected := cover.body_radius + cover.wall_gap
	_check(absf(wall_distance - expected) < 0.06, "snug to the wall (%.2f m)" % wall_distance)
	_check(player.hurtbox.get_height() < 1.2, "crouched hurtbox hidden behind the cover")
	var camera_ok := [true]
	var watch := func() -> void: camera_ok[0] = camera_ok[0] and _camera_clear()
	get_tree().physics_frame.connect(watch)
	# Move right along the cover to its edge: no snagging, stays in cover.
	var start := player.global_position
	var z := player.global_position.z
	Input.action_press(&"move_right")
	await _seconds(0.5)
	var speed := player.movement.get_horizontal_speed()
	_check(speed > cover.low_move_speed * 0.8, "slides along the cover (%.2f m/s)" % speed)
	await _seconds(2.0)
	Input.action_release(&"move_right")
	await _frames(3)
	_check(cover.is_in_cover(), "still in cover at the edge")
	_check(cover.at_right_edge, "right edge found")
	var edge_x := ARENA_LOW_COVER.x + 1.2
	_check(
		player.global_position.x <= edge_x and player.global_position.x > edge_x - 0.5,
		"stopped at the edge (x %.2f, edge %.2f)" % [player.global_position.x, edge_x]
	)
	_check(absf(player.global_position.z - z) < 0.05, "kept its distance to the wall")
	_check(player.global_position.x > start.x + 0.6, "moved along the cover")
	# Back left across the whole cover.
	Input.action_press(&"move_left")
	await _seconds(3.0)
	Input.action_release(&"move_left")
	await _frames(3)
	_check(cover.is_in_cover() and cover.at_left_edge, "left edge, still in cover")
	_check(
		player.global_position.x >= ARENA_LOW_COVER.x - 1.2,
		"stopped at the left edge (x %.2f)" % player.global_position.x
	)
	# Aim over it: stand up; release: crouch again.
	Input.action_press(&"aim")
	await _seconds(0.5)
	_check(cover.is_in_cover() and not player.movement.is_crouched, "aiming: up over the cover")
	_check(not player.aim.is_obstructed, "line of fire over the cover is clear")
	await _fire(false)
	_check(player.ranged.last_shot_end.z < ARENA_LOW_COVER.z - 1.0, "the shot went over it")
	Input.action_release(&"aim")
	await _seconds(0.5)
	_check(cover.is_in_cover() and player.movement.is_crouched, "aim released: down again")
	# Leave: F again.
	_press(&"cover")
	await _seconds(0.5)
	_check(not cover.is_in_cover(), "F again leaves cover")
	_check(not player.movement.is_crouched, "standing after leaving")
	# Leave by pulling away from the wall.
	_press(&"cover")
	await _seconds(0.7)
	_check(cover.is_in_cover(), "back in cover")
	Input.action_press(&"move_back")
	await _seconds(0.6)
	Input.action_release(&"move_back")
	_check(not cover.is_in_cover(), "holding away from the wall leaves cover")
	get_tree().physics_frame.disconnect(watch)
	_check(camera_ok[0], "camera never inside geometry")
	# No cover in reach: nothing happens.
	_place(player, Vector3(0, 0, 14))
	await _frames(3)
	_press(&"cover")
	await _frames(5)
	_check(not cover.is_in_cover(), "no cover in reach")


func test_cover_high_peek() -> void:
	await _load_arena(MODE_DUMMY)
	_park_enemies()
	player.receive_item(RIFLE)
	var cover := player.cover
	# West of the alley wall's south end, looking east at it.
	_place(player, ARENA_ALLEY_WALL_END + Vector3(-1.2, 0, -1.5))
	player.camera_rig.yaw = -PI / 2.0
	player.camera_rig.pitch = -0.1
	await _frames(3)
	_press(&"cover")
	await _seconds(0.7)
	_check(cover.height == CoverComponent.Height.HIGH, "high cover")
	_check(not player.movement.is_crouched, "standing behind high cover")
	var camera_ok := [true]
	var watch := func() -> void: camera_ok[0] = camera_ok[0] and _camera_clear()
	get_tree().physics_frame.connect(watch)
	# Facing east the wall's south end is on the right.
	Input.action_press(&"move_right")
	await _seconds(1.5)
	Input.action_release(&"move_right")
	await _frames(3)
	_check(cover.at_right_edge, "at the wall's end")
	var in_cover_z := player.global_position.z
	_check(in_cover_z < ARENA_ALLEY_WALL_END.z, "still covered (z %.2f)" % in_cover_z)
	# Aim: step out around the edge.
	Input.action_press(&"aim")
	await _seconds(0.6)
	_check(cover.peek_side == 1, "peeks out to the right")
	_check(
		player.global_position.z > ARENA_ALLEY_WALL_END.z,
		"stepped past the edge (z %.2f)" % player.global_position.z
	)
	_check(player.camera_rig.is_right_shoulder(), "camera on the peeking side")
	await _aim_at(Vector3(20, 1.4, 12))
	_check(not player.aim.is_obstructed, "clear line of fire around the corner")
	Input.action_release(&"aim")
	await _seconds(0.6)
	_check(cover.peek_side == 0 and cover.is_in_cover(), "back in cover")
	_check(
		absf(player.global_position.z - in_cover_z) < 0.1,
		"back where it was (z %.2f)" % player.global_position.z
	)
	get_tree().physics_frame.disconnect(watch)
	_check(camera_ok[0], "camera never inside geometry")
	# Sprinting leaves cover.
	Input.action_press(&"sprint")
	Input.action_press(&"move_left")
	await _frames(4)
	Input.action_release(&"sprint")
	Input.action_release(&"move_left")
	_check(not cover.is_in_cover(), "sprinting leaves cover")


# --- M4b.4 Ranged enemy ---------------------------------------------------------


func test_ranged_thug() -> void:
	await _load_arena(MODE_DUMMY)
	var spawner := (arena as FightArena).spawner
	spawner.clear()
	var rifle_thug := spawner.spawn(1, Callable(), [RIFLE_THUG])[0] as NpcCharacter
	await _frames(3)
	var ai := rifle_thug.ai as RangedThugAI
	_check(ai != null, "rifle thug runs RangedThugAI")
	_check(rifle_thug.combat.weapon == RIFLE, "rifle thug holds the rifle")
	_check(rifle_thug.ranged.attack_override == THUG_SHOT, "weaker NPC shots")
	player.health.max_health = 2000.0
	player.health.revive()
	_place(player, Vector3(0, 0, 9))
	var effects := rifle_thug.get_node(^"FirearmFx") as FirearmEffects
	var telegraph_start := [-1.0]
	var waits: Array[float] = []
	var lasers := [0, 0]
	var time := [0.0]
	var crouched_hold := [false]
	var tick := func() -> void:
		time[0] += 1.0 / 60.0
		if ai.tactic == RangedThugAI.Tactic.HOLD and ai.goal_is_cover:
			crouched_hold[0] = crouched_hold[0] or rifle_thug.movement.is_crouched
		if rifle_thug.ranged.is_telegraphing():
			lasers[0] += 1
			if effects.is_laser_visible():
				lasers[1] += 1
	get_tree().physics_frame.connect(tick)
	rifle_thug.ranged.telegraph_changed.connect(
		func(on: bool) -> void: telegraph_start[0] = time[0] if on else telegraph_start[0]
	)
	var shots := [0, 0]
	rifle_thug.ranged.shot_fired.connect(
		func(_s: Node3D, _w: FirearmData) -> void:
			shots[0] += 1
			waits.append(time[0] - telegraph_start[0])
	)
	rifle_thug.ranged.hit_confirmed.connect(
		func(victim: Node3D, _r: HurtboxComponent.HitResult) -> void:
			if victim == player:
				shots[1] += 1
	)
	# A standing target: the thug takes cover, telegraphs and hits.
	await _seconds(12.0)
	_check(ai.goal_is_cover, "found a cover point")
	_check(crouched_hold[0], "crouches behind cover between bursts")
	var distance := _flat(rifle_thug.global_position.distance_to(player.global_position))
	_check(distance >= ai.preferred_min_distance - 1.0, "keeps its distance (%.1f m)" % distance)
	_check(shots[0] >= 2, "fires at a standing target (%d shots)" % shots[0])
	var min_wait := INF
	for wait in waits:
		min_wait = minf(min_wait, wait)
	_check(
		min_wait >= ai.telegraph_time - 0.02,
		"every burst is telegraphed first (shortest %.2f s)" % min_wait
	)
	_check(lasers[0] > 0 and lasers[1] == lasers[0], "laser visible while telegraphing")
	_check(
		shots[1] >= ceili(shots[0] * 0.6), "standing target is hit (%d / %d)" % [shots[1], shots[0]]
	)
	# A target that keeps moving sideways is mostly missed (the aim lags).
	shots[0] = 0
	shots[1] = 0
	player.health.revive()
	var side := 1
	for i in 10:
		Input.action_press(&"move_right" if side > 0 else &"move_left")
		await _seconds(1.4)
		Input.action_release(&"move_right" if side > 0 else &"move_left")
		side = -side
	_check(shots[0] >= 2, "keeps firing (%d shots)" % shots[0])
	_check(
		shots[1] <= floori(shots[0] * 0.5),
		"a moving target is mostly missed (%d / %d)" % [shots[1], shots[0]]
	)
	# Come close: it backs off instead of standing there.
	_place(player, rifle_thug.global_position + Vector3(0, 0, 2.5))
	player.camera_rig.yaw = 0.0
	await _frames(2)
	var close := _flat(rifle_thug.global_position.distance_to(player.global_position))
	var retreated := [false]
	for i in 120:
		await _frames(1)
		retreated[0] = retreated[0] or ai.tactic == RangedThugAI.Tactic.RETREAT
	var after := _flat(rifle_thug.global_position.distance_to(player.global_position))
	_check(retreated[0] and after > close + 1.0, "backs off (%.1f -> %.1f m)" % [close, after])
	get_tree().physics_frame.disconnect(tick)
	_check(rifle_thug.combat.is_in_group(&"combatants"), "rifle thug is a combatant")


func test_shooter_limit() -> void:
	await _load_arena(MODE_DUMMY)
	var spawner := (arena as FightArena).spawner
	spawner.clear()
	var thugs := spawner.spawn(3, Callable(), [RIFLE_THUG])
	var director := arena.get_node(^"CombatDirector") as CombatDirector
	player.health.max_health = 5000.0
	player.health.revive()
	var most_aiming := [0]
	var shots := [0]
	for npc in thugs:
		(npc as NpcCharacter).ranged.shot_fired.connect(
			func(_s: Node3D, _w: FirearmData) -> void: shots[0] += 1
		)
	var tick := func() -> void:
		var aiming := 0
		for npc in thugs:
			if is_instance_valid(npc) and (npc as NpcCharacter).ranged.is_telegraphing():
				aiming += 1
		most_aiming[0] = maxi(most_aiming[0], aiming)
	get_tree().physics_frame.connect(tick)
	await _seconds(20.0)
	get_tree().physics_frame.disconnect(tick)
	_check(shots[0] >= 3, "the rifle thugs fire (%d shots)" % shots[0])
	_check(
		director.peak_shooters <= director.max_shooters,
		"shooter tokens never above %d (%d)" % [director.max_shooters, director.peak_shooters]
	)
	_check(
		most_aiming[0] <= director.max_shooters, "never two aiming at once (%d)" % most_aiming[0]
	)


# --- M4b.5 Balance --------------------------------------------------------------


## Melee stays a valid choice: with fists, a player who closes in on a rifle
## thug knocks it out without losing much health, and the rifle drops.
func test_melee_beats_rifle_thug() -> void:
	await _load_arena(MODE_DUMMY)
	var spawner := (arena as FightArena).spawner
	spawner.clear()
	var rifle_thug := spawner.spawn(1, Callable(), [RIFLE_THUG])[0] as NpcCharacter
	_place(player, Vector3(0, 0, 8))
	await _seconds(1.0)
	var start_health := player.health.health
	var won := await _melee_bot(rifle_thug, 25.0)
	_check(won, "fists knock out the rifle thug")
	var lost := start_health - player.health.health
	_check(lost <= start_health * 0.5, "player keeps most health (lost %.0f)" % lost)
	await _frames(5)
	var dropped := _rifle_pickup(true)
	_check(dropped != null, "the rifle thug dropped its rifle")
	# Damage numbers (M4b.5 proposal, GDD §19).
	var thug_health := 100.0
	_check(ceili(thug_health / RIFLE.fire_attack.damage) == 3, "rifle: 3 shots kill a thug")
	var player_hits := ceili(player.health.max_health / THUG_SHOT.damage)
	_check(player_hits >= 8, "thug rifle: %d hits down the player" % player_hits)


func test_mixed_fight() -> void:
	await _load_district()
	var gym := district.gym
	_place(player, gym.player_spawn.global_position)
	await _frames(3)
	for i in 3:
		_press_event(&"next_fight_mode")
		await _frames(3)
	_check(gym.mode == FightArena.Mode.MIXED, "F6 reaches the mixed fight")
	var enemies := gym.spawner.get_spawned()
	var melee := 0
	var ranged := 0
	for npc in enemies:
		var ai := (npc as NpcCharacter).ai
		if ai is RangedThugAI:
			ranged += 1
		elif ai is ThugAI:
			melee += 1
	_check(melee == 2 and ranged == 2, "2 melee + 2 rifle thugs (%d + %d)" % [melee, ranged])
	player.health.max_health = 5000.0
	player.health.revive()
	var director := district.get_node(^"CombatDirector") as CombatDirector
	var worst := [0, 0]
	var shots := [0]
	var melee_hits := [0]
	for npc in enemies:
		var character := npc as NpcCharacter
		if character.ranged != null:
			character.ranged.shot_fired.connect(
				func(_s: Node3D, _w: FirearmData) -> void: shots[0] += 1
			)
		else:
			character.combat.hit_landed.connect(
				func(_a: Node3D, _v: Node3D, _k: AttackData) -> void: melee_hits[0] += 1
			)
	var tick := func() -> void:
		worst[0] = maxi(worst[0], director.get_attacker_count())
		worst[1] = maxi(worst[1], director.get_shooter_count())
	get_tree().physics_frame.connect(tick)
	# The player guards in the middle of the yard for a while.
	_press_rmb(true)
	await _seconds(20.0)
	_press_rmb(false)
	get_tree().physics_frame.disconnect(tick)
	_check(shots[0] >= 2, "rifle thugs shoot (%d)" % shots[0])
	_check(melee_hits[0] >= 1, "melee thugs attack (%d hits)" % melee_hits[0])
	_check(worst[0] <= director.max_attackers, "melee attackers <= %d" % director.max_attackers)
	_check(worst[1] <= director.max_shooters, "shooters <= %d" % director.max_shooters)
	_check(not player.combat.is_down(), "player still standing")
	# F5 restarts it without a reload.
	_press_event(&"restart_fight")
	await _frames(5)
	_check(gym.spawner.get_spawned().size() == 4, "F5 restarts the mixed fight")
	_check(is_instance_valid(district) and district.is_inside_tree(), "no scene reload")


func test_district_firearms() -> void:
	await _load_district()
	var rifles := 0
	for spawner in district.get_spawners():
		for npc in spawner.get_spawned():
			if (npc as NpcCharacter).ai is RangedThugAI:
				rifles += 1
	_check(rifles >= 2, "rifle thugs in the district population (%d)" % rifles)
	var stash := district.get_node_or_null(^"Stash/Rifle")
	_check(stash != null and stash.get(&"weapon") == RIFLE, "a rifle lies in the district")
	_check(district.get_node_or_null(^"Stash/Magazine") != null, "and a magazine")
	var gym := district.gym
	_check(gym.rifle_weapon == RIFLE and gym.rifle_spawns != null, "the gym lays out a rifle")
