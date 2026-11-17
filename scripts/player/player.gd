class_name Player
extends CharacterBody3D
## Player root. Reads input (via the InputMap only) and turns it into intent
## for the separate components. Holds no movement/camera/aim/combat logic
## itself, so the components stay reusable (NPCs drive the same ones).
##
## Update order per physics tick: weapon switch -> aim/guard -> combat ->
## ranged -> cover -> movement -> interaction -> animation. Combat runs before
## movement because attacks lock or drive movement (lunges, dodges); cover
## runs after combat (a melee action leaves cover) and edits the movement
## intent last. Held interactions (searching a body) keep the player in place
## and are cancelled by attacking, guarding or being hit.
##
## The right mouse button guards while unarmed or holding a melee weapon and
## aims with a firearm in hand (M4b); with a firearm the attack button fires
## along the crosshair (without aiming it raises the weapon first: hip fire).
## Weapon switches (keys, wheel, holster) wait until combat is free.
##
## Crouch (M4a.4): toggle (or hold, see [member crouch_toggle]). Sprinting,
## jumping, guarding, attacking, dodging and being hit stand the player up
## when there is room; combat actions wait (buffered) until standing.

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

@export_group("Firearm input")
## Firing without aiming keeps the weapon raised this long (hip fire).
@export var hip_fire_aim_time: float = 0.8

@export_group("Debug")
## The debug clip key (F4) shows short clips (single-frame poses) at least
## this long, slowed down.
@export var debug_clip_min_time: float = 1.0

@export_group("Crouch")
## True: the crouch key toggles. False: crouch while it is held.
@export var crouch_toggle: bool = true

var _attack_held_time: float = 0.0
var _attack_charging: bool = false
var _debug_clip_index: int = -1
var _collision_layer: int = 0
var _crouch_wanted: bool = false
var _hip_fire_timer: float = 0.0
## Hand requested by a switch key, applied once combat is free (-1 = none).
var _pending_hand: int = -1
## Hand drawn before the last holster (H draws it again).
var _last_hand: InventoryComponent.Hand = InventoryComponent.Hand.MELEE

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
@onready var ranged: RangedCombat = $Ranged
@onready var cover: CoverComponent = $Cover


func _ready() -> void:
	add_to_group(&"player")
	_collision_layer = collision_layer
	camera_rig.add_collision_exception(get_rid())
	aim.add_collision_exception(get_rid())
	interaction.add_collision_exception(get_rid())
	combat.clip_source = animator
	ranged.clip_source = animator
	movement.jumped.connect(animator.notify_jump)
	movement.crouched_changed.connect(_on_crouched_changed)
	combat.clip_requested.connect(animator.play_combat_clip)
	combat.clip_stopped.connect(animator.stop_combat_clip)
	ranged.clip_requested.connect(animator.play_upper_clip)
	ranged.clip_stopped.connect(animator.stop_upper_clip)
	ranged.shot_fired.connect(_on_shot_fired)
	cover.peek_changed.connect(_on_peek_changed)
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
		# The weapon in hand; with nothing in hand, the melee weapon (M3a).
		var firearm_drawn := inventory.get_hand() == InventoryComponent.Hand.FIREARM
		inventory.drop_weapon(
			InventoryComponent.Hand.FIREARM if firearm_drawn else InventoryComponent.Hand.MELEE
		)
	elif event.is_action_pressed(&"holster_weapon"):
		_toggle_holster()
	elif event.is_action_pressed(&"weapon_unarmed"):
		request_hand(InventoryComponent.Hand.NONE)
	elif event.is_action_pressed(&"weapon_melee"):
		request_hand(InventoryComponent.Hand.MELEE)
	elif event.is_action_pressed(&"weapon_firearm"):
		request_hand(InventoryComponent.Hand.FIREARM)
	elif event.is_action_pressed(&"weapon_next"):
		request_hand(inventory.get_next_hand(1))
	elif event.is_action_pressed(&"weapon_prev"):
		request_hand(inventory.get_next_hand(-1))
	elif event.is_action_pressed(&"debug_combat_clip"):
		_debug_play_next_clip()


func _physics_process(delta: float) -> void:
	var mouse_captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var active := (mouse_captured or not require_mouse_capture) and not combat.is_down()
	_apply_pending_hand()
	var firearm := combat.firearm != null
	var look := -camera_rig.camera.global_basis.z
	var input := Vector2.ZERO
	if not combat.is_down() and not interaction.is_holding():
		input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var move_dir := camera_rig.get_yaw_basis() * Vector3(input.x, 0.0, input.y)

	# Aim / guard. RMB guards with fists or a melee weapon and aims a firearm.
	var aim_held := active and firearm and Input.is_action_pressed(&"aim")
	var fire := active and firearm and Input.is_action_just_pressed(&"attack_light")
	if fire and not aim_held:
		_hip_fire_timer = hip_fire_aim_time
	_hip_fire_timer = maxf(_hip_fire_timer - delta, 0.0) if firearm else 0.0
	var wants_aim := firearm and active and (aim_held or _hip_fire_timer > 0.0)
	aim.update(wants_aim and combat.is_free(), camera_rig.camera, get_aim_origin())
	camera_rig.set_aiming(aim.is_aiming)
	var guard := active and not firearm and Input.is_action_pressed(&"guard")
	# Dodge and jump share a key by default: dodge while guarding or aiming,
	# jump otherwise.
	var dodge := active and (guard or aim_held) and Input.is_action_just_pressed(&"dodge")
	var jump := not guard and not aim_held and not combat.is_down() and not interaction.is_holding()
	jump = jump and Input.is_action_just_pressed(&"jump")

	# Combat (melee; with a firearm in hand the attack button fires instead)
	var combat_intent := MeleeCombat.Intent.new()
	combat_intent.guard = guard
	combat_intent.dodge = dodge
	combat_intent.dodge_direction = move_dir
	combat_intent.look_direction = look
	_read_attack_input(delta, active and not firearm, combat_intent)
	var sprint := Input.is_action_pressed(&"sprint") and input.length() > 0.01
	_update_crouch_wish(active, sprint or jump or wants_aim, combat_intent)
	combat_intent.hold_actions = movement.is_crouched
	combat.physics_update(delta, combat_intent)

	# Ranged (fires along the crosshair)
	var ranged_intent := RangedCombat.Intent.new()
	ranged_intent.aim = aim.is_aiming
	ranged_intent.fire = fire
	ranged_intent.reload = active and Input.is_action_just_pressed(&"reload")
	ranged_intent.aim_point = aim.aim_point
	ranged_intent.precise = aim_held
	ranged.physics_update(delta, ranged_intent)

	# Cover (sticky; any melee action, sprinting or jumping leaves it)
	var cover_intent := CoverComponent.Intent.new()
	cover_intent.toggle = active and Input.is_action_just_pressed(&"cover")
	cover_intent.move_direction = move_dir
	cover_intent.look_direction = look
	cover_intent.aim = aim.is_aiming
	cover_intent.leave = (
		sprint
		or jump
		or dodge
		or guard
		or combat_intent.light
		or combat_intent.heavy
		or _attack_charging
		or not combat.is_free()
	)
	cover.physics_update(delta, cover_intent)

	# Movement (camera-relative)
	var intent := PlayerMovement.Intent.new()
	intent.move_direction = move_dir
	intent.walk = Input.is_action_pressed(&"walk")
	intent.sprint = Input.is_action_pressed(&"sprint")
	intent.jump = jump
	intent.crouch = _crouch_wanted
	intent.strafe = aim.is_aiming
	intent.face_yaw = camera_rig.yaw
	if aim.is_aiming and firearm:
		intent.face_yaw -= deg_to_rad(combat.firearm.aim_yaw_offset_degrees)
	combat.apply_to_movement(intent)
	if combat.is_free():
		cover.apply_to_movement(intent)
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
	animator.update(
		delta,
		aim.is_aiming or combat.is_guarding() or cover.is_in_cover(),
		combat.get_upper_body_clip(),
		movement.is_crouched,
		firearm
	)


## Asks to switch to [param hand] (unarmed, melee or firearm slot). Applied
## right away if combat allows it, else as soon as it does (mid-swing, reacting).
func request_hand(hand: InventoryComponent.Hand) -> void:
	if not inventory.has_hand(hand):
		return
	_pending_hand = hand
	_apply_pending_hand()


## Push the player with a physical impulse (N·s). Used by explosions, hits,
## test knockback pads, etc. A downed player's ragdoll takes it instead.
func apply_knockback(impulse: Vector3) -> void:
	if ragdoll.is_active:
		ragdoll.apply_impulse(impulse)
	else:
		movement.apply_knockback(impulse)


## Takes an item from the world (duck-typed, called by pickups). Weapons go in
## hand, replacing (dropping) the one in the same slot; a firearm comes with
## [param rounds] in its magazine (-1 = full). Returns false if the item can't
## be carried.
func receive_item(item: ItemData, rounds: int = -1) -> bool:
	if combat.is_down() or item == null:
		return false
	if item is WeaponData:
		return inventory.pick_up_weapon(item as WeaponData, rounds)
	return inventory.add_item(item)


## Duck-typed access for body searches and (M3b) pickpocketing.
func get_inventory() -> InventoryComponent:
	return inventory


## Back on your feet at [param at] with full health (fight restart).
func revive(at: Transform3D) -> void:
	_crouch_wanted = false
	_hip_fire_timer = 0.0
	_pending_hand = -1
	cover.exit()
	ragdoll.deactivate()
	flash.clear()
	health.revive()
	combat.reset()
	ranged.reset()
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


## Switches weapons once combat allows it (never mid-swing or mid-reaction;
## an attack's recovery is fine). Reloads are cancelled by the switch.
func _apply_pending_hand() -> void:
	if _pending_hand < 0 or not combat.can_switch_weapon():
		return
	var hand := _pending_hand as InventoryComponent.Hand
	_pending_hand = -1
	var current := inventory.get_hand()
	if hand == current:
		return
	if hand == InventoryComponent.Hand.NONE:
		_last_hand = current
	inventory.draw(hand)
	_attack_charging = false
	_hip_fire_timer = 0.0


## H: holster whatever is drawn, or draw the last holstered weapon.
func _toggle_holster() -> void:
	if inventory.get_hand() != InventoryComponent.Hand.NONE:
		request_hand(InventoryComponent.Hand.NONE)
	elif inventory.has_hand(_last_hand):
		request_hand(_last_hand)
	elif inventory.melee != null:
		request_hand(InventoryComponent.Hand.MELEE)
	elif inventory.firearm != null:
		request_hand(InventoryComponent.Hand.FIREARM)


## Crouch wish from the crouch key (toggle or hold). Anything that needs the
## player upright (sprint, jump, combat input, being hit) cancels it.
func _update_crouch_wish(active: bool, stand: bool, intent: MeleeCombat.Intent) -> void:
	if crouch_toggle:
		if active and Input.is_action_just_pressed(&"crouch"):
			_crouch_wanted = not _crouch_wanted
	else:
		_crouch_wanted = active and Input.is_action_pressed(&"crouch")
	var combat_input := intent.light or intent.heavy or intent.guard or intent.dodge
	combat_input = combat_input or _attack_charging
	if stand or combat_input or combat.state != MeleeCombat.State.IDLE:
		_crouch_wanted = false


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


func _on_shot_fired(_shooter: Node3D, weapon: FirearmData) -> void:
	camera_rig.add_recoil(weapon.recoil_degrees)
	camera_rig.add_trauma(weapon.fire_camera_shake)


## The hurtbox shrinks with the crouched capsule, so low cover hides the body.
func _on_crouched_changed(crouched: bool) -> void:
	hurtbox.set_height(movement.crouch_height if crouched else 0.0)


## Peeking around high cover: the camera moves to that shoulder.
func _on_peek_changed(side: int) -> void:
	if side != 0:
		camera_rig.set_shoulder(side > 0)


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
	cover.exit()
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
	var length := animator.get_clip_end(clip)
	var speed := minf(1.0, length / debug_clip_min_time) if debug_clip_min_time > 0.0 else 1.0
	animator.play_combat_clip(clip, maxf(speed, 0.01))
	Events.notify("Clip %d/%d: %s" % [_debug_clip_index + 1, clips.size(), clip])
