class_name NpcCharacter
extends CharacterBody3D
## Thin NPC body, the counterpart of [Player]: its controller ([ThugAI])
## decides, and the shared components act, in the same order as for the
## player: combat -> movement -> animation.

signal knocked_out(npc: NpcCharacter)

## Materials on the model that get replaced by [member tint_material] (e.g.
## the mannequin body material), so enemies read differently from the player.
@export var tint_replace: Material
@export var tint_material: Material

var _collision_layer: int = 0

@onready var model: Node3D = $Model
@onready var movement: PlayerMovement = $Movement
@onready var combat: MeleeCombat = $Combat
@onready var health: HealthComponent = $Health
@onready var hurtbox: HurtboxComponent = $Hurtbox
@onready var animator: PlayerAnimator = $Animator
@onready var ragdoll: RagdollComponent = $Ragdoll
@onready var flash: ModelFlash = $Flash
@onready var ai: ThugAI = $AI


func _ready() -> void:
	add_to_group(&"npcs")
	_collision_layer = collision_layer
	_apply_tint(model)
	combat.clip_requested.connect(animator.play_combat_clip)
	combat.clip_stopped.connect(animator.stop_combat_clip)
	combat.phase_changed.connect(_on_phase_changed)
	combat.state_changed.connect(_on_state_changed)
	combat.hit_taken.connect(_on_hit_taken)
	health.knocked_out.connect(_on_knocked_out)


func _physics_process(delta: float) -> void:
	ai.think(delta)
	combat.physics_update(delta, ai.combat_intent)
	combat.apply_to_movement(ai.move_intent)
	movement.physics_update(delta, ai.move_intent)
	animator.update(delta, ai.move_intent.strafe or combat.is_guarding(), combat.get_guard_clip())


## Physical push (N·s), duck-typed like the player's.
func apply_knockback(impulse: Vector3) -> void:
	movement.apply_knockback(impulse)


func get_facing() -> Vector3:
	return -model.global_basis.z


func _on_phase_changed(phase: MeleeCombat.Phase) -> void:
	flash.set_telegraph(phase == MeleeCombat.Phase.WINDUP)


func _on_state_changed(state: MeleeCombat.State) -> void:
	if state != MeleeCombat.State.ATTACK:
		flash.set_telegraph(false)


func _on_hit_taken(
	_attacker: Node3D, attack: AttackData, result: HurtboxComponent.HitResult
) -> void:
	if result >= HurtboxComponent.HitResult.GUARD_BROKEN:
		flash.flash_hit(attack.is_heavy())


func _on_knocked_out(_victim: Node3D, _by: Node3D) -> void:
	ai.on_knocked_out()
	flash.clear()
	collision_layer = 0
	hurtbox.enabled = false
	ragdoll.activate(combat.last_hit_impulse * 1.5, velocity)
	knocked_out.emit(self)


func _apply_tint(node: Node) -> void:
	if tint_replace == null or tint_material == null:
		return
	for child in node.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh is PrimitiveMesh:
			if (mesh_instance.mesh as PrimitiveMesh).material == tint_replace:
				mesh_instance.material_override = tint_material
		_apply_tint(child)
