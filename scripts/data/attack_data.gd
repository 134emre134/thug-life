class_name AttackData
extends Resource
## One attack (a single punch, swing, stab, stomp or shot). Instances live in
## res://data/attacks/*.tres and are referenced by a [WeaponData] (stomps by
## [member MeleeCombat.stomp_attack], shots by [member FirearmData.fire_attack]).
## A shot only uses the damage, reaction, guard, knockback and feel fields.
##
## Timeline: windup -> active -> recovery. Hits only land during the active
## phase. The next attack of a combo can start during recovery.
##
## Timing comes from the clip (M4a.2): its "hit" and "hit_end" animation markers
## are the contact window, and the clip ends at its "end" marker (or its end).
## The clip plays at [member speed], so windup = hit / speed and so on; it never
## plays faster than authored. The fallback times below are only used when the
## clip has no markers (and a warning is printed).

## How hard the victim reacts to a hit that is not blocked.
enum Reaction { NONE, FLINCH, STAGGER, KNOCKDOWN }
## What the damage does once health runs out (GDD §7 Lethality). M2 only
## knocks out; M3a gives blade and firearm damage their lethal behaviour.
enum DamageType { BLUNT, BLADE, FIREARM }

## Slowest and fastest allowed playback speed (never faster than the clip).
const MIN_SPEED := 0.25
const MAX_SPEED := 1.0

@export var id: StringName

@export_group("Animation")
## Clip name in the combat animation layer (an input of the AnimationTree's
## combat_clip node, see [PlayerAnimator]). Its markers define the timing.
@export var clip: StringName
## Playback speed of the clip (1 = authored speed). Lower = slower, heavier
## attack: every phase stretches with it.
@export_range(0.25, 1.0, 0.01) var speed: float = 1.0

@export_group("Fallback timing (s)")
## Only used when [member clip] has no "hit" / "hit_end" markers.
@export var windup: float = 0.15
@export var active: float = 0.1
@export var recovery: float = 0.3

@export_group("Damage")
@export var damage: float = 10.0
## Damage on a knocked-out body (downed damage, before the damage type's
## scale). Negative = same as [member damage].
@export var downed_damage: float = -1.0
@export var damage_type: DamageType = DamageType.BLUNT
@export var reaction: Reaction = Reaction.FLINCH
## Breaks a guard instead of being blocked by it.
@export var breaks_guard: bool = false
## False: a guard doesn't stop it at all (shots, M4b).
@export var can_be_blocked: bool = true
## Knockback impulse on the victim (N·s) along the hit direction. 80 kg: 160 -> 2 m/s.
@export var knockback: float = 120.0
## Extra upward share of the knockback (0 = flat).
@export_range(0.0, 1.0) var knockback_lift: float = 0.0

@export_group("Reach (m)")
## Distance from the attacker's origin to the hitbox centre, forward.
@export var reach: float = 0.8
## Radius of the hitbox sphere.
@export var hit_radius: float = 0.4
## Height of the hitbox centre above the attacker's origin.
@export var hit_height: float = 1.3

@export_group("Lunge (m)")
## Max distance the attacker lunges toward a soft target during windup + active.
@export var lunge_distance: float = 1.5
## Step forward when there is no target.
@export var step_distance: float = 0.25

@export_group("Feel")
## Hit stop duration (real seconds).
@export var hit_stop: float = 0.05
## Camera shake trauma added on hit (0..1).
@export_range(0.0, 1.0) var camera_shake: float = 0.2
## Optional impact sound; otherwise a placeholder is picked by severity.
@export var hit_sound: AudioStream


## Playback speed, clamped so an attack never plays faster than its clip.
func get_speed() -> float:
	return clampf(speed, MIN_SPEED, MAX_SPEED)


## Damage dealt to a knocked-out body.
func get_downed_damage() -> float:
	return downed_damage if downed_damage >= 0.0 else damage


## True for hits that should read as "heavy" (sound, flash).
func is_heavy() -> bool:
	return breaks_guard or reaction >= Reaction.STAGGER
