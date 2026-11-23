extends CanvasLayer
## THE PASS MODE SELECTOR: four small segments under the local pass button — Stop All / Smart / React / Pass All — set
## Game.pass_mode (see there for what each one answers). Built in code by Assistant._ready(); it follows the pass
## disc on screen, so a resized window or a moved station keeps it under the button.
##
## A click is the player's choice, so it is also SAVED (MatchSetup.set_pass_mode) and becomes the next match's
## default. Setting Game.pass_mode directly (tests) changes the match only.

const FONT := preload("res://assets/fonts/FOT-NewRodin Pro EB.otf")

const MODES: Array = [
	["stop_all", "Stop All", "Stop at every priority window, even when you have nothing to play.\nNothing gives away an empty hand: use it to bluff."],
	["smart", "Smart", "Pass for you when you have nothing you could play;\nstop when you do."],
	["react", "React", "Pass everything unless your opponent puts something on the stack\n(and you could answer it). Still stops in your own main phase when you have a card to play."],
	["pass_all", "Pass All", "Pass every chance to respond, even if you could, until your next turn starts.\nStill stops in your own main phase when you have a card to play."],
]
const KEY_HINT := "\n\n[Tab] next mode   [Space] pass"

## Distance from the screen's right and bottom edges, px.
@export var corner_margin_px: float = 14.0
@export var font_size: int = 15

var game: Node = null
var socket: Node3D = null
var _panel: PanelContainer = null
var _buttons: Dictionary = {}

func setup(game_node: Node, disc_socket: Node3D) -> void:
	game = game_node
	socket = disc_socket
	layer = 5
	_build()
	if game.has_signal("pass_mode_changed"):
		game.pass_mode_changed.connect(func(_m: String) -> void: _refresh())
	_refresh()

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "PassModeSelector"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.07, 0.06, 0.05, 0.82)
	frame.border_color = Color(0.78, 0.66, 0.42, 0.85)
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(15)
	frame.set_content_margin_all(3)
	frame.shadow_color = Color(0, 0, 0, 0.45)
	frame.shadow_size = 6
	_panel.add_theme_stylebox_override("panel", frame)
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_panel.add_child(row)
	var group := ButtonGroup.new()
	for entry in MODES:
		var b := Button.new()
		b.name = str(entry[0])
		b.text = str(entry[1])
		b.tooltip_text = str(entry[2]) + KEY_HINT
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(70, 26)
		b.add_theme_font_override("font", FONT)
		b.add_theme_font_size_override("font_size", font_size)
		b.add_theme_color_override("font_color", Color(0.82, 0.78, 0.70))
		b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.84))
		b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
		b.add_theme_color_override("font_hover_pressed_color", Color(1, 1, 1))
		b.add_theme_stylebox_override("normal", _segment(Color(0, 0, 0, 0)))
		b.add_theme_stylebox_override("hover", _segment(Color(1, 1, 1, 0.08)))
		# The chosen one wears the pass gem's teal.
		b.add_theme_stylebox_override("pressed", _segment(Color(0.10, 0.55, 0.56, 0.95)))
		b.add_theme_stylebox_override("hover_pressed", _segment(Color(0.14, 0.63, 0.64, 0.98)))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var mode: String = str(entry[0])
		b.pressed.connect(func() -> void: choose(mode))
		row.add_child(b)
		_buttons[mode] = b

func _segment(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(12)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box

## The player picked `mode`: the match changes now, and the choice is remembered for the next one — except PASS ALL,
## which only lasts until their next turn and so is never anyone's default.
func choose(mode: String) -> void:
	if game == null:
		return
	game.pass_mode = mode
	if mode != "pass_all":
		MatchSetup.set_pass_mode(mode)
	_refresh()

## [Tab] cycles the modes (Shift+Tab backwards); [Space] presses the pass button when it is offered. Unhandled keys
## only, so a focused text field or an open window keeps them.
func _unhandled_key_input(event: InputEvent) -> void:
	if game == null or _panel == null or not _panel.visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_TAB:
			var order: Array = []
			for entry in MODES:
				order.append(str(entry[0]))
			var i: int = order.find(str(game.get("pass_mode")))
			var step: int = -1 if (event as InputEventKey).shift_pressed else 1
			choose(order[posmod(i + step, order.size())])
			get_viewport().set_input_as_handled()
		KEY_SPACE:
			if press_pass():
				get_viewport().set_input_as_handled()

## Space: the pass button, exactly as a click would press it — only while the local player holds priority, and not in
## the attack/block declaration steps, where the same disc is the declaration.
func press_pass() -> bool:
	var assistant = game.get("assistant")
	if assistant == null or not assistant.local_holds_priority():
		return false
	var phase_now = game.get("phase")
	if phase_now == GlobalVariables.Phase.ATTACK_DECLARATION_STEP \
			or phase_now == GlobalVariables.Phase.BLOCKER_DECLARATION_STEP:
		return false
	var mode = GlobalVariables.get_player_mode()
	if mode != GlobalVariables.Player_Mode.FREE and mode != GlobalVariables.Player_Mode.INSTANT_SPEED_TIME:
		return false
	return assistant.passPhaseButton.press_from_key()

func _refresh() -> void:
	if game == null:
		return
	var current: String = str(game.get("pass_mode"))
	for mode in _buttons:
		(_buttons[mode] as Button).set_pressed_no_signal(mode == current)

func _process(_delta: float) -> void:
	if _panel == null or game == null or socket == null or not is_instance_valid(socket):
		return
	# Only a HUMAN at this seat has priority to be asked about.
	var agent = game.get("player_agent")
	var human: bool = agent != null and agent.has_method("on_pass_mode_changed")
	_panel.visible = human and not bool(game.get("match_over"))
	if not _panel.visible:
		return
	# THE BOTTOM-RIGHT CORNER OF THE SCREEN (2026-11-21). With the zoomed-out camera the coin moved down into that corner
	# and the old "just under the coin" spot fell on top of it; the selector now sits in the corner, beside the hand.
	var size: Vector2 = _panel.get_combined_minimum_size()
	_panel.size = size
	var view: Vector2 = socket.get_viewport().get_visible_rect().size
	_panel.position = Vector2(view.x - size.x - corner_margin_px, view.y - size.y - corner_margin_px)
