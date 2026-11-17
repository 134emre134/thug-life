class_name MeleeCombat
extends Node
## Melee combat for any character (player and NPCs), driven each physics tick
## through [method physics_update] with a [MeleeCombat.Intent], like
## [PlayerMovement]. It doesn't read input.
##
## Handles attack phases (windup / active / recovery), the light combo,
## input buffering, cancel rules (dodge cancels recovery), lunges toward the
## soft target, guard, dodge, hit reactions and knockouts. It changes movement
## only by editing the movement intent in [method apply_to_movement], and
## animation only through the clip_* signals, which the character root passes
## to its animator.
##
## Combat knows nothing about crime: it reports [signal hit_landed] here and
## knockouts and deaths on the [HealthComponent]; the M3b CrimeManager listens
## to those.
##
## Combat doesn't own weapons: it fights with whatever [method set_weapon]
## put in hand. The [InventoryComponent] owns, holsters and drops them.

signal state_changed(state: State)
signal phase_changed(phase: Phase)
signal attack_started(attack: AttackData)
## This character landed a hit (not blocked, not dodged).
signal hit_landed(attacker: Node3D, victim: Node3D, attack: AttackData)
## This character's attack was blocked.
signal attack_blocked(attacker: Node3D, victim: Node3D, attack: AttackData)
## This character was hit (any result except IGNORED).
signal hit_taken(attacker: Node3D, attack: AttackData, result: HurtboxComponent.HitResult)
## Play [param clip] on the combat animation layer, stretched to [param duration].
## If [param hit_time] > 0, clip time [param hit_time] lines up with [param hit_at].
## [param hold] keeps the last frame until [signal clip_stopped].
signal clip_requested(clip: StringName, duration: float, hit_time: float, hit_at: float, hold: bool)
signal clip_stopped
signal weapon_changed(weapon: WeaponData)

enum State { IDLE, ATTACK, GUARD, DODGE, REACTION, KNOCKDOWN, KNOCKED_OUT, DEAD }
enum Phase { NONE, WINDUP, ACTIVE, RECOVERY }
enum Action { NONE, LIGHT, HEAVY, DODGE }


## What the controller wants this tick.
class Intent:
	## Light attack pressed this tick.
	var light := false
	## Heavy attack pressed this tick.
	var heavy := false
	## Guard held.
	var guard := false
	## Dodge pressed this tick.
	var dodge := false
	## World direction of a dodge (horizontal). Zero = dodge backwards.
	var dodge_direction := Vector3.ZERO
	## Where the controller looks (camera forward for the player). Used for soft
	## targeting, attacks without a target and guard facing.
	var look_direction := Vector3.FORWARD
	## Explicit target (NPCs). Skips soft targeting when set.
	var target: MeleeCombat = null


@export var body: CharacterBody3D
## Node that turns with the character (local -Z = forward).
@export var model: Node3D
@export var health: HealthComponent
@export var hitbox: HitboxComponent
@export var hurtbox: HurtboxComponent
## Optional; without it attacks only use [member Intent.target].
@export var targeting: SoftTargeting
## Hand socket for held weapon visuals.
@export var weapon_socket: Node3D
## Characters on the same team don't hit or target each other.
@export var team: StringName = &"player"
## Used when no weapon is held.
@export var unarmed: WeaponData

@export_group("Input")
## How long a pressed action waits for its turn (seconds).
@export var input_buffer_time: float = 0.3
## Grace after an attack ends during which the next light attack still
## continues the combo.
@export var combo_reset_time: float = 0.25

@export_group("Attacks")
## Keep turning and steering toward the target during the windup. The player
## does; NPCs commit to a direction so their attacks can be dodged.
@export var track_target_in_windup: bool = true
## The lunge stops this much short of the attack's reach.
@export var lunge_stop_margin: float = 0.1
## Never lunge closer than this to the target's origin.
@export var lunge_min_distance: float = 0.75
## Hit stop scale for blocked hits.
@export_range(0.0, 1.0) var blocked_hit_stop_scale: float = 0.5

@export_group("Guard")
## Hits from within this arc in front are blocked.
@export_range(0.0, 360.0) var guard_arc_degrees: float = 150.0
## After blocking a hit, guard is held and no action is possible for this long.
@export var block_stun: float = 0.15
## Fraction of the attack's knockback that still pushes a blocking character.
@export_range(0.0, 1.0) var block_knockback_scale: float = 0.5
@export var guard_break_time: float = 0.9
## Fraction of the attack's damage taken when the guard is broken.
@export_range(0.0, 1.0) var guard_break_damage_scale: float = 0.5

@export_group("Dodge")
@export var dodge_distance: float = 2.4
@export var dodge_time: float = 0.35
## Hits are ignored for this long from the start of a dodge.
@export var dodge_invulnerable_time: float = 0.25
@export var dodge_cooldown: float = 0.15
@export var dodge_clip: StringName = &"dodge"

@export_group("Reactions")
@export var flinch_time: float = 0.35
@export var stagger_time: float = 0.75
@export var knockdown_fall_time: float = 0.5
@export var knockdown_down_time: float = 1.0
@export var get_up_time: float = 0.9
## No hits land while knocked down or getting up (no juggling a downed enemy).
@export var invulnerable_when_down: bool = true
@export var flinch_clip: StringName = &"flinch"
@export var stagger_clip: StringName = &"stagger"
@export var knockdown_clip: StringName = &"knockdown"
@export var get_up_clip: StringName = &"get_up"

var state: State = State.IDLE
var phase: Phase = Phase.NONE
## Current attack (null outside the ATTACK state).
var attack: AttackData = null
## Increments with every attack started (lets observers notice a new attack).
var attack_serial: int = 0
## Index in the light combo of the current/last light attack (-1 = none).
var combo_index: int = -1
## Held weapon; null = [member unarmed].
var weapon: WeaponData = null
## Current target (soft target or the intent's explicit target).
var current_target: MeleeCombat = null
## Impulse of the last hit taken (used for the knockout ragdoll).
var last_hit_impulse: Vector3 = Vector3.ZERO

var _state_time: float = 0.0
var _phase_time: float = 0.0
var _since_attack_end: float = INF
var _last_was_light: bool = false
var _buffered: Action = Action.NONE
var _buffer_timer: float = 0.0
var _attack_yaw: float = 0.0
var _attack_target: MeleeCombat = null
var _lunge_budget: float = 0.0
var _lunge_velocity: Vector3 = Vector3.ZERO
var _dodge_direction: Vector3 = Vector3.ZERO
var _dodge_cooldown_timer: float = 0.0
var _block_timer: float = 0.0
var _reaction_time: float = 0.0
var _getting_up: bool = false
var _look_yaw: float = 0.0
var _held_visual: Node3D = null


func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody3D
	assert(body != null, "MeleeCombat needs a CharacterBody3D")
	assert(unarmed != null, "MeleeCombat needs an unarmed WeaponData")
	add_to_group(&"combatants")
	if hurtbox != null:
		hurtbox.team = team
		hurtbox.receiver = self
		if hurtbox.health == null:
			hurtbox.health = health
	if health != null:
		health.knocked_out.connect(_on_down)
		health.killed.connect(_on_down)
		health.recovered.connect(_on_recovered)


func physics_update(delta: float, intent: Intent) -> void:
	_tick_timers(delta)
	if is_down():
		return
	if intent.look_direction.length_squared() > 0.0001:
		_look_yaw = atan2(-intent.look_direction.x, -intent.look_direction.z)
	_update_target(intent)

	if intent.dodge:
		_buffer(Action.DODGE)
	elif intent.heavy:
		_buffer(Action.HEAVY)
	elif intent.light:
		_buffer(Action.LIGHT)

	match state:
		State.ATTACK:
			_update_attack(delta, intent)
		State.DODGE:
			if _state_time >= dodge_time:
				_return_to_neutral(intent)
		State.REACTION:
			if _state_time >= _reaction_time:
				_return_to_neutral(intent)
		State.KNOCKDOWN:
			_update_knockdown(intent)

	_try_buffered(intent)

	if state == State.IDLE and intent.guard:
		_set_state(State.GUARD)
	elif state == State.GUARD and not intent.guard and _block_timer <= 0.0:
		_set_state(State.IDLE)


## Edits the movement intent: locks, lunges, dodges and guard strafing.
func apply_to_movement(intent: PlayerMovement.Intent) -> void:
	match state:
		State.IDLE:
			return
		State.GUARD:
			intent.strafe = true
			intent.face_yaw = _look_yaw
			intent.sprint = false
			intent.jump = false
		State.ATTACK:
			_lock_movement(intent, _attack_yaw)
			intent.use_velocity_override = true
			intent.velocity_override = _lunge_velocity
		State.DODGE:
			_lock_movement(intent, _get_model_yaw())
			intent.use_velocity_override = true
			intent.velocity_override = _get_dodge_velocity()
		_:
			_lock_movement(intent, _get_model_yaw())


## Resolves a hit on this character. Called by its [HurtboxComponent].
func receive_hit(
	attacker: Node3D, hit_attack: AttackData, direction: Vector3
) -> HurtboxComponent.HitResult:
	if state == State.DEAD or (health != null and not health.can_take_damage()):
		return HurtboxComponent.HitResult.IGNORED
	if state == State.KNOCKED_OUT or (health != null and health.is_down()):
		return _receive_downed_hit(attacker, hit_attack, direction)
	if is_invulnerable():
		var dodged := state == State.DODGE
		if dodged:
			hit_taken.emit(attacker, hit_attack, HurtboxComponent.HitResult.DODGED)
			return HurtboxComponent.HitResult.DODGED
		return HurtboxComponent.HitResult.IGNORED

	var flat := Vector3(direction.x, 0.0, direction.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else -_get_facing()
	var impulse := (flat + Vector3.UP * hit_attack.knockback_lift) * hit_attack.knockback

	var guarded := state == State.GUARD and _is_facing(attacker.global_position)
	if guarded and not hit_attack.breaks_guard:
		_knockback(impulse * block_knockback_scale)
		_block_timer = block_stun
		hit_taken.emit(attacker, hit_attack, HurtboxComponent.HitResult.BLOCKED)
		return HurtboxComponent.HitResult.BLOCKED

	last_hit_impulse = impulse
	var damage := hit_attack.damage * (guard_break_damage_scale if guarded else 1.0)
	if health != null:
		health.take_damage(damage, attacker, hit_attack)
		if health.is_dead():
			hit_taken.emit(attacker, hit_attack, HurtboxComponent.HitResult.KILLED)
			return HurtboxComponent.HitResult.KILLED
		if health.is_knocked_out():
			hit_taken.emit(attacker, hit_attack, HurtboxComponent.HitResult.KNOCKED_OUT)
			return HurtboxComponent.HitResult.KNOCKED_OUT
	_knockback(impulse)

	if guarded:
		_enter_reaction(guard_break_time, stagger_clip)
		hit_taken.emit(attacker, hit_attack, HurtboxComponent.HitResult.GUARD_BROKEN)
		return HurtboxComponent.HitResult.GUARD_BROKEN

	if state != State.KNOCKDOWN:
		match hit_attack.reaction:
			AttackData.Reaction.FLINCH:
				_enter_reaction(flinch_time, flinch_clip)
			AttackData.Reaction.STAGGER:
				_enter_reaction(stagger_time, stagger_clip)
			AttackData.Reaction.KNOCKDOWN:
				_enter_knockdown()
	hit_taken.emit(attacker, hit_attack, HurtboxComponent.HitResult.HIT)
	return HurtboxComponent.HitResult.HIT


## Puts [param new_weapon] in hand (null = [member unarmed]). Whatever was
## held before is simply let go; the [InventoryComponent] decides where it goes.
func set_weapon(new_weapon: WeaponData) -> void:
	if new_weapon == weapon:
		return
	weapon = new_weapon
	# A new move set starts its combo from the first hit.
	combo_index = -1
	_last_was_light = false
	_update_held_visual()
	weapon_changed.emit(weapon)


## Back to a fresh, standing state (fight restart).
func reset() -> void:
	_interrupt_attack()
	_buffered = Action.NONE
	_block_timer = 0.0
	_getting_up = false
	_since_attack_end = INF
	combo_index = -1
	last_hit_impulse = Vector3.ZERO
	current_target = null
	_set_state(State.IDLE)
	clip_stopped.emit()


func get_weapon() -> WeaponData:
	return weapon if weapon != null else unarmed


func is_guarding() -> bool:
	return state == State.GUARD


func is_knocked_out() -> bool:
	return state == State.KNOCKED_OUT


func is_dead() -> bool:
	return state == State.DEAD


## Knocked out or dead: out of the fight.
func is_down() -> bool:
	return state == State.KNOCKED_OUT or state == State.DEAD


func is_busy_reacting() -> bool:
	return state == State.REACTION or state == State.KNOCKDOWN


## Upper-body pose for the animator: the guard pose while guarding, else the
## weapon's ready pose (empty for fists). Attacks and reactions play on the
## full-body combat layer on top.
func get_upper_body_clip() -> StringName:
	return get_weapon().guard_clip if state == State.GUARD else get_weapon().ready_clip


func is_invulnerable() -> bool:
	if state == State.DODGE:
		return _state_time < dodge_invulnerable_time
	if state == State.KNOCKDOWN:
		return invulnerable_when_down
	return false


## Can be chosen as a target by others.
func is_targetable() -> bool:
	return not is_down() and is_inside_tree() and body.is_inside_tree()


func get_state_name() -> String:
	return State.keys()[state]


func get_phase_name() -> String:
	return Phase.keys()[phase]


func _tick_timers(delta: float) -> void:
	_state_time += delta
	_phase_time += delta
	_since_attack_end += delta
	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer - delta, 0.0)
	_block_timer = maxf(_block_timer - delta, 0.0)
	if _buffered != Action.NONE:
		_buffer_timer -= delta
		if _buffer_timer <= 0.0:
			_buffered = Action.NONE


func _update_target(intent: Intent) -> void:
	if intent.target != null:
		current_target = intent.target if intent.target.is_targetable() else null
	elif targeting != null:
		current_target = targeting.update(body.global_position, intent.look_direction, self)
	else:
		current_target = null


func _buffer(action: Action) -> void:
	_buffered = action
	_buffer_timer = input_buffer_time


func _try_buffered(intent: Intent) -> void:
	match _buffered:
		Action.DODGE:
			if _can_dodge():
				_buffered = Action.NONE
				_start_dodge(intent)
		Action.LIGHT:
			if _can_attack():
				var next := _next_light_attack()
				_buffered = Action.NONE
				if next != null:
					_start_attack(next, true)
		Action.HEAVY:
			if _can_attack():
				var heavy := get_weapon().heavy_attack
				_buffered = Action.NONE
				if heavy != null:
					_start_attack(heavy, false)


func _can_act() -> bool:
	if _block_timer > 0.0 or not body.is_on_floor():
		return false
	match state:
		State.IDLE, State.GUARD:
			return true
		State.ATTACK:
			return phase == Phase.RECOVERY
	return false


func _can_attack() -> bool:
	return _can_act()


func _can_dodge() -> bool:
	return _can_act() and _dodge_cooldown_timer <= 0.0


func _next_light_attack() -> AttackData:
	var combo := get_weapon().light_combo
	if combo.is_empty():
		return null
	var chaining := (
		_last_was_light and (state == State.ATTACK or _since_attack_end <= combo_reset_time)
	)
	var index := combo_index + 1 if chaining else 0
	if index >= combo.size():
		index = 0
	combo_index = index
	return combo[index]


func _start_attack(new_attack: AttackData, is_light: bool) -> void:
	_interrupt_attack()
	attack = new_attack
	attack_serial += 1
	_last_was_light = is_light
	if not is_light:
		combo_index = -1
	_set_state(State.ATTACK)
	_set_phase(Phase.WINDUP)
	_attack_target = current_target

	if _attack_target != null:
		var to_target := _flat_to(_attack_target.body.global_position)
		_attack_yaw = atan2(-to_target.x, -to_target.z) if to_target.length() > 0.01 else _look_yaw
		_lunge_budget = attack.lunge_distance
		if not track_target_in_windup:
			# Commit: fixed direction and distance from here on.
			_lunge_budget = _lunge_needed(_attack_target, _lunge_budget)
			_attack_target = null
	else:
		_attack_yaw = _look_yaw
		_lunge_budget = attack.step_distance
	_lunge_velocity = Vector3.ZERO

	if hitbox != null:
		hitbox.configure(attack)
	clip_requested.emit(
		attack.clip, attack.get_total_time(), attack.clip_hit_time, attack.windup, false
	)
	attack_started.emit(attack)


func _update_attack(delta: float, intent: Intent) -> void:
	match phase:
		Phase.WINDUP:
			if _phase_time >= attack.windup:
				_set_phase(Phase.ACTIVE)
				if hitbox != null:
					hitbox.begin()
				_process_hits()
		Phase.ACTIVE:
			_process_hits()
			if _phase_time >= attack.active:
				if hitbox != null:
					hitbox.end()
				_set_phase(Phase.RECOVERY)
		Phase.RECOVERY:
			if _phase_time >= attack.recovery:
				_finish_attack(intent)
				return
	_update_lunge(delta)


func _update_lunge(delta: float) -> void:
	if state != State.ATTACK or phase == Phase.RECOVERY:
		_lunge_velocity = Vector3.ZERO
		return
	var time_left := attack.active - _phase_time
	if phase == Phase.WINDUP:
		time_left += attack.windup
	time_left = maxf(time_left, delta)

	var target := _attack_target
	if target != null and not target.is_targetable():
		target = null
		_attack_target = null
	var needed := _lunge_budget
	if target != null:
		if phase == Phase.WINDUP:
			var to_target := _flat_to(target.body.global_position)
			if to_target.length() > 0.01:
				_attack_yaw = atan2(-to_target.x, -to_target.z)
		needed = _lunge_needed(target, _lunge_budget)

	var speed := needed / time_left
	_lunge_budget = maxf(_lunge_budget - speed * delta, 0.0)
	_lunge_velocity = Basis(Vector3.UP, _attack_yaw) * Vector3.FORWARD * speed


## Distance to move toward [param target] so it ends up at the attack's reach.
func _lunge_needed(target: MeleeCombat, budget: float) -> float:
	var distance := _flat_to(target.body.global_position).length()
	var stop := maxf(attack.reach - lunge_stop_margin, lunge_min_distance)
	return clampf(distance - stop, 0.0, budget)


func _process_hits() -> void:
	if hitbox == null:
		return
	for hurtbox_hit in hitbox.collect_hits(body, team):
		var victim := hurtbox_hit.body
		var direction := _flat_to(victim.global_position)
		if direction.length_squared() < 0.0001:
			direction = _get_facing()
		var result := hurtbox_hit.receive_hit(body, attack, direction.normalized())
		if result == HurtboxComponent.HitResult.BLOCKED:
			HitStop.apply(get_tree(), attack.hit_stop * blocked_hit_stop_scale)
			attack_blocked.emit(body, victim, attack)
		elif result >= HurtboxComponent.HitResult.GUARD_BROKEN:
			HitStop.apply(get_tree(), attack.hit_stop)
			hit_landed.emit(body, victim, attack)
		# The attacker may have been knocked out by a reaction chain meanwhile.
		if state != State.ATTACK:
			return


func _finish_attack(intent: Intent) -> void:
	_interrupt_attack()
	_since_attack_end = 0.0
	_set_state(State.GUARD if intent.guard else State.IDLE)
	clip_stopped.emit()


func _interrupt_attack() -> void:
	if hitbox != null:
		hitbox.end()
	attack = null
	_attack_target = null
	_lunge_velocity = Vector3.ZERO
	_set_phase(Phase.NONE)


func _start_dodge(intent: Intent) -> void:
	_interrupt_attack()
	var direction := Vector3(intent.dodge_direction.x, 0.0, intent.dodge_direction.z)
	_dodge_direction = (
		direction.normalized() if direction.length_squared() > 0.01 else -_get_facing()
	)
	_dodge_cooldown_timer = dodge_cooldown + dodge_time
	_set_state(State.DODGE)
	clip_requested.emit(dodge_clip, dodge_time, 0.0, 0.0, false)


## Fast start, slowing down; integrates to exactly [member dodge_distance].
func _get_dodge_velocity() -> Vector3:
	if dodge_time <= 0.0:
		return Vector3.ZERO
	var t := clampf(_state_time / dodge_time, 0.0, 1.0)
	return _dodge_direction * (2.0 * dodge_distance / dodge_time) * (1.0 - t)


func _enter_reaction(duration: float, clip: StringName) -> void:
	_interrupt_attack()
	_buffered = Action.NONE
	_reaction_time = duration
	_set_state(State.REACTION, true)
	clip_requested.emit(clip, duration, 0.0, 0.0, false)


func _enter_knockdown() -> void:
	_interrupt_attack()
	_buffered = Action.NONE
	_getting_up = false
	_set_state(State.KNOCKDOWN, true)
	clip_requested.emit(knockdown_clip, knockdown_fall_time, 0.0, 0.0, true)


func _update_knockdown(intent: Intent) -> void:
	var down_end := knockdown_fall_time + knockdown_down_time
	if not _getting_up and _state_time >= down_end:
		_getting_up = true
		clip_requested.emit(get_up_clip, get_up_time, 0.0, 0.0, false)
	if _state_time >= down_end + get_up_time:
		_getting_up = false
		_return_to_neutral(intent)


func _return_to_neutral(intent: Intent) -> void:
	_set_state(State.GUARD if intent.guard else State.IDLE)
	clip_stopped.emit()


## Hit on a knocked-out body: downed damage, a shove of the body, no reaction.
func _receive_downed_hit(
	attacker: Node3D, hit_attack: AttackData, direction: Vector3
) -> HurtboxComponent.HitResult:
	if health == null:
		return HurtboxComponent.HitResult.IGNORED
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	health.take_damage(hit_attack.damage, attacker, hit_attack)
	_knockback((flat + Vector3.UP * hit_attack.knockback_lift) * hit_attack.knockback)
	var result := HurtboxComponent.HitResult.DOWNED_HIT
	if health.is_dead():
		result = HurtboxComponent.HitResult.KILLED
	hit_taken.emit(attacker, hit_attack, result)
	return result


## Knocked out or killed (both can arrive, knockout first).
func _on_down(_victim: Node3D, _by: Node3D) -> void:
	_interrupt_attack()
	_buffered = Action.NONE
	_getting_up = false
	_set_state(State.DEAD if health.is_dead() else State.KNOCKED_OUT)
	clip_stopped.emit()


## Recovered from a knockout: play the get-up part of a knockdown.
func _on_recovered(_victim: Node3D) -> void:
	_set_state(State.KNOCKDOWN, true)
	_state_time = knockdown_fall_time + knockdown_down_time
	_getting_up = true
	clip_requested.emit(get_up_clip, get_up_time, 0.0, 0.0, false)


func _set_state(new_state: State, restart: bool = false) -> void:
	if new_state == state and not restart:
		return
	state = new_state
	_state_time = 0.0
	state_changed.emit(state)


func _set_phase(new_phase: Phase) -> void:
	if new_phase == phase:
		return
	phase = new_phase
	_phase_time = 0.0
	phase_changed.emit(phase)


func _lock_movement(intent: PlayerMovement.Intent, yaw: float) -> void:
	intent.move_direction = Vector3.ZERO
	intent.jump = false
	intent.sprint = false
	intent.strafe = true
	intent.face_yaw = yaw


func _knockback(impulse: Vector3) -> void:
	if body.has_method(&"apply_knockback"):
		body.call(&"apply_knockback", impulse)


func _is_facing(point: Vector3) -> bool:
	var to_point := _flat_to(point)
	if to_point.length_squared() < 0.0001:
		return true
	return _get_facing().dot(to_point.normalized()) >= cos(deg_to_rad(guard_arc_degrees * 0.5))


func _get_facing() -> Vector3:
	var node := model if model != null else body
	var forward := -node.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD


func _get_model_yaw() -> float:
	var forward := _get_facing()
	return atan2(-forward.x, -forward.z)


func _flat_to(point: Vector3) -> Vector3:
	var offset := point - body.global_position
	offset.y = 0.0
	return offset


func _update_held_visual() -> void:
	if _held_visual != null:
		if _held_visual.get_parent() != null:
			_held_visual.get_parent().remove_child(_held_visual)
		_held_visual.queue_free()
		_held_visual = null
	var held := get_weapon().held_scene
	if held != null and weapon_socket != null:
		_held_visual = held.instantiate() as Node3D
		weapon_socket.add_child(_held_visual)
