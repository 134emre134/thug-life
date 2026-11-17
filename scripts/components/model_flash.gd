class_name ModelFlash
extends Node
## Tints a model through material overlays (per instance, never touches the
## shared materials): a short flash when hit, and a steady glow while
## telegraphing an attack (NPC windups).

@export var model: Node3D
@export var hit_color: Color = Color(1.0, 1.0, 1.0, 0.65)
@export var heavy_hit_color: Color = Color(1.0, 0.85, 0.3, 0.8)
@export var hit_time: float = 0.08
@export var telegraph_color: Color = Color(1.0, 0.12, 0.05, 0.5)

var _meshes: Array[GeometryInstance3D] = []
var _hit_material: StandardMaterial3D
var _telegraph_material: StandardMaterial3D
var _hit_timer: float = 0.0
var _telegraph: bool = false


func _ready() -> void:
	_hit_material = _make_material(hit_color)
	_telegraph_material = _make_material(telegraph_color)


func _process(delta: float) -> void:
	if _hit_timer > 0.0:
		_hit_timer -= delta
		if _hit_timer <= 0.0:
			_apply()


func flash_hit(heavy: bool = false) -> void:
	_hit_material.albedo_color = heavy_hit_color if heavy else hit_color
	_hit_timer = hit_time
	_apply()


func set_telegraph(on: bool) -> void:
	if on == _telegraph:
		return
	_telegraph = on
	_apply()


func clear() -> void:
	_hit_timer = 0.0
	_telegraph = false
	_apply()


func _apply() -> void:
	if _meshes.is_empty() and model != null:
		_collect(model)
	var overlay: Material = null
	if _hit_timer > 0.0:
		overlay = _hit_material
	elif _telegraph:
		overlay = _telegraph_material
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = overlay


func _collect(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			_meshes.append(child)
		_collect(child)


static func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	return material
