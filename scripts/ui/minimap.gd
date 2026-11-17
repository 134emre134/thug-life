class_name Minimap
extends Control
## Basic district minimap (GDD §13, M3b.6): the footprints the level provides
## (a node in the "minimap_world" group with [code]get_minimap_shapes()[/code],
## e.g. [District]) around the player, the player's position and facing, and
## a north marker. Hidden in levels without map data (combat arena).
##
## No police data: the M5a search area is drawn on top later, never live
## police positions (GDD §8).

## Metres from the centre to the edge of the map.
@export var world_radius: float = 45.0
## Turn the map with the camera, so "up" is where the camera looks.
@export var rotate_with_camera: bool = true
@export var background_color: Color = Color(0.1, 0.11, 0.13, 0.85)
@export var border_color: Color = Color(1, 1, 1, 0.5)
@export var player_color: Color = Color(1.0, 0.95, 0.3)
@export var player_marker_size: float = 9.0
## Fill colour per layer (as named by the level). Layers not listed are skipped.
@export var layer_colors: Dictionary[StringName, Color] = {
	&"water": Color(0.16, 0.3, 0.42),
	&"plaza": Color(0.42, 0.37, 0.32),
	&"sidewalk": Color(0.36, 0.36, 0.36),
	&"road": Color(0.22, 0.23, 0.25),
	&"lot": Color(0.85, 0.68, 0.15, 0.55),
	&"obstacle": Color(0.5, 0.5, 0.52),
	&"building": Color(0.7, 0.7, 0.72),
	&"gym": Color(0.95, 0.45, 0.2, 0.45),
}

## The player the map is centred on (found through the "player" group).
var player: Player = null

var _source: Node = null
var _shapes: Array[Dictionary] = []


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_find_source()


func _process(_delta: float) -> void:
	if _source == null or not is_instance_valid(_source):
		_find_source()
	visible = _source != null and player != null
	if visible:
		queue_redraw()


## Map position (local pixels) of a world point, for the current player
## position and camera.
func world_to_map(world: Vector3) -> Vector2:
	var relative := Vector2(world.x - player.global_position.x, world.z - player.global_position.z)
	var yaw := get_map_yaw()
	# Camera forward in XZ is (-sin yaw, -cos yaw), its right (cos yaw, -sin yaw).
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var local := Vector2(relative.dot(right), -relative.dot(forward))
	return size * 0.5 + local * (minf(size.x, size.y) * 0.5 / world_radius)


## Yaw the map is turned by (0 = north up).
func get_map_yaw() -> float:
	return player.camera_rig.yaw if rotate_with_camera and player != null else 0.0


## Number of shapes the level provided.
func get_shape_count() -> int:
	return _shapes.size()


func _draw() -> void:
	if _source == null or player == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), background_color)
	var bounds := Rect2(Vector2.ZERO, size).grow(size.x)
	for shape in _shapes:
		var layer: StringName = shape[&"layer"]
		if not layer_colors.has(layer):
			continue
		var world_points: PackedVector2Array = shape[&"points"]
		var points := PackedVector2Array()
		var inside := false
		for point in world_points:
			var mapped := world_to_map(Vector3(point.x, 0.0, point.y))
			points.append(mapped)
			inside = inside or bounds.has_point(mapped)
		if inside:
			draw_colored_polygon(points, layer_colors[layer])
	_draw_north()
	_draw_player()
	draw_rect(Rect2(Vector2.ZERO, size), border_color, false, 2.0)


func _draw_player() -> void:
	var centre := world_to_map(player.global_position)
	# Facing of the model, relative to the map.
	var facing := player.get_facing()
	var tip_world := player.global_position + facing
	var direction := (world_to_map(tip_world) - centre).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.UP
	var side := Vector2(-direction.y, direction.x)
	var length := player_marker_size
	var points := PackedVector2Array(
		[
			centre + direction * length,
			centre - direction * length * 0.6 + side * length * 0.7,
			centre - direction * length * 0.3,
			centre - direction * length * 0.6 - side * length * 0.7,
		]
	)
	draw_colored_polygon(points, player_color)


func _draw_north() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var centre := size * 0.5
	var north := world_to_map(player.global_position + Vector3.FORWARD * world_radius * 2.0)
	var direction := (north - centre).normalized()
	var radius := minf(size.x, size.y) * 0.5 - 10.0
	var position_on_edge := centre + direction * radius
	draw_string(font, position_on_edge + Vector2(-5, 6), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 14)


func _find_source() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Player
	_source = get_tree().get_first_node_in_group(&"minimap_world")
	_shapes = []
	if _source != null and _source.has_method(&"get_minimap_shapes"):
		_shapes = _source.call(&"get_minimap_shapes")
	elif _source != null:
		_source = null
