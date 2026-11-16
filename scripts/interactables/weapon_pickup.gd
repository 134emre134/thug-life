class_name WeaponPickup
extends RigidBody3D
## A weapon lying in the world: a physical prop that hands its [WeaponData] to
## whoever uses it, through a duck-typed [code]equip_weapon(weapon)[/code]
## method on the interactor. The scene doesn't reference its weapon itself
## (see [WeaponData]); the level or the dropping character assigns it.

@export var weapon: WeaponData

@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	add_to_group(&"weapon_pickups")
	_interactable.interacted.connect(_on_interacted)
	if weapon != null:
		_interactable.prompt_text = "Pick up %s" % weapon.display_name


func _on_interacted(interactor: Node3D) -> void:
	if weapon == null or not interactor.has_method(&"equip_weapon"):
		return
	var taken := weapon
	weapon = null
	_interactable.enabled = false
	queue_free()
	interactor.call(&"equip_weapon", taken)
	Events.notify("Picked up: %s" % taken.display_name)
