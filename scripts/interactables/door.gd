extends Node3D
## Hinged door. Opens away from whoever uses it.
## Scene: Door -> Hinge (AnimatableBody3D) -> mesh, collision, Interactable.

@export var open_angle_degrees: float = 100.0
@export var open_time: float = 0.6
@export var open_prompt: String = "Open"
@export var close_prompt: String = "Close"
@export var start_open: bool = false

var is_open: bool = false

var _tween: Tween

@onready var _hinge: Node3D = $Hinge
@onready var _interactable: Interactable = $Hinge/Interactable


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)
	is_open = start_open
	_hinge.rotation.y = deg_to_rad(open_angle_degrees) if start_open else 0.0
	_update_prompt()


func _on_interacted(interactor: Node3D) -> void:
	var target_angle := 0.0
	if not is_open:
		# Swing away from the interactor: the door's local +Z side faces "front".
		var local := to_local(interactor.global_position)
		var side := 1.0 if local.z > 0.0 else -1.0
		target_angle = deg_to_rad(open_angle_degrees) * side
	is_open = not is_open
	_update_prompt()
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(_hinge, "rotation:y", target_angle, open_time)


func _update_prompt() -> void:
	_interactable.prompt_text = close_prompt if is_open else open_prompt
