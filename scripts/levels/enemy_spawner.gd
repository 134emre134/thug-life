class_name EnemySpawner
extends Node3D
## Spawns NPCs at its Marker3D children and keeps track of them. NPC i uses
## [member enemy_scenes] entry i (cycled), so a fight can mix NPC types;
## without entries every NPC is [member enemy_scene].
##
## Two ways to use it:
## - Manual (arena fights): [method spawn] / [method clear].
## - Population (M3b district: street thugs, civilians): after
##   [method start_population] it keeps [member population] NPCs standing.
##   Lost NPCs (dead or removed) are replaced one at a time after
##   [member respawn_delay], at a marker the player is far from; dead bodies
##   are removed after [member corpse_time] once the player is far away.
##   Knocked-out NPCs still count: they get back up.

signal spawned(npc: Node3D)

@export var enemy_scene: PackedScene
## Scene per spawn, in order (cycled). Empty = always [member enemy_scene].
@export var enemy_scenes: Array[PackedScene] = []
## Node the NPCs are added to. Defaults to this spawner.
@export var container: Node

@export_group("Population")
## NPCs to keep standing once [method start_population] is called.
@export var population: int = 0
## Seconds between replacing a lost NPC.
@export var respawn_delay: float = 20.0
## New NPCs only appear at markers at least this far from the player, and
## bodies are only removed this far from the player.
@export var min_player_distance: float = 25.0
## Seconds a dead body stays before it may be removed.
@export var corpse_time: float = 45.0

var _spawned: Array[Node3D] = []
var _spawn_count: int = 0
var _populating: bool = false
var _respawn_timer: float = 0.0
## Dead NPC instance id -> seconds since death.
var _dead_time: Dictionary = {}


func _physics_process(delta: float) -> void:
	if not _populating:
		return
	_prune()
	_remove_old_bodies(delta)
	if get_standing_count() >= population:
		_respawn_timer = 0.0
		return
	_respawn_timer += delta
	if _respawn_timer < respawn_delay:
		return
	var marker := _pick_far_marker()
	if marker != null:
		_respawn_timer = 0.0
		_spawn_at(marker, _spawn_count)


## Spawns [param count] NPCs at the markers in order. [param configure] is
## called with each NPC before it enters the tree (e.g. to change exports).
## [param scenes] replaces [member enemy_scenes] for this call (cycled).
func spawn(
	count: int, configure: Callable = Callable(), scenes: Array[PackedScene] = []
) -> Array[Node3D]:
	var markers := _markers()
	var result: Array[Node3D] = []
	var no_scene := enemy_scene == null and enemy_scenes.is_empty() and scenes.is_empty()
	if no_scene or markers.is_empty():
		push_warning("EnemySpawner: no enemy scene or no Marker3D spawn points.")
		return result
	for i in count:
		result.append(_spawn_at(markers[i % markers.size()], i, configure, scenes))
	return result


## Fills up to [member population] and keeps it there from now on.
func start_population() -> void:
	_populating = true
	_respawn_timer = 0.0
	var missing := population - get_standing_count()
	if missing > 0:
		spawn(missing)


func stop_population() -> void:
	_populating = false


## Removes everything this spawner created (ragdolls included).
func clear() -> void:
	for npc in _spawned:
		if is_instance_valid(npc):
			npc.get_parent().remove_child(npc)
			npc.queue_free()
	_spawned.clear()
	_dead_time.clear()


## NPCs that are not knocked out or dead.
func get_alive() -> Array[Node3D]:
	var alive: Array[Node3D] = []
	for npc in _spawned:
		if not is_instance_valid(npc):
			continue
		var combat := npc.get_node_or_null(^"Combat") as MeleeCombat
		if combat == null or not combat.is_down():
			alive.append(npc)
	return alive


## Every NPC this spawner created that still exists.
func get_spawned() -> Array[Node3D]:
	_prune()
	var result: Array[Node3D] = _spawned.duplicate()
	return result


## NPCs that are not dead (knocked-out ones get back up).
func get_standing_count() -> int:
	var count := 0
	for npc in _spawned:
		if is_instance_valid(npc) and not _is_dead(npc):
			count += 1
	return count


## Spawns one NPC at [param marker], using scene [param index] (cycled) of
## [param scenes], else of [member enemy_scenes].
func _spawn_at(
	marker: Marker3D, index: int, configure: Callable = Callable(), scenes: Array[PackedScene] = []
) -> Node3D:
	var scene := enemy_scene
	var pool := scenes if not scenes.is_empty() else enemy_scenes
	if not pool.is_empty() and pool[index % pool.size()] != null:
		scene = pool[index % pool.size()]
	_spawn_count += 1
	var npc := scene.instantiate() as Node3D
	if configure.is_valid():
		configure.call(npc)
	var parent := container if container != null else self
	parent.add_child(npc, true)
	# Only the model turns: the movement component assumes an unrotated body.
	npc.global_position = marker.global_position
	var model := npc.get_node_or_null(^"Model") as Node3D
	if model != null:
		model.rotation.y = marker.global_rotation.y
	npc.reset_physics_interpolation()
	_spawned.append(npc)
	spawned.emit(npc)
	return npc


func _markers() -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D:
			markers.append(child)
	return markers


## A random marker far enough from the player (null if none is).
func _pick_far_marker() -> Marker3D:
	var candidates: Array[Marker3D] = []
	for marker in _markers():
		if _player_distance(marker.global_position) >= min_player_distance:
			candidates.append(marker)
	return candidates.pick_random() if not candidates.is_empty() else null


func _remove_old_bodies(delta: float) -> void:
	for npc: Node3D in _spawned.duplicate():
		if not _is_dead(npc):
			continue
		var id := npc.get_instance_id()
		_dead_time[id] = float(_dead_time.get(id, 0.0)) + delta
		if _dead_time[id] < corpse_time:
			continue
		if _player_distance(_body_position(npc)) < min_player_distance:
			continue
		_dead_time.erase(id)
		_spawned.erase(npc)
		npc.get_parent().remove_child(npc)
		npc.queue_free()


func _prune() -> void:
	for i in range(_spawned.size() - 1, -1, -1):
		if not is_instance_valid(_spawned[i]) or _spawned[i].is_queued_for_deletion():
			_spawned.remove_at(i)


func _is_dead(npc: Node3D) -> bool:
	var health := npc.get_node_or_null(^"Health") as HealthComponent
	return health != null and health.is_dead()


## Where the NPC (or its ragdoll) lies.
func _body_position(npc: Node3D) -> Vector3:
	var hurtbox := npc.get_node_or_null(^"Hurtbox") as Node3D
	return hurtbox.global_position if hurtbox != null else npc.global_position


func _player_distance(point: Vector3) -> float:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	return player.global_position.distance_to(point) if player != null else INF
