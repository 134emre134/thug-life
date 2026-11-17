class_name ItemData
extends Resource
## Data definition for an item. Instances live in res://data/items/*.tres.

## Which [InventoryComponent] slot the item goes in.
enum Slot { POCKET, MELEE, FIREARM }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Base value in cash.
@export var value: int = 0


## Slot kind; [WeaponData] answers [code]MELEE[/code], [FirearmData] [code]FIREARM[/code].
func get_slot() -> Slot:
	return Slot.POCKET
