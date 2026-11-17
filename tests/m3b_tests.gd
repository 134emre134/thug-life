extends Node
## Headless M3b checks (district, gym, thugs, civilians, panic, minimap).
## Loads the real district and drives the real player through the InputMap;
## checks the GDD §19 M3b "Done when" criteria.
##
## Run: godot --headless --fixed-fps 60 res://tests/m3b_tests.tscn
## Exit code 0 = all passed.

const DISTRICT := preload("res://scenes/levels/district.tscn")
const PHONE := preload("res://data/items/phone.tres")
const CIVILIAN_LOOT := preload("res://data/loot/civilian.tres")

var district: District
var player: Player

var _checks: int = 0
var _failures: PackedStringArray = []
var _current: String = ""


func _ready() -> void:
	var tests: Array[StringName] = [
		&"test_district_layout",
		&"test_walk_the_district",
		&"test_gym_fight",
		&"test_street_thugs",
		&"test_civilians_walk",
		&"test_civilian_knockout_and_loot",
		&"test_civilian_panic",
		&"test_civilian_recovers_and_flees",
		&"test_minimap",
		&"test_clinic",
		&"test_population_respawn",
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


# --- M3b.1 District block-out ---------------------------------------------------


func test_district_layout() -> void:
	await _load_district()
	var region := district.get_node(^"NavigationRegion3D") as NavigationRegion3D
	_check(region.navigation_mesh.get_polygon_count() > 50, "navigation mesh baked")
	_check(player.is_on_floor(), "player stands on the street")
	var lots := district.get_node(^"Lots").get_children()
	_check(lots.size() >= 4, "reserved lots present (%d)" % lots.size())
	var labelled := 0
	for lot in lots:
		var label := lot.get_node_or_null(^"Label") as Label3D
		if label != null and label.text.begins_with("RESERVED"):
			labelled += 1
	_check(labelled == lots.size(), "every reserved lot is marked")
	for spawner in district.get_spawners():
		_check(
			spawner.get_standing_count() == spawner.population,
			(
				"%s populated (%d/%d)"
				% [spawner.name, spawner.get_standing_count(), spawner.population]
			)
		)
	var civilians := _civilians().size()
	var thugs := _street_thugs().size()
	_check(civilians >= 8 and thugs >= 5, "civilians %d, street thugs %d" % [civilians, thugs])


## Walks the player (real input) along navigation paths to every part of the
## district: no snagging means each goal is reached in time without stalling.
func test_walk_the_district() -> void:
	await _load_district()
	await _remove_npcs()
	var goals: Array[Vector3] = [
		Vector3(-28, 0, -14),  # Brix Square
		Vector3(-44.5, 0, -44),  # NW alley
		Vector3(-5, 0, -40),  # Dock Street north
		Vector3(36, 0, -20),  # inside the gym yard (south gate)
		Vector3(26, 0, -25),  # out through the west gate
		Vector3(30, 0, -38),  # NE back alley
		Vector3(55, 0, 0),  # Harbour Road east
		Vector3(30, 0, 22),  # SE alley
		Vector3(48, 0, 32),  # warehouse lot
		Vector3(0, 0, 46),  # Old Quay
		Vector3(-30, 0, 24),  # SW alley
		Vector3(-17, 0, 14),  # general store lot
		Vector3(-55, 0, 0),  # Harbour Road west
	]
	var map := player.get_world_3d().navigation_map
	var reached := 0
	for goal in goals:
		var from := player.global_position
		var path := NavigationServer3D.map_get_path(map, from, goal, true)
		if path.is_empty() or path[-1].distance_to(goal) > 1.0:
			_check(false, "path to %s exists" % goal)
			_place(player, goal)
			continue
		var ok := await _follow_path(path)
		_check(ok, "walked to %s without snagging" % goal)
		if ok:
			reached += 1
		else:
			_place(player, goal)
	_check(reached == goals.size(), "whole district walkable (%d/%d)" % [reached, goals.size()])


# --- M3b.2 District gym ----------------------------------------------------------


func test_gym_fight() -> void:
	await _load_district()
	var gym := district.gym
	var spawner := gym.spawner
	_check(spawner.get_spawned().is_empty(), "gym empty until a fight is started")
	# Outside the yard the fight keys do nothing.
	_press_event(&"restart_fight")
	await _frames(3)
	_check(spawner.get_spawned().is_empty(), "F5 outside the yard does nothing")

	var button := gym.get_node(^"StartButton") as Node3D
	_place(player, button.global_position + Vector3(0, 0, -1.0))
	player.camera_rig.yaw = PI  # look south, at the button
	await _seconds(0.4)
	_check(player.interaction.current_target != null, "start button is the interaction target")
	_press_event(&"interact")
	await _frames(5)
	var first := spawner.get_spawned()
	var first_ids := first.map(func(n: Node3D) -> int: return n.get_instance_id())
	_check(first.size() == 3, "button starts the 1 vs 3 fight (%d)" % first.size())
	var thugs := 0
	for npc in first:
		thugs += 1 if npc.scene_file_path.ends_with("thug.tscn") else 0
	_check(thugs == 2, "two thugs and a collector")
	_check(_weapon_pickups_in(gym).size() == 3, "bats and knife laid out")
	await _seconds(2.0)
	var engaged := 0
	for npc in first:
		var ai := (npc as NpcCharacter).ai as ThugAI
		engaged += 1 if ai.target == player.combat else 0
	_check(engaged == 3, "gym thugs go for the player (%d)" % engaged)

	_press_event(&"restart_fight")
	await _frames(5)
	var second := spawner.get_spawned()
	_check(second.size() == 3, "F5 in the yard restarts the fight")
	var fresh := second.all(func(n: Node3D) -> bool: return not first_ids.has(n.get_instance_id()))
	_check(fresh, "fresh enemies")
	var spawn := gym.player_spawn.global_position
	_check(player.global_position.distance_to(spawn) < 0.5, "player back at the gym spawn")
	_check(_weapon_pickups_in(gym).size() == 3, "weapons reset, not duplicated")
	_check(is_instance_valid(district) and district.is_inside_tree(), "no scene reload")

	_press_event(&"next_fight_mode")
	await _frames(5)
	_check(spawner.get_spawned().size() == 1, "F6 switches to 1 vs 1")


# --- M3b.3 Thug spawns -----------------------------------------------------------


func test_street_thugs() -> void:
	await _load_district()
	var thug := _thug_of(&"ThugsNE")
	_check(thug != null, "a street thug in the NE back alley")
	if thug == null:
		return
	for other in _street_thugs():
		if other != thug:
			other.ai.enabled = false
	for civilian in _civilians():
		civilian.ai.enabled = false
	var ai := thug.ai as ThugAI
	var home := thug.global_position
	_check(ai.aggro_radius > 0.0, "street thugs have a limited aggro radius")

	# Far away (Harbour Road): the thug ignores the player.
	_place(player, Vector3(12, 0, -8))
	await _seconds(1.5)
	_check(ai.target == null, "player far away: no target")
	_check(thug.global_position.distance_to(home) < 1.5, "thug stays in its alley")

	# Close and in sight: he engages, as in the arena.
	_place(player, home + Vector3(6, 0, 0))
	await _seconds(1.5)
	_check(ai.target == player.combat, "player close: thug targets the player")
	var attacked := []
	thug.combat.attack_started.connect(func(a: AttackData) -> void: attacked.append(a.id))
	await _seconds(5.0)
	_check(not attacked.is_empty(), "thug attacks in the street (%s)" % [attacked])

	# Run off: he gives up and walks home.
	_place(player, Vector3(-30, 0, 5))
	player.health.revive()
	await _seconds(1.0)
	_check(ai.target == null, "player gone: target dropped")
	await _seconds(8.0)
	_check(
		thug.global_position.distance_to(home) < 2.5,
		"thug walked back home (%.1f m)" % thug.global_position.distance_to(home)
	)


# --- M3b.4 Civilian walkers --------------------------------------------------------


func test_civilians_walk() -> void:
	await _load_district()
	for thug in _street_thugs():
		thug.ai.enabled = false
	_place(player, Vector3(-60, 0, -20))
	var civilians := _civilians()
	var start: Dictionary = {}
	for civilian in civilians:
		start[civilian] = civilian.global_position
	var max_moved: Dictionary = {}
	for i in 20:
		await _seconds(0.5)
		for civilian in civilians:
			if is_instance_valid(civilian):
				var moved := civilian.global_position.distance_to(start[civilian])
				max_moved[civilian] = maxf(float(max_moved.get(civilian, 0.0)), moved)
	var walking := 0
	for civilian in civilians:
		walking += 1 if float(max_moved.get(civilian, 0.0)) > 3.0 else 0
		var ai := civilian.ai as CivilianAI
		_check(ai.route != null, "%s has a route" % civilian.name)
	_check(
		walking >= civilians.size() - 1,
		"civilians walk their routes (%d/%d moved > 3 m)" % [walking, civilians.size()]
	)
	var calm := civilians.all(func(c: NpcCharacter) -> bool: return not c.ai.is_panicking())
	_check(calm, "nobody panics on a quiet street")


func test_civilian_knockout_and_loot() -> void:
	await _load_district()
	_freeze_npcs()
	var civilian := _civilians()[0]
	_check(civilian.inventory.loot_table == CIVILIAN_LOOT, "civilians use the civilian loot table")
	_check(civilian.combat.team == &"civilians", "civilians are their own team")
	civilian.inventory.clear()
	civilian.inventory.add_cash(35)
	civilian.inventory.add_item(PHONE)
	player.inventory.clear()
	var spot := Vector3(-30, 0, 5)
	_place(civilian, spot)
	civilian.model.rotation.y = 0.0
	_place(player, spot + Vector3(0, 0, 1.3))
	player.camera_rig.yaw = 0.0
	await _seconds(0.3)
	var hits: Array[int] = []
	civilian.combat.hit_taken.connect(
		func(_a: Node3D, _b: AttackData, result: int) -> void: hits.append(result)
	)
	for i in 20:
		if civilian.health.is_down():
			break
		_place(player, civilian.global_position + Vector3(0, 0, 1.2))
		await _tap(&"attack_light")
		await _seconds(0.7)
	_check(hits.size() > 0, "civilian can be hit (%d hits)" % hits.size())
	_check(civilian.health.is_knocked_out(), "civilian knocked out")
	await _seconds(1.0)
	_approach_body(civilian)
	await _seconds(0.3)
	_check(player.interaction.current_target == civilian.search.interactable, "body searchable")
	Input.action_press(&"interact")
	await _seconds(1.8)
	Input.action_release(&"interact")
	_check(player.inventory.cash == 35, "civilian's cash looted (%d)" % player.inventory.cash)
	_check(player.inventory.has_item(PHONE), "civilian's phone looted")


# --- M3b.5 Civilian panic ------------------------------------------------------------


func test_civilian_panic() -> void:
	await _load_district()
	_freeze_npcs()
	var civilians := _civilians()
	var fight := Vector3(-28, 0, -14)  # Brix Square
	var near: Array[NpcCharacter] = []
	for i in 3:
		var civilian := civilians[i]
		_place(civilian, fight + Vector3(-6.0 + 6.0 * i, 0, -5.0))
		civilian.ai.enabled = true
		near.append(civilian)
	var far := civilians[3]
	_place(far, Vector3(30, 0, 5))
	far.ai.enabled = true
	var thug := _street_thugs()[0]
	_place(thug, fight + Vector3(0, 0, -1.3))
	_place(player, fight)
	player.camera_rig.yaw = 0.0
	await _seconds(0.5)
	_check(near.all(func(c: NpcCharacter) -> bool: return not c.ai.is_panicking()), "calm before")
	# Start a fight: punch the thug.
	for i in 3:
		await _tap(&"attack_light")
		await _seconds(0.5)
	await _seconds(0.5)
	var fleeing := near.filter(func(c: NpcCharacter) -> bool: return c.ai.is_panicking())
	_check(fleeing.size() == near.size(), "nearby civilians panic (%d/3)" % fleeing.size())
	_check(not far.ai.is_panicking(), "civilians across the district stay calm")
	var start: Array[float] = []
	for civilian in near:
		start.append(_flat(civilian.global_position - fight))
	await _seconds(4.0)
	var scattered := 0
	for i in near.size():
		var distance := _flat(near[i].global_position - fight)
		scattered += 1 if distance > start[i] + 6.0 else 0
	_check(scattered == near.size(), "they scatter away from the fight (%d/3)" % scattered)
	var running := near.filter(
		func(c: NpcCharacter) -> bool: return c.movement.get_horizontal_speed() > 3.0
	)
	_check(running.size() > 0 or scattered == near.size(), "civilians run")

	# A body on the ground scares civilians once.
	var bystander := civilians[4]
	_place(bystander, Vector3(8, 0, -46))
	bystander.ai.enabled = true
	await _seconds(0.5)
	var victim := civilians[5]
	_place(victim, Vector3(8, 0, -40))
	victim.health.take_damage(1000.0, player)
	await _seconds(1.0)
	_check(bystander.ai.is_panicking(), "a knocked-out body nearby makes a civilian flee")


func test_civilian_recovers_and_flees() -> void:
	await _load_district()
	_freeze_npcs()
	var civilian := _civilians()[0]
	_place(civilian, Vector3(-30, 0, 5))
	civilian.ai.enabled = true
	civilian.health.knockout_recovery_time = 1.0
	_place(player, Vector3(-30, 0, 6.5))
	civilian.health.take_damage(1000.0, player)
	await _seconds(0.5)
	_check(civilian.health.is_knocked_out(), "civilian down")
	await _seconds(1.5)
	_check(civilian.health.is_active(), "civilian got back up")
	_check(civilian.ai.is_panicking(), "and runs away instead of walking on")


# --- M3b.6 Minimap ----------------------------------------------------------------


func test_minimap() -> void:
	await _load_district()
	var minimap := district.get_node(^"HUD/Minimap") as Minimap
	await _frames(2)
	_check(minimap.visible, "minimap shown in the district")
	_check(
		minimap.get_shape_count() > 60,
		"district shapes on the map (%d)" % minimap.get_shape_count()
	)
	var layers: Dictionary = {}
	for shape in district.get_minimap_shapes():
		layers[shape[&"layer"]] = true
	for layer: StringName in [&"building", &"road", &"lot", &"gym"]:
		_check(layers.has(layer), "map layer %s" % layer)
	var centre := minimap.size * 0.5
	_check(
		minimap.world_to_map(player.global_position).distance_to(centre) < 0.5, "player at centre"
	)
	# Moving changes what's under the player marker: a building corner 10 m
	# ahead appears 10 m "up" on the map.
	player.camera_rig.yaw = 0.0
	var ahead := player.global_position + Vector3(0, 0, -10)
	var mapped := minimap.world_to_map(ahead)
	var scale := minf(minimap.size.x, minimap.size.y) * 0.5 / minimap.world_radius
	_check(absf(mapped.x - centre.x) < 0.5, "forward stays centred horizontally")
	_check(absf((centre.y - mapped.y) - 10.0 * scale) < 0.5, "forward is up, to scale")
	player.camera_rig.yaw = -PI / 2.0  # camera looks east
	mapped = minimap.world_to_map(player.global_position + Vector3(10, 0, 0))
	_check(centre.y - mapped.y > 10.0 * scale - 0.5, "map turns with the camera")
	# Walk east: the player stays centred and the map moves.
	var before := minimap.world_to_map(Vector3(0, 0, 0))
	Input.action_press(&"move_forward")
	await _seconds(1.0)
	Input.action_release(&"move_forward")
	var after := minimap.world_to_map(Vector3(0, 0, 0))
	_check(before.distance_to(after) > 3.0 * scale, "map scrolls while moving")
	_check(minimap.world_to_map(player.global_position).distance_to(centre) < 0.5, "still centred")
	minimap.rotate_with_camera = false
	_check(minimap.get_map_yaw() == 0.0, "north-up option")


# --- Clinic and population -----------------------------------------------------------


func test_clinic() -> void:
	await _load_district()
	_freeze_npcs()
	player.inventory.clear()
	player.inventory.add_cash(80)
	player.health.take_damage(1000.0, null)
	await _frames(2)
	_check(player.health.is_down(), "player knocked out")
	await _seconds(district.clinic_delay + 0.5)
	var clinic := district.get_node(^"ClinicSpawn") as Marker3D
	_check(
		player.global_position.distance_to(clinic.global_position) < 0.5, "woke up at the clinic"
	)
	_check(player.health.is_active() and player.health.get_fraction() == 1.0, "patched up")
	_check(
		player.inventory.cash == 80 - district.clinic_fee,
		"clinic bill paid (%d left)" % player.inventory.cash
	)


func test_population_respawn() -> void:
	await _load_district()
	var spawner := district.get_node(^"NpcSpawners/ThugsSW") as EnemySpawner
	spawner.respawn_delay = 1.0
	spawner.corpse_time = 1.0
	_place(player, Vector3(40, 0, -10))
	var victim := spawner.get_spawned()[0] as NpcCharacter
	victim.health.take_damage(1000.0, player, preload("res://data/attacks/knife_1.tres"))
	await _frames(2)
	_check(victim.health.is_dead(), "street thug killed")
	_check(spawner.get_standing_count() == spawner.population - 1, "one short")
	await _seconds(2.5)
	_check(spawner.get_standing_count() == spawner.population, "replaced after the delay")
	_check(not is_instance_valid(victim) or victim.is_queued_for_deletion(), "old body removed")


# --- Helpers ------------------------------------------------------------------------


func _load_district() -> void:
	district = DISTRICT.instantiate() as District
	add_child(district)
	player = district.get_node(^"Player") as Player
	player.require_mouse_capture = false
	player.capture_mouse_on_start = false
	# Navigation bake and populations happen in _ready (awaits the map).
	for i in 240:
		await get_tree().physics_frame
		if not _civilians().is_empty():
			break
	await _seconds(0.3)


func _teardown() -> void:
	for action: StringName in [
		&"move_forward",
		&"move_back",
		&"move_left",
		&"move_right",
		&"sprint",
		&"interact",
		&"attack_light",
		&"guard",
	]:
		Input.action_release(action)
	HitStop.cancel()
	if district != null:
		district.queue_free()
		district = null
	await _frames(5)


func _npcs() -> Array[NpcCharacter]:
	var result: Array[NpcCharacter] = []
	for node in district.get_node(^"NPCs").get_children():
		if node is NpcCharacter and not node.is_queued_for_deletion():
			result.append(node)
	return result


func _civilians() -> Array[NpcCharacter]:
	if district == null:
		return []
	var result: Array[NpcCharacter] = []
	for npc in _npcs():
		if npc.ai is CivilianAI:
			result.append(npc)
	return result


func _street_thugs() -> Array[NpcCharacter]:
	var result: Array[NpcCharacter] = []
	for spawner in district.get_spawners():
		for npc in spawner.get_spawned():
			if (npc as NpcCharacter).ai is ThugAI:
				result.append(npc)
	return result


func _thug_of(spawner_name: StringName) -> NpcCharacter:
	var spawner := district.get_node(NodePath("NpcSpawners/" + spawner_name)) as EnemySpawner
	var spawned := spawner.get_spawned()
	return spawned[0] as NpcCharacter if not spawned.is_empty() else null


## Stops every NPC controller (tests re-enable the ones they need).
func _freeze_npcs() -> void:
	for npc in _npcs():
		npc.ai.enabled = false


func _remove_npcs() -> void:
	for spawner in district.get_spawners():
		spawner.stop_population()
		spawner.clear()
	await _frames(2)


func _weapon_pickups_in(arena: FightArena) -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().get_nodes_in_group(&"weapon_pickups"):
		if not node.is_queued_for_deletion() and arena.is_ancestor_of(node):
			result.append(node)
	return result


## Steers the player along [param path] with real input (camera yaw +
## move_forward). False if it stalls or runs out of time.
func _follow_path(path: PackedVector3Array) -> bool:
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	var budget := length / 3.0 + 4.0
	var index := 1
	var elapsed := 0.0
	var stall := 0.0
	var last := player.global_position
	Input.action_press(&"move_forward")
	while index < path.size():
		var offset := path[index] - player.global_position
		offset.y = 0.0
		if offset.length() < 0.6:
			index += 1
			continue
		player.camera_rig.yaw = atan2(-offset.x, -offset.z)
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		var progress := _flat(player.global_position - last)
		last = player.global_position
		stall = stall + 1.0 / 60.0 if progress < 0.01 else 0.0
		if stall > 1.0 or elapsed > budget:
			Input.action_release(&"move_forward")
			print("    stuck at %s (next %s)" % [player.global_position, path[index]])
			return false
	Input.action_release(&"move_forward")
	await _frames(10)
	return true


## Puts the player 1.1 m from the downed body, looking at it.
func _approach_body(npc: NpcCharacter) -> void:
	var body := npc.ragdoll.get_root_body().global_position
	body.y = player.global_position.y
	var from := player.global_position - body
	from.y = 0.0
	from = from.normalized() if from.length() > 0.1 else Vector3.BACK
	_place(player, body + from * 1.1)
	player.camera_rig.yaw = atan2(from.x, from.z)


func _place(node: Node3D, at: Vector3) -> void:
	node.global_position = at
	if node is CharacterBody3D:
		(node as CharacterBody3D).velocity = Vector3.ZERO
	node.reset_physics_interpolation()


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _frames(ceili(seconds * 60.0))


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
