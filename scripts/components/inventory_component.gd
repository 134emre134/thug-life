class_name InventoryComponent
extends Node
## What a character carries (GDD §12), for the player and NPCs alike:
## one melee slot, one firearm slot (M4b), a few pocket slots and a wallet
## (cash is a number, not an item).
##
## The inventory owns weapons. At most one weapon is drawn (in hand: the
## [MeleeCombat] holds it, [RangedCombat] fires a drawn firearm); the other
## is holstered (carried). Nothing drawn = fists. Dropping spawns the weapon's
## world pickup. NPCs fill their inventory from a [LootTable] on spawn;
## looting moves the contents to another inventory with [method transfer_to].
##
## Weapon switching (M4b.2): [method draw] picks the hand (unarmed, melee or
## firearm), [method get_next_hand] steps through the carried ones.
##
## Ammo (M4b.1): the firearm's magazine holds [member firearm_rounds]; ammo
## items are ordinary pocket items. [RangedCombat] uses rounds and reloads.

## Any slot, the drawn weapon, the magazine or the wallet changed.
signal changed
signal cash_changed(cash: int, delta: int)

## What is in hand.
enum Hand { NONE, MELEE, FIREARM }


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
## Firearm slot (active since M4b).
@export var firearm_slot_active: bool = true

@export_group("Start")
@export var start_cash: int = 0
@export var start_melee: WeaponData
## Carried from the start, drawn unless [member start_melee] is set too.
@export var start_firearm: FirearmData
@export var start_items: Array[ItemData] = []
## Rolled into the inventory on spawn (NPC types).
@export var loot_table: LootTable
@export var roll_loot_on_ready: bool = true

@export_group("Drop")
## Knockout and death drop the carried weapons physically (GDD §7 Weapons).
@export var drop_on_down: bool = true
## Velocity given to a dropped weapon (m/s, local to the model: -Z forward).
@export var drop_velocity: Vector3 = Vector3(0.0, 1.5, -1.0)

var cash: int = 0
var melee: WeaponData = null
## The melee weapon is in hand (false = holstered).
var melee_drawn: bool = false
var firearm: FirearmData = null
## The firearm is in hand (false = holstered). Never together with [member melee_drawn].
var firearm_drawn: bool = false
## Rounds in the firearm's magazine.
var firearm_rounds: int = 0
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
	if start_firearm != null:
		firearm = start_firearm
		firearm_rounds = start_firearm.magazine_size
		firearm_drawn = start_melee == null
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
	if firearm_drawn:
		return firearm
	return melee if melee_drawn else null


func get_hand() -> Hand:
	if firearm_drawn:
		return Hand.FIREARM
	return Hand.MELEE if melee_drawn else Hand.NONE


## True if [param hand] can be drawn (unarmed always can).
func has_hand(hand: Hand) -> bool:
	match hand:
		Hand.MELEE:
			return melee != null
		Hand.FIREARM:
			return firearm != null
	return true


## Puts [param hand] in hand and holsters the rest. Returns false if that
## slot is empty.
func draw(hand: Hand) -> bool:
	if not has_hand(hand):
		return false
	if hand == get_hand():
		return true
	melee_drawn = hand == Hand.MELEE
	firearm_drawn = hand == Hand.FIREARM
	_sync_combat()
	changed.emit()
	return true


## Next carried hand in the order unarmed -> melee -> firearm ([param step] = 1)
## or backwards (-1).
func get_next_hand(step: int = 1) -> Hand:
	var hand := get_hand()
	for i in Hand.size():
		hand = posmod(hand + step, Hand.size()) as Hand
		if has_hand(hand):
			return hand
	return get_hand()


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
			firearm_drawn = false
			_sync_combat()
		ItemData.Slot.FIREARM:
			if not firearm_slot_active or firearm != null:
				return false
			firearm = item as FirearmData
			firearm_rounds = firearm.magazine_size
			# A new weapon ends up in hand, like a melee pickup.
			melee_drawn = false
			firearm_drawn = true
			_sync_combat()
		_:
			var index := pockets.find(null)
			if index < 0:
				return false
			pockets[index] = item
	changed.emit()
	return true


## Takes a weapon from the world: the weapon in the same slot is dropped
## first, the new one ends up in hand. A firearm comes with [param rounds] in
## its magazine (-1 = full).
func pick_up_weapon(weapon: WeaponData, rounds: int = -1) -> bool:
	if weapon == null:
		return false
	var slot := Hand.FIREARM if weapon is FirearmData else Hand.MELEE
	if slot == Hand.FIREARM and not firearm_slot_active:
		return false
	if (slot == Hand.MELEE and melee != null) or (slot == Hand.FIREARM and firearm != null):
		drop_weapon(slot)
	if not add_item(weapon):
		return false
	if slot == Hand.FIREARM and rounds >= 0:
		set_firearm_rounds(rounds)
	return true


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
		firearm_drawn = false
		firearm_rounds = 0
		_sync_combat()
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


## Sets the rounds in the firearm's magazine (clamped to its size).
func set_firearm_rounds(rounds: int) -> void:
	if firearm == null:
		return
	firearm_rounds = clampi(rounds, 0, firearm.magazine_size)
	changed.emit()


## Drops the weapon of [param slot] (melee or firearm, drawn or holstered) as
## a world pickup and returns the pickup (null if there is none). A dropped
## firearm keeps the rounds in its magazine.
func drop_weapon(slot: Hand) -> Node3D:
	var dropped: WeaponData = firearm if slot == Hand.FIREARM else melee
	if slot == Hand.NONE or dropped == null:
		return null
	var rounds := firearm_rounds if slot == Hand.FIREARM else -1
	remove_item(dropped)
	if dropped.pickup_scene == null or not is_inside_tree():
		return null
	var pickup := dropped.pickup_scene.instantiate() as Node3D
	if &"weapon" in pickup:
		pickup.set(&"weapon", dropped)
	if &"rounds" in pickup:
		pickup.set(&"rounds", rounds)
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


## Removes both weapons without dropping them (fight restart).
func clear_weapons() -> void:
	if melee != null:
		remove_item(melee)
	if firearm != null:
		remove_item(firearm)


## Empties every slot and the wallet.
func clear() -> void:
	melee = null
	melee_drawn = false
	firearm = null
	firearm_drawn = false
	firearm_rounds = 0
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
		drop_weapon(Hand.MELEE)
		drop_weapon(Hand.FIREARM)
