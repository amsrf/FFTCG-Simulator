@tool
extends Node3D

signal dust_emitted
## Two editable Model 3 instances move as one column. Only Lift is animated.
var rise_seconds: float:
	get:
		return $AnimationPlayer.get_animation("rise").length
var rise_height: float:
	get:
		return -$AnimationPlayer.get_animation("rise").bezier_track_get_key_value(0, 0)
@export var autoplay := false
@export var rock_material: Material:
	set(value):
		rock_material = value
		if is_inside_tree():
			_apply_material($Lift)
			_apply_material($Debris)
			_apply_material($BaseRocks)

func _ready() -> void:
	_apply_material($Lift)
	_apply_material($Debris)
	_apply_material($BaseRocks)
	if not Engine.is_editor_hint() and autoplay:
		play()

func _apply_material(node: Node) -> void:
	if node is GeometryInstance3D:
		node.material_override = rock_material
	for child in node.get_children():
		_apply_material(child)

func reset() -> void:
	_clear_particles()
	var player: AnimationPlayer = $AnimationPlayer
	player.play("rise")
	player.seek(0.0, true)
	player.pause()

func show_raised() -> void:
	_clear_particles()
	var player: AnimationPlayer = $AnimationPlayer
	player.play("RESET")
	player.advance(0.0)
	player.pause()

func play() -> AnimationPlayer:
	_clear_particles()
	var player: AnimationPlayer = $AnimationPlayer
	player.stop()
	player.play("rise")
	player.advance(0.0)
	return player

## Called by the rise timeline when the column breaks the surface.
func emit_debris() -> void:
	for emitter: GPUParticles3D in $Debris.get_children():
		emitter.visible = true
		emitter.restart()

func emit_dust() -> void:
	for emitter: GPUParticles3D in $Dust.get_children():
		emitter.visible = true
		emitter.restart()

	dust_emitted.emit()

func _clear_particles() -> void:
	for group in [$Debris, $Dust]:
		for emitter: GPUParticles3D in group.get_children():
			emitter.emitting = false
			emitter.visible = false

func retreat() -> AnimationPlayer:
	var player: AnimationPlayer = $AnimationPlayer
	player.play("retreat")
	player.advance(0.0)
	return player
