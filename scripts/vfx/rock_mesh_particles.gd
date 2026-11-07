@tool
extends GPUParticles3D
## Convert the imported FBX hierarchy into a centered, unit-sized particle mesh.
## Emitter settings stay native/editable in ParticleProcessMaterial.
@export var source_scene: PackedScene:
	set(value):
		source_scene = value
		if is_inside_tree():
			_build_draw_mesh()

func _ready() -> void:
	_build_draw_mesh()

func _build_draw_mesh() -> void:
	draw_pass_1 = preload("res://scripts/vfx/rock_mesh_library.gd").get_mesh(source_scene)
