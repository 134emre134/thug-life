class_name Interactable
extends Area3D
## Reusable interaction component.
##
## Add as a child of any object (with a CollisionShape3D child of its own) and
## connect to [signal interacted]. The player's [InteractionComponent] finds
## Interactables by physics layer, so the player never needs special-case code
## for specific object types.

## Emitted when an interactor (usually the player) uses this object.
signal interacted(interactor: Node3D)
## Emitted when this becomes / stops being the interactor's current best target.
signal focus_changed(focused: bool)

const LAYER_INTERACTABLE := 1 << 3  # physics layer 4 "interactable"

## Text shown in the on-screen prompt, e.g. "Open", "Pick up".
@export var prompt_text: String = "Interact"
## Disabled interactables are ignored by the interactor.
@export var enabled: bool = true
## Disable automatically after the first successful interaction.
@export var one_shot: bool = false
## Added to the target score; use to favour important objects that overlap others.
@export var focus_priority: float = 0.0
## Optional point used for distance / line-of-sight checks. Defaults to this node.
@export var focus_point: Node3D


func _ready() -> void:
	collision_layer = LAYER_INTERACTABLE
	collision_mask = 0
	monitoring = false
	monitorable = true


func can_interact(_interactor: Node3D) -> bool:
	return enabled


func interact(interactor: Node3D) -> void:
	if not can_interact(interactor):
		return
	interacted.emit(interactor)
	if one_shot:
		enabled = false


func get_focus_position() -> Vector3:
	return focus_point.global_position if focus_point else global_position
