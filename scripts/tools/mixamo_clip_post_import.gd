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

const HIPS_TRACK_SUFFIX := ":Hips"
## Ignore drift below this distance (metres): normal sway of in-place clips.
const DRIFT_TOLERANCE := 0.05


func _post_import(scene: Node) -> Object:
	var clip_name := get_source_file().get_file().get_basename()
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
	return scene


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
