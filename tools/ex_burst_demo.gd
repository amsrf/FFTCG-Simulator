extends Node3D
## Viewing harness for the EX BURST REVEAL (scripts/vfx/ex_burst_reveal.gd): a damage card lands, a gold aura snaps
## onto it, two pulses leave its outline and "EX BURST" rides in on a light streak. No match, no rules.
##   Space  replay     A  auto-replay on/off     S  slow motion (x0.25)
## Screenshots: tools/shot.tscn ... -- --scene res://tools/ex_burst_demo.tscn --as-scene 1 --freeze=<seconds>
## (take ~900 frames: shot.tscn counts uncapped frames, not time).

const CARD_SCENE := preload("res://scenes/cards/card.tscn")
const REVEAL := preload("res://scripts/vfx/ex_burst_reveal.gd")
const CARD_ID := 25
## The card "lands" this long after a replay starts.
const LAND := 0.3
const AUTO_SECONDS := 2.6

var _auto := false
var _auto_timer := 0.0
var _label: Label
var _card: Card = null
var _reveal: Node = null

func _ready() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	add_child(camera)
	camera.current = true
	camera.rotation_degrees = Vector3(-62.0, 180.0, 0.0)
	camera.position = camera.basis.z * 6.0
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
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	ground.mesh = plane
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.30, 0.24, 0.20)
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

func _play() -> void:
	for node in [_reveal, _card]:
		if is_instance_valid(node):
			node.queue_free()
	_auto_timer = 0.0
	_card = CARD_SCENE.instantiate()
	add_child(_card)
	_card.initialize(CARD_ID, "player")
	_card.enter_zone(Card.Zone.DAMAGE)
	_card.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	_card.scale = Vector3.ONE * 1.2
	_reveal = REVEAL.new()
	add_child(_reveal)
	_reveal.setup(_card, LAND)
	_update_label()

func _update_label() -> void:
	_label.text = "EX BURST REVEAL  |  auto %s  |  %s\nSpace replay   A auto   S slow" % [
		"ON" if _auto else "off", "SLOW x0.25" if is_equal_approx(Engine.time_scale, 0.25) else "normal speed"]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_play()
		KEY_A:
			_auto = not _auto
			_auto_timer = 0.0
		KEY_S:
			Engine.time_scale = 0.25 if is_equal_approx(Engine.time_scale, 1.0) else 1.0
	_update_label()

func _exit_tree() -> void:
	Engine.time_scale = 1.0
