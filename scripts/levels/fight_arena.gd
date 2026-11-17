class_name FightArena
extends Node3D
## A restartable test fight (M2.8, reused by the M3b district gym): spawns the
## fight for the current mode, lays out the weapons and starts it again
## without reloading the scene.
##   restart_fight   : same fight again (enemies, player, weapons reset)
##   next_fight_mode : 1 vs 3 -> 1 vs 1 -> training dummy -> mixed -> ...
## The 1 vs 3 fight mixes NPC types (two thugs and a collector, with different
## loot), as set on the spawner. The mixed fight (M4b.4) is melee thugs plus
## rifle thugs ([member mixed_scenes]).
##
## Nodes are found by name when the exports are empty: EnemySpawner,
## BatSpawns, KnifeSpawns, RifleSpawns, MagazineSpawns, PlayerSpawn; the
## player through the "player" group.

signal fight_started(mode: Mode)

enum Mode { ONE_VS_THREE, ONE_VS_ONE, DUMMY, MIXED }

const MODE_NAMES := ["1 vs 3 thugs", "1 vs 1 thug", "Training dummy", "Mixed: 2 thugs + 2 rifles"]

@export var mode: Mode = Mode.ONE_VS_THREE
@export var bat_weapon: WeaponData
@export var knife_weapon: WeaponData
## Laid out at the RifleSpawns markers (M4b).
@export var rifle_weapon: FirearmData
## Ammo pickups laid out at the MagazineSpawns markers.
@export var magazine_pickup: PackedScene
## NPCs of the mixed fight, in spawn order (cycled over the spawn markers).
@export var mixed_scenes: Array[PackedScene] = []
## Health of the training dummy (doesn't fight back).
@export var dummy_health: float = 400.0
## A restart takes the weapons away (cash and pockets are kept).
@export var restart_clears_weapon: bool = true
## A restart also removes weapons dropped during the fight (inside
## [member input_area], or anywhere without one).
@export var clear_dropped_weapons: bool = true
## The restart/next-mode keys only work while the player is inside this area.
## Empty = anywhere.
@export var input_area: Area3D

@export_group("Nodes")
@export var spawner: EnemySpawner
@export var bat_spawns: Node3D
@export var knife_spawns: Node3D
@export var rifle_spawns: Node3D
@export var magazine_spawns: Node3D
@export var player_spawn: Marker3D
@export var player: Player

var _weapons: Array[Node3D] = []


func _ready() -> void:
	if spawner == null:
		spawner = get_node_or_null(^"EnemySpawner") as EnemySpawner
	if bat_spawns == null:
		bat_spawns = get_node_or_null(^"BatSpawns") as Node3D
	if knife_spawns == null:
		knife_spawns = get_node_or_null(^"KnifeSpawns") as Node3D
	if rifle_spawns == null:
		rifle_spawns = get_node_or_null(^"RifleSpawns") as Node3D
	if magazine_spawns == null:
		magazine_spawns = get_node_or_null(^"MagazineSpawns") as Node3D
	if player_spawn == null:
		player_spawn = get_node_or_null(^"PlayerSpawn") as Marker3D
	_resolve_player()


func _unhandled_input(event: InputEvent) -> void:
	if not (
		event.is_action_pressed(&"restart_fight") or event.is_action_pressed(&"next_fight_mode")
	):
		return
	if not is_player_inside():
		return
	if event.is_action_pressed(&"next_fight_mode"):
		mode = ((mode + 1) % Mode.size()) as Mode
	start_fight()
	get_viewport().set_input_as_handled()


## Starts the fight for [member mode]. With [param reset_player] the player is
## revived at the player spawn (and loses the held weapon if
## [member restart_clears_weapon]); without it the player stays where they are.
func start_fight(reset_player: bool = true) -> void:
	HitStop.cancel()
	stop_fight()
	_spawn_weapons(bat_weapon, bat_spawns)
	_spawn_weapons(knife_weapon, knife_spawns)
	_spawn_weapons(rifle_weapon, rifle_spawns)
	_spawn_scene(magazine_pickup, magazine_spawns)
	_resolve_player()
	if reset_player and player != null and player_spawn != null:
		if restart_clears_weapon:
			player.inventory.clear_weapons()
		player.revive(player_spawn.global_transform)
	match mode:
		Mode.ONE_VS_THREE:
			spawner.spawn(3)
		Mode.ONE_VS_ONE:
			spawner.spawn(1)
		Mode.DUMMY:
			spawner.spawn(1, _make_dummy)
		Mode.MIXED:
			spawner.spawn(mixed_scenes.size(), Callable(), mixed_scenes)
	Events.notify("Fight: %s" % MODE_NAMES[mode])
	fight_started.emit(mode)


## Removes this arena's enemies and the weapons it laid out.
func stop_fight() -> void:
	spawner.clear()
	var remove: Array[Node3D] = []
	for pickup in _weapons:
		if is_instance_valid(pickup) and pickup.is_inside_tree():
			remove.append(pickup)
	if clear_dropped_weapons:
		for node in get_tree().get_nodes_in_group(&"weapon_pickups"):
			var pickup := node as Node3D
			if pickup == null or remove.has(pickup):
				continue
			if input_area == null or input_area.overlaps_body(pickup):
				remove.append(pickup)
	for pickup in remove:
		pickup.get_parent().remove_child(pickup)
		pickup.queue_free()
	_weapons.clear()


func is_player_inside() -> bool:
	if input_area == null:
		return true
	_resolve_player()
	return player != null and input_area.overlaps_body(player)


## The player may be added after this node (it is found through its group).
func _resolve_player() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Player


func _spawn_weapons(weapon: WeaponData, markers: Node3D) -> void:
	if weapon == null or weapon.pickup_scene == null or markers == null:
		return
	for marker in markers.get_children():
		if not marker is Marker3D:
			continue
		var pickup := weapon.pickup_scene.instantiate() as Node3D
		if &"weapon" in pickup:
			pickup.set(&"weapon", weapon)
		add_child(pickup)
		pickup.global_transform = (marker as Marker3D).global_transform
		pickup.reset_physics_interpolation()
		_weapons.append(pickup)


func _spawn_scene(scene: PackedScene, markers: Node3D) -> void:
	if scene == null or markers == null:
		return
	for marker in markers.get_children():
		if not marker is Marker3D:
			continue
		var pickup := scene.instantiate() as Node3D
		add_child(pickup)
		pickup.global_transform = (marker as Marker3D).global_transform
		pickup.reset_physics_interpolation()
		_weapons.append(pickup)


func _make_dummy(npc: Node) -> void:
	var ai := npc.get_node(^"AI") as NpcController
	var health := npc.get_node(^"Health") as HealthComponent
	ai.enabled = false
	health.max_health = dummy_health
