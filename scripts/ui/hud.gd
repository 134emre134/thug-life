extends CanvasLayer
## Player HUD: crosshair, line-of-fire blocked marker, interaction prompt,
## notifications and a debug readout (toggle with the debug_toggle action).

@export var player: Player
@export var notification_time: float = 2.0

var _notify_tween: Tween

@onready var _crosshair: Control = $Crosshair
@onready var _blocked_marker: Control = $BlockedMarker
@onready var _prompt: Label = $Prompt
@onready var _notification: Label = $Notification
@onready var _debug: Label = $Debug


func _ready() -> void:
	_crosshair.visible = false
	_blocked_marker.visible = false
	_prompt.visible = false
	_notification.modulate.a = 0.0
	_debug.visible = false
	Events.notification_requested.connect(_on_notification)
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Player
	if player:
		player.aim.aiming_changed.connect(func(aiming: bool) -> void: _crosshair.visible = aiming)
		player.interaction.target_changed.connect(_on_target_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle"):
		_debug.visible = not _debug.visible


func _process(_delta: float) -> void:
	if player == null:
		return
	_update_blocked_marker()
	var target := player.interaction.current_target
	if is_instance_valid(target) and _prompt.visible:
		_prompt.text = "[%s] %s" % [_action_key(&"interact"), target.prompt_text]
	if _debug.visible:
		_update_debug()


func _update_blocked_marker() -> void:
	var aim := player.aim
	var camera := player.camera_rig.camera
	var point := aim.obstructed_point
	var blocked := aim.is_aiming and aim.is_obstructed and not camera.is_position_behind(point)
	_blocked_marker.visible = blocked
	if blocked:
		_blocked_marker.position = camera.unproject_position(point) - _blocked_marker.size * 0.5


func _on_target_changed(target: Interactable) -> void:
	_prompt.visible = target != null


func _on_notification(text: String) -> void:
	_notification.text = text
	if _notify_tween:
		_notify_tween.kill()
	_notify_tween = create_tween()
	_notify_tween.tween_property(_notification, "modulate:a", 1.0, 0.15)
	_notify_tween.tween_interval(notification_time)
	_notify_tween.tween_property(_notification, "modulate:a", 0.0, 0.4)


func _update_debug() -> void:
	var m := player.movement
	var lines := PackedStringArray(
		[
			"FPS: %d" % Engine.get_frames_per_second(),
			"Speed: %.2f m/s" % m.get_horizontal_speed(),
			"Vertical: %.2f m/s" % player.velocity.y,
			"Gait: %s" % PlayerMovement.Gait.keys()[m.gait],
			"On floor: %s" % player.is_on_floor(),
			"Knockback: %s" % m.is_knocked_back(),
			"Aiming: %s" % player.aim.is_aiming,
			(
				"Aim point: %s (%.1f m)"
				% [
					player.aim.aim_point.snapped(Vector3.ONE * 0.01),
					player.get_aim_origin().distance_to(player.aim.aim_point)
				]
			),
			"Line of fire blocked: %s" % player.aim.is_obstructed,
			"Shoulder: %s" % ("right" if player.camera_rig.is_right_shoulder() else "left"),
		]
	)
	_debug.text = "\n".join(lines)


static func _action_key(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var keycode := (
				DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
				if key.physical_keycode != KEY_NONE
				else key.keycode
			)
			return OS.get_keycode_string(keycode)
		if event is InputEventMouseButton:
			return "Mouse %d" % (event as InputEventMouseButton).button_index
	return "?"
