extends Node3D
## Viewing harness for a Character MATERIALISING on the field (Card.teleport.play_in, card_teleport.gd): the two-layer
## crystal triangle build, the glow beat, the shard burst and the reveal, at the game's own Field durations.
##   Space  replay            2  slow motion (x0.25)
##   C      crystal triangles / plain squares
##   D      build from the top / from the bottom
##   E      next card (another element)
##   V      camera: board (the game's ~80 degree view) / straight down / low side view
## Screenshots: tools/shot.tscn ... -- --scene res://tools/materialize_demo.tscn --as-scene 1 --mat-time=<seconds>
## freezes the timeline at that moment (and --mat-squares / --mat-bottom select the variants; --mat-shards=<0..1>
## also shows the crystal burst frozen at that point; --mat-cam=board|top|side picks the camera).

const CARD_SCENE := preload("res://scenes/cards/card.tscn")
const TELEPORT := preload("res://scripts/cards/card_teleport.gd")
## One card per element for E (card ids from the database; the first is the default).
const CARD_IDS := [25, 1, 40, 60, 80, 100, 120, 140]
## The Field's exported durations (battle_field.gd teleport_*_seconds).
const BUILD := 0.9
const GLOW := 0.18
const REVEAL := 0.30

var _card: Card = null
var _card_index := 0
var _from_top := true
var _frozen_at := -1.0
var _shards_at := -1.0   # --mat-shards=<0..1>: freeze the shard burst at that point (alignment check)
var _label: Label
var _camera: Camera3D
## Camera pitch in degrees per view. "board" is the match camera's angle, which is what the effect must read from.
const VIEWS := {"board": -80.0, "top": -90.0, "side": -32.0}
var _view := "board"

func _ready() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 1.2
	add_child(_camera)
	_camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.13, 0.14, 0.17)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.3
	add_child(env)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	layer.add_child(_label)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mat-time="):
			_frozen_at = argument.trim_prefix("--mat-time=").to_float()
		elif argument.begins_with("--mat-shards="):
			_shards_at = argument.trim_prefix("--mat-shards=").to_float()
		elif argument == "--mat-squares":
			TELEPORT.crystal_build = false
		elif argument == "--mat-bottom":
			_from_top = false
		elif argument.begins_with("--mat-cam=") and VIEWS.has(argument.trim_prefix("--mat-cam=")):
			_view = argument.trim_prefix("--mat-cam=")
	_aim_camera()
	_play()

func _aim_camera() -> void:
	# Field cards carry a half turn, so the camera is yawed 180 to read them upright.
	_camera.rotation_degrees = Vector3(VIEWS[_view], 180.0, 0.0)
	_camera.position = _camera.basis.z * 3.0 + Vector3.UP * 0.1

func _play() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = CARD_SCENE.instantiate()
	add_child(_card)
	_card.initialize(CARD_IDS[_card_index], "player")
	_card.enter_zone(Card.Zone.FIELD)
	_card.position = Vector3.ZERO
	_card.scale = Vector3.ONE * 1.4
	var tween: Tween = _card.teleport.play_in(BUILD, GLOW, REVEAL)
	_card.mat.set_shader_parameter("teleport_build_from_top", _from_top)
	if is_instance_valid(_card.teleport.crystals):
		_card.teleport.crystals.from_top = _from_top
	if _frozen_at >= 0.0:
		tween.pause()
		tween.custom_step(_frozen_at)
		var crystals = _card.teleport.crystals
		if _shards_at >= 0.0 and is_instance_valid(crystals):
			crystals._sample_shatter(_shards_at)
	_label.text = "%s  |  %s  |  from the %s  |  Space replay  2 slow  C crystal/squares  D direction  E next card  V camera" % [
		_card.card_name if "card_name" in _card else str(CARD_IDS[_card_index]),
		"crystal triangles" if TELEPORT.crystal_build else "plain squares",
		"top" if _from_top else "bottom"]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_play()
		KEY_2:
			Engine.time_scale = 0.25 if is_equal_approx(Engine.time_scale, 1.0) else 1.0
		KEY_C:
			TELEPORT.crystal_build = not TELEPORT.crystal_build
			_play()
		KEY_D:
			_from_top = not _from_top
			_play()
		KEY_E:
			_card_index = (_card_index + 1) % CARD_IDS.size()
			_play()
		KEY_V:
			var names: Array = VIEWS.keys()
			_view = names[(names.find(_view) + 1) % names.size()]
			_aim_camera()

func _exit_tree() -> void:
	Engine.time_scale = 1.0
	TELEPORT.crystal_build = true
