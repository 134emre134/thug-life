class_name CombatAudio
extends AudioStreamPlayer3D
## Impact sounds for hits taken by a character. Until real sounds exist, the
## placeholders are synthesized at startup (no audio files): a short, bright
## slap for light hits, a deep long thud for heavy ones and a dry clack for
## blocks. [member AttackData.hit_sound] overrides the placeholder.

@export var combat: MeleeCombat

@export_group("Light hit")
@export var light_frequency: float = 260.0
@export var light_length: float = 0.09
@export_range(0.0, 1.0) var light_noise: float = 0.65
@export var light_volume_db: float = -4.0

@export_group("Heavy hit")
@export var heavy_frequency: float = 65.0
@export var heavy_length: float = 0.38
@export_range(0.0, 1.0) var heavy_noise: float = 0.3
@export var heavy_volume_db: float = 2.0

@export_group("Block")
@export var block_frequency: float = 1100.0
@export var block_length: float = 0.06
@export_range(0.0, 1.0) var block_noise: float = 0.25
@export var block_volume_db: float = -6.0

@export_group("Synthesis")
@export var mix_rate: int = 22050

var _light: AudioStreamWAV
var _heavy: AudioStreamWAV
var _block: AudioStreamWAV


func _ready() -> void:
	_light = synthesize(light_frequency, light_length, light_noise, 1)
	_heavy = synthesize(heavy_frequency, heavy_length, heavy_noise, 2)
	_block = synthesize(block_frequency, block_length, block_noise, 3)
	if combat != null:
		combat.hit_taken.connect(_on_hit_taken)


## A decaying sine (with a pitch drop) mixed with noise, as 16-bit mono PCM.
func synthesize(frequency: float, length: float, noise: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count := maxi(int(length * mix_rate), 1)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / mix_rate
		var progress := float(i) / count
		var envelope := exp(-5.0 * progress) * minf(t * 2000.0, 1.0)
		phase += TAU * frequency * (1.0 - 0.5 * progress) / mix_rate
		var sample := sin(phase) * (1.0 - noise) + rng.randf_range(-1.0, 1.0) * noise
		data.encode_s16(i * 2, int(clampf(sample * envelope, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream


func _on_hit_taken(
	_attacker: Node3D, attack: AttackData, result: HurtboxComponent.HitResult
) -> void:
	match result:
		HurtboxComponent.HitResult.BLOCKED:
			_play(_block, block_volume_db)
		HurtboxComponent.HitResult.IGNORED, HurtboxComponent.HitResult.DODGED:
			return
		_:
			if attack.hit_sound != null:
				_play(attack.hit_sound, 0.0)
			elif attack.is_heavy() or result == HurtboxComponent.HitResult.KNOCKED_OUT:
				_play(_heavy, heavy_volume_db)
			else:
				_play(_light, light_volume_db)


func _play(sound: AudioStream, volume: float) -> void:
	stream = sound
	volume_db = volume
	play()
