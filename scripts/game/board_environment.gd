extends MeshInstance3D
## Actual scenery geometry with the approved fixed-camera lighting baked into a texture.
## Raw assets avoid requiring an editor import before headless harness runs.
const GEOMETRY_PATH := "res://assets/board/board_mesh.bin"
const APPEARANCE_PATH := "res://assets/board/board_appearance.png"
const RIVER_SHADER := preload("res://shaders/board_river.gdshader")
const SURFACE_SHADER := preload("res://shaders/board_surface.gdshader")
## Multiplies the baked board (wood, stone, river). 1.0 = the texture as baked; lower = a darker scene.
## The cards are unshaded and unaffected, so they keep their contrast against it.
@export_range(0.2, 1.0, 0.01) var brightness: float = 0.78:
	set(value):
		brightness = value
		_apply_brightness()
## How much darker the far rim is than the play area (0 = flat board). The board and the river share it
## (shaders/board_edge_shade.gdshaderinc), so the eye goes to the cards rather than to bright empty wood.
@export_range(0.0, 1.0, 0.01) var edge_darkness: float = 0.5:
	set(value):
		edge_darkness = value
		_apply_brightness()
var displayed_seat: int = 0
var river: MeshInstance3D
var _board_material: ShaderMaterial
var _river_material: ShaderMaterial

func _ready() -> void:
	configure_seat(1)

func configure_seat(seat: int) -> void:
	var next_seat := 2 if seat == 2 else 1
	if displayed_seat == next_seat:
		return
	var geometry_path := GEOMETRY_PATH.replace(".bin", "_seat2.bin") if next_seat == 2 else GEOMETRY_PATH
	var appearance_path := APPEARANCE_PATH.replace(".png", "_seat2.png") if next_seat == 2 else APPEARANCE_PATH
	var board_mesh := _load_geometry(geometry_path)
	if board_mesh == null:
		return
	var appearance := Image.load_from_file(appearance_path)
	if appearance == null:
		push_error("Board environment appearance missing")
		return
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	var appearance_texture := ImageTexture.create_from_image(appearance)
	material.set_shader_parameter("appearance", appearance_texture)
	board_mesh.surface_set_material(0, material)
	_board_material = material
	mesh = board_mesh
	var river_path := geometry_path.replace("board_mesh", "river_mesh")
	var river_mesh := _load_geometry(river_path)
	if river_mesh == null:
		return
	if river == null:
		river = MeshInstance3D.new()
		river.name = "River"
		add_child(river)
		river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var water := ShaderMaterial.new()
	water.shader = RIVER_SHADER
	water.set_shader_parameter("baked_appearance", appearance_texture)
	water.set_shader_parameter("flow_direction", -1.0 if next_seat == 2 else 1.0)
	water.set_shader_parameter("river_center_z", 0.31 if next_seat == 2 else 0.29)
	river_mesh.surface_set_material(0, water)
	_river_material = water
	_apply_brightness()
	river.mesh = river_mesh
	displayed_seat = next_seat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _apply_brightness() -> void:
	for m in [_board_material, _river_material]:
		if m != null:
			m.set_shader_parameter("brightness", brightness)
			m.set_shader_parameter("edge_darkness", edge_darkness)

func _load_geometry(geometry_path: String) -> ArrayMesh:
	var file := FileAccess.open(geometry_path, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != "BRD1":
		push_error("Board environment geometry missing or invalid")
		return null
	var vertex_count := file.get_32()
	var index_count := file.get_32()
	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()
	positions.resize(vertex_count)
	uvs.resize(vertex_count)
	for i in range(vertex_count):
		positions[i] = Vector3(file.get_float(), file.get_float(), file.get_float())
		uvs[i] = Vector2(file.get_float(), file.get_float())
	var indices := PackedInt32Array()
	indices.resize(index_count)
	for i in range(index_count):
		indices[i] = file.get_32()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var board_mesh := ArrayMesh.new()
	board_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return board_mesh
