extends Node3D
## World pickup for an [ItemData]. Spins/bobs, disappears when collected.

signal picked_up(item: ItemData, by: Node3D)

@export var item: ItemData
@export var spin_speed: float = 1.5
@export var bob_height: float = 0.08
@export var bob_speed: float = 2.0

var _time: float = 0.0

@onready var _visual: Node3D = $Visual
@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)
	if item:
		_interactable.prompt_text = "Pick up %s" % item.display_name


func _process(delta: float) -> void:
	_time += delta
	_visual.rotation.y += spin_speed * delta
	_visual.position.y = sin(_time * bob_speed) * bob_height


func _on_interacted(interactor: Node3D) -> void:
	picked_up.emit(item, interactor)
	var item_name := item.display_name if item else "item"
	Events.notify("Picked up: %s" % item_name)
	queue_free()
