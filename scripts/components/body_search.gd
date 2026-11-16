class_name BodySearch
extends Node3D
## "Search" interaction on a knocked-out or dead body (GDD §12 Looting).
##
## Needs an [Interactable] child with a hold time (searching leaves the
## player exposed). While the character is down it follows the body (the
## ragdoll's root) and, when used, moves the cash and items of
## [member inventory] to the interactor's inventory. The interactor provides
## it through a duck-typed [code]get_inventory() -> InventoryComponent[/code].
##
## Combat and looting know nothing about crime: the M3b CrimeManager listens
## to [signal looted].

## [param by] searched [param victim]'s body and took something (or nothing).
signal looted(victim: Node3D, by: Node3D)

@export var health: HealthComponent
@export var inventory: InventoryComponent
## Optional; the search point follows its root body. Falls back to [member body].
@export var ragdoll: RagdollComponent
## The character. Defaults to the parent.
@export var body: Node3D
## Height of the search point above the followed body.
@export var height_offset: float = 0.3
## Allow another search while something is left behind (pockets were full).
@export var allow_repeat_search: bool = true

## The body has been searched since it went down.
var searched: bool = false

@onready var interactable: Interactable = $Interactable


func _ready() -> void:
	if body == null:
		body = get_parent() as Node3D
	top_level = true
	interactable.enabled = false
	interactable.interacted.connect(_on_interacted)
	if health != null:
		health.knocked_out.connect(_on_down)
		health.killed.connect(_on_down)
		health.recovered.connect(_on_up)
		health.revived.connect(_on_up.bind(null))


func _physics_process(_delta: float) -> void:
	if not interactable.enabled:
		return
	var root: Node3D = ragdoll.get_root_body() if ragdoll != null else null
	var point := root.global_position if root != null else body.global_position
	global_position = point + Vector3.UP * height_offset


func _on_down(_victim: Node3D, _by: Node3D) -> void:
	if not searched:
		interactable.enabled = true
		_physics_process(0.0)
		reset_physics_interpolation()


func _on_up(_victim: Node3D) -> void:
	interactable.enabled = false
	searched = false


func _on_interacted(interactor: Node3D) -> void:
	if not interactor.has_method(&"get_inventory"):
		return
	var target := interactor.call(&"get_inventory") as InventoryComponent
	if target == null or inventory == null:
		return
	var result := inventory.transfer_to(target)
	searched = true
	interactable.enabled = allow_repeat_search and not result.left_behind.is_empty()
	Events.notify(_describe(result))
	looted.emit(body, interactor)


static func _describe(result: InventoryComponent.Transfer) -> String:
	if result.is_empty():
		return "Nothing worth taking" if result.left_behind.is_empty() else "Pockets full"
	var parts := PackedStringArray()
	if result.cash > 0:
		parts.append("$%d" % result.cash)
	for item in result.items:
		parts.append(item.display_name)
	var text := "Found: %s" % ", ".join(parts)
	if not result.left_behind.is_empty():
		text += " (pockets full)"
	return text
