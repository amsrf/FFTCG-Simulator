extends Node3D
class_name GemButtonModel
## Applies the gem-button materials to an instanced `capsule_gx_f.glb` (or any model that has a
## frame mesh and a stone mesh).
##
## Why a script at all: the model is an INSTANCED glb scene, so a `.tscn` cannot reach the
## MeshInstance3D nodes inside it to set `surface_material_override`. This walks to them once and
## does it in code — which also keeps the metal/stone values in one place for the preview scene
## and the real button alike.
##
## Which mesh is the stone? The glb names it `Cylinder.001` and gives it the green material
## (`Material.003`); the frame is `Cube` with the grey one. The node name is checked first and the
## material COLOUR is the fallback, so a re-export that renames things still works.

const FRAME_MATERIAL := preload("res://gem_button_metal.tres")
const STONE_MATERIAL := preload("res://gem_button_stone.tres")

## The frame's material, so a button can dim it on hover/disable.
var frame_material: StandardMaterial3D = null
## The stone's material — a ShaderMaterial, so a button can drive its `emission_strength` to
## switch between the lit stone and the reference's grey "disabled" one.
var stone_material: ShaderMaterial = null

func _ready() -> void:
	apply_materials()

func apply_materials() -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(self, meshes)
	for mi in meshes:
		if _looks_like_stone(mi):
			mi.set_surface_override_material(0, STONE_MATERIAL)
			stone_material = STONE_MATERIAL
		else:
			mi.set_surface_override_material(0, FRAME_MATERIAL)
			frame_material = FRAME_MATERIAL
	print("[GemButtonModel] %d mesh(es): frame=%s stone=%s" % [
		meshes.size(), frame_material != null, stone_material != null])

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		_collect_meshes(child, out)

func _looks_like_stone(mi: MeshInstance3D) -> bool:
	if String(mi.name).to_lower().begins_with("cylinder"):
		return true
	if mi.mesh == null:
		return false
	var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
	if src != null:
		var c: Color = src.albedo_color
		if absf(c.r - c.g) > 0.12 or absf(c.g - c.b) > 0.12:
			return true
	return false
