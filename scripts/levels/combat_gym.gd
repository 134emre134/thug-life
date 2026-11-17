extends FightArena
## Combat arena (M2.8, extended in M3a), kept as a debug scene next to the M3b
## district gym. Bakes the navigation mesh, then runs the [FightArena] fight;
## the restart and next-mode keys work anywhere.

@export var kill_height: float = -20.0
## Max physics frames to wait for the navigation map at startup.
@export var navigation_sync_max_frames: int = 120

@onready var _navigation: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	super()
	NavigationBaker.bake_csg_boxes(_navigation)
	await NavigationBaker.wait_for_region(
		_navigation, player_spawn.global_position, navigation_sync_max_frames
	)
	start_fight()


func _physics_process(_delta: float) -> void:
	if player.global_position.y < kill_height:
		player.revive(player_spawn.global_transform)
	for npc in spawner.get_alive():
		if npc.global_position.y < kill_height:
			npc.queue_free()
