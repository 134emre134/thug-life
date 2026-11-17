class_name AttackData
extends Resource
## One melee attack (a single punch or swing). Instances live in
## res://data/attacks/*.tres and are referenced by a [WeaponData].
##
## Timeline: windup -> active -> recovery. Hits only land during the active
## phase. The next attack of a combo can start during recovery.

## How hard the victim reacts to a hit that is not blocked.
enum Reaction { NONE, FLINCH, STAGGER, KNOCKDOWN }
## What the damage does once health runs out (GDD §7 Lethality). M2 only
## knocks out; M3a gives blade and firearm damage their lethal behaviour.
enum DamageType { BLUNT, BLADE, FIREARM }

@export var id: StringName

@export_group("Animation")
## Clip name in the combat animation layer (an input of the AnimationTree's
## combat_clip node, see [PlayerAnimator]).
@export var clip: StringName
## Time in the clip (seconds, at authored speed) where the hit lands. The clip
## is time-stretched so this moment lines up with the start of the active
## phase, whatever the windup length. 0 = stretch the clip uniformly.
@export var clip_hit_time: float = 0.0

@export_group("Timing (s)")
@export var windup: float = 0.15
@export var active: float = 0.1
@export var recovery: float = 0.3

@export_group("Damage")
@export var damage: float = 10.0
@export var damage_type: DamageType = DamageType.BLUNT
@export var reaction: Reaction = Reaction.FLINCH
## Breaks a guard instead of being blocked by it.
@export var breaks_guard: bool = false
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


func get_total_time() -> float:
	return windup + active + recovery


## True for hits that should read as "heavy" (sound, flash).
func is_heavy() -> bool:
	return breaks_guard or reaction >= Reaction.STAGGER
