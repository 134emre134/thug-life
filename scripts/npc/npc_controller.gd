class_name NpcController
extends Node
## Base for NPC decision-making ([ThugAI], [RangedThugAI], [CivilianAI]).
## Each tick [NpcCharacter] calls [method think], then passes
## [member move_intent], [member combat_intent] and (if it has one) the
## [member ranged_intent] to the same [PlayerMovement], [MeleeCombat] and
## [RangedCombat] components the player uses. Controllers never move the
## body themselves.

## Disabled controllers stand still (training dummy, tests).
@export var enabled: bool = true
@export var body: CharacterBody3D
@export var combat: MeleeCombat
## Optional; without it the NPC walks straight at its goal.
@export var agent: NavigationAgent3D

var move_intent := PlayerMovement.Intent.new()
var combat_intent := MeleeCombat.Intent.new()
var ranged_intent := RangedCombat.Intent.new()


func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody3D


## Fills [member move_intent] and [member combat_intent] for this tick.
func think(_delta: float) -> void:
	move_intent = PlayerMovement.Intent.new()
	combat_intent = MeleeCombat.Intent.new()
	ranged_intent = RangedCombat.Intent.new()


## Called by the NPC when knocked out or killed.
func on_knocked_out() -> void:
	pass


## Called by the NPC when it gets back up after a knockout.
func on_recovered() -> void:
	pass


## Short state readout for the floating debug label.
func get_debug_text() -> String:
	return ""


## Horizontal direction toward [param goal], following the navigation path if
## there is one and the goal is further than [param direct_distance].
func steer_to(goal: Vector3, direct_distance: float = 2.0) -> Vector3:
	var direct := goal - body.global_position
	direct.y = 0.0
	var direction := direct.normalized() if direct.length_squared() > 0.0001 else Vector3.ZERO
	if agent != null and direct.length() > direct_distance:
		if not agent.target_position.is_equal_approx(goal):
			agent.target_position = goal
		if not agent.is_navigation_finished():
			var next := agent.get_next_path_position() - body.global_position
			next.y = 0.0
			if next.length_squared() > 0.0025:
				direction = next.normalized()
	return direction


## True if nothing on the world layer blocks the line between two points.
func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
