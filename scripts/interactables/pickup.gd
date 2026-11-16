extends Node3D
## World pickup for an [ItemData]. Spins/bobs, disappears when collected.
## The item goes to the interactor through a duck-typed
## [code]receive_item(item) -> bool[/code] (the player's inventory); if that
## refuses it (pockets full), the pickup stays.

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
	if item != null and interactor.has_method(&"receive_item"):
		if not interactor.call(&"receive_item", item):
			Events.notify("Pockets full")
			# The interactable is one-shot: keep it usable.
			_interactable.set_deferred(&"enabled", true)
			return
	picked_up.emit(item, interactor)
	var item_name := item.display_name if item else "item"
	Events.notify("Picked up: %s" % item_name)
	queue_free()
