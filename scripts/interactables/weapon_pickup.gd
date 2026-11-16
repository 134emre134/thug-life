class_name WeaponPickup
extends RigidBody3D
## A weapon lying in the world: a physical prop that hands its [WeaponData] to
## whoever uses it, through a duck-typed [code]receive_item(item) -> bool[/code]
## method on the interactor (the player puts it in its inventory). The scene
## doesn't reference its weapon itself (see [WeaponData]); the level or the
## dropping inventory assigns it.

@export var weapon: WeaponData

@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	add_to_group(&"weapon_pickups")
	_interactable.interacted.connect(_on_interacted)
	if weapon != null:
		_interactable.prompt_text = "Pick up %s" % weapon.display_name


func _on_interacted(interactor: Node3D) -> void:
	if weapon == null or not interactor.has_method(&"receive_item"):
		return
	var taken := weapon
	weapon = null
	if not interactor.call(&"receive_item", taken):
		weapon = taken
		return
	_interactable.enabled = false
	queue_free()
	Events.notify("Picked up: %s" % taken.display_name)
