class_name CivilianAI
extends NpcController
## Decision-making for a civilian walker (M3b.4, M3b.5). Walks a [WalkRoute]
## (idling now and then at its points) and panics when it notices danger:
## someone attacking, someone being hit, or a knocked-out or dead body nearby,
## within [member panic_radius] and in sight. It is also scared by being hit
## and by fleeing civilians close by. Panicking civilians run away from the
## danger until they are far enough away and have calmed down, then walk back
## to their route.
##
## No reporting: that becomes the M5a WitnessComponent. Civilians never fight
## back.

enum Mode { WALK, IDLE, FLEE, CALM_DOWN }

## Route to walk. Empty = the nearest [WalkRoute] when the civilian first thinks.
@export var route: WalkRoute

@export_group("Walking")
## A route point counts as reached within this distance.
@export var arrive_distance: float = 0.8
@export var idle_time_min: float = 2.0
@export var idle_time_max: float = 6.0
## Input strength while walking (0..1, scales walk speed).
@export_range(0.1, 1.0) var walk_input: float = 1.0

@export_group("Panic")
## Notice danger within this distance.
@export var panic_radius: float = 14.0
## Danger must be in sight (world geometry blocks it).
@export var panic_needs_line_of_sight: bool = true
## How often surroundings are checked (s).
@export var perception_interval: float = 0.3
## Fleeing civilians this close spread the panic.
@export var contagion_radius: float = 6.0
## How far ahead to aim each flee goal (m).
@export var flee_distance: float = 14.0
## Keep running until this far from the danger...
@export var safe_distance: float = 22.0
## ...and for at least this long (s).
@export var min_flee_time: float = 4.0
## Give up running after this long, wherever the danger is (s).
@export var max_flee_time: float = 14.0
## Stand and catch breath before walking the route again (s).
@export var calm_down_time: float = 3.0
## Eye height for line-of-sight checks.
@export var eye_height: float = 1.6
## Flee goals more than this far above or below the civilian are rejected (roofs).
@export var max_goal_height_difference: float = 1.0

var mode: Mode = Mode.WALK
## Where the danger was when the civilian last noticed it.
var danger_position := Vector3.ZERO

var _mode_time: float = 0.0
var _perception_timer: float = 0.0
var _point_index: int = -1
var _direction: int = 1
var _idle_time: float = 0.0
var _flee_goal := Vector3.ZERO
var _has_flee_goal: bool = false
## Bodies already seen (instance id -> true), so a body lying in the street
## scares a civilian once, not every time it walks past.
var _seen_bodies: Dictionary = {}


func _ready() -> void:
	super()
	add_to_group(&"civilians")
	_perception_timer = randf() * perception_interval
	_direction = 1 if randf() < 0.5 else -1
	if combat != null:
		combat.hit_taken.connect(_on_hit_taken)


func think(delta: float) -> void:
	super(delta)
	_mode_time += delta
	if not enabled or combat.is_down():
		return
	_perception_timer -= delta
	if _perception_timer <= 0.0:
		_perception_timer = perception_interval
		_perceive()
	if combat.is_busy_reacting():
		return
	match mode:
		Mode.WALK:
			_walk()
		Mode.IDLE:
			if _mode_time >= _idle_time:
				_advance_point()
				_set_mode(Mode.WALK)
		Mode.FLEE:
			_flee()
		Mode.CALM_DOWN:
			if _mode_time >= calm_down_time:
				_point_index = -1
				_set_mode(Mode.WALK)


func on_knocked_out() -> void:
	_has_flee_goal = false


## Back on its feet: run from whoever knocked it down.
func on_recovered() -> void:
	panic(danger_position if mode == Mode.FLEE else body.global_position)


func get_debug_text() -> String:
	return Mode.keys()[mode]


func is_panicking() -> bool:
	return mode == Mode.FLEE


## Starts (or refreshes) fleeing from [param from].
func panic(from: Vector3) -> void:
	danger_position = from
	if mode != Mode.FLEE:
		_set_mode(Mode.FLEE)
		_has_flee_goal = false


func _walk() -> void:
	if route == null:
		route = WalkRoute.find_nearest(get_tree(), body.global_position)
		if route == null:
			return
	var points := route.get_points()
	if points.is_empty():
		return
	if _point_index < 0 or _point_index >= points.size():
		_point_index = route.closest_index(body.global_position)
	var goal := points[_point_index]
	var offset := goal - body.global_position
	offset.y = 0.0
	if offset.length() <= arrive_distance:
		if randf() < route.idle_chance:
			_idle_time = randf_range(idle_time_min, idle_time_max)
			_set_mode(Mode.IDLE)
		else:
			_advance_point()
		return
	move_intent.move_direction = steer_to(goal) * walk_input
	move_intent.walk = true


func _advance_point() -> void:
	if route == null:
		return
	var next := route.next_index(_point_index, _direction)
	_point_index = next.x
	_direction = next.y


func _flee() -> void:
	var away := body.global_position - danger_position
	away.y = 0.0
	var far_enough := away.length() >= safe_distance and _mode_time >= min_flee_time
	if far_enough or _mode_time >= max_flee_time:
		_set_mode(Mode.CALM_DOWN)
		return
	if not _has_flee_goal or _flat_distance(_flee_goal) <= arrive_distance * 2.0:
		_pick_flee_goal(away)
	move_intent.move_direction = steer_to(_flee_goal)
	move_intent.sprint = true


## A reachable point roughly away from the danger: straight away first, then
## turning further and further to the sides.
func _pick_flee_goal(away: Vector3) -> void:
	var base := away.normalized() if away.length_squared() > 0.01 else -body.global_basis.z
	var map := body.get_world_3d().navigation_map
	for degrees: float in [0.0, 40.0, -40.0, 80.0, -80.0, 120.0, -120.0]:
		var direction := base.rotated(Vector3.UP, deg_to_rad(degrees))
		var wanted := body.global_position + direction * flee_distance
		var goal := NavigationServer3D.map_get_closest_point(map, wanted)
		if absf(goal.y - body.global_position.y) > max_goal_height_difference:
			continue
		if _flat_distance(goal) < flee_distance * 0.4:
			continue
		_flee_goal = goal
		_has_flee_goal = true
		return
	_flee_goal = body.global_position + base * flee_distance
	_has_flee_goal = true


## Looks for danger around the civilian.
func _perceive() -> void:
	var eye := body.global_position + Vector3.UP * eye_height
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var other := node as MeleeCombat
		if other == null or other == combat or not other.body.is_inside_tree():
			continue
		var position := other.body.global_position
		var is_body := other.is_down()
		if is_body:
			# A downed body lies where its ragdoll is.
			var hurtbox := other.hurtbox
			if hurtbox != null:
				position = hurtbox.global_position
		if _flat_distance(position) > panic_radius:
			continue
		var violent := other.state == MeleeCombat.State.ATTACK or other.is_busy_reacting()
		if not violent and not is_body:
			continue
		if is_body and _seen_bodies.has(other.get_instance_id()):
			continue
		if panic_needs_line_of_sight:
			if not has_line_of_sight(eye, position + Vector3.UP * (0.4 if is_body else eye_height)):
				continue
		if is_body:
			_seen_bodies[other.get_instance_id()] = true
		panic(position)
		return
	if mode == Mode.FLEE:
		return
	for node in get_tree().get_nodes_in_group(&"civilians"):
		var other := node as CivilianAI
		if other == null or other == self or not other.is_panicking():
			continue
		if _flat_distance(other.body.global_position) <= contagion_radius:
			panic(other.danger_position)
			return


func _on_hit_taken(
	attacker: Node3D, _attack: AttackData, _result: HurtboxComponent.HitResult
) -> void:
	if attacker != null:
		panic(attacker.global_position)


func _flat_distance(point: Vector3) -> float:
	var offset := point - body.global_position
	offset.y = 0.0
	return offset.length()


func _set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	_mode_time = 0.0
