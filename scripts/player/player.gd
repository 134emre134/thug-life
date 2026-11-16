class_name Player
extends CharacterBody3D
## Player root. Reads input (via the InputMap only) and turns it into intent
## for the separate components. Holds no movement/camera/aim/interaction logic
## itself, so components stay reusable (e.g. by NPC controllers later).
##
## Update order per physics tick: aim -> movement -> interaction -> animation.

## Capture the mouse when the scene starts.
@export var capture_mouse_on_start: bool = true

@onready var movement: PlayerMovement = $Movement
@onready var camera_rig: CameraRig = $CameraRig
@onready var aim: PlayerAim = $Aim
@onready var interaction: InteractionComponent = $Interaction
@onready var animator: PlayerAnimator = $Animator
@onready var model: Node3D = $Model


func _ready() -> void:
	add_to_group(&"player")
	camera_rig.add_collision_exception(get_rid())
	aim.add_collision_exception(get_rid())
	interaction.add_collision_exception(get_rid())
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
	elif event.is_action_pressed(&"interact"):
		interaction.try_interact(self)


func _physics_process(delta: float) -> void:
	var mouse_captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	# Aim
	var wants_aim := mouse_captured and Input.is_action_pressed(&"aim")
	aim.update(wants_aim, camera_rig.camera, get_aim_origin())
	camera_rig.set_aiming(aim.is_aiming)

	# Movement (camera-relative)
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var move_dir := camera_rig.get_yaw_basis() * Vector3(input.x, 0.0, input.y)
	var intent := PlayerMovement.Intent.new()
	intent.move_direction = move_dir
	intent.walk = Input.is_action_pressed(&"walk")
	intent.sprint = Input.is_action_pressed(&"sprint")
	intent.jump = Input.is_action_just_pressed(&"jump")
	intent.strafe = aim.is_aiming
	intent.face_yaw = camera_rig.yaw
	movement.physics_update(delta, intent)

	# Interaction
	interaction.update(get_aim_origin(), -camera_rig.camera.global_basis.z)

	# Animation
	animator.update(delta, aim.is_aiming)


## Push the player with a physical impulse (N·s). Used by explosions, hits,
## test knockback pads, etc.
func apply_knockback(impulse: Vector3) -> void:
	movement.apply_knockback(impulse)


## Approximate chest/shoulder point; origin for aim and interaction checks.
func get_aim_origin() -> Vector3:
	return global_position + Vector3.UP * aim.origin_height


## Direction the character model is facing (horizontal).
func get_facing() -> Vector3:
	return -model.global_basis.z
