@tool
extends Node3D
## Absolute-time sprites keep replay, slow motion and preview sampling identical.
const SHADER := preload("res://shaders/ice_conjure.gdshader")
var _sparks: Array[MeshInstance3D] = []
var _mist: Array[MeshInstance3D] = []
var _wisps: Array[MeshInstance3D] = []

func _ready() -> void:
	for i in 24:
		_sparks.append(_sprite(false))
	for i in 14:
		_mist.append(_sprite(true))
	for i in 18:
		_wisps.append(_sprite(false))

func _sprite(is_mist: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	node.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("mist", is_mist)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func _place(node: MeshInstance3D, point: Vector3, size: float, opacity: float, phase: float) -> void:
	node.visible = opacity > 0.001
	node.position = point
	# Billboard shader replaces the basis, so size belongs to the quad itself.
	(node.mesh as QuadMesh).size = Vector2.ONE * size
	node.material_override.set_shader_parameter("opacity", opacity)
	node.material_override.set_shader_parameter("phase", phase)

func sample(seconds: float, forming: float, impact: float, crystal_position: Vector3, crystal_size: float) -> void:
	var progress := clampf(seconds / forming, 0.0, 1.0)
	var front := crystal_position + Vector3.UP * ((1.0 - progress) * 1.65 * crystal_size)
	var envelope := smoothstep(0.0, 0.12, seconds) * (1.0 - smoothstep(forming * 0.85, forming + 0.16, seconds))
	for i in _wisps.size():
		var trail := i % 6
		var angle := seconds * 7.0 + float(i / 6) * TAU / 3.0 - float(trail) * 0.17
		var orbit := Vector3(cos(angle), sin(angle * 1.7) * 0.25, sin(angle)) * 0.10
		orbit.y += float(trail) * 0.014
		var tail_fade := pow(0.65, float(trail))
		_place(_wisps[i], front + orbit, 0.20 * pow(0.90, float(trail)), envelope * tail_fade * 0.85, seconds)
	for i in _sparks.size():
		var cycle := fmod(seconds * 1.7 + float(i) / 24.0, 1.0)
		var angle := float(i) * 2.39996 + cycle * 2.0
		var radius := (1.0 - cycle) * (0.48 + 0.08 * sin(float(i)))
		var point := front + Vector3(cos(angle) * radius, (1.0 - cycle) * sin(float(i) * 4.1) * 0.35, sin(angle) * radius)
		var fade := sin(cycle * PI) * envelope
		_place(_sparks[i], point, 0.025 + cycle * 0.025, fade, seconds)
	for i in _mist.size():
		var cycle := fmod(seconds * 1.25 + float(i) / 14.0, 1.0)
		var angle := float(i) * 2.39996
		var drift := Vector3(cos(angle) * cycle * 0.24, cycle * 0.22, sin(angle) * cycle * 0.24)
		var point := front + drift
		var opacity := sin(cycle * PI) * envelope * 0.32
		var size := lerpf(0.16, 0.48, cycle)
		if seconds >= impact:
			var age := seconds - impact
			point = Vector3(cos(angle) * age * 0.65, 0.035 + age * 0.09, sin(angle) * age * 0.65)
			opacity = (1.0 - smoothstep(0.0, 0.55, age)) * 0.28
			size = 0.18 + age * 0.65
		_place(_mist[i], point, size, opacity, seconds + float(i))
