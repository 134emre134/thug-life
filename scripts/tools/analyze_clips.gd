extends SceneTree
## Measures imported clips on the real character skeleton (forward kinematics),
## to place blend points and contact markers (CLAUDE.md, "Adding Mixamo clips").
##
## Run: godot --headless --script res://scripts/tools/analyze_clips.gd -- <clip> [<clip> ...]
##   <clip> = file name in assets/animations/mixamo/ without extension, or
##   "combat/<name>" for a generated placeholder clip. "--all" lists every clip.
##   Add "--frames" to print a per-frame table.
##
## Per clip it prints:
## - length and loop mode;
## - ground speed: how fast the planted (lowest) foot slides backwards relative
##   to the hips, i.e. the speed the character must move at for the feet to stick;
## - contact candidates: the frames where each hand / foot reaches furthest
##   forward from the hips (strike contact), and the lowest foot after a raise
##   (stomp contact);
## - hip height range (crouch / lying down) and the in-air span (both feet up).
## Character space: the model faces +Z, its right is -X (see CLAUDE.md).

const MODEL := "res://assets/models/player.fbx"
const CLIP_DIR := "res://assets/animations/mixamo/"
const PLACEHOLDERS := "res://assets/animations/combat_placeholder.tres"
const FPS := 30.0
## A foot counts as planted within this height of the lowest foot of the clip.
const PLANT_TOLERANCE := 0.04
## Both feet above their lowest point by this much = airborne.
const AIR_TOLERANCE := 0.12

var _skeleton: Skeleton3D
var _player: AnimationPlayer
## Skeleton transform relative to the model root (the scene isn't in the tree).
var _to_model := Transform3D.IDENTITY


func _initialize() -> void:
	# The player only applies poses inside the tree: run once the tree is up.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var frames := args.has("--frames")
	args.erase("--frames")
	var model := (load(MODEL) as PackedScene).instantiate()
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	var node: Node = _skeleton
	while node != model and node is Node3D:
		_to_model = (node as Node3D).transform * _to_model
		node = node.get_parent()
	root.add_child(model)
	_player = AnimationPlayer.new()
	model.add_child(_player)
	_player.root_node = NodePath("..")
	var clips: PackedStringArray = []
	if args.has("--all"):
		for file in DirAccess.get_files_at(CLIP_DIR):
			if file.ends_with(".fbx"):
				clips.append(file.get_basename())
		var placeholders := load(PLACEHOLDERS) as AnimationLibrary
		for clip in placeholders.get_animation_list():
			clips.append("combat/%s" % clip)
	else:
		clips = args
	for clip in clips:
		_analyze(clip, frames)
	model.free()
	quit()


func _analyze(clip: String, frames: bool) -> void:
	var library_name := clip.get_slice("/", 0) if clip.contains("/") else clip
	var animation_name := clip.get_slice("/", 1) if clip.contains("/") else clip
	var path := PLACEHOLDERS if library_name == "combat" else CLIP_DIR + clip + ".fbx"
	var library := load(path) as AnimationLibrary
	if library == null or not library.has_animation(animation_name):
		print("%s: not found" % clip)
		return
	if _player.has_animation_library(library_name):
		_player.remove_animation_library(library_name)
	_player.add_animation_library(library_name, library)
	var animation := library.get_animation(animation_name)
	var full := "%s/%s" % [library_name, animation_name]
	_player.play(full)
	var count := int(round(animation.length * FPS)) + 1
	var samples: Array[Dictionary] = []
	for i in count:
		var time := minf(i / FPS, animation.length)
		_player.seek(time, true)
		samples.append(_sample(time))
	_player.stop()
	_report(clip, animation, samples, frames)


func _sample(time: float) -> Dictionary:
	var hips := _global(&"Hips")
	return {
		"t": time,
		"hips": hips.origin,
		"hips_up": hips.basis.y.normalized(),
		"head": _global(&"Head").origin,
		"lhand": _global(&"LeftHand").origin,
		"rhand": _global(&"RightHand").origin,
		"lfoot": _global(&"LeftFoot").origin,
		"rfoot": _global(&"RightFoot").origin,
	}


func _global(bone: StringName) -> Transform3D:
	var index := _skeleton.find_bone(bone)
	return _to_model * _skeleton.get_bone_global_pose(index)


func _report(clip: String, animation: Animation, samples: Array[Dictionary], frames: bool) -> void:
	var low_foot := INF
	var hips_min := INF
	var hips_max := -INF
	for s: Dictionary in samples:
		low_foot = minf(low_foot, minf((s["lfoot"] as Vector3).y, (s["rfoot"] as Vector3).y))
		hips_min = minf(hips_min, (s["hips"] as Vector3).y)
		hips_max = maxf(hips_max, (s["hips"] as Vector3).y)
	print(
		(
			"== %s  length %.2f s  loop %s  hips y %.2f..%.2f"
			% [
				clip,
				animation.length,
				animation.loop_mode != Animation.LOOP_NONE,
				hips_min,
				hips_max
			]
		)
	)
	print("   ground speed %.2f m/s" % _ground_speed(samples, low_foot))
	for limb in ["rhand", "lhand", "rfoot", "lfoot"]:
		var best := _furthest_forward(samples, limb)
		print(
			(
				"   %s furthest forward at %.2f s (%.2f m in front of the hips, %.2f m up)"
				% [limb, best["t"], best["forward"], best["up"]]
			)
		)
	for foot in ["rfoot", "lfoot"]:
		var stomp := _stomp(samples, foot)
		if not stomp.is_empty():
			print(
				(
					"   %s stomp: raised %.2f m at %.2f s, down at %.2f s"
					% [foot, stomp["raise"], stomp["raised_at"], stomp["down_at"]]
				)
			)
	var air := _air_span(samples, low_foot)
	if not air.is_empty():
		print("   airborne %.2f..%.2f s" % [air[0], air[1]])
	if frames:
		print(
			"   t     hips_y up_y  head_y  rhand(right,up,fwd)  lhand(right,up,fwd)  rfoot_y lfoot_y"
		)
		for s: Dictionary in samples:
			var hips: Vector3 = s["hips"]
			var r: Vector3 = s["rhand"] - hips
			var l: Vector3 = s["lhand"] - hips
			print(
				(
					"   %.2f  %.2f  %5.2f  %.2f  %5.2f %5.2f %5.2f    %5.2f %5.2f %5.2f    %.2f    %.2f"
					% [
						s["t"],
						hips.y,
						(s["hips_up"] as Vector3).y,
						(s["head"] as Vector3).y,
						-r.x,
						(s["rhand"] as Vector3).y,
						r.z,
						-l.x,
						(s["lhand"] as Vector3).y,
						l.z,
						(s["rfoot"] as Vector3).y,
						(s["lfoot"] as Vector3).y,
					]
				)
			)


## Median backward speed of whichever foot is planted, relative to the hips.
func _ground_speed(samples: Array[Dictionary], low_foot: float) -> float:
	var speeds: Array[float] = []
	for i in range(1, samples.size()):
		for foot in ["lfoot", "rfoot"]:
			var a: Vector3 = samples[i - 1][foot] - samples[i - 1]["hips"]
			var b: Vector3 = samples[i][foot] - samples[i]["hips"]
			var y: float = (samples[i][foot] as Vector3).y
			if y > low_foot + PLANT_TOLERANCE:
				continue
			var dt: float = samples[i]["t"] - samples[i - 1]["t"]
			if dt <= 0.0:
				continue
			speeds.append(Vector2(b.x - a.x, b.z - a.z).length() / dt)
	if speeds.is_empty():
		return 0.0
	speeds.sort()
	return speeds[speeds.size() / 2]


func _furthest_forward(samples: Array[Dictionary], limb: String) -> Dictionary:
	var best := {"t": 0.0, "forward": -INF, "up": 0.0}
	for s: Dictionary in samples:
		var offset: Vector3 = s[limb] - s["hips"]
		if offset.z > best["forward"]:
			best = {"t": s["t"], "forward": offset.z, "up": (s[limb] as Vector3).y}
	return best


## A foot raised clearly above the floor and then brought down hard.
func _stomp(samples: Array[Dictionary], foot: String) -> Dictionary:
	var floor_y := INF
	for s: Dictionary in samples:
		floor_y = minf(floor_y, (s[foot] as Vector3).y)
	var peak := -INF
	var peak_t := 0.0
	for s: Dictionary in samples:
		var y: float = (s[foot] as Vector3).y
		if y > peak:
			peak = y
			peak_t = s["t"]
	if peak - floor_y < 0.25:
		return {}
	for s: Dictionary in samples:
		if s["t"] > peak_t and (s[foot] as Vector3).y <= floor_y + PLANT_TOLERANCE:
			return {"raise": peak - floor_y, "raised_at": peak_t, "down_at": s["t"]}
	return {}


func _air_span(samples: Array[Dictionary], low_foot: float) -> Array[float]:
	var start := -1.0
	var end := -1.0
	for s: Dictionary in samples:
		var l: float = (s["lfoot"] as Vector3).y
		var r: float = (s["rfoot"] as Vector3).y
		var up := minf(l, r) > low_foot + AIR_TOLERANCE
		if up and start < 0.0:
			start = s["t"]
		if up:
			end = s["t"]
	if start < 0.0:
		return []
	return [start, end]
