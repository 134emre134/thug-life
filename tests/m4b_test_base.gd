extends Node
## Shared state and helpers of the M4b test suite (tests/m4b_tests.gd): level
## loading, real-input helpers (aiming the crosshair, firing, pressing keys),
## a navmesh-following melee bot and checks.

const ARENA := preload("res://scenes/levels/combat_gym.tscn")
const DISTRICT := preload("res://scenes/levels/district.tscn")
const RIFLE := preload("res://data/items/rifle.tres")
const MAGAZINE := preload("res://data/items/rifle_magazine.tres")
const FISTS := preload("res://data/items/fists.tres")

var arena: Node3D
var district: District
var player: Player

var _checks: int = 0
var _failures: PackedStringArray = []
var _current: String = ""

# --- Helpers ---------------------------------------------------------------------


## Fists against [param npc]: run at it along the navigation mesh and punch
## until it is knocked out.
func _melee_bot(npc: NpcCharacter, timeout: float) -> bool:
	var punch_timer := 0
	var path := PackedVector3Array()
	var map := player.get_world_3d().navigation_map
	for i in ceili(timeout * 60.0):
		if npc.combat.is_down():
			_release_moves()
			return true
		if player.combat.is_down():
			break
		var to_npc := npc.global_position - player.global_position
		to_npc.y = 0.0
		var goal := npc.global_position
		if i % 10 == 0:
			path = NavigationServer3D.map_get_path(map, player.global_position, goal, true)
		for point in path:
			var flat := Vector2(
				point.x - player.global_position.x, point.z - player.global_position.z
			)
			if flat.length() > 0.5:
				goal = point
				break
		var to_goal := goal - player.global_position
		to_goal.y = 0.0
		var heading := to_npc if to_npc.length() <= 2.5 else to_goal
		player.camera_rig.yaw = atan2(-heading.x, -heading.z)
		player.camera_rig.pitch = -0.15
		if to_npc.length() > 1.3:
			Input.action_press(&"move_forward")
			Input.action_press(&"sprint")
		else:
			Input.action_release(&"move_forward")
			Input.action_release(&"sprint")
			punch_timer -= 1
			if punch_timer <= 0:
				Input.action_press(&"attack_light")
				punch_timer = 20
			elif punch_timer == 17:
				Input.action_release(&"attack_light")
		await _frames(1)
	_release_moves()
	return npc.combat.is_down()


func _release_moves() -> void:
	for action: StringName in [&"move_forward", &"sprint", &"attack_light"]:
		Input.action_release(action)


## Turns the camera until the crosshair ray passes through [param point] and
## holds aim (the "aim" action stays pressed).
func _aim_at(point: Vector3) -> void:
	Input.action_press(&"aim")
	for i in 12:
		var camera := player.camera_rig.camera
		var direction := (point - camera.global_position).normalized()
		var yaw_error := atan2(-direction.x, -direction.z) - _ray_yaw(camera)
		var pitch_error := asin(direction.y) - asin(-camera.global_basis.z.y)
		player.camera_rig.yaw = wrapf(player.camera_rig.yaw + yaw_error, -PI, PI)
		player.camera_rig.pitch += pitch_error
		await get_tree().process_frame
		await _frames(2)
	await _seconds(0.3)


func _ray_yaw(camera: Camera3D) -> float:
	var forward := -camera.global_basis.z
	return atan2(-forward.x, -forward.z)


## The crosshair ray hits [param npc]'s body or passes within its hurtbox.
func _crosshair_on(npc: NpcCharacter) -> bool:
	var point := player.aim.aim_point
	var center := npc.hurtbox.get_center()
	return Vector2(point.x - center.x, point.z - center.z).length() < 0.6


## One press of the fire button (aim must be held) and a short wait.
func _fire(wait_long: bool = true) -> void:
	_tap(&"attack_light")
	await _frames(20 if wait_long else 22)


func _hit_player(attack: AttackData) -> void:
	var thug := _enemies()[0] if not _enemies().is_empty() else null
	var attacker: Node3D = thug if thug != null else self as Node as Node3D
	player.hurtbox.receive_hit(attacker, attack, Vector3.BACK)


## The camera isn't inside any world geometry.
func _camera_clear() -> bool:
	var camera := player.camera_rig.camera
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.05
	query.shape = sphere
	query.transform = Transform3D(Basis(), camera.global_position)
	query.collision_mask = 1
	return camera.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _rifle_pickup(dropped_only: bool = false) -> Node3D:
	for node in get_tree().get_nodes_in_group(&"weapon_pickups"):
		if node.is_queued_for_deletion() or node.get(&"weapon") != RIFLE:
			continue
		if dropped_only and node.get(&"rounds") < 0:
			continue
		return node as Node3D
	return null


func _magazine_pickups() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child in arena.get_children():
		if child.get(&"item") == MAGAZINE and not child.is_queued_for_deletion():
			result.append(child as Node3D)
	return result


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
		if not get_tree().get_nodes_in_group(&"npcs").is_empty():
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
		&"attack_heavy",
		&"guard",
		&"aim",
		&"crouch",
		&"jump",
		&"reload",
		&"cover",
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


func _flat(distance: float) -> float:
	return distance


## RMB: guard and aim share the button.
func _press_rmb(pressed: bool) -> void:
	if pressed:
		Input.action_press(&"guard")
		Input.action_press(&"aim")
	else:
		Input.action_release(&"guard")
		Input.action_release(&"aim")


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


## For actions read with is_action_just_pressed in _physics_process.
func _press(action: StringName) -> void:
	Input.action_press(action)
	await _frames(1)
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
