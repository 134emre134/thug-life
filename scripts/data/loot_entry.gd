class_name LootEntry
extends Resource
## One possible item in a [LootTable].

@export var item: ItemData
## Chance (0..1) that the item is carried.
@export_range(0.0, 1.0) var chance: float = 0.5
