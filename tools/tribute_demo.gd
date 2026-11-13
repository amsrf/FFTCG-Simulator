extends Node3D
## Viewing harness for the TRIBUTE: an effect puts a field card into the Break Zone (not a break). A light orb charges
## and bursts on the slot, and the card rises clear, crosses and drops onto a raised pile (scripts/vfx/tribute_cue.gd).
## No match, no rules: each replay builds a fresh card and hands the cue a TRIBUTE event exactly as Vfx.tributed() does.
## A second card sits beside the slot so you can see that the flight passes above it.
##   Space  replay     A  auto-replay on/off     S  slow motion (x0.25)
## Screenshots: tools/shot.tscn ... -- --scene res://tools/tribute_demo.tscn --as-scene 1 --freeze=<seconds>

const CARD_SCENE := preload("res://scenes/cards/card.tscn")
const CUE_SCRIPT := preload("res://scripts/vfx/tribute_cue.gd")
const CARD_ID := 25
const AUTO_SECONDS := 2.2
## The pile: up and to the side, 0.5 m above the board like the game's Break Zone.
const PILE_AT := Vector3(-1.0, 0.5, 0.55)

var _auto := false
var _auto_timer := 0.0
var _camera: Camera3D
var _label: Label
var _cue: Node = null
var _card: Card = null
var _stand_in: Card = null
var _neighbour: Card = null

func _ready() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.6
	add_child(_camera)
	_camera.current = true
	_camera.rotation_degrees = Vector3(-80.0, 180.0, 0.0)
	_camera.position = _camera.basis.z * 6.0
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
	plane.size = Vector2(6.0, 6.0)
	ground.mesh = plane
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.33, 0.24)
	wood.roughness = 0.9
	ground.material_override = wood
	ground.position.y = -0.4
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

func _new_card() -> Card:
	var card: Card = CARD_SCENE.instantiate()
	add_child(card)
	card.initialize(CARD_ID, "player")
	card.enter_zone(Card.Zone.FIELD)
	card.position = Vector3.ZERO
	card.scale = Vector3.ONE * 1.2
	card.hide_power_display()
	return card

func _play() -> void:
	for node in [_cue, _card, _stand_in, _neighbour]:
		if is_instance_valid(node):
			node.queue_free()
	_auto_timer = 0.0
	# The real card is in the pile already, hidden: the cue lands the stand-in on it and then shows it.
	_card = _new_card()
	_card.position = PILE_AT
	_card.set_hidden(true)
	_neighbour = _new_card()
	_neighbour.position = Vector3(-0.6, 0.0, 0.0)
	_stand_in = _new_card()
	_stand_in.name = "HeldCard"
	_stand_in.position = Vector3(0.0, 0.0, 0.0)
	var visual := {"transform": _stand_in.global_transform, "stand_in": _stand_in, "hid_card": true}
	var event := VfxEvent.new(VfxEvent.Kind.TRIBUTE, [_card], _card.element, 0, null, "single")
	event.target_visuals[_card.get_instance_id()] = visual
	_cue = CUE_SCRIPT.new()
	add_child(_cue)
	_cue.play(event)
	_update_label()

func _update_label() -> void:
	_label.text = "TRIBUTE  |  auto %s  |  %s\nSpace replay   A auto   S slow" % [
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
