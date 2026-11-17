extends SceneTree
## Writes a BoneMap from Mixamo bone names to Godot's humanoid profile, used by
## the FBX import settings to retarget models and clips onto standard bone
## names (Hips, LeftUpperArm, ...), so characters and animations from
## different sources share one skeleton.
##
## Run: godot --headless --script res://scripts/tools/generate_mixamo_bone_map.gd -- [prefix]
## The prefix differs per Mixamo download (mixamorig_, mixamorig9_, ...).

const DEFAULT_PREFIX := "mixamorig9_"
const OUTPUT := "res://assets/animations/%sbone_map.tres"

## Humanoid profile bone -> Mixamo bone (without prefix).
const MAP := {
	"Hips": "Hips",
	"Spine": "Spine",
	"Chest": "Spine1",
	"UpperChest": "Spine2",
	"Neck": "Neck",
	"Head": "Head",
	"LeftShoulder": "LeftShoulder",
	"LeftUpperArm": "LeftArm",
	"LeftLowerArm": "LeftForeArm",
	"LeftHand": "LeftHand",
	"LeftThumbMetacarpal": "LeftHandThumb1",
	"LeftThumbProximal": "LeftHandThumb2",
	"LeftThumbDistal": "LeftHandThumb3",
	"LeftIndexProximal": "LeftHandIndex1",
	"LeftIndexIntermediate": "LeftHandIndex2",
	"LeftIndexDistal": "LeftHandIndex3",
	"LeftMiddleProximal": "LeftHandMiddle1",
	"LeftMiddleIntermediate": "LeftHandMiddle2",
	"LeftMiddleDistal": "LeftHandMiddle3",
	"LeftRingProximal": "LeftHandRing1",
	"LeftRingIntermediate": "LeftHandRing2",
	"LeftRingDistal": "LeftHandRing3",
	"LeftLittleProximal": "LeftHandPinky1",
	"LeftLittleIntermediate": "LeftHandPinky2",
	"LeftLittleDistal": "LeftHandPinky3",
	"RightShoulder": "RightShoulder",
	"RightUpperArm": "RightArm",
	"RightLowerArm": "RightForeArm",
	"RightHand": "RightHand",
	"RightThumbMetacarpal": "RightHandThumb1",
	"RightThumbProximal": "RightHandThumb2",
	"RightThumbDistal": "RightHandThumb3",
	"RightIndexProximal": "RightHandIndex1",
	"RightIndexIntermediate": "RightHandIndex2",
	"RightIndexDistal": "RightHandIndex3",
	"RightMiddleProximal": "RightHandMiddle1",
	"RightMiddleIntermediate": "RightHandMiddle2",
	"RightMiddleDistal": "RightHandMiddle3",
	"RightRingProximal": "RightHandRing1",
	"RightRingIntermediate": "RightHandRing2",
	"RightRingDistal": "RightHandRing3",
	"RightLittleProximal": "RightHandPinky1",
	"RightLittleIntermediate": "RightHandPinky2",
	"RightLittleDistal": "RightHandPinky3",
	"LeftUpperLeg": "LeftUpLeg",
	"LeftLowerLeg": "LeftLeg",
	"LeftFoot": "LeftFoot",
	"LeftToes": "LeftToeBase",
	"RightUpperLeg": "RightUpLeg",
	"RightLowerLeg": "RightLeg",
	"RightFoot": "RightFoot",
	"RightToes": "RightToeBase",
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if not args.is_empty() else DEFAULT_PREFIX
	var bone_map := BoneMap.new()
	bone_map.profile = SkeletonProfileHumanoid.new()
	for profile_bone: String in MAP:
		bone_map.set_skeleton_bone_name(profile_bone, prefix + MAP[profile_bone])
	var path := OUTPUT % prefix
	var error := ResourceSaver.save(bone_map, path)
	print("Saved %s (error %d)" % [path, error])
	quit(error)
