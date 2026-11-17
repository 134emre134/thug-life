class_name FirearmEffects
extends Node3D
## Shot feedback for one character's [RangedCombat] (M4b.1), all gray-box and
## generated at runtime (no assets): a muzzle flash (light + glowing quad), a
## tracer from the muzzle to where the shot ended, an impact puff, a
## synthesized gunshot (and a dry click on an empty magazine), and the NPC aim
## telegraph: a red laser from the muzzle to the aim point that brightens
## until the shot (M4b.4, shots must be readable).
##
## Effect nodes are top-level children of this node, so they stay where they
## were spawned while the character moves.

@export var ranged: RangedCombat

@export_group("Muzzle flash")
@export var flash_color: Color = Color(1.0, 0.75, 0.35)
@export var flash_time: float = 0.05
@export var flash_size: float = 0.22
@export var flash_light_energy: float = 3.0

@export_group("Tracer")
@export var tracer_color: Color = Color(1.0, 0.9, 0.6, 0.9)
@export var tracer_width: float = 0.025
@export var tracer_time: float = 0.07
@export var impact_color: Color = Color(0.85, 0.8, 0.7, 0.9)
@export var impact_size: float = 0.12
@export var impact_time: float = 0.15

@export_group("Telegraph")
@export var laser_color: Color = Color(1.0, 0.1, 0.05, 0.35)
@export var laser_full_color: Color = Color(1.0, 0.15, 0.05, 0.95)
@export var laser_width: float = 0.018
## Seconds for the laser to reach full brightness.
@export var laser_ramp_time: float = 0.8

@export_group("Sound")
@export var shot_volume_db: float = 4.0
@export var shot_length: float = 0.22
@export var click_volume_db: float = -8.0
@export var mix_rate: int = 22050

var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_timer: float = 0.0
var _laser: MeshInstance3D
var _laser_material: StandardMaterial3D
var _laser_time: float = 0.0
var _audio: AudioStreamPlayer3D
var _shot_sound: AudioStreamWAV
var _click_sound: AudioStreamWAV


func _ready() -> void:
	_flash = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * flash_size
	quad.material = _unshaded(flash_color, true)
	_flash.mesh = quad
	_flash.top_level = true
	_flash.visible = false
	add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = flash_color
	_flash_light.light_energy = flash_light_energy
	_flash_light.omni_range = 4.0
	_flash_light.top_level = true
	_flash_light.visible = false
	add_child(_flash_light)
	_laser = MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(laser_width, laser_width, 1.0)
	_laser_material = _unshaded(laser_color, false)
	beam.material = _laser_material
	_laser.mesh = beam
	_laser.top_level = true
	_laser.visible = false
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_laser)
	_audio = AudioStreamPlayer3D.new()
	add_child(_audio)
	_shot_sound = _synthesize(shot_length, 0.85, 90.0, 1)
	_click_sound = _synthesize(0.03, 0.2, 1800.0, 2)
	if ranged != null:
		ranged.shot_traced.connect(_on_shot_traced)
		ranged.dry_fired.connect(_on_dry_fired)
		ranged.telegraph_changed.connect(_on_telegraph_changed)


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash.visible = false
			_flash_light.visible = false
	if _laser.visible:
		_laser_time += delta
		_update_laser()


func is_laser_visible() -> bool:
	return _laser.visible


func _on_shot_traced(from: Vector3, to: Vector3, normal: Vector3, hit_character: bool) -> void:
	_flash.global_position = from
	var camera := get_viewport().get_camera_3d()
	if camera != null and not from.is_equal_approx(camera.global_position):
		_flash.look_at(camera.global_position)
	_flash.visible = true
	_flash_light.global_position = from
	_flash_light.visible = true
	_flash_timer = flash_time
	_spawn_beam(from, to, tracer_width, tracer_color, tracer_time)
	if normal != Vector3.ZERO or hit_character:
		var color := Color(0.6, 0.05, 0.05, 0.9) if hit_character else impact_color
		_spawn_puff(to, color)
	if ranged != null and ranged.get_weapon() != null and ranged.get_weapon().shot_sound != null:
		_play(ranged.get_weapon().shot_sound, shot_volume_db)
	else:
		_play(_shot_sound, shot_volume_db)


func _on_dry_fired() -> void:
	_play(_click_sound, click_volume_db)


func _on_telegraph_changed(on: bool) -> void:
	_laser.visible = on
	_laser_time = 0.0
	if on:
		_update_laser()


func _update_laser() -> void:
	if ranged == null:
		return
	var from := ranged.get_muzzle_position()
	var to := ranged.aim_point
	if from.distance_to(to) < 0.05:
		_laser.visible = false
		return
	_place_beam(_laser, from, to)
	var t := clampf(_laser_time / laser_ramp_time, 0.0, 1.0) if laser_ramp_time > 0.0 else 1.0
	_laser_material.albedo_color = laser_color.lerp(laser_full_color, t)


func _spawn_beam(from: Vector3, to: Vector3, width: float, color: Color, time: float) -> void:
	if from.distance_to(to) < 0.05:
		return
	var beam := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, 1.0)
	var material := _unshaded(color, false)
	mesh.material = material
	beam.mesh = mesh
	beam.top_level = true
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	_place_beam(beam, from, to)
	_fade_out(beam, material, time)


func _spawn_puff(at: Vector3, color: Color) -> void:
	var puff := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = impact_size * 0.5
	mesh.height = impact_size
	var material := _unshaded(color, false)
	mesh.material = material
	puff.mesh = mesh
	puff.top_level = true
	add_child(puff)
	puff.global_position = at
	_fade_out(puff, material, impact_time)


## Stretches a unit-length box from [param from] to [param to].
func _place_beam(beam: Node3D, from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	var forward := (to - from) / length
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var beam_basis := Basis.looking_at(forward, up).scaled(Vector3(1.0, 1.0, length))
	beam.global_transform = Transform3D(beam_basis, (from + to) * 0.5)


func _fade_out(node: Node3D, material: StandardMaterial3D, time: float) -> void:
	var tween := node.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, time)
	tween.tween_callback(node.queue_free)


func _play(sound: AudioStream, volume: float) -> void:
	_audio.stream = sound
	_audio.volume_db = volume
	_audio.play()


static func _unshaded(color: Color, additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return material


## A noise burst with a low thump (gunshot) or a short tick (dry fire), as
## 16-bit mono PCM.
func _synthesize(length: float, noise: float, frequency: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count := maxi(int(length * mix_rate), 1)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var progress := float(i) / count
		var envelope := exp(-9.0 * progress)
		phase += TAU * frequency * (1.0 - 0.6 * progress) / mix_rate
		var sample := sin(phase) * (1.0 - noise) + rng.randf_range(-1.0, 1.0) * noise
		data.encode_s16(i * 2, int(clampf(sample * envelope, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav
