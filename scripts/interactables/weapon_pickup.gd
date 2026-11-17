class_name WeaponPickup
extends RigidBody3D
## A weapon lying in the world: a physical prop that hands its [WeaponData] to
## whoever uses it, through a duck-typed [code]receive_item(item) -> bool[/code]
## method on the interactor (the player puts it in its inventory). A firearm
## also hands over the rounds in its magazine:
## [code]receive_item(item, rounds) -> bool[/code]. The scene
## doesn't reference its weapon itself (see [WeaponData]); the level or the
## dropping inventory assigns it.

@export var weapon: WeaponData
## Rounds in a firearm's magazine (-1 = full). Set when a firearm is dropped.
@export var rounds: int = -1

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
	var accepted: bool
	if taken is FirearmData:
		accepted = interactor.call(&"receive_item", taken, rounds)
	else:
		accepted = interactor.call(&"receive_item", taken)
	if not accepted:
		weapon = taken
		return
	_interactable.enabled = false
	queue_free()
	Events.notify("Picked up: %s" % taken.display_name)
