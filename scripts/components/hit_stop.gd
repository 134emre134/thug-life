class_name HitStop
extends RefCounted
## Global hit stop: slows the whole game for a few real milliseconds when a hit
## lands. Overlapping requests extend the stop; the longest one wins.

## Time scale during a hit stop.
const STOP_TIME_SCALE := 0.05

## Timer of the stop that ends last; only it may end the hit stop.
static var _timer: SceneTreeTimer = null
## Identifies that timer in its callback (capturing the timer itself in the
## callback would be a reference cycle and leak every timer).
static var _serial: int = 0


## Freezes the game for [param duration] real seconds.
static func apply(tree: SceneTree, duration: float) -> void:
	if duration <= 0.0 or tree == null:
		return
	if _timer != null and _timer.time_left >= duration:
		return  # a longer stop is already running
	_serial += 1
	var serial := _serial
	_timer = tree.create_timer(duration, true, false, true)
	_timer.timeout.connect(func() -> void: _release(serial))
	Engine.time_scale = STOP_TIME_SCALE


static func is_active() -> bool:
	return _timer != null


## Ends any running hit stop immediately (scene changes, fight restarts).
static func cancel() -> void:
	if _timer != null:
		_timer = null
		Engine.time_scale = 1.0


static func _release(serial: int) -> void:
	if serial == _serial and _timer != null:
		_timer = null
		Engine.time_scale = 1.0
