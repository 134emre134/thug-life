class_name LootTable
extends Resource
## What an NPC type carries (GDD §12). Instances live in res://data/loot/ and
## are assigned to an NPC's [InventoryComponent]; the roll fills that
## inventory on spawn. Looting (M3a) and pickpocketing (M3b) both take from it.

## Cash range (inclusive) in the wallet.
@export var cash_min: int = 0
@export var cash_max: int = 0
## Chance (0..1) to carry any cash at all.
@export_range(0.0, 1.0) var cash_chance: float = 1.0
## Each entry is rolled on its own.
@export var entries: Array[LootEntry] = []
## Upper limit on rolled items (0 = no limit beyond the pocket slots).
@export var max_items: int = 0


func roll_cash(rng: RandomNumberGenerator) -> int:
	if cash_max <= 0 or rng.randf() >= cash_chance:
		return 0
	return rng.randi_range(maxi(cash_min, 0), maxi(cash_max, cash_min))


func roll_items(rng: RandomNumberGenerator) -> Array[ItemData]:
	var items: Array[ItemData] = []
	for entry in entries:
		if entry == null or entry.item == null:
			continue
		if max_items > 0 and items.size() >= max_items:
			break
		if rng.randf() < entry.chance:
			items.append(entry.item)
	return items
