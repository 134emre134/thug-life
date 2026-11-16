extends Node3D
## Pressable button. Connect [signal pressed] to whatever it should trigger.

signal pressed(by: Node3D)

@export var prompt: String = "Press"
@export var cooldown: float = 0.4
@export var press_depth: float = 0.04
## Optional notification shown when pressed.
@export var message: String = ""

var _ready_at: float = 0.0

@onready var _cap: Node3D = $Cap
@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.prompt_text = prompt
	_interactable.interacted.connect(_on_interacted)


func _on_interacted(interactor: Node3D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _ready_at:
		return
	_ready_at = now + cooldown
	var rest := _cap.position
	var tween := create_tween()
	tween.tween_property(_cap, "position", rest - _cap.basis.y * press_depth, cooldown * 0.3)
	tween.tween_property(_cap, "position", rest, cooldown * 0.5)
	if not message.is_empty():
		Events.notify(message)
	pressed.emit(interactor)
