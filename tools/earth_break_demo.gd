extends Node3D
## Viewing harness for the EARTH BREAK: the golden crystal rising through a card, sinking back, and the card breaking
## (scripts/vfx/earth_break_crystal.gd, through the real EarthTotemCue). Replays as often as you like - no match, no
## rules: each replay builds a fresh card and hands it to the cue as a held break.
##   Space  replay              A  auto-replay on/off
##   1-4    damage tier         S  slow motion (x0.25)
##   V      camera: board (the game's ~80 degree view) / low side view
## Screenshots: tools/shot.tscn ... -- --scene res://tools/earth_break_demo.tscn --as-scene 1 --freeze=<seconds>
## (and --tier=<0..3>, --cam=side).

const CARD_SCENE := preload("res://scenes/cards/card.tscn")
const CUE_SCENE := preload("res://assets/effects/earth/earth_totem_cue.tscn")
const CARD_ID := 25
## Damage that lands in each tier (VfxEvent.damage_tier_for).
const TIER_DAMAGE: Array[int] = [3000, 6000, 8000, 10000]
const VIEWS := {"board": -80.0, "side": -30.0}
const AUTO_SECONDS := 2.4

var _tier := 3
var _view := "board"
var _auto := false
var _camera: Camera3D
var _label: Label
var _cue: Node = null
var _card: Card = null       # what the cue is told it breaks (kept hidden, like the real card in the Break Zone)
var _stand_in: Card = null   # what you see on the slot
var _auto_timer := 0.0

func _ready() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.6
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
	# A board to stand on.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6.0, 6.0)
	ground.mesh = plane
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.33, 0.24)
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
		if argument.begins_with("--tier="):
			_tier = clampi(argument.trim_prefix("--tier=").to_int(), 0, 3)
		elif argument.begins_with("--freeze="):
			freeze = argument.trim_prefix("--freeze=").to_float()
		elif argument.begins_with("--cam=") and VIEWS.has(argument.trim_prefix("--cam=")):
			_view = argument.trim_prefix("--cam=")
	_aim_camera()
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
	_camera.position = _camera.basis.z * 6.0 + Vector3(0.0, 0.0, 0.0)

func _new_card() -> Card:
	var card: Card = CARD_SCENE.instantiate()
	add_child(card)
	card.initialize(CARD_ID, "player")
	card.enter_zone(Card.Zone.FIELD)
	card.position = Vector3.ZERO
	card.hide_power_display()
	return card

func _clear() -> void:
	if is_instance_valid(_cue):
		_cue.queue_free()
	for node in [_card, _stand_in]:
		if is_instance_valid(node):
			node.queue_free()
	# Crystals, shards and mist left over from the previous run.
	for child in get_children():
		if child.name.begins_with("EarthBreakCrystal") or child.get_script() == preload("res://scripts/cards/card_shards.gd"):
			child.queue_free()

func _play() -> void:
	_clear()
	_auto_timer = 0.0
	_card = _new_card()
	_card.set_hidden(true)
	_stand_in = _new_card()
	_stand_in.name = "HeldCard"
	# Exactly what the director hands the cue for a held break (Vfx.hold_for_break + _claim_holds).
	var visual := {"transform": _stand_in.global_transform, "floor_y": 0.0, "stand_in": _stand_in,
		"shatter": true, "lethal": true}
	var event := VfxEvent.new(VfxEvent.Kind.DAMAGE, [_card], "土", TIER_DAMAGE[_tier], null, "single")
	event.target_visuals[_card.get_instance_id()] = visual
	_cue = CUE_SCENE.instantiate()
	add_child(_cue)
	_cue.play(event)
	_update_label()

func _update_label() -> void:
	_label.text = "EARTH BREAK  |  tier %d (%d dmg)  |  %s camera  |  auto %s  |  %s\nSpace replay   1-4 tier   A auto   S slow   V camera" % [
		_tier, TIER_DAMAGE[_tier], _view, "ON" if _auto else "off",
		"SLOW x0.25" if is_equal_approx(Engine.time_scale, 0.25) else "normal speed"]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_play()
		KEY_1, KEY_2, KEY_3, KEY_4:
			_tier = event.keycode - KEY_1
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
