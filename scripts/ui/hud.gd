extends CanvasLayer
## Player HUD (GDD §13): cash, health bar, held weapon, ammo (magazine and
## spare magazines, M4b), soft-target marker, crosshair (while aiming), hit
## marker for landed shots, line-of-fire blocked marker, interaction prompt
## with hold progress, notifications, an inventory overlay (toggle_inventory)
## and a debug readout (debug_toggle; also shows the floating combat labels
## on NPCs).
##
## The inventory overlay pauses the game while it is open (M4a.6, GDD §12:
## decided as temporary, revisit with crime and pursuits in M5). The HUD keeps
## processing while paused. Searching a body is a world action and stays
## real-time (it doesn't open the overlay).

@export var player: Player
@export var notification_time: float = 2.0
## Colour the cash label flashes when cash comes in / goes out.
@export var cash_gain_color: Color = Color(0.45, 1.0, 0.45)
@export var cash_loss_color: Color = Color(1.0, 0.4, 0.35)
## Pause the game while the inventory overlay is open (temporary, M4a.6).
@export var inventory_pauses_game: bool = true
## Seconds the hit marker shows after a landed shot.
@export var hit_marker_time: float = 0.15
@export var hit_marker_color: Color = Color(1.0, 1.0, 1.0, 0.95)
@export var kill_marker_color: Color = Color(1.0, 0.3, 0.25, 1.0)

var _notify_tween: Tween
var _cash_tween: Tween
var _hit_marker_timer: float = 0.0

@onready var _crosshair: Control = $Crosshair
@onready var _blocked_marker: Control = $BlockedMarker
@onready var _prompt: Label = $Prompt
@onready var _notification: Label = $Notification
@onready var _debug: Label = $Debug
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _weapon_label: Label = $HealthBar/Weapon
@onready var _ammo_label: Label = $HealthBar/Ammo
@onready var _hit_marker: Label = $HitMarker
@onready var _target_marker: Label = $TargetMarker
@onready var _cash: Label = $Cash
@onready var _hold_bar: ProgressBar = $Prompt/HoldBar
@onready var _inventory_panel: Control = $InventoryPanel
@onready var _inventory_text: Label = $InventoryPanel/Text


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_crosshair.visible = false
	_blocked_marker.visible = false
	_prompt.visible = false
	_notification.modulate.a = 0.0
	_debug.visible = false
	_target_marker.visible = false
	_hold_bar.visible = false
	_inventory_panel.visible = false
	_hit_marker.visible = false
	CombatDebugLabel.shown = false
	Events.notification_requested.connect(_on_notification)
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Player
	if player:
		player.aim.aiming_changed.connect(func(aiming: bool) -> void: _crosshair.visible = aiming)
		player.interaction.target_changed.connect(_on_target_changed)
		player.health.health_changed.connect(_on_health_changed)
		player.interaction.hold_progress_changed.connect(_on_hold_progress)
		player.inventory.changed.connect(_refresh_inventory)
		player.inventory.cash_changed.connect(_on_cash_changed)
		player.ranged.reload_started.connect(_refresh_inventory)
		player.ranged.reload_finished.connect(_refresh_inventory)
		player.ranged.hit_confirmed.connect(_on_hit_confirmed)
		_on_health_changed(player.health.health, player.health.max_health)
		_refresh_inventory()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle"):
		_debug.visible = not _debug.visible
		CombatDebugLabel.shown = _debug.visible
	elif event.is_action_pressed(&"toggle_inventory"):
		set_inventory_open(not _inventory_panel.visible)


func _exit_tree() -> void:
	if _inventory_panel != null and _inventory_panel.visible and inventory_pauses_game:
		get_tree().paused = false


## Shows or hides the inventory overlay; pauses the game while it is open.
func set_inventory_open(open: bool) -> void:
	_inventory_panel.visible = open
	if inventory_pauses_game:
		get_tree().paused = open


func is_inventory_open() -> bool:
	return _inventory_panel.visible


func _process(delta: float) -> void:
	if player == null:
		return
	if _hit_marker_timer > 0.0:
		_hit_marker_timer -= delta
		_hit_marker.visible = _hit_marker_timer > 0.0
	_update_blocked_marker()
	_update_target_marker()
	var target := player.interaction.current_target
	if is_instance_valid(target) and _prompt.visible:
		var hold := " (hold)" if target.is_hold() else ""
		_prompt.text = "[%s] %s%s" % [_action_key(&"interact"), target.prompt_text, hold]
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


func _update_target_marker() -> void:
	var target := player.combat.current_target
	var camera := player.camera_rig.camera
	var marker_visible := target != null and not player.combat.is_down()
	var point := Vector3.ZERO
	if marker_visible:
		point = target.body.global_position + Vector3.UP * 2.1
		marker_visible = not camera.is_position_behind(point)
	_target_marker.visible = marker_visible
	if marker_visible:
		_target_marker.position = camera.unproject_position(point) - _target_marker.size * 0.5


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_hold_progress(progress: float) -> void:
	_hold_bar.visible = progress > 0.0
	_hold_bar.value = progress


func _on_cash_changed(_cash_now: int, delta: int) -> void:
	if _cash_tween:
		_cash_tween.kill()
	_cash.modulate = cash_gain_color if delta > 0 else cash_loss_color
	_cash_tween = create_tween()
	_cash_tween.tween_property(_cash, "modulate", Color.WHITE, 0.8)


func _refresh_inventory() -> void:
	var inventory := player.inventory
	_cash.text = "$%d" % inventory.cash
	var held := inventory.get_held_weapon()
	var holstered := PackedStringArray()
	for weapon: WeaponData in [inventory.melee, inventory.firearm]:
		if weapon != null and weapon != held:
			holstered.append(weapon.display_name)
	_weapon_label.text = held.display_name if held != null else "Fists"
	if not holstered.is_empty():
		_weapon_label.text += " (%s holstered)" % ", ".join(holstered)
	_ammo_label.text = _ammo_text()
	var lines := PackedStringArray(["INVENTORY", "Cash: $%d" % inventory.cash, ""])
	var melee := "-"
	if inventory.melee != null:
		var melee_state := "in hand" if inventory.melee_drawn else "holstered"
		melee = "%s (%s)" % [inventory.melee.display_name, melee_state]
	lines.append("Melee: %s" % melee)
	var firearm := "-"
	if inventory.firearm != null:
		var firearm_state := "in hand" if inventory.firearm_drawn else "holstered"
		firearm = (
			"%s (%s, %d/%d)"
			% [
				inventory.firearm.display_name,
				firearm_state,
				inventory.firearm_rounds,
				inventory.firearm.magazine_size
			]
		)
	if not inventory.firearm_slot_active:
		firearm = "(locked)"
	lines.append("Firearm: %s" % firearm)
	for i in inventory.pockets.size():
		var item := inventory.pockets[i]
		lines.append("Pocket %d: %s" % [i + 1, item.display_name if item != null else "-"])
	lines.append("")
	lines.append(
		"[%s] holster  [%s] drop" % [_action_key(&"holster_weapon"), _action_key(&"drop_weapon")]
	)
	lines.append(
		(
			"[%s/%s/%s, wheel] switch  [%s] reload"
			% [
				_action_key(&"weapon_unarmed"),
				_action_key(&"weapon_melee"),
				_action_key(&"weapon_firearm"),
				_action_key(&"reload")
			]
		)
	)
	_inventory_text.text = "\n".join(lines)


## "5 / 8  +2" for the drawn firearm (rounds / magazine, spare magazines).
func _ammo_text() -> String:
	var inventory := player.inventory
	var firearm := inventory.firearm if inventory.firearm_drawn else null
	if firearm == null:
		return ""
	if player.ranged.is_reloading:
		return "reloading..."
	var text := "%d / %d" % [inventory.firearm_rounds, firearm.magazine_size]
	return text + "  +%d" % player.ranged.get_magazine_count()


func _on_hit_confirmed(victim: Node3D, result: HurtboxComponent.HitResult) -> void:
	var killed := result == HurtboxComponent.HitResult.KILLED
	_hit_marker.modulate = kill_marker_color if killed else hit_marker_color
	_hit_marker.visible = victim != null
	_hit_marker_timer = hit_marker_time


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
				"Ranged: raised %s  reloading %s  shots %d"
				% [player.ranged.is_raised(), player.ranged.is_reloading, player.ranged.shots_fired]
			),
			"Cover: %s" % CoverComponent.Height.keys()[player.cover.height],
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
	lines.append_array(_combat_debug_lines())
	_debug.text = "\n".join(lines)


func _combat_debug_lines() -> PackedStringArray:
	var c := player.combat
	var lines := PackedStringArray(
		[
			"--- Combat ---",
			"Health: %d / %d" % [ceili(player.health.health), ceili(player.health.max_health)],
			"State: %s  Phase: %s" % [c.state_name, c.phase_name],
			"Attack: %s  Combo: %d" % [String(c.attack.id) if c.attack else "-", c.combo_index + 1],
			"Weapon: %s" % c.get_weapon().display_name,
			"Target: %s" % (String(c.current_target.body.name) if c.current_target else "-"),
			"Clip: %s" % player.animator.combat_clip,
			"Hit stop: %s  Shake: %.2f" % [HitStop.is_active(), player.camera_rig.get_trauma()],
		]
	)
	var director := get_tree().get_first_node_in_group(&"combat_director") as CombatDirector
	if director != null:
		lines.append("Attackers: %d / %d" % [director.get_attacker_count(), director.max_attackers])
		lines.append("Shooters: %d / %d" % [director.get_shooter_count(), director.max_shooters])
	return lines


static func _action_key(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var keycode := key.keycode
			if key.physical_keycode != KEY_NONE:
				keycode = key.physical_keycode
				# Layout-aware name; not supported by the headless display server.
				if DisplayServer.get_name() != "headless":
					keycode = DisplayServer.keyboard_get_keycode_from_physical(keycode)
			return OS.get_keycode_string(keycode)
		if event is InputEventMouseButton:
			return "Mouse %d" % (event as InputEventMouseButton).button_index
	return "?"
