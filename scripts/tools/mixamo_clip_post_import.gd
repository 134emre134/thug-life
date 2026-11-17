@tool
extends EditorScenePostImport
## Post-import step for single-clip animation files (Mixamo FBX). Used by the
## .import settings of assets/animations/mixamo/**.
##
## - Renames the clip ("mixamo_com") after its file, e.g. walk.fbx -> "walk".
## - Removes horizontal drift of the hips, so clips downloaded without
##   "In Place" still play in place (movement comes from PlayerMovement).
##   The drift speed is printed: it is the clip's real ground speed, which is
##   where its blend-space point belongs.
## - Applies the clip's entry in [constant CLIP_DATA] (M4a, see CLIPS.md):
##   "trim": [start, end] cuts the clip to that span (seconds);
##   "markers": {name: time} adds animation markers (contact frames such as
##   "hit" / "hit_end", "recover", "down", ...) that combat timing is read from;
##   "segments": {name: [start, end]} adds extra animations "<clip>_<name>" to
##   the same library (e.g. a jump's airborne and landing parts).
##   All times are in the source file's time line, before trimming.
## The data file is not an import dependency: after editing it, reimport the
## clip (Import dock -> Reimport; headless: delete its .godot/imported/<clip>.fbx-*
## files and run --import).

const HIPS_TRACK_SUFFIX := ":Hips"
## Ignore drift below this distance (metres): normal sway of in-place clips.
const DRIFT_TOLERANCE := 0.05
const CLIP_DATA := "res://assets/animations/clip_data.json"
## Sample rate used when cutting clips.
const RESAMPLE_FPS := 30.0


func _post_import(scene: Node) -> Object:
	var clip_name := get_source_file().get_file().get_basename()
	var data := _clip_data(clip_name)
	# Retargeting stores position tracks divided by the skeleton's motion scale.
	var motion_scale := 1.0
	for skeleton in scene.find_children("*", "Skeleton3D", true, false):
		motion_scale = (skeleton as Skeleton3D).motion_scale
	for player in scene.find_children("*", "AnimationPlayer", true, false):
		var animation_player := player as AnimationPlayer
		for library_name in animation_player.get_animation_library_list():
			var library := animation_player.get_animation_library(library_name)
			var names := library.get_animation_list()
			for animation_name in names:
				_remove_drift(library.get_animation(animation_name), clip_name, motion_scale)
			if names.size() == 1 and names[0] != StringName(clip_name):
				library.rename_animation(names[0], clip_name)
			if names.size() == 1 and not data.is_empty():
				_apply_data(library, clip_name, data)
	return scene


func _clip_data(clip_name: String) -> Dictionary:
	if not FileAccess.file_exists(CLIP_DATA):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CLIP_DATA))
	if not parsed is Dictionary:
		push_warning("Mixamo import: %s is not a JSON object." % CLIP_DATA)
		return {}
	var entry: Variant = (parsed as Dictionary).get(clip_name, {})
	return entry if entry is Dictionary else {}


func _apply_data(library: AnimationLibrary, clip_name: String, data: Dictionary) -> void:
	var source := library.get_animation(clip_name)
	var segments: Dictionary = data.get("segments", {})
	for segment: String in segments:
		var span: Array = segments[segment]
		var part := _cut(source, span[0], span[1])
		part.loop_mode = Animation.LOOP_NONE
		library.add_animation(StringName("%s_%s" % [clip_name, segment]), part)
	var offset := 0.0
	var clip := source
	if data.has("trim"):
		var trim: Array = data["trim"]
		offset = trim[0]
		clip = _cut(source, trim[0], trim[1])
		clip.loop_mode = source.loop_mode
		library.remove_animation(clip_name)
		library.add_animation(clip_name, clip)
	var markers: Dictionary = data.get("markers", {})
	for marker: String in markers:
		var time := clampf(float(markers[marker]) - offset, 0.0, clip.length)
		clip.add_marker(StringName(marker), time)


## A copy of [param source] between [param start] and [param end] seconds,
## resampled, starting at 0.
func _cut(source: Animation, start: float, end: float) -> Animation:
	start = clampf(start, 0.0, source.length)
	end = clampf(end, start, source.length)
	var cut := Animation.new()
	cut.length = end - start
	var steps := maxi(int(ceil(cut.length * RESAMPLE_FPS)), 1)
	for track in source.get_track_count():
		var type := source.track_get_type(track)
		if (
			type != Animation.TYPE_POSITION_3D
			and type != Animation.TYPE_ROTATION_3D
			and type != Animation.TYPE_SCALE_3D
		):
			continue
		var copy := cut.add_track(type)
		cut.track_set_path(copy, source.track_get_path(track))
		cut.track_set_interpolation_type(copy, source.track_get_interpolation_type(track))
		for step in steps + 1:
			var time := minf(start + step / RESAMPLE_FPS, end)
			var at := time - start
			match type:
				Animation.TYPE_POSITION_3D:
					cut.position_track_insert_key(
						copy, at, source.position_track_interpolate(track, time)
					)
				Animation.TYPE_ROTATION_3D:
					cut.rotation_track_insert_key(
						copy, at, source.rotation_track_interpolate(track, time)
					)
				Animation.TYPE_SCALE_3D:
					cut.scale_track_insert_key(
						copy, at, source.scale_track_interpolate(track, time)
					)
	return cut


func _remove_drift(animation: Animation, clip_name: String, motion_scale: float) -> void:
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		if not String(animation.track_get_path(track)).ends_with(HIPS_TRACK_SUFFIX):
			continue
		var count := animation.track_get_key_count(track)
		if count < 2 or animation.length <= 0.0:
			return
		var first: Vector3 = animation.track_get_key_value(track, 0)
		var last: Vector3 = animation.track_get_key_value(track, count - 1)
		var drift := Vector3(last.x - first.x, 0.0, last.z - first.z)
		var metres := drift.length() * motion_scale
		if metres < DRIFT_TOLERANCE:
			return
		print(
			(
				"Mixamo import: %s drifts %.2f m (%.2f m/s); removed (download 'In Place')."
				% [clip_name, metres, metres / animation.length]
			)
		)
		for key in count:
			var t := animation.track_get_key_time(track, key) / animation.length
			var value: Vector3 = animation.track_get_key_value(track, key)
			animation.track_set_key_value(track, key, value - drift * t)
		return
