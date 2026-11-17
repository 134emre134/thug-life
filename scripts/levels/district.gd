class_name District
extends Node3D
## Gray-box Brickhaven (M3b): streets, Brix Square, back alleys, reserved lots
## for the M5b shops and the M6 warehouse, the district gym (a [FightArena] in
## the boxing club yard), street thugs and civilians kept up by
## [EnemySpawner]s in population mode.
##
## Startup: bake navigation, wait for the map, put the player at the spawn,
## start the NPC populations. A downed or dead player wakes up at the clinic
## after [member clinic_delay], paying [member clinic_fee] (GDD §7, starting
## value). No police, crime or cars yet (M5a, M8).
##
## Also the minimap's data source ("minimap_world" group): the footprints of
## the nodes listed in [member minimap_layers], in world XZ.

## The gym fight (started by its button or the fight keys inside the yard).
@export var gym: FightArena
@export var kill_height: float = -20.0
## Max physics frames to wait for the navigation map at startup.
@export var navigation_sync_max_frames: int = 180

@export_group("Clinic")
## Seconds a downed player lies before waking up at the clinic.
@export var clinic_delay: float = 4.0
## Cash taken at the clinic (as much as the player has).
@export var clinic_fee: int = 50

@export_group("Minimap")
## Minimap layer -> node whose CSGBox3D / box CollisionShape3D descendants form
## it. Drawn in this order.
@export var minimap_layers: Dictionary[StringName, NodePath] = {}

var _clinic_timer: float = -1.0
var _minimap_shapes: Array[Dictionary] = []

@onready var _navigation: NavigationRegion3D = $NavigationRegion3D
@onready var _player: Player = $Player
@onready var _player_spawn: Marker3D = $PlayerSpawn
@onready var _clinic_spawn: Marker3D = $ClinicSpawn
@onready var _spawners: Node3D = $NpcSpawners


func _ready() -> void:
	add_to_group(&"minimap_world")
	_build_minimap_shapes()
	_player.knocked_out.connect(_on_player_down)
	_player.killed.connect(_on_player_down)
	if gym != null:
		var button := gym.get_node_or_null(^"StartButton")
		if button != null and button.has_signal(&"pressed"):
			button.connect(&"pressed", _on_gym_button)
	_player.revive(_player_spawn.global_transform)
	NavigationBaker.bake_csg_boxes(_navigation)
	await NavigationBaker.wait_for_region(
		_navigation, _player_spawn.global_position, navigation_sync_max_frames
	)
	for spawner in get_spawners():
		spawner.start_population()
	Events.notify("Brickhaven. The boxing club yard is up Dock Street (north-east).")


func _physics_process(delta: float) -> void:
	if _player.global_position.y < kill_height:
		_send_to_clinic()
	for spawner in get_spawners():
		for npc in spawner.get_spawned():
			if npc.global_position.y < kill_height:
				npc.queue_free()
	if _clinic_timer >= 0.0:
		_clinic_timer -= delta
		if _clinic_timer < 0.0:
			_send_to_clinic()


## The population spawners (street thugs, civilians).
func get_spawners() -> Array[EnemySpawner]:
	var result: Array[EnemySpawner] = []
	for child in _spawners.get_children():
		if child is EnemySpawner:
			result.append(child)
	return result


## Minimap data: [code]{layer: StringName, points: PackedVector2Array}[/code]
## per shape, points in world XZ.
func get_minimap_shapes() -> Array[Dictionary]:
	return _minimap_shapes


## Wakes the player up at the clinic and takes the fee.
func _send_to_clinic() -> void:
	_clinic_timer = -1.0
	_player.revive(_clinic_spawn.global_transform)
	var paid := _player.inventory.take_cash(mini(clinic_fee, _player.inventory.cash))
	Events.notify("St. Brix Clinic: you were patched up. Bill: $%d" % paid)


func _on_player_down() -> void:
	if _clinic_timer < 0.0:
		_clinic_timer = clinic_delay


func _on_gym_button(_by: Node3D) -> void:
	gym.start_fight(false)


func _build_minimap_shapes() -> void:
	_minimap_shapes.clear()
	for layer: StringName in minimap_layers:
		var root := get_node_or_null(minimap_layers[layer])
		if root == null:
			push_warning("District: minimap layer %s has no node." % layer)
			continue
		_collect_shapes(root, layer)


func _collect_shapes(node: Node, layer: StringName) -> void:
	var size := Vector3.ZERO
	if node is CSGBox3D:
		size = (node as CSGBox3D).size
	elif node is CollisionShape3D and (node as CollisionShape3D).shape is BoxShape3D:
		size = ((node as CollisionShape3D).shape as BoxShape3D).size
	if size != Vector3.ZERO:
		var xform := (node as Node3D).global_transform
		var points := PackedVector2Array()
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var local := Vector3(corner.x * size.x, 0.0, corner.y * size.z) * 0.5
			var world := xform * local
			points.append(Vector2(world.x, world.z))
		_minimap_shapes.append({&"layer": layer, &"points": points})
	for child in node.get_children():
		_collect_shapes(child, layer)
