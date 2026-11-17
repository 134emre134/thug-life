class_name WeaponData
extends ItemData
## A weapon (fists count as one). Instances live in res://data/items/.
## Melee weapons go in the melee slot; [FirearmData] (M4b) extends this for
## the firearm slot.
##
## [member pickup_scene] must not reference this resource itself (that would be
## a cyclic load); whoever spawns the pickup assigns the weapon to it.

## Light attack combo, in order (up to 3 hits).
@export var light_combo: Array[AttackData] = []
## Heavy attack (hold attack); usually breaks guard.
@export var heavy_attack: AttackData
## Upper-body pose while guarding (an input of the AnimationTree's guard_clip node).
@export var guard_clip: StringName = &"guard"
## Upper-body pose while holding the weapon outside attacks (e.g. bat over the
## shoulder). Empty = the locomotion clips move the arms freely.
@export var ready_clip: StringName = &""
## Visual attached to the hand socket while held (origin = grip, extends along -Y).
@export var held_scene: PackedScene
## World pickup spawned when dropped. Empty = cannot be dropped (fists).
@export var pickup_scene: PackedScene
## Light hit reactions while this weapon is in hand (e.g. a rifle flinch).
## Empty = the character's own [member MeleeCombat.flinch_clips].
@export var flinch_clips: Array[StringName] = []


func get_slot() -> ItemData.Slot:
	return ItemData.Slot.MELEE
