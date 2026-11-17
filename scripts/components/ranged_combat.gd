class_name RangedCombat
extends Node
## Firearm combat for any character (M4b), driven each physics tick through
## [method physics_update] with a [RangedCombat.Intent], like [MeleeCombat].
## It doesn't read input.
##
## Fires the [FirearmData] the character holds ([member MeleeCombat.weapon],
## put in hand by the [InventoryComponent]) at the intent's aim point: the
## crosshair point of [PlayerAim] for the player, the AI's aim point for NPCs.
## A shot is a ray from the chest (the same origin [PlayerAim] checks the line
## of fire from) toward that point, inside the weapon's spread cone. The first
## hurtbox of another team or piece of world geometry on the way takes it;
## same-team hurtboxes are passed through.
##
## Hits go through the victim's [HurtboxComponent] like melee hits (damage,
## reactions, knockback, firearm lethality). Shots and landed hits are
## reported through the character's [MeleeCombat] ([method MeleeCombat.report_shot]:
## [signal MeleeCombat.shot_fired] and [signal MeleeCombat.hit_landed]), so the
## M5a CrimeManager listens to one component per character; combat knows
## nothing about crime.
##
## Ammo: the magazine lives in the [InventoryComponent]; a reload takes an ammo
## item from the pockets at the reload clip's "reload" marker (an interrupted
## reload before it costs nothing). Firing and reloading only happen while
## melee combat is free (not reacting, dodging or down); a hit cancels a reload.
##
## Animation goes up as [signal clip_requested] (upper-body one-shots: fire,
## reload); the character root passes them to its [PlayerAnimator].

## A shot was fired (hit or miss). Also reported on [MeleeCombat].
signal shot_fired(shooter: Node3D, weapon: FirearmData)
## For effects: the shot went from [param from] (the muzzle) to [param to];
## [param normal] is the surface normal there (zero = hit nothing).
signal shot_traced(from: Vector3, to: Vector3, normal: Vector3, hit_character: bool)
## A shot hit a character (any result except IGNORED).
signal hit_confirmed(victim: Node3D, result: HurtboxComponent.HitResult)
## Fire pressed with an empty magazine.
signal dry_fired
signal reload_started
signal reload_finished
signal aiming_changed(aiming: bool)
## NPC aim telegraph on / off (laser sight and glow, see [FirearmEffects]).
signal telegraph_changed(on: bool)
## Play [param clip] once on the upper body at [param speed].
signal clip_requested(clip: StringName, speed: float)
signal clip_stopped


## What the controller wants this tick.
class Intent:
	## Weapon raised (aim mode). Shots only leave once it is fully raised.
	var aim := false
	## Fire pressed this tick (buffered briefly).
	var fire := false
	## Reload pressed this tick.
	var reload := false
	## World point to shoot at.
	var aim_point := Vector3.ZERO
	## Aimed on purpose (aim button held); false = hip fire, wider spread.
	var precise := true
	## Show the aim telegraph (NPCs, before they shoot).
	var telegraph := false


@export var body: CharacterBody3D
## Holds the weapon, gates firing (reactions, dodges) and reports the shots.
@export var melee: MeleeCombat
## Owns the magazine and the ammo items.
@export var inventory: InventoryComponent
## The character's own hurtbox (never hit by its own shots).
@export var hurtbox: HurtboxComponent
## Optional: crouching lowers the shot origin.
@export var movement: PlayerMovement

@export_group("Shots")
## Height of the shot origin (chest) above the body origin, standing. Same as
## [member PlayerAim.origin_height], so the HUD's line-of-fire marker matches.
@export var origin_height: float = 1.45
@export var crouched_origin_height: float = 0.95
## Layers a shot hits: world, props and hurtboxes (character bodies are
## skipped: the hurtbox is the hit volume).
@export_flags_3d_physics var shot_mask: int = 1 | 4 | 64
## Used instead of the weapon's [member FirearmData.fire_attack] (e.g. weaker
## NPC shots, M4b.5). Empty = the weapon's.
@export var attack_override: AttackData
## A fire press waits this long for the weapon to be ready (raised, cooled down).
@export var fire_buffer_time: float = 0.2
## Moving at this speed (m/s) adds the full moving spread.
@export var reference_run_speed: float = 4.5
## Scale of the attack's hit stop for landed shots.
@export_range(0.0, 1.0) var hit_stop_scale: float = 1.0

@export_group("Ammo")
## Reloads without using ammo items (NPCs). They still reload when empty.
@export var endless_ammo: bool = false
## Firing an empty magazine starts a reload.
@export var auto_reload: bool = true

var is_aiming: bool = false
## Seconds the weapon has been raised.
var aim_time: float = 0.0
var is_reloading: bool = false
## Point the weapon is aimed at (last intent).
var aim_point: Vector3 = Vector3.ZERO
## Shots fired since the start (tests, debug).
var shots_fired: int = 0
## Character (body) hit by the last shot, or null.
var last_hit: Node3D = null
## Where the last shot ended.
var last_shot_end: Vector3 = Vector3.ZERO
## Clip lengths and markers, duck-typed like [member MeleeCombat.clip_source].
var clip_source: Object = null

var _cooldown: float = 0.0
var _fire_buffer: float = 0.0
var _reload_time: float = 0.0
var _reload_total: float = 0.0
var _reload_load_at: float = 0.0
var _reload_loaded: bool = false
var _telegraph: bool = false
var _weapon: FirearmData = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody3D
	_rng.randomize()


func physics_update(delta: float, intent: Intent) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_fire_buffer = maxf(_fire_buffer - delta, 0.0)
	var weapon := get_weapon()
	if weapon != _weapon:
		_weapon = weapon
		cancel_reload()
		aim_time = 0.0
		_fire_buffer = 0.0
	if weapon == null or melee == null or not melee.is_free():
		cancel_reload()
		_set_aiming(false)
		_set_telegraph(false)
		_fire_buffer = 0.0
		return
	aim_point = intent.aim_point
	_set_aiming(intent.aim)
	aim_time = aim_time + delta if is_aiming else 0.0
	_set_telegraph(intent.telegraph and is_aiming)
	if intent.fire:
		_fire_buffer = fire_buffer_time
	if is_reloading:
		_update_reload(delta)
		return
	if intent.reload:
		start_reload()
		return
	if _fire_buffer <= 0.0 or not is_raised() or _cooldown > 0.0:
		return
	_fire_buffer = 0.0
	if inventory.firearm_rounds <= 0:
		dry_fired.emit()
		if auto_reload:
			start_reload()
		return
	_fire(weapon, intent.precise)


## The firearm in hand, or null.
func get_weapon() -> FirearmData:
	return melee.firearm if melee != null else null


func get_attack() -> AttackData:
	if attack_override != null:
		return attack_override
	var weapon := get_weapon()
	return weapon.fire_attack if weapon != null else null


## The weapon is up and shots can leave.
func is_raised() -> bool:
	var weapon := get_weapon()
	return weapon != null and is_aiming and aim_time >= weapon.aim_raise_time


## Ready for a shot now (raised, cooled down, not reloading, rounds loaded).
func can_fire() -> bool:
	return is_raised() and _cooldown <= 0.0 and not is_reloading and inventory.firearm_rounds > 0


## Starts a reload if the magazine isn't full and ammo is carried (or
## [member endless_ammo]). Returns false otherwise.
func start_reload() -> bool:
	var weapon := get_weapon()
	if weapon == null or is_reloading or melee == null or not melee.is_free():
		return false
	if inventory.firearm_rounds >= weapon.magazine_size:
		return false
	if not endless_ammo and get_magazine_count() <= 0:
		return false
	is_reloading = true
	_reload_loaded = false
	_reload_time = 0.0
	var end := _clip_end(weapon.reload_clip)
	var speed := weapon.reload_speed
	if end > 0.0 and speed > 0.0:
		_reload_total = end / speed
		var load := _clip_marker(weapon.reload_clip, &"reload")
		_reload_load_at = (load if load > 0.0 else end * 0.65) / speed
	else:
		_reload_total = weapon.fallback_reload_time
		_reload_load_at = _reload_total * 0.65
	clip_requested.emit(weapon.reload_clip, speed)
	reload_started.emit()
	return true


## Ammo items for the held firearm in the pockets (one per full magazine).
func get_magazine_count() -> int:
	var weapon := get_weapon()
	if weapon == null or weapon.ammo_item == null:
		return 0
	return inventory.pockets.count(weapon.ammo_item)


## Stops a reload; before the magazine went in, no ammo is used.
func cancel_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	clip_stopped.emit()


## Seconds a full reload takes (0 while not reloading).
func get_reload_time() -> float:
	return _reload_total if is_reloading else 0.0


func is_telegraphing() -> bool:
	return _telegraph


## Back to a fresh state (fight restart, revive).
func reset() -> void:
	cancel_reload()
	_set_aiming(false)
	_set_telegraph(false)
	_cooldown = 0.0
	_fire_buffer = 0.0
	aim_time = 0.0


## Where shots start (chest height, lower when crouched).
func get_shot_origin() -> Vector3:
	var crouched := movement != null and movement.is_crouched
	var height := crouched_origin_height if crouched else origin_height
	return body.global_position + Vector3.UP * height


## The muzzle of the held weapon's visual (its "Muzzle" node), for effects.
func get_muzzle_position() -> Vector3:
	var visual := melee.held_visual if melee != null else null
	if visual != null:
		var muzzle := visual.find_child("Muzzle", true, false) as Node3D
		if muzzle != null:
			return muzzle.global_position
	return get_shot_origin()


## Current spread (half angle, degrees) for a shot now.
func get_spread_degrees(precise: bool = true) -> float:
	var weapon := get_weapon()
	if weapon == null:
		return 0.0
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	var spread := weapon.spread_degrees
	if reference_run_speed > 0.0:
		spread += weapon.moving_spread_degrees * clampf(speed / reference_run_speed, 0.0, 1.0)
	if not precise:
		spread += weapon.unaimed_spread_degrees
	return spread


func _fire(weapon: FirearmData, precise: bool) -> void:
	inventory.set_firearm_rounds(inventory.firearm_rounds - 1)
	_cooldown = weapon.fire_interval
	shots_fired += 1
	var attack := get_attack()
	var origin := get_shot_origin()
	var direction := aim_point - origin
	if direction.length_squared() < 0.0001:
		direction = -body.global_basis.z
		if melee.model != null:
			direction = -melee.model.global_basis.z
	direction = _spread(direction.normalized(), get_spread_degrees(precise))
	var hit := _trace(origin, origin + direction * weapon.max_range)
	var end: Vector3 = hit.get(&"position", origin + direction * weapon.max_range)
	var normal: Vector3 = hit.get(&"normal", Vector3.ZERO)
	var victim: HurtboxComponent = hit.get(&"hurtbox", null)
	var landed := false
	last_hit = null
	last_shot_end = end
	if victim != null and attack != null:
		var result := victim.receive_hit(body, attack, direction)
		if result != HurtboxComponent.HitResult.IGNORED:
			last_hit = victim.body
			hit_confirmed.emit(victim.body, result)
		if result >= HurtboxComponent.HitResult.GUARD_BROKEN:
			landed = true
			HitStop.apply(get_tree(), attack.hit_stop * hit_stop_scale)
	else:
		var prop := hit.get(&"collider", null) as RigidBody3D
		if prop != null:
			prop.apply_impulse(direction * weapon.prop_impulse, end - prop.global_position)
	melee.report_shot(weapon, last_hit if landed else null, attack)
	shot_fired.emit(body, weapon)
	shot_traced.emit(get_muzzle_position(), end, normal, victim != null)
	clip_requested.emit(weapon.fire_clip, 1.0)


## First thing a shot from [param from] to [param to] hits: world, a prop or a
## hurtbox of another team. Returns the ray result plus "hurtbox" for
## characters (empty when nothing was hit).
func _trace(from: Vector3, to: Vector3) -> Dictionary:
	var space := body.get_world_3d().direct_space_state
	var exclude: Array[RID] = [body.get_rid()]
	if hurtbox != null:
		exclude.append(hurtbox.get_rid())
	for i in 8:
		var query := PhysicsRayQueryParameters3D.create(from, to, shot_mask, exclude)
		query.collide_with_areas = true
		query.hit_from_inside = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return hit
		var area := hit.collider as Area3D
		if area == null:
			return hit
		var target := area as HurtboxComponent
		var own_team := melee != null and target != null and target.team == melee.team
		if target == null or not target.can_be_hit() or target.body == body or own_team:
			exclude.append(area.get_rid())
			continue
		hit[&"hurtbox"] = target
		return hit
	return {}


## [param direction] turned randomly inside a cone of [param degrees].
func _spread(direction: Vector3, degrees: float) -> Vector3:
	if degrees <= 0.0:
		return direction
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized().rotated(direction, _rng.randf() * TAU)
	var angle := deg_to_rad(degrees) * sqrt(_rng.randf())
	return direction.rotated(side, angle).normalized()


## Uses one ammo item from the pockets (none with [member endless_ammo]) and
## fills the magazine; the old magazine's rounds are lost.
func _load_magazine() -> bool:
	var weapon := get_weapon()
	if weapon == null:
		return false
	if not endless_ammo and not inventory.remove_item(weapon.ammo_item):
		return false
	inventory.set_firearm_rounds(weapon.magazine_size)
	return true


func _update_reload(delta: float) -> void:
	_reload_time += delta
	if not _reload_loaded and _reload_time >= _reload_load_at:
		_reload_loaded = _load_magazine()
		if not _reload_loaded:
			cancel_reload()
			return
	if _reload_time >= _reload_total:
		is_reloading = false
		reload_finished.emit()


func _set_aiming(aiming: bool) -> void:
	if aiming == is_aiming:
		return
	is_aiming = aiming
	aiming_changed.emit(aiming)


func _set_telegraph(on: bool) -> void:
	if on == _telegraph:
		return
	_telegraph = on
	telegraph_changed.emit(on)


func _clip_marker(clip: StringName, marker: StringName) -> float:
	if clip_source == null or not clip_source.has_method(&"get_clip_marker"):
		return -1.0
	return clip_source.call(&"get_clip_marker", clip, marker)


func _clip_end(clip: StringName) -> float:
	if clip_source == null or not clip_source.has_method(&"get_clip_end"):
		return 0.0
	return clip_source.call(&"get_clip_end", clip)
