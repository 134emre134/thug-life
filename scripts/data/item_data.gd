class_name ItemData
extends Resource
## Data definition for an item. Instances live in res://data/items/*.tres.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Base value in cash.
@export var value: int = 0
