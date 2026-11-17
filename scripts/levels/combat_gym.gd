extends Node3D
## M2 combat arena (M2.8). Bakes the navigation mesh, spawns the fight for
## the current mode and restarts it without reloading the scene.
##   restart_fight   : same fight again (enemies, player, weapons reset)
##   next_fight_mode : 1 vs 3 -> 1 vs 1 -> training dummy -> ...

signal fight_started(mode: Mode)

enum Mode { ONE_VS_THREE, ONE_VS_ONE, DUMMY }

const MODE_NAMES := ["1 vs 3 thugs", "1 vs 1 thug", "Training dummy"]

@export var mode: Mode = Mode.ONE_VS_THREE
@export var bat_weapon: WeaponData
## Health of the training dummy (doesn't fight back).
@export var dummy_health: float = 400.0
@export var kill_height: float = -20.0
## Max physics frames to wait for the navigation map at startup.
@export var navigation_sync_max_frames: int = 120

@onready var _player: Player = $Player
@onready var _player_spawn: Marker3D = $PlayerSpawn
@onready var _spawner: EnemySpawner = $EnemySpawner
@onready var _bat_spawns: Node3D = $BatSpawns
@onready var _navigation: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	NavigationBaker.bake_csg_boxes(_navigation)
	await _wait_for_navigation()
	start_fight()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart_fight"):
		start_fight()
	elif event.is_action_pressed(&"next_fight_mode"):
		mode = ((mode + 1) % Mode.size()) as Mode
		start_fight()


func _physics_process(_delta: float) -> void:
	if _player.global_position.y < kill_height:
		_player.revive(_player_spawn.global_transform)
	for npc in _spawner.get_alive():
		if npc.global_position.y < kill_height:
			npc.queue_free()


func start_fight() -> void:
	HitStop.cancel()
	_spawner.clear()
	for pickup in get_tree().get_nodes_in_group(&"weapon_pickups"):
		pickup.get_parent().remove_child(pickup)
		pickup.queue_free()
	_spawn_weapons()
	_player.revive(_player_spawn.global_transform)
	match mode:
		Mode.ONE_VS_THREE:
			_spawner.spawn(3)
		Mode.ONE_VS_ONE:
			_spawner.spawn(1)
		Mode.DUMMY:
			_spawner.spawn(1, _make_dummy)
	Events.notify("Fight: %s" % MODE_NAMES[mode])
	fight_started.emit(mode)


## The navigation map syncs asynchronously; wait until the baked region is in
## it, so NPCs get paths from their first tick.
func _wait_for_navigation() -> void:
	var map := _navigation.get_navigation_map()
	for i in navigation_sync_max_frames:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) == 0:
			continue
		var owner_rid := NavigationServer3D.map_get_closest_point_owner(
			map, _player_spawn.global_position
		)
		if owner_rid == _navigation.get_rid():
			return
	push_warning("CombatGym: navigation map not ready; NPCs steer directly until it is.")


func _spawn_weapons() -> void:
	if bat_weapon == null or bat_weapon.pickup_scene == null:
		return
	for marker in _bat_spawns.get_children():
		if not marker is Marker3D:
			continue
		var pickup := bat_weapon.pickup_scene.instantiate() as Node3D
		if &"weapon" in pickup:
			pickup.set(&"weapon", bat_weapon)
		add_child(pickup)
		pickup.global_transform = (marker as Marker3D).global_transform
		pickup.reset_physics_interpolation()


func _make_dummy(npc: Node) -> void:
	var ai := npc.get_node(^"AI") as ThugAI
	var health := npc.get_node(^"Health") as HealthComponent
	ai.enabled = false
	health.max_health = dummy_health
