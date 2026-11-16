class_name Player
extends CharacterBody3D
## Player root. Reads input (via the InputMap only) and turns it into intent
## for the separate components. Holds no movement/camera/aim/combat logic
## itself, so the components stay reusable (NPCs drive the same ones).
##
## Update order per physics tick: aim/guard -> combat -> movement ->
## interaction -> animation. Combat runs before movement because attacks lock
## or drive movement (lunges, dodges). Held interactions (searching a body)
## keep the player in place and are cancelled by attacking, guarding or being
## hit.
##
## From M2 on, the right mouse button guards (unarmed and melee weapons). Aim
## mode is kept intact for firearms (M4) but is never entered.

## Knocked out or killed.
signal knocked_out
signal killed
signal revived

## Capture the mouse when the scene starts.
@export var capture_mouse_on_start: bool = true
## Only read combat input while the mouse is captured, so the click that
## captures the mouse doesn't also attack. Off for automated tests (headless
## can't capture the mouse).
@export var require_mouse_capture: bool = true

@export_group("Combat input")
## Holding the light attack button this long triggers a heavy attack instead.
@export var heavy_hold_time: float = 0.28

var _attack_held_time: float = 0.0
var _attack_charging: bool = false
var _debug_clip_index: int = -1
var _collision_layer: int = 0

@onready var movement: PlayerMovement = $Movement
@onready var camera_rig: CameraRig = $CameraRig
@onready var aim: PlayerAim = $Aim
@onready var interaction: InteractionComponent = $Interaction
@onready var animator: PlayerAnimator = $Animator
@onready var model: Node3D = $Model
@onready var health: HealthComponent = $Health
@onready var combat: MeleeCombat = $Combat
@onready var hurtbox: HurtboxComponent = $Hurtbox
@onready var ragdoll: RagdollComponent = $Ragdoll
@onready var flash: ModelFlash = $Flash
@onready var inventory: InventoryComponent = $Inventory


func _ready() -> void:
	add_to_group(&"player")
	_collision_layer = collision_layer
	camera_rig.add_collision_exception(get_rid())
	aim.add_collision_exception(get_rid())
	interaction.add_collision_exception(get_rid())
	combat.clip_requested.connect(animator.play_combat_clip)
	combat.clip_stopped.connect(animator.stop_combat_clip)
	combat.hit_landed.connect(_on_hit_landed)
	combat.attack_blocked.connect(_on_attack_blocked)
	combat.hit_taken.connect(_on_hit_taken)
	health.knocked_out.connect(_on_down)
	health.killed.connect(_on_down)
	if capture_mouse_on_start:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_mouse_capture"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif (
		event is InputEventMouseButton
		and event.pressed
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"shoulder_swap"):
		camera_rig.swap_shoulder()
	elif combat.is_down():
		return
	elif event.is_action_pressed(&"interact"):
		interaction.try_interact(self)
	elif event.is_action_pressed(&"drop_weapon"):
		inventory.drop_melee()
	elif event.is_action_pressed(&"holster_weapon"):
		inventory.toggle_melee()
	elif event.is_action_pressed(&"debug_combat_clip"):
		_debug_play_next_clip()


func _physics_process(delta: float) -> void:
	var mouse_captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var active := (mouse_captured or not require_mouse_capture) and not combat.is_down()
	var look := -camera_rig.camera.global_basis.z
	var input := Vector2.ZERO
	if not combat.is_down() and not interaction.is_holding():
		input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var move_dir := camera_rig.get_yaw_basis() * Vector3(input.x, 0.0, input.y)

	# Aim / guard. Melee only for now: RMB guards, aim mode stays off (M4).
	aim.update(false, camera_rig.camera, get_aim_origin())
	camera_rig.set_aiming(aim.is_aiming)
	var guard := active and Input.is_action_pressed(&"guard")
	# Dodge and jump share a key by default: dodge while guarding, jump otherwise.
	var dodge := active and guard and Input.is_action_just_pressed(&"dodge")
	var jump := not guard and not combat.is_down() and not interaction.is_holding()
	jump = jump and Input.is_action_just_pressed(&"jump")

	# Combat
	var combat_intent := MeleeCombat.Intent.new()
	combat_intent.guard = guard
	combat_intent.dodge = dodge
	combat_intent.dodge_direction = move_dir
	combat_intent.look_direction = look
	_read_attack_input(delta, active, combat_intent)
	combat.physics_update(delta, combat_intent)

	# Movement (camera-relative)
	var intent := PlayerMovement.Intent.new()
	intent.move_direction = move_dir
	intent.walk = Input.is_action_pressed(&"walk")
	intent.sprint = Input.is_action_pressed(&"sprint")
	intent.jump = jump
	intent.strafe = aim.is_aiming
	intent.face_yaw = camera_rig.yaw
	combat.apply_to_movement(intent)
	movement.physics_update(delta, intent)

	# Interaction (a held search only progresses while combat is idle)
	interaction.update(get_aim_origin(), look)
	var hold := (
		active
		and Input.is_action_pressed(&"interact")
		and combat.state == MeleeCombat.State.IDLE
		and is_on_floor()
	)
	interaction.update_hold(delta, hold, self)

	# Animation
	animator.update(delta, aim.is_aiming or combat.is_guarding(), combat.get_guard_clip())


## Push the player with a physical impulse (N·s). Used by explosions, hits,
## test knockback pads, etc. A downed player's ragdoll takes it instead.
func apply_knockback(impulse: Vector3) -> void:
	if ragdoll.is_active:
		ragdoll.apply_impulse(impulse)
	else:
		movement.apply_knockback(impulse)


## Takes an item from the world (duck-typed, called by pickups). Weapons go in
## hand, replacing (dropping) the current melee weapon. Returns false if the
## item can't be carried.
func receive_item(item: ItemData) -> bool:
	if combat.is_down() or item == null:
		return false
	if item.get_slot() == ItemData.Slot.MELEE:
		return inventory.pick_up_weapon(item as WeaponData)
	return inventory.add_item(item)


## Duck-typed access for body searches and (M3b) pickpocketing.
func get_inventory() -> InventoryComponent:
	return inventory


## Back on your feet at [param at] with full health (fight restart).
func revive(at: Transform3D) -> void:
	ragdoll.deactivate()
	flash.clear()
	health.revive()
	combat.reset()
	collision_layer = _collision_layer
	hurtbox.enabled = true
	velocity = Vector3.ZERO
	# Only the model and camera turn: the movement component assumes an unrotated body.
	global_position = at.origin
	var yaw := at.basis.get_euler().y
	model.rotation = Vector3(0.0, yaw, 0.0)
	camera_rig.yaw = yaw
	reset_physics_interpolation()
	revived.emit()


## Approximate chest/shoulder point; origin for aim and interaction checks.
func get_aim_origin() -> Vector3:
	return global_position + Vector3.UP * aim.origin_height


## Direction the character model is facing (horizontal).
func get_facing() -> Vector3:
	return -model.global_basis.z


## Tap = light attack (on release), hold = heavy (as soon as the hold time is
## reached). The dedicated heavy action triggers a heavy attack directly.
func _read_attack_input(delta: float, active: bool, intent: MeleeCombat.Intent) -> void:
	if not active:
		_attack_charging = false
		return
	intent.heavy = Input.is_action_just_pressed(&"attack_heavy")
	if Input.is_action_just_pressed(&"attack_light"):
		_attack_charging = true
		_attack_held_time = 0.0
	if not _attack_charging:
		return
	if Input.is_action_pressed(&"attack_light"):
		_attack_held_time += delta
		if _attack_held_time >= heavy_hold_time:
			intent.heavy = true
			_attack_charging = false
	else:
		intent.light = true
		_attack_charging = false


func _on_hit_landed(_attacker: Node3D, _victim: Node3D, attack: AttackData) -> void:
	camera_rig.add_trauma(attack.camera_shake)


func _on_attack_blocked(_attacker: Node3D, _victim: Node3D, attack: AttackData) -> void:
	camera_rig.add_trauma(attack.camera_shake * 0.4)


func _on_hit_taken(
	_attacker: Node3D, attack: AttackData, result: HurtboxComponent.HitResult
) -> void:
	if result >= HurtboxComponent.HitResult.GUARD_BROKEN:
		interaction.cancel_hold()
	match result:
		HurtboxComponent.HitResult.BLOCKED:
			camera_rig.add_trauma(attack.camera_shake * 0.5)
		HurtboxComponent.HitResult.IGNORED, HurtboxComponent.HitResult.DODGED:
			pass
		_:
			camera_rig.add_trauma(attack.camera_shake * 1.3)
			flash.flash_hit(attack.is_heavy())


## Knocked out or killed (a knockout can be followed by death).
func _on_down(_victim: Node3D, _by: Node3D) -> void:
	_attack_charging = false
	interaction.cancel_hold()
	collision_layer = 0
	hurtbox.enabled = false
	ragdoll.activate(combat.last_hit_impulse * 1.5, velocity)
	if health.is_dead():
		Events.notify("You died")
		killed.emit()
	else:
		Events.notify("Knocked out")
		knocked_out.emit()


## Debug (M2.1): plays every combat clip in turn on the player model.
func _debug_play_next_clip() -> void:
	var clips := animator.get_combat_clips()
	if clips.is_empty() or combat.state != MeleeCombat.State.IDLE:
		return
	_debug_clip_index = (_debug_clip_index + 1) % clips.size()
	var clip := StringName(clips[_debug_clip_index])
	animator.play_combat_clip(clip, animator.get_clip_length(clip))
	Events.notify("Clip %d/%d: %s" % [_debug_clip_index + 1, clips.size(), clip])
