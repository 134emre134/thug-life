class_name WalkRoute
extends Node3D
## A civilian walking route (M3b): its Marker3D children, in order, are the
## points. Civilians without an assigned route pick the nearest one
## ([method find_nearest]).

## Walk the points in a loop; otherwise walk back and forth.
@export var loop: bool = true
## Chance to stop and idle at each point.
@export_range(0.0, 1.0) var idle_chance: float = 0.35


func _ready() -> void:
	add_to_group(&"walk_routes")


func get_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for child in get_children():
		if child is Marker3D:
			points.append((child as Marker3D).global_position)
	return points


## Index of the point closest to [param from] (-1 without points).
func closest_index(from: Vector3) -> int:
	var points := get_points()
	var best := -1
	var best_distance := INF
	for i in points.size():
		var distance := points[i].distance_squared_to(from)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## Index after [param index] when walking in [param direction] (+1/-1). Updates
## the direction at the ends of a back-and-forth route; returns the new pair.
func next_index(index: int, direction: int) -> Vector2i:
	var count := get_points().size()
	if count <= 1:
		return Vector2i(0, direction)
	if loop:
		return Vector2i(posmod(index + direction, count), direction)
	var next := index + direction
	if next < 0 or next >= count:
		direction = -direction
		next = index + direction
	return Vector2i(next, direction)


## The route closest to [param from] in [param tree] (null if none).
static func find_nearest(tree: SceneTree, from: Vector3) -> WalkRoute:
	var best: WalkRoute = null
	var best_distance := INF
	for node in tree.get_nodes_in_group(&"walk_routes"):
		var route := node as WalkRoute
		if route == null:
			continue
		var index := route.closest_index(from)
		if index < 0:
			continue
		var distance := route.get_points()[index].distance_squared_to(from)
		if distance < best_distance:
			best_distance = distance
			best = route
	return best
