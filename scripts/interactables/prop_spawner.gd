extends Marker3D
## Spawns physics props on demand (hooked to a button in the test gym).

@export var prop_scenes: Array[PackedScene] = []
## Oldest props are removed above this count.
@export var max_props: int = 12
@export var random_spin: float = 2.0

var _spawned: Array[Node3D] = []


func spawn(_by: Node3D = null) -> void:
	if prop_scenes.is_empty():
		return
	var prop := prop_scenes.pick_random().instantiate() as Node3D
	get_tree().current_scene.add_child(prop)
	prop.global_transform = global_transform
	if prop is RigidBody3D:
		(prop as RigidBody3D).angular_velocity = (
			Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * random_spin
		)
	_spawned.append(prop)
	while _spawned.size() > max_props:
		var old: Node3D = _spawned.pop_front()
		if is_instance_valid(old):
			old.queue_free()
