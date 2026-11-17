class_name EnemySpawner
extends Node3D
## Spawns NPCs at its Marker3D children (in order) and keeps track of them.

signal spawned(npc: Node3D)

@export var enemy_scene: PackedScene
## Node the NPCs are added to. Defaults to this spawner.
@export var container: Node

var _spawned: Array[Node3D] = []


## Spawns [param count] NPCs. [param configure] is called with each NPC before
## it enters the tree (e.g. to change exports).
func spawn(count: int, configure: Callable = Callable()) -> Array[Node3D]:
	var markers: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D:
			markers.append(child)
	var result: Array[Node3D] = []
	if enemy_scene == null or markers.is_empty():
		push_warning("EnemySpawner: no enemy scene or no Marker3D spawn points.")
		return result
	var parent := container if container != null else self
	for i in count:
		var npc := enemy_scene.instantiate() as Node3D
		if configure.is_valid():
			configure.call(npc)
		parent.add_child(npc)
		# Only the model turns: the movement component assumes an unrotated body.
		var marker := markers[i % markers.size()]
		npc.global_position = marker.global_position
		var model := npc.get_node_or_null(^"Model") as Node3D
		if model != null:
			model.rotation.y = marker.global_rotation.y
		npc.reset_physics_interpolation()
		_spawned.append(npc)
		result.append(npc)
		spawned.emit(npc)
	return result


## Removes everything this spawner created (ragdolls included).
func clear() -> void:
	for npc in _spawned:
		if is_instance_valid(npc):
			npc.get_parent().remove_child(npc)
			npc.queue_free()
	_spawned.clear()


func get_alive() -> Array[Node3D]:
	var alive: Array[Node3D] = []
	for npc in _spawned:
		if not is_instance_valid(npc):
			continue
		var combat := npc.get_node_or_null(^"Combat") as MeleeCombat
		if combat == null or not combat.is_knocked_out():
			alive.append(npc)
	return alive
