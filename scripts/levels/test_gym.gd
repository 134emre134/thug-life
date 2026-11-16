extends Node3D
## M1 gray-box test level ("gym"). Respawns the player if they fall out.

@export var kill_height: float = -20.0
@export var spawn_point: Vector3 = Vector3.ZERO

@onready var _player: Player = $Player


func _physics_process(_delta: float) -> void:
	if _player.global_position.y < kill_height:
		_player.global_position = spawn_point
		_player.velocity = Vector3.ZERO
		_player.reset_physics_interpolation()
