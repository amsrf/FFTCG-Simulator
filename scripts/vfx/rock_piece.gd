@tool
extends MeshInstance3D
## A centered mesh from an existing rock model; transform stays editor-owned.
@export var source_scene: PackedScene:
	set(value):
		source_scene = value
		if is_inside_tree():
			_update_mesh()

func _ready() -> void:
	_update_mesh()

func _update_mesh() -> void:
	mesh = preload("res://scripts/vfx/rock_mesh_library.gd").get_mesh(source_scene)
