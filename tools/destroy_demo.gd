extends Node3D
## Viewing harness for the DESTROY BURST (scripts/vfx/card_destroy_burst.gd, through CardShards exactly as
## Game.break_card spawns it). No match, no rules: each replay builds a fresh card and breaks it.
##   Space  replay              A  auto-replay on/off
##   G      style: destroy burst / glass shatter
##   S      slow motion (x0.25)  V  camera: board (the game's ~80 degree view) / low side view
## Screenshots: tools/shot.tscn ... -- --scene res://tools/destroy_demo.tscn --as-scene 1 --freeze=<seconds>
## (and --cam=side, --glass, --card=<id>).

const CARD_SCENE := preload("res://scenes/cards/card.tscn")
const SHARDS_SCENE := preload("res://scenes/cards/card_shards.tscn")
const SHARDS_SCRIPT := preload("res://scripts/cards/card_shards.gd")
## The card that breaks (its element colours the crystals). `--card=<id>` overrides it.
var card_id := 25
const VIEWS := {"board": -80.0, "side": -30.0}
const AUTO_SECONDS := 2.0

var _view := "board"
var _glass := false
var _auto := true
var _camera: Camera3D
var _label: Label
var _card: Card = null
var _auto_timer := 0.0

func _ready() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 3.2
	add_child(_camera)
	_camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.10, 0.10, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.35
	add_child(env)
	# A pale board to stand on: the burst must read over the game's light wood, not only over black.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	ground.mesh = plane
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.62, 0.50, 0.38)
	wood.roughness = 0.9
	ground.material_override = wood
	ground.position.y = -0.02
	add_child(ground)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	layer.add_child(_label)
	var freeze := -1.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--freeze="):
			freeze = argument.trim_prefix("--freeze=").to_float()
			_auto = false
		elif argument.begins_with("--card="):
			card_id = argument.trim_prefix("--card=").to_int()
		elif argument == "--glass":
			_glass = true
		elif argument.begins_with("--cam=") and VIEWS.has(argument.trim_prefix("--cam=")):
			_view = argument.trim_prefix("--cam=")
	_aim_camera()
	# A throwaway burst first: the first render compiles every shader (the game does this in
	# _warm_up_effect_shaders), and that frame's long delta would otherwise jump the shown burst ahead.
	await get_tree().process_frame
	_play()
	for i in 20:
		await get_tree().process_frame
	_play()
	if freeze >= 0.0:
		await get_tree().create_timer(freeze).timeout
		Engine.time_scale = 0.0

func _process(delta: float) -> void:
	if not _auto:
		return
	_auto_timer += delta
	if _auto_timer >= AUTO_SECONDS:
		_play()

func _aim_camera() -> void:
	# Field cards carry a half turn, so the camera is yawed 180 to read them upright.
	_camera.rotation_degrees = Vector3(VIEWS[_view], 180.0, 0.0)
	_camera.position = _camera.basis.z * 6.0

func _play() -> void:
	for child in get_children():
		if child.get_script() == SHARDS_SCRIPT:
			child.queue_free()
	if is_instance_valid(_card):
		_card.queue_free()
	_auto_timer = 0.0
	_card = CARD_SCENE.instantiate()
	add_child(_card)
	_card.initialize(card_id, "player")
	_card.enter_zone(Card.Zone.FIELD)
	_card.position = Vector3.ZERO
	_card.hide_power_display()
	var fx: Node3D = SHARDS_SCENE.instantiate()
	fx.set("style", SHARDS_SCRIPT.Style.GLASS_SHATTER if _glass else SHARDS_SCRIPT.Style.DESTROY_BURST)
	add_child(fx)
	fx.global_transform = _card.global_transform
	fx.call("burst_from_card", _card)
	# Exactly as in a match: the card leaves the slot the frame it breaks.
	_card.visible = false
	_update_label()

func _update_label() -> void:
	_label.text = "CARD BREAK  |  %s  |  %s camera  |  auto %s  |  %s\nSpace replay   G style   A auto   S slow   V camera" % [
		"glass shatter" if _glass else "destroy burst", _view, "ON" if _auto else "off",
		"SLOW x0.25" if is_equal_approx(Engine.time_scale, 0.25) else "normal speed"]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_play()
		KEY_G:
			_glass = not _glass
			_play()
		KEY_A:
			_auto = not _auto
			_auto_timer = 0.0
		KEY_S:
			Engine.time_scale = 0.25 if is_equal_approx(Engine.time_scale, 1.0) else 1.0
		KEY_V:
			var names: Array = VIEWS.keys()
			_view = names[(names.find(_view) + 1) % names.size()]
			_aim_camera()
	_update_label()

func _exit_tree() -> void:
	Engine.time_scale = 1.0
