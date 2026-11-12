extends Node3D
const MOTION := preload("res://scripts/vfx/wind_card_motion.gd")
const TIMELINE := preload("res://scripts/vfx/wind_tornado.gd")
var _age := 0.0
var _playing := true
var _tier := 1   # damage tier 0..3 (T cycles; --wind-tier=N)

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--wind-cam=game":
			# The match's board camera (game.tscn): orthographic, ~80 degrees down. The tornado sits where
			# a card in the middle of the board would be.
			$Camera3D.transform = Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 0.173648, 0.984808),
				Vector3(0, 0.984808, -0.173648)), Vector3(0, 4.346, -0.86))
			$Camera3D.size = 5.766
		if argument.begins_with("--wind-tier="):
			_tier = clampi(argument.trim_prefix("--wind-tier=").to_int(), 0, 3)
		if argument.begins_with("--wind-time="):
			_playing = false
			$WindTornado.reset()
			_age = argument.trim_prefix("--wind-time=").to_float()
			_sample(_age)

func _process(delta: float) -> void:
	# Re-sample even when frozen: the camera lean is read from the CURRENT camera, which is not yet current
	# during _ready().
	if _playing:
		_age += delta
	_sample(_age)

func _sample(seconds: float) -> void:
	$WindTornado.set_damage_tier(_tier)
	$WindTornado.sample(seconds)
	$CardSizeReference.transform = MOTION.pose_at(seconds, TIMELINE.card_height_for(_tier), 0.0,
		TIMELINE.length_for(_tier))
	$CardSizeReference.position.y += 0.018

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_age = 0.0
			_playing = true
		KEY_R:
			_playing = false
			_age = MOTION.total_for(TIMELINE.length_for(_tier))   # rest pose: tornado gone, card landed
		KEY_T:
			_tier = (_tier + 1) % 4
			print("wind tier %d: height x%.2f, %.1f s" % [_tier, TIMELINE.height_for(_tier), TIMELINE.length_for(_tier)])
			_age = 0.0
			_playing = true
		KEY_2:
			Engine.time_scale = 0.25 if is_equal_approx(Engine.time_scale, 1.0) else 1.0

func _exit_tree() -> void:
	Engine.time_scale = 1.0
