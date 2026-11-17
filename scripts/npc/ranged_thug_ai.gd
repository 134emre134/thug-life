class_name RangedThugAI
extends ThugAI
## Decision-making for a thug with a firearm (M4b.4). Shares targeting, aggro
## and walking home with [ThugAI]; the fight itself is a ranged one:
##
## find a position -> move there -> hold it (crouched behind low cover) ->
## get a shooter token from the [CombatDirector] -> stand up and aim
## (telegraph: red laser and glow for [member telegraph_time]) -> fire a short
## burst -> give the token back -> hold again. Empty magazine: reload in cover.
## A target closer than [member retreat_distance] makes it back off first
## (before it starts aiming); one that stays that close (a cornered thug)
## gets shot at anyway, still telegraphed.
##
## Readable shots: the aim follows the target [member aim_lag] seconds late,
## so a target that keeps moving (sideways, sprinting, dodging) is missed and
## one that stands still is hit. Only [member CombatDirector.max_shooters]
## thugs aim at once.
##
## Cover: no authored cover markers. Around itself the thug samples navigation
## mesh points on a grid and keeps those with an obstacle right in front
## (toward the target) that hides a crouched body but not a standing one,
## i.e. low cover it can shoot over. Without one it holds a spot at its
## preferred distance in the open.

enum Tactic { IDLE, MOVE, HOLD, AIM, FIRE, RELOAD, RETREAT }

## Found as the "Ranged" sibling when empty.
@export var ranged: RangedCombat

@export_group("Range (m)")
## Keeps between these distances from its target.
@export var preferred_min_distance: float = 8.0
@export var preferred_max_distance: float = 16.0
## A target this close makes the thug back off before shooting.
@export var retreat_distance: float = 5.0
## Doesn't shoot from further away than this.
@export var max_fire_distance: float = 28.0

@export_group("Cover")
@export var use_cover: bool = true
## Cover points are searched within this radius around the thug.
@export var cover_search_radius: float = 9.0
@export var cover_grid_step: float = 1.0
## The obstacle must stand this close in front of the point.
@export var cover_obstacle_distance: float = 1.2
## Height of a crouched head (must be hidden) and of the standing gun (must see).
@export var crouched_eye_height: float = 0.75
@export var standing_eye_height: float = 1.45
## Height of the target's point used for visibility checks.
@export var target_eye_height: float = 1.2
## Gives up walking to a position after this long.
@export var move_timeout: float = 6.0

@export_group("Shooting")
## Seconds of visible aiming (laser, glow) before the first shot.
@export var telegraph_time: float = 0.9
## The aim follows the target this many seconds late (moving targets are missed).
@export var aim_lag: float = 0.3
@export_range(1, 5) var burst_min: int = 1
@export_range(1, 5) var burst_max: int = 2
## Seconds between the shots of a burst.
@export var burst_interval: float = 0.6
## Seconds holding a position between bursts.
@export var hold_time_min: float = 1.0
@export var hold_time_max: float = 2.2
## Out of sight this long while holding: find another position.
@export var lost_sight_time: float = 2.5
## Chance to change position after a burst.
@export_range(0.0, 1.0) var reposition_chance: float = 0.35
## Backs off this long (at most) when the target comes too close.
@export var retreat_time: float = 1.6

var tactic: Tactic = Tactic.IDLE
## Position chosen to fight from.
var goal_position := Vector3.ZERO
## [member goal_position] is a cover point (crouch there).
var goal_is_cover: bool = false

var _tactic_time: float = 0.0
var _cornered: bool = false
var _hold_time: float = 0.0
var _shots_left: int = 0
var _next_shot: float = 0.0
var _unseen_time: float = 0.0
var _clock: float = 0.0
var _history_time: PackedFloat32Array = []
var _history_point: PackedVector3Array = []


func _ready() -> void:
	super()
	if ranged == null:
		ranged = get_node_or_null(^"../Ranged") as RangedCombat


func on_knocked_out() -> void:
	super()
	_release_shot_token()
	_set_tactic(Tactic.IDLE)


func uses_melee_spacing() -> bool:
	return false


func get_debug_text() -> String:
	var token := director != null and director.has_shot_token(self)
	var rounds := ranged.inventory.firearm_rounds if ranged != null else 0
	return "%s%s %d" % [Tactic.keys()[tactic], " [SHOOTER]" if token else "", rounds]


## Where the thug aims now: the target's chest as it was [member aim_lag] ago.
func get_lagged_aim_point() -> Vector3:
	var at := _clock - aim_lag
	for i in _history_time.size():
		if _history_time[i] >= at:
			return _history_point[i]
	return _history_point[-1] if not _history_point.is_empty() else Vector3.ZERO


func _engage(delta: float, distance: float, direction: Vector3) -> void:
	_clock += delta
	_tactic_time += delta
	_record_target()
	if ranged == null or ranged.get_weapon() == null:
		super(delta, distance, direction)
		return
	move_intent.strafe = true
	var yaw := atan2(-direction.x, -direction.z)
	if ranged.is_aiming:
		yaw -= deg_to_rad(ranged.get_weapon().aim_yaw_offset_degrees)
	move_intent.face_yaw = yaw
	if combat.is_busy_reacting():
		_release_shot_token()
		if tactic == Tactic.AIM or tactic == Tactic.FIRE:
			_set_tactic(Tactic.HOLD)
		return
	match tactic:
		Tactic.IDLE:
			_choose_position(distance)
		Tactic.MOVE:
			_move(distance)
		Tactic.HOLD:
			_hold(delta, distance)
		Tactic.AIM:
			_aim(delta, distance)
		Tactic.FIRE:
			_fire(delta)
		Tactic.RELOAD:
			_reload()
		Tactic.RETREAT:
			_retreat(distance, direction)


func _on_no_target() -> void:
	super()
	_release_shot_token()
	_set_tactic(Tactic.IDLE)


func _choose_position(distance: float) -> void:
	goal_is_cover = use_cover and _find_cover_point(target.body.global_position)
	if not goal_is_cover:
		goal_position = body.global_position
		if distance < preferred_min_distance or distance > preferred_max_distance:
			var away := body.global_position - target.body.global_position
			away.y = 0.0
			away = away.normalized() if away.length_squared() > 0.01 else Vector3.BACK
			var keep := clampf(distance, preferred_min_distance, preferred_max_distance)
			goal_position = target.body.global_position + away * keep
	_set_tactic(Tactic.MOVE)


func _move(distance: float) -> void:
	if distance < retreat_distance:
		_set_tactic(Tactic.RETREAT)
		return
	var offset := goal_position - body.global_position
	offset.y = 0.0
	if offset.length() < 0.5 or _tactic_time > move_timeout:
		_start_hold()
		return
	move_intent.move_direction = steer_to(goal_position)


func _hold(delta: float, distance: float) -> void:
	move_intent.crouch = goal_is_cover and _at_goal()
	if ranged.inventory.firearm_rounds <= 0:
		_set_tactic(Tactic.RELOAD)
		return
	if distance >= preferred_min_distance:
		_cornered = false
	if distance < retreat_distance and not _cornered:
		_set_tactic(Tactic.RETREAT)
		return
	var sees := _can_shoot_from(body.global_position)
	_unseen_time = 0.0 if sees else _unseen_time + delta
	if distance > max_fire_distance or _unseen_time > lost_sight_time:
		_set_tactic(Tactic.IDLE)
		return
	if _tactic_time < _hold_time or not sees:
		return
	if _request_shot_token():
		_set_tactic(Tactic.AIM)


func _aim(delta: float, distance: float) -> void:
	_aim_at_target()
	var sees := _can_shoot_from(body.global_position)
	_unseen_time = 0.0 if sees else _unseen_time + delta
	if _unseen_time > 0.5 or distance > max_fire_distance:
		_release_shot_token()
		_set_tactic(Tactic.IDLE)
		return
	if distance < retreat_distance and not _cornered:
		_release_shot_token()
		_set_tactic(Tactic.RETREAT)
		return
	if _tactic_time >= telegraph_time and ranged.is_raised():
		_shots_left = randi_range(burst_min, maxi(burst_min, burst_max))
		_next_shot = 0.0
		_set_tactic(Tactic.FIRE)


func _fire(delta: float) -> void:
	_aim_at_target()
	_next_shot -= delta
	if ranged.inventory.firearm_rounds <= 0 and not ranged.is_reloading:
		_release_shot_token()
		_set_tactic(Tactic.RELOAD)
		return
	if _shots_left > 0:
		if _next_shot <= 0.0 and ranged.can_fire():
			ranged_intent.fire = true
			_shots_left -= 1
			_next_shot = burst_interval
		return
	if _next_shot > 0.0:
		return
	_release_shot_token()
	if randf() < reposition_chance:
		_set_tactic(Tactic.IDLE)
	else:
		_start_hold()


func _reload() -> void:
	move_intent.crouch = goal_is_cover and _at_goal()
	var weapon := ranged.get_weapon()
	if not ranged.is_reloading:
		if ranged.inventory.firearm_rounds >= weapon.magazine_size:
			_start_hold()
			return
		ranged_intent.reload = true


func _retreat(distance: float, direction: Vector3) -> void:
	if distance >= preferred_min_distance:
		_set_tactic(Tactic.IDLE)
		return
	if _tactic_time > retreat_time:
		# Couldn't get away: fight from here.
		_cornered = distance < retreat_distance
		if _cornered:
			_hold_time = 0.0
			_unseen_time = 0.0
			_set_tactic(Tactic.HOLD)
		else:
			_set_tactic(Tactic.IDLE)
		return
	var away := body.global_position - direction * 4.0
	move_intent.move_direction = (steer_to(away) + _separation() * 0.5).limit_length(1.0)


func _start_hold() -> void:
	_hold_time = randf_range(hold_time_min, maxf(hold_time_min, hold_time_max))
	_unseen_time = 0.0
	_set_tactic(Tactic.HOLD)


func _aim_at_target() -> void:
	ranged_intent.aim = true
	ranged_intent.telegraph = true
	ranged_intent.aim_point = get_lagged_aim_point()


func _at_goal() -> bool:
	var offset := goal_position - body.global_position
	offset.y = 0.0
	return offset.length() < 1.0


## Remembers where the target's chest was (for the lagged aim).
func _record_target() -> void:
	_history_time.append(_clock)
	_history_point.append(_target_point())
	var keep_from := _clock - aim_lag - 0.5
	while _history_time.size() > 2 and _history_time[0] < keep_from:
		_history_time.remove_at(0)
		_history_point.remove_at(0)


## Centre of the target's hurtbox (lower when it crouches).
func _target_point() -> Vector3:
	if target.hurtbox != null and target.hurtbox.is_inside_tree():
		return target.hurtbox.get_center()
	return target.body.global_position + Vector3.UP * target_eye_height


## A standing shot from [param point] would reach the target.
func _can_shoot_from(point: Vector3) -> bool:
	return has_line_of_sight(point + Vector3.UP * standing_eye_height, _target_point())


## Picks the best cover point against [param threat] near the thug into
## [member goal_position]. Returns false if there is none.
func _find_cover_point(threat: Vector3) -> bool:
	var map := body.get_world_3d().navigation_map
	var origin := body.global_position
	var threat_eye := threat + Vector3.UP * target_eye_height
	var middle := (preferred_min_distance + preferred_max_distance) * 0.5
	var steps := int(cover_search_radius / cover_grid_step)
	var best_score := -INF
	for ix in range(-steps, steps + 1):
		for iz in range(-steps, steps + 1):
			var offset := Vector3(ix, 0.0, iz) * cover_grid_step
			if offset.length() > cover_search_radius:
				continue
			var wanted := origin + offset
			var point := NavigationServer3D.map_get_closest_point(map, wanted)
			if absf(point.y - origin.y) > 0.6:
				continue
			if Vector2(point.x - wanted.x, point.z - wanted.z).length() > 0.4:
				continue
			# The navigation mesh floats a little above the floor.
			point.y = origin.y
			var to_threat := threat - point
			to_threat.y = 0.0
			var distance := to_threat.length()
			if distance < preferred_min_distance or distance > preferred_max_distance + 4.0:
				continue
			var low := point + Vector3.UP * crouched_eye_height
			var ahead := low + to_threat / distance * cover_obstacle_distance
			if has_line_of_sight(low, ahead):
				continue  # nothing right in front
			if has_line_of_sight(low, threat_eye):
				continue  # a crouched body would still be seen
			if not has_line_of_sight(point + Vector3.UP * standing_eye_height, threat_eye):
				continue  # can't shoot over it
			var score := -point.distance_to(origin) * 0.5 - absf(distance - middle) * 0.3
			if score > best_score:
				best_score = score
				goal_position = point
	return best_score > -INF


func _request_shot_token() -> bool:
	return director == null or director.request_shot_token(self)


func _release_shot_token() -> void:
	if director != null:
		director.release_shot_token(self)


func _set_tactic(new_tactic: Tactic) -> void:
	if new_tactic == tactic:
		return
	tactic = new_tactic
	_tactic_time = 0.0
