class_name FirearmData
extends WeaponData
## A firearm (GDD §7, M4b). Goes in the firearm slot of the
## [InventoryComponent] and is fired by [RangedCombat] along the aim ray
## (the crosshair for the player, the AI's aim point for NPCs). Instances live
## in res://data/items/.
##
## The melee fields inherited from [WeaponData] stay empty: with a firearm in
## hand the attack button fires instead of punching. [member WeaponData.ready_clip]
## is the upper-body pose while it is held, [member WeaponData.held_scene] the
## gray-box model (its "Muzzle" node is where shots and flashes start).
##
## Ammo: the magazine is loaded from [member ammo_item]s in the pockets; one
## item is one full magazine. The rounds in the magazine are kept by the
## carrying inventory (and by a dropped pickup), not here: this resource is
## shared.

@export_group("Firing")
## Damage, damage type (firearm = lethal), reaction and knockback of one shot.
@export var fire_attack: AttackData
## Minimum seconds between two shots (semi-automatic: one shot per press).
@export var fire_interval: float = 0.32
## Shots don't reach further than this (metres).
@export var max_range: float = 60.0
## Spread cone (half angle, degrees) while aiming and standing still.
@export var spread_degrees: float = 0.25
## Added at full running speed while aiming (scaled by speed).
@export var moving_spread_degrees: float = 2.0
## Added while the weapon is not fully raised (hip fire).
@export var unaimed_spread_degrees: float = 2.5
## Seconds from starting to aim until the weapon is raised (hip fire waits for it).
@export var aim_raise_time: float = 0.15
## The aim clips hold the weapon this far off the character's forward
## (degrees, positive = left): the body turns by the opposite so the barrel
## points where the shot goes. Measured on rifle_aim_idle (hand to hand).
@export var aim_yaw_offset_degrees: float = 28.0
## Push given to physics props that are hit (N·s).
@export var prop_impulse: float = 6.0

@export_group("Ammo")
@export var magazine_size: int = 8
## Pocket item that reloads one full magazine (the leftover rounds of the
## magazine taken out are lost).
@export var ammo_item: ItemData

@export_group("Animation")
## Upper-body clip played for every shot (recoil).
@export var fire_clip: StringName = &"rifle_fire"
## Upper-body reload clip. The magazine is full at its "reload" marker, the
## reload ends at its "end" marker (or its end).
@export var reload_clip: StringName = &"rifle_reload"
## Playback speed of [member reload_clip] (1 = authored).
@export_range(0.25, 1.0, 0.01) var reload_speed: float = 1.0
## Fallback reload length (s) when the clip is missing.
@export var fallback_reload_time: float = 2.5

@export_group("Feel")
## Camera kick per shot (degrees of pitch, the player only).
@export var recoil_degrees: float = 1.0
## Camera shake trauma per shot (the player only).
@export_range(0.0, 1.0) var fire_camera_shake: float = 0.12
## Optional shot sound; otherwise a placeholder is synthesized.
@export var shot_sound: AudioStream


func get_slot() -> ItemData.Slot:
	return ItemData.Slot.FIREARM
