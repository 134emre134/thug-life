class_name ThugAI
extends NpcController
## Decision-making for one melee thug (M2.7). Each tick [method think] fills
## [member move_intent] and [member combat_intent]; [NpcCharacter] passes them
## to the same [PlayerMovement] and [MeleeCombat] components the player uses.
##
## Behaviour: approach (navigation) -> circle the target at a distance, spaced
## out from other thugs -> attack once the [CombatDirector] grants a token
## (combo of 1-2 hits or a heavy) -> back off and return the token. Attacks are
## committed at the start of the windup (no tracking) and telegraphed, so they
## can be seen coming and dodged. Occasionally guards against the target's
## attacks.
##
## Aggro (M3b): with an [member aggro_radius] the thug only picks targets that
## come that close (and are in sight), drops them beyond [member lose_radius]
## and walks back to where it spawned. Hitting it always provokes it. With
## the defaults (0) it hunts the nearest target anywhere, as in the arena.

enum Mode { IDLE, APPROACH, CIRCLE, ATTACK, BACK_OFF }

## Optional; found through the "combat_director" group when empty. Without a
## director every attack request is granted.
@export var director: CombatDirector
## Team this thug attacks.
@export var target_team: StringName = &"player"

@export_group("Aggro")
## Only pick targets within this distance. 0 = any distance (arena).
@export var aggro_radius: float = 0.0
## Drop the target beyond this distance from the thug. 0 = never.
@export var lose_radius: float = 0.0
## A target must be in sight (world geometry) to be picked up.
@export var aggro_needs_line_of_sight: bool = true
## Eye height for line-of-sight checks.
@export var eye_height: float = 1.6
## Back home when this close to the spawn point.
@export var home_tolerance: float = 1.0

@export_group("Distances (m)")
## Start circling within this distance of the target.
@export var engage_distance: float = 6.0
@export var circle_radius: float = 3.2
## Start the attack within this distance.
@export var attack_distance: float = 1.5
## Push away from other NPCs closer than this.
@export var separation_radius: float = 1.4
## Minimum angle between two thugs around the target.
@export var spacing_degrees: float = 70.0

@export_group("Timing (s)")
## How often the navigation goal is refreshed.
@export var repath_interval: float = 0.25
## Give the token back if the target can't be reached in time.
@export var attack_approach_timeout: float = 2.5
@export var back_off_time: float = 1.0
## Average time between changes of circling direction.
@export var circle_direction_time: float = 2.5

@export_group("Attacks")
@export_range(1, 3) var max_combo_hits: int = 2
@export_range(0.0, 1.0) var heavy_chance: float = 0.2

@export_group("Guard")
## Chance to guard against an attack aimed at this thug.
@export_range(0.0, 1.0) var guard_chance: float = 0.35
## Only react to attacks started within this distance.
@export var guard_reaction_distance: float = 3.5
@export var guard_time: float = 0.9
@export var guard_cooldown: float = 2.0

@export_group("Steering")
## Input strength while circling (strafe speed scale).
@export_range(0.0, 1.0) var circle_move_scale: float = 0.6
@export var separation_weight: float = 1.2
@export var spacing_weight: float = 1.0

var mode: Mode = Mode.IDLE
var target: MeleeCombat = null
## Where the thug returns to without a target (its spawn point).
var home_position := Vector3.ZERO

var _mode_time: float = 0.0
var _repath_timer: float = 0.0
var _hits_left: int = 0
var _use_heavy: bool = false
var _last_serial: int = -1
var _guard_timer: float = 0.0
var _guard_cooldown_timer: float = 0.0
var _seen_target_serial: int = -1
var _circle_dir: float = 1.0
var _circle_dir_timer: float = 0.0
var _has_home: bool = false
var _provoked_by: MeleeCombat = null


func _ready() -> void:
	super()
	_circle_dir = 1.0 if randf() < 0.5 else -1.0
	_circle_dir_timer = randf_range(0.5, 1.5) * circle_direction_time
	if director == null:
		director = get_tree().get_first_node_in_group(&"combat_director") as CombatDirector
	if director != null:
		director.register(self)
	if combat != null:
		combat.hit_taken.connect(_on_hit_taken)


func _exit_tree() -> void:
	if director != null and is_instance_valid(director):
		director.unregister(self)


func think(delta: float) -> void:
	super(delta)
	if not _has_home:
		# The spawner places the body after _ready.
		home_position = body.global_position
		_has_home = true
	_mode_time += delta
	_repath_timer -= delta
	_guard_timer -= delta
	_guard_cooldown_timer -= delta
	if not enabled or combat.is_down():
		return
	_update_target()
	if target == null:
		_set_mode(Mode.IDLE)
		_return_home()
		return

	var to_target := target.body.global_position - body.global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var direction := to_target / distance if distance > 0.001 else -body.global_basis.z
	combat_intent.target = target
	combat_intent.look_direction = direction

	if combat.is_busy_reacting():
		# Hit: give up the attack and keep distance afterwards.
		if mode == Mode.ATTACK:
			_set_mode(Mode.BACK_OFF)
		return

	_update_guard(distance)
	match mode:
		Mode.IDLE:
			_set_mode(Mode.APPROACH)
		Mode.APPROACH:
			_approach(distance)
		Mode.CIRCLE:
			_circle(delta, distance, direction)
		Mode.ATTACK:
			_attack(distance)
		Mode.BACK_OFF:
			_back_off(distance, direction)

	if distance <= engage_distance + 1.0 or mode == Mode.ATTACK:
		move_intent.strafe = true
		move_intent.face_yaw = atan2(-direction.x, -direction.z)


func on_knocked_out() -> void:
	_set_mode(Mode.IDLE)


func get_debug_text() -> String:
	var token := director != null and director.has_token(self)
	return "%s%s" % [Mode.keys()[mode], " [TOKEN]" if token else ""]


func _approach(distance: float) -> void:
	if distance <= engage_distance:
		_set_mode(Mode.CIRCLE)
		return
	move_intent.move_direction = _steer_to(target.body.global_position)


func _circle(delta: float, distance: float, direction: Vector3) -> void:
	if distance > engage_distance + 1.5:
		_set_mode(Mode.APPROACH)
		return
	if _request_token():
		_hits_left = randi_range(1, max_combo_hits)
		_use_heavy = randf() < heavy_chance
		_last_serial = combat.attack_serial
		_set_mode(Mode.ATTACK)
		return
	_circle_dir_timer -= delta
	if _circle_dir_timer <= 0.0:
		_circle_dir = -_circle_dir
		_circle_dir_timer = randf_range(0.5, 1.5) * circle_direction_time
	var radial := -direction * clampf(distance - circle_radius, -1.0, 1.0)
	var tangent := direction.cross(Vector3.UP) * _circle_dir * 0.6
	var steer := radial + tangent + _spacing(direction) + _separation()
	move_intent.move_direction = steer.limit_length(1.0) * circle_move_scale
	move_intent.walk = true


func _attack(distance: float) -> void:
	if combat.state == MeleeCombat.State.ATTACK:
		# Chain the next hit of the combo during recovery.
		if (
			_hits_left > 0
			and combat.phase == MeleeCombat.Phase.RECOVERY
			and combat.attack_serial == _last_serial
		):
			combat_intent.light = true
			_hits_left -= 1
		_last_serial = combat.attack_serial
		return
	if _hits_left <= 0:
		_release_token()
		_set_mode(Mode.BACK_OFF)
		return
	if distance <= attack_distance:
		if _use_heavy:
			combat_intent.heavy = true
			_hits_left = 0
		else:
			combat_intent.light = true
			_hits_left -= 1
		return
	if _mode_time > attack_approach_timeout:
		_release_token()
		_set_mode(Mode.CIRCLE)
		return
	move_intent.move_direction = _steer_to(target.body.global_position)


func _back_off(distance: float, direction: Vector3) -> void:
	_release_token()
	if _mode_time >= back_off_time:
		_set_mode(Mode.CIRCLE)
		return
	if distance < circle_radius:
		move_intent.move_direction = (-direction + _separation()).limit_length(1.0) * 0.7
		move_intent.walk = true


func _update_guard(distance: float) -> void:
	if (
		mode != Mode.ATTACK
		and target.state == MeleeCombat.State.ATTACK
		and target.attack_serial != _seen_target_serial
	):
		_seen_target_serial = target.attack_serial
		if (
			target.current_target == combat
			and distance <= guard_reaction_distance
			and _guard_cooldown_timer <= 0.0
			and randf() < guard_chance
		):
			_guard_timer = guard_time
			_guard_cooldown_timer = guard_cooldown
	combat_intent.guard = _guard_timer > 0.0 and mode != Mode.ATTACK


func _update_target() -> void:
	if target != null and _keeps_target(target):
		return
	target = null
	if _provoked_by != null and _keeps_target(_provoked_by):
		target = _provoked_by
		return
	_provoked_by = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var candidate := node as MeleeCombat
		if candidate == null or candidate.team != target_team or not candidate.is_targetable():
			continue
		var distance := candidate.body.global_position.distance_to(body.global_position)
		if distance >= best_distance:
			continue
		if aggro_radius > 0.0 and (distance > aggro_radius or not _can_see(candidate)):
			continue
		best_distance = distance
		target = candidate
	if target == null:
		_release_token()


func _keeps_target(candidate: MeleeCombat) -> bool:
	if not is_instance_valid(candidate) or not candidate.is_targetable():
		return false
	if lose_radius <= 0.0:
		return true
	return candidate.body.global_position.distance_to(body.global_position) <= lose_radius


func _can_see(candidate: MeleeCombat) -> bool:
	if not aggro_needs_line_of_sight:
		return true
	var eye := body.global_position + Vector3.UP * eye_height
	return has_line_of_sight(eye, candidate.body.global_position + Vector3.UP * eye_height)


## Walks back to the spawn point (only for thugs with a limited aggro radius).
func _return_home() -> void:
	if aggro_radius <= 0.0:
		return
	var offset := home_position - body.global_position
	offset.y = 0.0
	if offset.length() > home_tolerance:
		move_intent.move_direction = _steer_to(home_position)
		move_intent.walk = true


## Hitting a thug makes the attacker its target, whatever the distance.
func _on_hit_taken(
	attacker: Node3D, _attack: AttackData, _result: HurtboxComponent.HitResult
) -> void:
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var candidate := node as MeleeCombat
		if candidate != null and candidate.body == attacker and candidate.team == target_team:
			_provoked_by = candidate
			if target == null:
				target = candidate
			return


## Direction toward [param goal], following the navigation path if there is one.
func _steer_to(goal: Vector3) -> Vector3:
	var direct := goal - body.global_position
	direct.y = 0.0
	var direction := direct.normalized() if direct.length_squared() > 0.0001 else Vector3.ZERO
	if agent != null and direct.length() > 2.0:
		if _repath_timer <= 0.0:
			agent.target_position = goal
			_repath_timer = repath_interval
		if not agent.is_navigation_finished():
			var next := agent.get_next_path_position() - body.global_position
			next.y = 0.0
			if next.length_squared() > 0.0025:
				direction = next.normalized()
	return (direction + _separation() * 0.5).limit_length(1.0)


## Pushes away from nearby NPCs.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for node in get_tree().get_nodes_in_group(&"npcs"):
		var other := node as Node3D
		if other == null or other == body:
			continue
		var offset := body.global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < 0.001 or distance >= separation_radius:
			continue
		push += offset / distance * (1.0 - distance / separation_radius)
	return push * separation_weight


## Keeps thugs apart around the target (angular spacing).
func _spacing(direction_to_target: Vector3) -> Vector3:
	if director == null:
		return Vector3.ZERO
	var my_angle := atan2(-direction_to_target.x, -direction_to_target.z)
	var gap := deg_to_rad(spacing_degrees)
	var push := 0.0
	for member in director.get_members():
		var other := member as ThugAI
		if other == null or other == self or other.target != target or not other.enabled:
			continue
		if other.combat.is_down():
			continue
		var to_target := target.body.global_position - other.body.global_position
		var angle := atan2(-to_target.x, -to_target.z)
		var diff := wrapf(my_angle - angle, -PI, PI)
		if absf(diff) < gap:
			push += signf(diff if diff != 0.0 else 1.0) * (1.0 - absf(diff) / gap)
	# Moving along direction x UP increases my angle around the target, so a
	# positive push widens a positive difference.
	var tangent := direction_to_target.cross(Vector3.UP)
	return tangent * push * spacing_weight


func _request_token() -> bool:
	return director == null or director.request_token(self)


func _release_token() -> void:
	if director != null:
		director.release_token(self)


func _set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	if mode == Mode.ATTACK and new_mode != Mode.ATTACK:
		_release_token()
	mode = new_mode
	_mode_time = 0.0
