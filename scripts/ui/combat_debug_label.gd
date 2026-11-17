class_name CombatDebugLabel
extends Label3D
## Floating debug readout above a combatant: health, combat state / phase,
## attack token and AI mode. Shown with the HUD's debug toggle.

## Shared visibility for all labels (set by the HUD).
static var shown: bool = false

@export var combat: MeleeCombat
@export var health: HealthComponent
## Optional.
@export var ai: ThugAI


func _process(_delta: float) -> void:
	visible = shown and combat != null and health != null
	if not visible:
		return
	var lines := PackedStringArray(
		["HP %d/%d" % [ceili(health.health), ceili(health.max_health)], combat.get_state_name()]
	)
	if combat.attack != null:
		lines.append("%s %s" % [combat.attack.id, combat.get_phase_name()])
	if ai != null:
		var token := ai.director != null and ai.director.has_token(ai)
		lines.append("%s%s" % [ThugAI.Mode.keys()[ai.mode], " [TOKEN]" if token else ""])
	text = "\n".join(lines)
