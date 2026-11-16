class_name SoftTargeting
extends Node
## Picks the best melee target in a cone around a view direction (M2.4).
## No lock-on: the target is re-evaluated every tick, with a small bonus for
## the current one so it doesn't flicker between two enemies.
##
## Candidates are [MeleeCombat] nodes in the "combatants" group on another team.

@export var max_range: float = 5.0
## Half-angle of the cone around the view direction.
@export_range(0.0, 180.0) var max_angle_degrees: float = 60.0
## Score per unit of alignment (1 = dead centre, cos(max angle) = cone edge).
@export var angle_weight: float = 1.0
## Score penalty per metre of distance.
@export var distance_weight: float = 0.25
## Score bonus for the current target (hysteresis).
@export var current_target_bonus: float = 0.15

var current_target: MeleeCombat = null


## Re-evaluates and returns [member current_target] (null if none).
func update(origin: Vector3, direction: Vector3, own: MeleeCombat) -> MeleeCombat:
	var flat_dir := Vector3(direction.x, 0.0, direction.z)
	if flat_dir.length_squared() < 0.0001:
		current_target = null
		return null
	flat_dir = flat_dir.normalized()
	var min_dot := cos(deg_to_rad(max_angle_degrees))
	var best: MeleeCombat = null
	var best_score := -INF
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var candidate := node as MeleeCombat
		if candidate == null or candidate == own or not candidate.is_targetable():
			continue
		if own != null and candidate.team == own.team:
			continue
		var to_target := candidate.body.global_position - origin
		to_target.y = 0.0
		var distance := to_target.length()
		if distance > max_range:
			continue
		var alignment := flat_dir.dot(to_target / distance) if distance > 0.001 else 1.0
		if alignment < min_dot:
			continue
		var score := alignment * angle_weight - distance * distance_weight
		if candidate == current_target:
			score += current_target_bonus
		if score > best_score:
			best = candidate
			best_score = score
	current_target = best
	return best
