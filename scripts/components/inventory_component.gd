class_name InventoryComponent
extends Node
## What a character carries (GDD §12), for the player and NPCs alike:
## one melee slot, one firearm slot (inactive until M4), a few pocket slots and
## a wallet (cash is a number, not an item).
##
## The inventory owns weapons. The melee weapon is either drawn (in hand: the
## [MeleeCombat] fights with it) or holstered (carried, fists in use).
## Dropping spawns the weapon's world pickup. NPCs fill their inventory from a
## [LootTable] on spawn; looting moves the contents to another inventory with
## [method transfer_to].

## Any slot or the wallet changed.
signal changed
signal cash_changed(cash: int, delta: int)


## Result of [method transfer_to].
class Transfer:
	var cash: int = 0
	var items: Array[ItemData] = []
	## Items that didn't fit and stayed behind.
	var left_behind: Array[ItemData] = []

	func is_empty() -> bool:
		return cash == 0 and items.is_empty()


## Optional: receives the drawn melee weapon via [method MeleeCombat.set_weapon].
@export var combat: MeleeCombat
## Optional: knockout and death drop the melee weapon (see [member drop_on_down]).
@export var health: HealthComponent
## The character. Defaults to the parent.
@export var body: Node3D
## Node that turns with the character (drop direction). Defaults to [member body].
@export var model: Node3D
## Where dropped weapons appear (the hand socket). Defaults to [member body].
@export var drop_origin: Node3D

@export_group("Slots")
@export_range(0, 12) var pocket_slots: int = 4
## Firearm slot; stays inactive until M4.
@export var firearm_slot_active: bool = false

@export_group("Start")
@export var start_cash: int = 0
@export var start_melee: WeaponData
@export var start_items: Array[ItemData] = []
## Rolled into the inventory on spawn (NPC types).
@export var loot_table: LootTable
@export var roll_loot_on_ready: bool = true

@export_group("Drop")
## Knockout and death drop the melee weapon physically (GDD §7 Weapons).
@export var drop_on_down: bool = true
## Velocity given to a dropped weapon (m/s, local to the model: -Z forward).
@export var drop_velocity: Vector3 = Vector3(0.0, 1.5, -1.0)

var cash: int = 0
var melee: WeaponData = null
## The melee weapon is in hand (false = holstered).
var melee_drawn: bool = false
## Always null until M4.
var firearm: ItemData = null
## Fixed size ([member pocket_slots]); empty slots are null.
var pockets: Array[ItemData] = []


func _ready() -> void:
	if body == null:
		body = get_parent() as Node3D
	if model == null:
		model = body
	if drop_origin == null:
		drop_origin = body
	pockets.resize(pocket_slots)
	cash = maxi(start_cash, 0)
	for item in start_items:
		add_item(item)
	if start_melee != null:
		melee = start_melee
		melee_drawn = true
	if loot_table != null and roll_loot_on_ready:
		roll_loot(loot_table)
	if health != null:
		health.knocked_out.connect(_on_down)
		health.killed.connect(_on_down)
	_sync_combat.call_deferred()


## Weapon in hand, or null (fists).
func get_held_weapon() -> WeaponData:
	return melee if melee_drawn else null


## Every carried item (melee, firearm, pockets), in slot order.
func get_items() -> Array[ItemData]:
	var items: Array[ItemData] = []
	if melee != null:
		items.append(melee)
	if firearm != null:
		items.append(firearm)
	for item in pockets:
		if item != null:
			items.append(item)
	return items


func is_empty() -> bool:
	return cash == 0 and get_items().is_empty()


func get_free_pocket_count() -> int:
	return pockets.count(null)


func has_item(item: ItemData) -> bool:
	return get_items().has(item)


## Stores [param item] in its slot. A weapon goes to an empty melee slot and is
## drawn. Returns false if there is no room.
func add_item(item: ItemData) -> bool:
	if item == null:
		return false
	match item.get_slot():
		ItemData.Slot.MELEE:
			if melee != null:
				return false
			melee = item as WeaponData
			melee_drawn = true
			_sync_combat()
		ItemData.Slot.FIREARM:
			if not firearm_slot_active or firearm != null:
				return false
			firearm = item
		_:
			var index := pockets.find(null)
			if index < 0:
				return false
			pockets[index] = item
	changed.emit()
	return true


## Takes a weapon from the world: the current melee weapon is dropped first,
## the new one ends up in hand.
func pick_up_weapon(weapon: WeaponData) -> bool:
	if weapon == null:
		return false
	if melee != null:
		drop_melee()
	return add_item(weapon)


## Removes one [param item] without dropping it. Returns false if not carried.
func remove_item(item: ItemData) -> bool:
	if item == null:
		return false
	if item == melee:
		melee = null
		melee_drawn = false
		_sync_combat()
	elif item == firearm:
		firearm = null
	else:
		var index := pockets.find(item)
		if index < 0:
			return false
		pockets[index] = null
	changed.emit()
	return true


func add_cash(amount: int) -> void:
	if amount <= 0:
		return
	cash += amount
	cash_changed.emit(cash, amount)
	changed.emit()


## Removes up to [param amount] (all of it by default). Returns what was taken.
func take_cash(amount: int = -1) -> int:
	var taken := cash if amount < 0 else mini(amount, cash)
	if taken <= 0:
		return 0
	cash -= taken
	cash_changed.emit(cash, -taken)
	changed.emit()
	return taken


func draw_melee() -> void:
	if melee == null or melee_drawn:
		return
	melee_drawn = true
	_sync_combat()
	changed.emit()


func holster_melee() -> void:
	if melee == null or not melee_drawn:
		return
	melee_drawn = false
	_sync_combat()
	changed.emit()


func toggle_melee() -> void:
	if melee_drawn:
		holster_melee()
	else:
		draw_melee()


## Drops the melee weapon (drawn or holstered) as a world pickup and returns
## the pickup (null if the weapon has none, e.g. fists).
func drop_melee() -> Node3D:
	if melee == null:
		return null
	var dropped := melee
	remove_item(dropped)
	if dropped.pickup_scene == null or not is_inside_tree():
		return null
	var pickup := dropped.pickup_scene.instantiate() as Node3D
	if &"weapon" in pickup:
		pickup.set(&"weapon", dropped)
	var spawn := drop_origin.global_transform.orthonormalized()
	get_tree().current_scene.add_child(pickup)
	pickup.global_transform = spawn
	pickup.reset_physics_interpolation()
	if pickup is RigidBody3D:
		var velocity := Vector3.ZERO
		if body is CharacterBody3D:
			velocity = (body as CharacterBody3D).velocity
		(pickup as RigidBody3D).linear_velocity = velocity + model.global_basis * drop_velocity
	return pickup


## Removes the melee weapon without dropping it (fight restart).
func clear_melee() -> void:
	if melee != null:
		remove_item(melee)


## Empties every slot and the wallet.
func clear() -> void:
	melee = null
	melee_drawn = false
	firearm = null
	pockets.fill(null)
	var had := cash
	cash = 0
	_sync_combat()
	if had != 0:
		cash_changed.emit(0, -had)
	changed.emit()


## Adds a roll of [param table] (cash and items that fit).
func roll_loot(table: LootTable, rng: RandomNumberGenerator = null) -> void:
	if table == null:
		return
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	add_cash(table.roll_cash(rng))
	for item in table.roll_items(rng):
		add_item(item)


## Moves cash and every item that fits into [param other] (looting).
func transfer_to(other: InventoryComponent) -> Transfer:
	var result := Transfer.new()
	if other == null or other == self:
		return result
	var taken := take_cash()
	other.add_cash(taken)
	result.cash = taken
	for item in get_items():
		if other.add_item(item):
			remove_item(item)
			result.items.append(item)
		else:
			result.left_behind.append(item)
	return result


func _sync_combat() -> void:
	if combat != null:
		combat.set_weapon(get_held_weapon())


func _on_down(_victim: Node3D, _by: Node3D) -> void:
	if drop_on_down:
		drop_melee()
