extends SceneTree
## Generates the placeholder combat clips for the primitive mannequin
## (res://assets/animations/mannequin_combat.tres). Temporary, like the
## mannequin itself: the Mixamo clips replace these (CLAUDE.md, M2.1).
##
## Run: godot --headless --script res://scripts/tools/generate_combat_clips.gd
##
## Key times of attack clips match the clip_hit_time of the AttackData that
## uses them (data/attacks/*.tres).

const OUTPUT := "res://assets/animations/mannequin_combat.tres"

const HIPS_POS := "Hips:position"
const HIPS_ROT := "Hips:rotation"
const TORSO := "Hips/Torso:rotation"
const HEAD := "Hips/Torso/Head:rotation"
const ARM_L := "Hips/Torso/ArmL:rotation"
const ARM_R := "Hips/Torso/ArmR:rotation"
const LEG_L := "Hips/LegL:rotation"
const LEG_R := "Hips/LegR:rotation"
const LEG_L_POS := "Hips/LegL:position"
const LEG_R_POS := "Hips/LegR:position"

## Every combat clip animates all of these, so blends between clips are defined.
const NEUTRAL := {
	HIPS_POS: Vector3(0, 0.895, 0),
	HIPS_ROT: Vector3.ZERO,
	TORSO: Vector3.ZERO,
	HEAD: Vector3.ZERO,
	ARM_L: Vector3(0, 0, -0.1),
	ARM_R: Vector3(0, 0, 0.1),
	LEG_L: Vector3(0, 0, -0.03),
	LEG_R: Vector3(0, 0, 0.03),
	LEG_L_POS: Vector3(-0.12, 0, 0),
	LEG_R_POS: Vector3(0.12, 0, 0),
}

## Fighting stance: hands up, left foot forward.
const STANCE := {
	HIPS_POS: Vector3(0, 0.88, 0),
	TORSO: Vector3(-0.08, 0, 0),
	HEAD: Vector3(-0.05, 0, 0),
	ARM_L: Vector3(1.0, -0.35, -0.15),
	ARM_R: Vector3(0.9, 0.35, 0.15),
	LEG_L: Vector3(0.2, 0, -0.05),
	LEG_R: Vector3(-0.15, 0, 0.05),
}

## Lying on the back (end of knockdown, start of get-up).
const LYING := {
	HIPS_POS: Vector3(0, 0.12, 0.55),
	HIPS_ROT: Vector3(1.5, 0, 0),
	HEAD: Vector3(-0.25, 0, 0),
	ARM_L: Vector3(0.3, 0, -0.6),
	ARM_R: Vector3(0.3, 0, 0.6),
	LEG_L: Vector3(0.1, 0, -0.1),
	LEG_R: Vector3(-0.05, 0, 0.12),
}


func _initialize() -> void:
	var library := AnimationLibrary.new()
	for clip in _clips():
		library.add_animation(clip.resource_name, clip)
	var error := ResourceSaver.save(library, OUTPUT)
	print("Saved %d clips to %s (error %d)" % [library.get_animation_list().size(), OUTPUT, error])
	quit(error)


func _clips() -> Array[Animation]:
	var clips: Array[Animation] = []
	# --- Unarmed attacks -------------------------------------------------
	(
		clips
		. append(
			_clip(
				"punch_1",
				0.42,
				[
					[0.0, STANCE],
					[
						0.06,
						_with(
							STANCE,
							{ARM_L: Vector3(0.8, -0.3, -0.2), TORSO: Vector3(-0.05, 0.15, 0)}
						)
					],
					[
						0.10,
						_with(
							STANCE,
							{
								ARM_L: Vector3(1.57, -0.12, 0),
								TORSO: Vector3(-0.1, -0.35, 0),
								HIPS_POS: Vector3(0, 0.86, 0),
								LEG_L: Vector3(0.3, 0, -0.05),
							}
						)
					],
					[
						0.18,
						_with(
							STANCE, {ARM_L: Vector3(1.5, -0.12, 0), TORSO: Vector3(-0.1, -0.3, 0)}
						)
					],
					[0.42, STANCE],
				]
			)
		)
	)
	(
		clips
		. append(
			_clip(
				"punch_2",
				0.46,
				[
					[0.0, STANCE],
					[
						0.07,
						_with(STANCE, {ARM_R: Vector3(0.7, 0.3, 0.2), TORSO: Vector3(0, -0.25, 0)})
					],
					[
						0.12,
						_with(
							STANCE,
							{
								ARM_R: Vector3(1.57, 0.12, 0),
								TORSO: Vector3(-0.12, 0.45, 0),
								HIPS_POS: Vector3(0, 0.85, 0),
								LEG_R: Vector3(-0.3, 0, 0.05),
							}
						)
					],
					[
						0.2,
						_with(STANCE, {ARM_R: Vector3(1.5, 0.12, 0), TORSO: Vector3(-0.1, 0.4, 0)})
					],
					[0.46, STANCE],
				]
			)
		)
	)
	(
		clips
		. append(
			_clip(
				"punch_3",
				0.64,
				[
					[0.0, STANCE],
					[
						0.1,
						_with(
							STANCE,
							{
								ARM_R: Vector3(1.3, -0.9, 0.4),
								TORSO: Vector3(0, -0.55, 0),
								HIPS_POS: Vector3(0, 0.84, 0),
							}
						)
					],
					[
						0.16,
						_with(
							STANCE,
							{
								ARM_R: Vector3(1.45, 0.55, 0),
								TORSO: Vector3(-0.15, 0.6, 0),
								HIPS_POS: Vector3(0, 0.85, 0),
							}
						)
					],
					[
						0.26,
						_with(STANCE, {ARM_R: Vector3(1.3, 0.9, 0), TORSO: Vector3(-0.1, 0.75, 0)})
					],
					[0.64, STANCE],
				]
			)
		)
	)
	var heavy_windup := _with(
		STANCE,
		{
			ARM_R: Vector3(-0.5, 0, 0.3),
			ARM_L: Vector3(1.2, -0.5, -0.2),
			TORSO: Vector3(0.05, -0.8, 0),
			HIPS_POS: Vector3(0, 0.8, 0.1),
			LEG_L: Vector3(0.45, 0, -0.05),
			LEG_R: Vector3(-0.35, 0, 0.05),
		}
	)
	(
		clips
		. append(
			_clip(
				"punch_heavy",
				1.04,
				[
					[0.0, STANCE],
					[0.3, heavy_windup],
					[0.38, heavy_windup],
					[
						0.42,
						_with(
							STANCE,
							{
								ARM_R: Vector3(1.8, 0.1, 0),
								TORSO: Vector3(-0.25, 0.5, 0),
								HIPS_POS: Vector3(0, 0.86, -0.15),
								LEG_R: Vector3(-0.5, 0, 0.05),
							}
						)
					],
					[
						0.6,
						_with(STANCE, {ARM_R: Vector3(2.0, 0.2, 0), TORSO: Vector3(-0.2, 0.45, 0)})
					],
					[1.04, STANCE],
				]
			)
		)
	)
	# --- Bat attacks (bat extends the right arm) --------------------------
	(
		clips
		. append(
			_clip(
				"bat_1",
				0.6,
				[
					[0.0, STANCE],
					[
						0.12,
						_with(
							STANCE,
							{
								ARM_R: Vector3(1.45, -1.3, 0),
								ARM_L: Vector3(1.0, -0.2, 0),
								TORSO: Vector3(0, -0.6, 0),
							}
						)
					],
					[
						0.18,
						_with(STANCE, {ARM_R: Vector3(1.5, 0, 0), TORSO: Vector3(-0.05, 0.1, 0)})
					],
					[
						0.28,
						_with(STANCE, {ARM_R: Vector3(1.45, 1.0, 0), TORSO: Vector3(-0.05, 0.6, 0)})
					],
					[0.6, STANCE],
				]
			)
		)
	)
	var backhand_start := _with(STANCE, {ARM_R: Vector3(1.45, 0.9, 0), TORSO: Vector3(0, 0.5, 0)})
	(
		clips
		. append(
			_clip(
				"bat_2",
				0.64,
				[
					[0.0, backhand_start],
					[0.14, _with(STANCE, {ARM_R: Vector3(1.5, 1.2, 0), TORSO: Vector3(0, 0.7, 0)})],
					[
						0.2,
						_with(STANCE, {ARM_R: Vector3(1.5, 0, 0), TORSO: Vector3(-0.05, -0.1, 0)})
					],
					[
						0.3,
						_with(STANCE, {ARM_R: Vector3(1.4, -1.0, 0), TORSO: Vector3(0, -0.6, 0)})
					],
					[0.64, STANCE],
				]
			)
		)
	)
	(
		clips
		. append(
			_clip(
				"bat_3",
				0.88,
				[
					[0.0, STANCE],
					[
						0.2,
						_with(
							STANCE,
							{
								ARM_R: Vector3(2.9, 0.2, 0),
								ARM_L: Vector3(2.6, -0.2, 0),
								TORSO: Vector3(0.2, 0, 0),
								HIPS_POS: Vector3(0, 0.9, 0),
							}
						)
					],
					[
						0.26,
						_with(
							STANCE,
							{
								ARM_R: Vector3(1.2, 0.1, 0),
								ARM_L: Vector3(1.0, -0.1, 0),
								TORSO: Vector3(-0.35, 0, 0),
								HIPS_POS: Vector3(0, 0.82, -0.1),
								LEG_L: Vector3(0.4, 0, -0.05),
								LEG_R: Vector3(-0.3, 0, 0.05),
							}
						)
					],
					[
						0.36,
						_with(STANCE, {ARM_R: Vector3(0.8, 0.1, 0), TORSO: Vector3(-0.3, 0, 0)})
					],
					[0.88, STANCE],
				]
			)
		)
	)
	var bat_heavy_windup := _with(
		STANCE,
		{
			ARM_R: Vector3(1.4, -1.9, 0.2),
			TORSO: Vector3(0.05, -1.0, 0),
			HIPS_POS: Vector3(0, 0.82, 0),
			LEG_L: Vector3(0.3, 0, -0.05),
			LEG_R: Vector3(-0.3, 0, 0.05),
		}
	)
	(
		clips
		. append(
			_clip(
				"bat_heavy",
				1.29,
				[
					[0.0, STANCE],
					[0.4, bat_heavy_windup],
					[0.5, bat_heavy_windup],
					[
						0.55,
						_with(STANCE, {ARM_R: Vector3(1.5, 0.1, 0), TORSO: Vector3(-0.1, 0.2, 0)})
					],
					[
						0.7,
						_with(
							STANCE,
							{
								ARM_R: Vector3(1.4, 1.4, 0),
								TORSO: Vector3(-0.1, 1.0, 0),
								HIPS_POS: Vector3(0, 0.84, -0.2),
							}
						)
					],
					[1.29, STANCE],
				]
			)
		)
	)
	# --- Guard poses (upper body, looped) ---------------------------------
	(
		clips
		. append(
			_pose_clip(
				"guard",
				_with(
					STANCE,
					{
						ARM_L: Vector3(2.2, -0.5, -0.1),
						ARM_R: Vector3(2.2, 0.5, 0.1),
						TORSO: Vector3(-0.12, 0, 0),
						HEAD: Vector3(-0.15, 0, 0),
					}
				)
			)
		)
	)
	(
		clips
		. append(
			_pose_clip(
				"bat_guard",
				_with(
					STANCE,
					{
						ARM_L: Vector3(2.1, -0.5, 0),
						ARM_R: Vector3(1.9, 0.85, 0),
						TORSO: Vector3(-0.12, 0, 0),
						HEAD: Vector3(-0.15, 0, 0),
					}
				)
			)
		)
	)
	# --- Dodge -------------------------------------------------------------
	# Direction-neutral: dodges go back or sideways, so no forward lean.
	var duck := _with(
		STANCE,
		{
			HIPS_POS: Vector3(0, 0.78, 0),
			TORSO: Vector3(-0.15, 0, 0),
			HEAD: Vector3(-0.2, 0, 0),
			ARM_L: Vector3(2.0, -0.5, -0.1),
			ARM_R: Vector3(2.0, 0.5, 0.1),
			LEG_L: Vector3(0.35, 0, -0.2),
			LEG_R: Vector3(-0.3, 0, 0.2),
		}
	)
	clips.append(_clip("dodge", 0.35, [[0.0, STANCE], [0.08, duck], [0.22, duck], [0.35, STANCE]]))
	# --- Hit reactions -----------------------------------------------------
	(
		clips
		. append(
			_clip(
				"flinch",
				0.35,
				[
					[0.0, STANCE],
					[
						0.06,
						_with(
							STANCE,
							{
								HEAD: Vector3(0.45, 0, 0),
								TORSO: Vector3(0.25, 0.1, 0),
								ARM_L: Vector3(0.5, -0.2, -0.4),
								ARM_R: Vector3(0.4, 0.2, 0.4),
							}
						)
					],
					[0.35, STANCE],
				]
			)
		)
	)
	(
		clips
		. append(
			_clip(
				"stagger",
				0.8,
				[
					[0.0, STANCE],
					[
						0.1,
						_with(
							STANCE,
							{
								TORSO: Vector3(0.45, -0.2, 0),
								HEAD: Vector3(0.5, 0, 0),
								HIPS_POS: Vector3(0, 0.86, 0.15),
								ARM_L: Vector3(0.8, 0, -0.8),
								ARM_R: Vector3(0.6, 0, 0.9),
								LEG_L: Vector3(0.25, 0, -0.05),
								LEG_R: Vector3(-0.35, 0, 0.05),
							}
						)
					],
					[
						0.35,
						_with(
							STANCE,
							{
								TORSO: Vector3(0.3, 0.15, 0),
								HEAD: Vector3(0.3, 0, 0),
								HIPS_POS: Vector3(0, 0.86, 0.3),
								ARM_L: Vector3(0.6, 0, -0.6),
								ARM_R: Vector3(0.5, 0, 0.6),
								LEG_L: Vector3(-0.3, 0, -0.05),
								LEG_R: Vector3(0.2, 0, 0.05),
							}
						)
					],
					[0.8, STANCE],
				]
			)
		)
	)
	(
		clips
		. append(
			_clip(
				"knockdown",
				0.5,
				[
					[0.0, STANCE],
					[
						0.15,
						_with(
							STANCE,
							{
								TORSO: Vector3(0.4, 0, 0),
								HEAD: Vector3(0.4, 0, 0),
								HIPS_POS: Vector3(0, 0.75, 0.2),
								HIPS_ROT: Vector3(0.3, 0, 0),
								ARM_L: Vector3(1.0, 0, -1.0),
								ARM_R: Vector3(1.0, 0, 1.0),
							}
						)
					],
					[0.5, _with(NEUTRAL, LYING)],
				]
			)
		)
	)
	(
		clips
		. append(
			_clip(
				"get_up",
				0.9,
				[
					[0.0, _with(NEUTRAL, LYING)],
					[
						0.3,
						_with(
							NEUTRAL,
							{
								HIPS_POS: Vector3(0, 0.12, 0.35),
								TORSO: Vector3(-0.2, 0, 0),
								ARM_L: Vector3(-0.5, 0, -0.3),
								ARM_R: Vector3(-0.5, 0, 0.3),
								LEG_L: Vector3(1.5, 0, -0.05),
								LEG_R: Vector3(1.3, 0, 0.05),
							}
						)
					],
					[
						0.6,
						_with(
							NEUTRAL,
							{
								HIPS_POS: Vector3(0, 0.55, 0.15),
								TORSO: Vector3(-0.5, 0, 0),
								ARM_L: Vector3(0.6, 0, -0.3),
								ARM_R: Vector3(0.6, 0, 0.3),
								LEG_L: Vector3(0.9, 0, -0.05),
								LEG_R: Vector3(0.6, 0, 0.05),
							}
						)
					],
					[0.9, STANCE],
				]
			)
		)
	)
	return clips


## [param base] with [param overrides] applied, on top of [constant NEUTRAL].
func _with(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var pose := NEUTRAL.duplicate()
	pose.merge(base, true)
	pose.merge(overrides, true)
	return pose


## A clip from [time, pose] keys. Tracks missing in a pose use the stance.
func _clip(clip_name: String, length: float, keys: Array) -> Animation:
	var animation := Animation.new()
	animation.resource_name = clip_name
	animation.length = length
	animation.loop_mode = Animation.LOOP_NONE
	for path: String in NEUTRAL:
		var track := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, NodePath(path))
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		animation.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
		for key: Array in keys:
			var pose := _with(STANCE, key[1])
			animation.track_insert_key(track, key[0], pose[path])
	return animation


## A looping, static pose.
func _pose_clip(clip_name: String, pose: Dictionary) -> Animation:
	var animation := _clip(clip_name, 0.5, [[0.0, pose], [0.5, pose]])
	animation.loop_mode = Animation.LOOP_LINEAR
	return animation
