class_name CombatDebugLabel
extends Label3D
## Floating debug readout above a combatant: health, combat state / phase,
## attack token and AI mode ([method NpcController.get_debug_text]). Shown
## with the HUD's debug toggle.

## Shared visibility for all labels (set by the HUD).
static var shown: bool = false

@export var combat: MeleeCombat
@export var health: HealthComponent
## Optional.
@export var ai: NpcController


func _process(_delta: float) -> void:
	visible = shown and combat != null and health != null
	if not visible:
		return
	var lines := PackedStringArray(
		["HP %d/%d" % [ceili(health.health), ceili(health.max_health)], combat.state_name]
	)
	if combat.attack != null:
		lines.append("%s %s" % [combat.attack.id, combat.phase_name])
	if ai != null and not ai.get_debug_text().is_empty():
		lines.append(ai.get_debug_text())
	text = "\n".join(lines)
