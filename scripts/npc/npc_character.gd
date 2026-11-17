class_name NpcCharacter
extends CharacterBody3D
## Thin NPC body, the counterpart of [Player]: its controller (any
## [NpcController]: [ThugAI], [RangedThugAI], [CivilianAI]) decides, and the
## shared components act, in the same order as for the player: combat ->
## ranged (only NPCs with a "Ranged" node) -> movement -> animation.
##
## Knocked out, it lies as a ragdoll that can still be hit (downed damage: the
## hurtbox follows the ragdoll) and searched ([BodySearch]); untouched, it
## gets back up after the [HealthComponent]'s recovery time. Dead, it stays a
## ragdoll that can only be searched.

signal knocked_out(npc: NpcCharacter)
signal killed(npc: NpcCharacter)
signal recovered(npc: NpcCharacter)

## Multiplied into the model's materials (per-instance copies), so enemies
## read differently from the player. White = no tint.
@export var tint_color: Color = Color.WHITE

@export_group("Getting up")
## Where the hips sit along the character's forward axis at the start of the
## get-up clips (metres; getup_from_back / getup_from_front). The body is
## placed so the clip's hips start where the ragdoll's pelvis lies.
@export var get_up_back_hips_offset: float = -0.38
@export var get_up_front_hips_offset: float = 0.11

var _collision_layer: int = 0

@onready var model: Node3D = $Model
@onready var movement: PlayerMovement = $Movement
@onready var combat: MeleeCombat = $Combat
@onready var health: HealthComponent = $Health
@onready var hurtbox: HurtboxComponent = $Hurtbox
@onready var animator: PlayerAnimator = $Animator
@onready var ragdoll: RagdollComponent = $Ragdoll
@onready var flash: ModelFlash = $Flash
@onready var ai: NpcController = $AI
@onready var inventory: InventoryComponent = $Inventory
@onready var search: BodySearch = $Search
## Optional (armed NPC variants, M4b).
@onready var ranged: RangedCombat = get_node_or_null(^"Ranged") as RangedCombat


func _ready() -> void:
	add_to_group(&"npcs")
	_collision_layer = collision_layer
	_apply_tint(model)
	combat.clip_source = animator
	combat.clip_requested.connect(animator.play_combat_clip)
	combat.clip_stopped.connect(animator.stop_combat_clip)
	combat.phase_changed.connect(_on_phase_changed)
	combat.state_changed.connect(_on_state_changed)
	combat.hit_taken.connect(_on_hit_taken)
	movement.crouched_changed.connect(_on_crouched_changed)
	if ranged != null:
		ranged.clip_source = animator
		ranged.clip_requested.connect(animator.play_upper_clip)
		ranged.clip_stopped.connect(animator.stop_upper_clip)
		ranged.telegraph_changed.connect(_on_telegraph_changed)
	health.knocked_out.connect(_on_down)
	health.killed.connect(_on_down)
	health.recovered.connect(_on_recovered)


func _physics_process(delta: float) -> void:
	ai.think(delta)
	combat.physics_update(delta, ai.combat_intent)
	if ranged != null:
		ranged.physics_update(delta, ai.ranged_intent)
	combat.apply_to_movement(ai.move_intent)
	movement.physics_update(delta, ai.move_intent)
	animator.update(
		delta,
		ai.move_intent.strafe or combat.is_guarding(),
		combat.get_upper_body_clip(),
		movement.is_crouched,
		combat.firearm != null
	)


## Physical push (N·s), duck-typed like the player's. A downed NPC's ragdoll
## takes it instead.
func apply_knockback(impulse: Vector3) -> void:
	if ragdoll.is_active:
		ragdoll.apply_impulse(impulse)
	else:
		movement.apply_knockback(impulse)


## Duck-typed access for body searches and (M5a) pickpocketing.
func get_inventory() -> InventoryComponent:
	return inventory


func get_facing() -> Vector3:
	return -model.global_basis.z


func _on_phase_changed(phase: MeleeCombat.Phase) -> void:
	flash.set_telegraph(phase == MeleeCombat.Phase.WINDUP)


func _on_state_changed(state: MeleeCombat.State) -> void:
	if state != MeleeCombat.State.ATTACK and (ranged == null or not ranged.is_telegraphing()):
		flash.set_telegraph(false)


## Aiming at someone glows red like a melee windup (and shows a laser).
func _on_telegraph_changed(on: bool) -> void:
	flash.set_telegraph(on)


## The hurtbox shrinks with the crouched capsule, so low cover hides the body.
func _on_crouched_changed(crouched: bool) -> void:
	hurtbox.set_height(movement.crouch_height if crouched else 0.0)


func _on_hit_taken(
	_attacker: Node3D, attack: AttackData, result: HurtboxComponent.HitResult
) -> void:
	if result >= HurtboxComponent.HitResult.GUARD_BROKEN:
		flash.flash_hit(attack.is_heavy())


## Knocked out or killed (a knockout can be followed by death).
func _on_down(_victim: Node3D, _by: Node3D) -> void:
	if not ragdoll.is_active:
		ai.on_knocked_out()
		if ranged != null:
			ranged.reset()
		flash.clear()
		collision_layer = 0
		ragdoll.activate(combat.last_hit_impulse * 1.5, velocity)
		hurtbox.follow = ragdoll.get_root_body()
	if health.is_dead():
		hurtbox.enabled = false
		killed.emit(self)
	else:
		knocked_out.emit(self)


## Gets up where the ragdoll lies, turned so the get-up clip (from the back
## or the front, chosen by [MeleeCombat]) starts in the ragdoll's pose.
func _on_recovered(_victim: Node3D) -> void:
	var root := ragdoll.get_root_body()
	if root != null:
		var pelvis := Vector3(root.global_position.x, global_position.y, root.global_position.z)
		var face_down := ragdoll.is_face_down()
		var head := ragdoll.get_head_direction()
		var facing := get_facing()
		if head != Vector3.ZERO:
			# On the back the head points backwards, face down it points forwards.
			facing = head if face_down else -head
			model.rotation = Vector3(0.0, atan2(-facing.x, -facing.z), 0.0)
		var offset := get_up_front_hips_offset if face_down else get_up_back_hips_offset
		global_position = pelvis - facing * offset
	ragdoll.deactivate()
	hurtbox.follow = null
	hurtbox.enabled = true
	collision_layer = _collision_layer
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	ai.on_recovered()
	recovered.emit(self)


func _apply_tint(node: Node) -> void:
	if tint_color == Color.WHITE:
		return
	for child in node.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null:
			for surface in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
				if material == null:
					continue
				var tinted := material.duplicate() as BaseMaterial3D
				tinted.albedo_color *= tint_color
				mesh_instance.set_surface_override_material(surface, tinted)
		_apply_tint(child)
