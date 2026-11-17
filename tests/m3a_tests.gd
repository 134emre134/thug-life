extends Node
## Headless M3a checks (inventory, loot tables, lethality, looting, HUD).
## Drives the real arena and the real player through the InputMap and checks
## the GDD §19 M3a "Done when" criteria.
##
## Run: godot --headless --fixed-fps 60 res://tests/m3a_tests.tscn
## Exit code 0 = all passed.

const ARENA := preload("res://scenes/levels/combat_gym.tscn")
const BAT := preload("res://data/items/bat.tres")
const KNIFE := preload("res://data/items/knife.tres")
const KNIFE_1 := preload("res://data/attacks/knife_1.tres")
const THUG_JAB := preload("res://data/attacks/thug_jab.tres")
const THUG_LOOT := preload("res://data/loot/thug.tres")
const COLLECTOR_LOOT := preload("res://data/loot/collector.tres")
const LIGHTER := preload("res://data/items/lighter.tres")
const PHONE := preload("res://data/items/phone.tres")
const WRISTWATCH := preload("res://data/items/wristwatch.tres")
const LEDGER := preload("res://data/items/collection_ledger.tres")
const CASH_BUNDLE := preload("res://data/items/cash_bundle.tres")
const MODE_ONE_VS_THREE := 0
const MODE_ONE_VS_ONE := 1

var arena: Node3D
var player: Player

var _checks: int = 0
var _failures: PackedStringArray = []
var _current: String = ""


func _ready() -> void:
	var tests: Array[StringName] = [
		&"test_inventory_bat",
		&"test_inventory_slots",
		&"test_loot_tables",
		&"test_downed_punches_kill",
		&"test_bat_kills_downed_faster",
		&"test_knife_kills",
		&"test_knockout_recovery",
		&"test_looting",
		&"test_search_cancel",
		&"test_loot_dead_body",
		&"test_hud",
		&"test_player_death_and_restart",
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


# --- M3a.1 Inventory ---------------------------------------------------------


func test_inventory_bat() -> void:
	await _load_arena(MODE_ONE_VS_ONE)
	_park_enemies()
	var inventory := player.inventory
	var socket := player.get_node(^"Model/Character/GeneralSkeleton/RightHandAttachment/Grip")
	var bat := _pickup_of(BAT)
	bat.global_transform = Transform3D(
		Basis(Vector3.RIGHT, PI / 2), player.global_position + Vector3(0, 0.1, -0.9)
	)
	bat.linear_velocity = Vector3.ZERO
	await _seconds(0.3)
	_press_event(&"interact")
	await _frames(3)
	_check(inventory.melee == BAT, "picked-up bat is in the melee slot")
	_check(inventory.melee_drawn and player.combat.weapon == BAT, "bat in hand")
	_check(socket.get_child_count() == 1, "bat visible in hand")

	_press_event(&"holster_weapon")
	await _frames(3)
	_check(inventory.melee == BAT and not inventory.melee_drawn, "bat holstered, still carried")
	_check(player.combat.weapon == null, "combat uses fists while holstered")
	_check(player.combat.get_weapon().id == &"fists", "fists move set")
	_check(socket.get_child_count() == 0, "hand empty while holstered")
	var started: Array[StringName] = []
	player.combat.attack_started.connect(func(a: AttackData) -> void: started.append(a.id))
	await _tap(&"attack_light")
	await _seconds(0.6)
	_check(started == [&"punch_1"], "holstered: punches (%s)" % [started])

	_press_event(&"holster_weapon")
	await _frames(3)
	_check(inventory.melee_drawn and player.combat.weapon == BAT, "bat drawn again")
	started.clear()
	await _tap(&"attack_light")
	await _seconds(0.8)
	_check(started == [&"bat_1"], "drawn: bat swings (%s)" % [started])

	# Holstered weapons drop too.
	_press_event(&"holster_weapon")
	await _frames(3)
	var before := _pickups().size()
	_press_event(&"drop_weapon")
	await _frames(3)
	_check(inventory.melee == null, "melee slot empty after drop")
	_check(_pickups().size() == before + 1, "dropped bat is a pickup again")
	var dropped := _pickups()[-1] as WeaponPickup
	_check(dropped.weapon == BAT, "dropped pickup carries the bat")

	# Picking up a knife while holding a bat swaps them (receive_item adds a
	# third bat, as if it came from somewhere else).
	player.receive_item(BAT)
	await _frames(2)
	before = _pickups().size()
	var knife := _pickup_of(KNIFE)
	_place(player, knife.global_position + Vector3(0, 0, 0.8))
	player.camera_rig.yaw = 0.0
	await _seconds(0.3)
	_check(player.interaction.current_target != null, "knife is the interaction target")
	_press_event(&"interact")
	await _frames(3)
	_check(inventory.melee == KNIFE and player.combat.weapon == KNIFE, "knife in hand")
	var bats := _pickups().filter(func(p: Node) -> bool: return p.weapon == BAT)
	_check(bats.size() == 3, "bat was dropped for the knife (%d bat pickups)" % bats.size())
	_check(_pickups().size() == before, "one pickup taken, one dropped")


func test_inventory_slots() -> void:
	await _load_arena(MODE_ONE_VS_ONE)
	_park_enemies()
	var inventory := player.inventory
	inventory.clear()
	_check(inventory.pockets.size() == 4, "4 pocket slots")
	_check(not inventory.firearm_slot_active, "firearm slot inactive until M4")
	for i in 4:
		_check(inventory.add_item(PHONE), "pocket %d takes an item" % (i + 1))
	_check(not inventory.add_item(LIGHTER), "full pockets refuse items")
	_check(inventory.get_free_pocket_count() == 0, "no free pockets")
	_check(inventory.remove_item(PHONE), "remove an item")
	_check(inventory.get_free_pocket_count() == 1, "one pocket free again")
	_check(inventory.add_item(BAT), "weapon goes to the melee slot, not a pocket")
	_check(inventory.melee == BAT and inventory.get_free_pocket_count() == 1, "pockets untouched")
	_check(not inventory.add_item(KNIFE), "occupied melee slot refuses a second weapon")
	inventory.add_cash(30)
	_check(inventory.take_cash(10) == 10 and inventory.cash == 20, "wallet add/take")
	_check(inventory.take_cash() == 20 and inventory.cash == 0, "take all cash")


# --- M3a.2 Loot tables -------------------------------------------------------


func test_loot_tables() -> void:
	await _load_arena(MODE_ONE_VS_THREE)
	_park_enemies()
	var enemies := _enemies()
	_check(enemies.size() == 3, "3 NPCs spawned")
	var tables := enemies.map(func(n: NpcCharacter) -> LootTable: return n.inventory.loot_table)
	_check(tables.count(THUG_LOOT) == 2, "two thugs with the thug loot table")
	_check(tables.count(COLLECTOR_LOOT) == 1, "one collector with the collector loot table")
	for npc in enemies:
		var table := npc.inventory.loot_table
		var cash := npc.inventory.cash
		_check(
			cash >= table.cash_min and cash <= table.cash_max,
			"%s cash %d within %d..%d" % [npc.name, cash, table.cash_min, table.cash_max]
		)
		if table == COLLECTOR_LOOT:
			_check(npc.inventory.has_item(LEDGER), "collector always carries a ledger")
	# Many rolls: each type only ever carries what its table lists.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var seen := {THUG_LOOT: {}, COLLECTOR_LOOT: {}}
	for table: LootTable in [THUG_LOOT, COLLECTOR_LOOT]:
		for i in 200:
			for item in table.roll_items(rng):
				seen[table][item] = true
	_check(seen[THUG_LOOT].has(LIGHTER) and seen[THUG_LOOT].has(PHONE), "thugs: lighter, phone")
	_check(
		not seen[THUG_LOOT].has(WRISTWATCH) and not seen[THUG_LOOT].has(LEDGER),
		"thugs never carry watches or ledgers"
	)
	_check(
		seen[COLLECTOR_LOOT].has(WRISTWATCH) and not seen[COLLECTOR_LOOT].has(LIGHTER),
		"collectors: watches, no lighters"
	)
	var collector := (
		enemies.filter(func(n: NpcCharacter) -> bool: return n.inventory.loot_table == COLLECTOR_LOOT)[0]
		as NpcCharacter
	)
	_check(collector.health.max_health == 120.0, "collector variant overrides health")


# --- M3a.3 Lethality ---------------------------------------------------------


func test_downed_punches_kill() -> void:
	await _load_arena(MODE_ONE_VS_ONE)
	var thug := _enemies()[0]
	thug.ai.enabled = false
	_place(thug, player.global_position + Vector3(0, 0, -1.6))
	var kills: Array = []
	thug.health.killed.connect(func(v: Node3D, by: Node3D) -> void: kills.append([v, by]))
	var landed: Array = []
	player.combat.hit_landed.connect(
		func(_a: Node3D, v: Node3D, _at: AttackData) -> void: landed.append(v)
	)
	thug.health.health = 5.0
	await _tap(&"attack_light")
	await _seconds(0.6)
	_check(thug.health.is_knocked_out(), "punch knocks out")
	_check(thug.hurtbox.enabled and thug.hurtbox.can_be_hit(), "knocked-out body can be hit")
	_check(thug.search.interactable.enabled, "knocked-out body can be searched")
	var downed := thug.health.downed_health_left
	var punches := 0
	while not thug.health.is_dead() and punches < 12:
		await _punch_body(thug)
		punches += 1
		if punches == 1:
			_check(thug.health.downed_health_left < downed, "downed damage taken")
			_check(thug.health.is_knocked_out(), "still knocked out after one punch")
	_check(thug.health.is_dead(), "punching a downed thug kills him (%d punches)" % punches)
	_check(punches >= 3 and punches <= 6, "takes a few punches (%d)" % punches)
	_check(kills.size() == 1, "killed emitted once")
	if kills.size() == 1:
		_check(kills[0][0] == thug and kills[0][1] == player, "killed(victim, by)")
	_check(landed.count(thug) >= punches + 1, "downed hits are reported as hit_landed")
	_check(thug.combat.is_dead(), "combat state DEAD")
	_check(not thug.hurtbox.enabled, "dead body can't be hit")
	_check(thug.ragdoll.is_active, "dead body stays a ragdoll")
	var before := thug.health.recovery_time_left
	_check(before == INF, "dead bodies never recover")


func test_bat_kills_downed_faster() -> void:
	await _load_arena(MODE_ONE_VS_ONE)
	var thug := _enemies()[0]
	thug.ai.enabled = false
	player.receive_item(BAT)
	_place(thug, player.global_position + Vector3(0, 0, -2.0))
	await _frames(2)
	thug.health.take_damage(1000.0, player)
	await _frames(2)
	var swings := 0
	while not thug.health.is_dead() and swings < 10:
		await _punch_body(thug)
		swings += 1
	_check(thug.health.is_dead(), "bat kills a downed thug (%d swings)" % swings)
	_check(swings <= 3, "bat needs fewer hits than fists (%d)" % swings)


func test_knife_kills() -> void:
	await _load_arena(MODE_ONE_VS_ONE)
	var thug := _enemies()[0]
	thug.ai.enabled = false
	player.receive_item(KNIFE)
	_place(thug, player.global_position + Vector3(0, 0, -1.6))
	await _frames(2)
	var states: Array[int] = []
	thug.health.state_changed.connect(func(s: int) -> void: states.append(s))
	var kills: Array = []
	thug.health.killed.connect(func(v: Node3D, by: Node3D) -> void: kills.append([v, by]))
	var stabs := 0
	while not thug.health.is_dead() and stabs < 10:
		_place(player, thug.global_position + Vector3(0, 0, 1.2))
		player.camera_rig.yaw = 0.0
		await _frames(2)
		await _tap(&"attack_light")
		await _seconds(0.6)
		stabs += 1
	_check(thug.health.is_dead(), "knife kills (%d stabs)" % stabs)
	_check(stabs >= 2 and stabs <= 5, "a few stabs (%d)" % stabs)
	_check(
		not states.has(HealthComponent.State.KNOCKED_OUT), "blade kills without a knockout first"
	)
	_check(kills.size() == 1 and kills[0][1] == player, "killed(victim, by player)")
	_check(thug.ragdoll.is_active and thug.combat.is_dead(), "stabbed thug ragdolls, dead")
	_check(KNIFE_1.damage_type == AttackData.DamageType.BLADE, "knife attacks are blades")


func test_knockout_recovery() -> void:
	await _load_arena(MODE_ONE_VS_THREE)
	_park_enemies()
	var enemies := _enemies()
	var untouched := enemies[0]
	var beaten := enemies[1]
	for npc in [untouched, beaten]:
		npc.health.knockout_recovery_time = 2.0
		_place(npc, Vector3(-4 if npc == untouched else 4, 0, -4))
		npc.health.take_damage(1000.0, player)
	await _seconds(1.5)
	_check(untouched.health.is_knocked_out(), "still down after 1.5 s")
	beaten.health.take_damage(5.0, player)
	_check(beaten.health.recovery_time_left > 1.9, "a downed hit restarts the recovery timer")
	var recovered: Array[NpcCharacter] = []
	untouched.recovered.connect(func(n: NpcCharacter) -> void: recovered.append(n))
	await _seconds(0.8)
	_check(recovered == [untouched], "untouched thug recovers")
	_check(beaten.health.is_knocked_out(), "the beaten one is still down")
	_check(untouched.health.is_active(), "health active again")
	_check(
		is_equal_approx(untouched.health.health, 30.0),
		"recovers with 30%% health (%.0f)" % untouched.health.health
	)
	_check(not untouched.ragdoll.is_active and untouched.model.visible, "ragdoll replaced")
	_check(untouched.collision_layer != 0 and untouched.hurtbox.follow == null, "body restored")
	_check(not untouched.search.interactable.enabled, "no search on a standing thug")
	_check(
		String(untouched.animator.combat_clip).begins_with("getup_from"),
		"get-up clip plays (%s)" % untouched.animator.combat_clip
	)
	await _until(func() -> bool: return untouched.combat.state == MeleeCombat.State.IDLE, 4.0)
	_check(untouched.combat.state == MeleeCombat.State.IDLE, "got up (get-up clip) and idle")
	untouched.ai.enabled = true
	await _seconds(0.5)
	_check((untouched.ai as ThugAI).target == player.combat, "back in the fight")


# --- M3a.4 Looting -----------------------------------------------------------


func test_looting() -> void:
	await _load_arena(MODE_ONE_VS_ONE)
	var thug := _enemies()[0]
	thug.ai.enabled = false
	thug.inventory.clear()
	thug.inventory.add_cash(25)
	thug.inventory.add_item(LIGHTER)
	thug.inventory.add_item(PHONE)
	player.inventory.clear()
	_check(not thug.search.interactable.enabled, "standing thugs can't be searched")
	_place(thug, player.global_position + Vector3(0, 0, -2.0))
	thug.health.take_damage(1000.0, player)
	await _seconds(1.5)
	_check(thug.search.interactable.enabled, "KO exposes a Search interactable")
	var body_pos := thug.ragdoll.get_root_body().global_position
	_check(thug.search.global_position.distance_to(body_pos) < 0.5, "search point follows the body")
	_approach_body(thug)
	await _seconds(0.3)
	_check(player.interaction.current_target == thug.search.interactable, "search is the target")
	var loots: Array = []
	thug.search.looted.connect(func(v: Node3D, by: Node3D) -> void: loots.append([v, by]))
	# A tap does nothing: searching is a hold action.
	_press_event(&"interact")
	await _frames(5)
	_check(loots.is_empty() and player.inventory.cash == 0, "tap doesn't search")
	Input.action_press(&"interact")
	Input.action_press(&"move_forward")
	await _seconds(0.7)
	_check(player.interaction.is_holding(), "holding: search in progress")
	_check(
		player.movement.get_horizontal_speed() < 0.3,
		"player stands still while searching (%.2f)" % player.movement.get_horizontal_speed()
	)
	_check(loots.is_empty(), "not done after 0.7 s")
	await _seconds(1.0)
	Input.action_release(&"move_forward")
	Input.action_release(&"interact")
	_check(loots.size() == 1, "looted emitted once")
	if loots.size() == 1:
		_check(loots[0][0] == thug and loots[0][1] == player, "looted(victim, by)")
	_check(player.inventory.cash == 25, "cash moved to the player (%d)" % player.inventory.cash)
	_check(
		player.inventory.has_item(LIGHTER) and player.inventory.has_item(PHONE),
		"items moved to the player"
	)
	_check(thug.inventory.is_empty(), "body emptied")
	_check(not thug.search.interactable.enabled, "searched body can't be searched again")


func test_search_cancel() -> void:
	await _load_arena(MODE_ONE_VS_ONE)
	var thug := _enemies()[0]
	thug.ai.enabled = false
	thug.inventory.clear()
	thug.inventory.add_cash(10)
	player.inventory.clear()
	_place(thug, player.global_position + Vector3(0, 0, -2.0))
	thug.health.take_damage(1000.0, player)
	await _seconds(1.5)
	_approach_body(thug)
	await _seconds(0.3)
	Input.action_press(&"interact")
	await _seconds(0.8)
	Input.action_release(&"interact")
	await _frames(2)
	_check(not player.interaction.is_holding(), "releasing cancels the search")
	_check(player.inventory.cash == 0, "nothing taken on cancel")
	# Getting hit cancels it too.
	Input.action_press(&"interact")
	await _seconds(0.8)
	_check(player.interaction.is_holding(), "searching again")
	var result := player.combat.receive_hit(thug, THUG_JAB, Vector3.FORWARD)
	await _frames(1)
	_check(result == HurtboxComponent.HitResult.HIT, "player hit while searching")
	_check(player.interaction.hold_progress < 0.1, "being hit cancels the search")
	await _seconds(1.0)
	Input.action_release(&"interact")
	_check(player.inventory.cash == 0, "nothing taken after the hit")
	# Pockets full: the rest stays on the body and can be searched again.
	await _seconds(0.6)
	thug.inventory.add_item(WRISTWATCH)
	for i in 4:
		player.inventory.add_item(CASH_BUNDLE)
	_approach_body(thug)
	await _seconds(0.3)
	Input.action_press(&"interact")
	await _seconds(1.8)
	Input.action_release(&"interact")
	_check(player.inventory.cash == 10, "cash taken even with full pockets")
	_check(thug.inventory.has_item(WRISTWATCH), "watch left behind (pockets full)")
	_check(thug.search.interactable.enabled, "body can be searched again")


func test_loot_dead_body() -> void:
	await _load_arena(MODE_ONE_VS_ONE)
	var thug := _enemies()[0]
	thug.ai.enabled = false
	thug.inventory.clear()
	thug.inventory.add_cash(40)
	player.inventory.clear()
	_place(thug, player.global_position + Vector3(0, 0, -2.0))
	thug.health.take_damage(1000.0, player, KNIFE_1)
	await _seconds(1.5)
	_check(thug.health.is_dead(), "killed outright by a blade")
	_check(thug.search.interactable.enabled, "dead body can be searched")
	_approach_body(thug)
	await _seconds(0.3)
	Input.action_press(&"interact")
	await _seconds(1.8)
	Input.action_release(&"interact")
	_check(player.inventory.cash == 40, "cash taken from the dead body")


# --- M3a.5 HUD ---------------------------------------------------------------


func test_hud() -> void:
	await _load_arena(MODE_ONE_VS_ONE)
	_park_enemies()
	var hud := arena.get_node(^"HUD")
	var cash := hud.get_node(^"Cash") as Label
	var weapon := hud.get_node(^"HealthBar/Weapon") as Label
	var panel := hud.get_node(^"InventoryPanel") as Control
	var text := hud.get_node(^"InventoryPanel/Text") as Label
	player.inventory.clear()
	await _frames(1)
	_check(cash.text == "$0", "cash on the HUD (%s)" % cash.text)
	player.inventory.add_cash(37)
	await _frames(1)
	_check(cash.text == "$37", "cash updates (%s)" % cash.text)
	_check(weapon.text == "Fists", "weapon: fists (%s)" % weapon.text)
	player.receive_item(BAT)
	await _frames(1)
	_check(weapon.text == BAT.display_name, "weapon: bat (%s)" % weapon.text)
	_press_event(&"holster_weapon")
	await _frames(2)
	_check(weapon.text.contains("holstered"), "weapon: holstered (%s)" % weapon.text)
	player.inventory.add_item(PHONE)
	_check(not panel.visible, "inventory overlay hidden by default")
	_press_event(&"toggle_inventory")
	await _frames(2)
	_check(panel.visible, "inventory overlay opens")
	for line in ["Cash: $37", "Melee: Baseball bat (holstered)", "Firearm:", "Pocket 1: Phone"]:
		_check(text.text.contains(line), "overlay shows '%s'" % line)
	for i in 4:
		_check(text.text.contains("Pocket %d:" % (i + 1)), "overlay shows pocket %d" % (i + 1))
	_press_event(&"toggle_inventory")
	await _frames(2)
	_check(not panel.visible, "inventory overlay closes")
	_check(_has_progress_bar(hud), "search progress bar exists")


func test_player_death_and_restart() -> void:
	await _load_arena(MODE_ONE_VS_ONE)
	var thug := _enemies()[0]
	thug.ai.enabled = false
	player.inventory.add_cash(15)
	player.receive_item(KNIFE)
	await _frames(1)
	var before := _pickups().size()
	player.health.take_damage(1000.0, thug, KNIFE_1)
	await _frames(3)
	_check(player.health.is_dead() and player.combat.is_dead(), "player killed by a blade")
	_check(player.ragdoll.is_active, "dead player ragdolls")
	_check(player.inventory.melee == null, "weapon dropped on death")
	_check(_pickups().size() == before + 1, "dropped knife in the world")
	arena.start_fight()
	await _frames(3)
	_check(player.health.is_active() and not player.combat.is_down(), "restart revives")
	_check(not player.ragdoll.is_active and player.model.visible, "ragdoll removed")
	_check(player.inventory.cash == 15, "restart keeps the wallet")


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
		&"attack_light", &"attack_heavy", &"guard", &"dodge", &"move_forward", &"interact"
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


func _pickup_of(weapon: WeaponData) -> RigidBody3D:
	for pickup in _pickups():
		if pickup.weapon == weapon:
			return pickup as RigidBody3D
	return null


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


## One light attack at a downed body; waits for the attack to finish.
func _punch_body(npc: NpcCharacter) -> void:
	_approach_body(npc)
	await _frames(2)
	await _tap(&"attack_light")
	await _seconds(0.9)


func _has_progress_bar(hud: Node) -> bool:
	return hud.get_node_or_null(^"Prompt/HoldBar") is ProgressBar


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
