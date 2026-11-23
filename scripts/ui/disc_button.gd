extends Node3D
## A match button (Confirm / Cancel / Pass) that lives on the board: it drives a DiscSocket in the local button station
## instead of drawing anything itself. It keeps BigButton's public API — configure(), set_text(), set_disabled(),
## show_button(), hide_button(), set_on_press_callback(), the `pressed` signal — so Assistant's flows did not change.
##
## `visible` still means "this button is offered right now" (probes read it), but it no longer draws: the disc is a
## separate node, and a button that is not offered is shown by its disc turned to the stone face, never by hiding.
## Disabled is presented the same way — a disc face-up but unpressable was a lie the old floating button could tell
## with a grey gem; on the board, "you cannot press this now" is the stone face.
##
## Each button keeps its OWN click area over its disc. Confirm and Pass share the large disc, and Assistant never
## offers both at once (show_modal() hides Pass first), so at most one of the two areas takes input.

signal pressed

const AREA_SCRIPT := preload("res://scripts/cards/area_3d.gd")

@export var socket_path: NodePath

var _socket: Node3D
var _disabled := false
var _text := ""
var _on_press_callback: Callable
var _area: Area3D
var _hovering := false


func _ready() -> void:
	_socket = get_node_or_null(socket_path)
	if _socket == null:
		push_error("%s: no disc socket at %s" % [name, socket_path])
		return
	global_position = _socket.global_position
	_area = Area3D.new()
	_area.name = "Area3D"
	_area.set_script(AREA_SCRIPT)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = float(_socket.call("hit_radius"))
	cylinder.height = 0.14
	if bool(_socket.get("use_priority_coin")):
		cylinder.height = 0.24
		shape.position.y = 0.045
	shape.shape = cylinder
	_area.add_child(shape)
	add_child(_area)
	_area.button_pressed.connect(_on_area_pressed)
	_area.button_hovered.connect(_on_hover.bind(true))
	_area.button_unhovered.connect(_on_hover.bind(false))
	if _socket.has_signal("released"):
		_socket.released.connect(_sync)
	_sync()


func configure(text: String, callback: Callable = Callable(), enabled: bool = true) -> void:
	_text = text
	_on_press_callback = callback
	_disabled = not enabled
	_sync()

func set_text(text) -> void:
	_text = str(text)
	_sync()

func get_text() -> String:
	return _text

func set_on_press_callback(callback: Callable) -> void:
	_on_press_callback = callback
	_sync()

func set_disabled(value: bool) -> void:
	_disabled = value
	_sync()

func show_button() -> void:
	visible = true
	_sync()

func hide_button() -> void:
	visible = false
	_sync()

## Offered AND pressable: what the disc shows.
func is_active() -> bool:
	return visible and not _disabled


func _sync() -> void:
	# A disc still spinning (or holding) from a press shows the stone: it takes no press until it releases.
	var pressable: bool = is_active() and not (_socket != null and _socket.is_busy())
	if _area != null:
		_area.set_input_enabled(pressable)
		_area.set_on_press_callback(_on_press_callback if pressable else Callable())
	if _socket != null:
		_socket.set_claim(self, is_active(), _text)
		# A button taken away under the pointer gets no mouse_exited (its area stops picking): release the glow here.
		if _hovering and not is_active():
			_on_hover(false)

func _on_hover(on: bool) -> void:
	_hovering = on
	if _socket != null:
		_socket.set_hovered(on)

## A key press standing in for a click (Space on the pass button): the same press, spin and callback, and refused
## exactly when a click would be (not offered, disabled, or still spinning from the last press).
func press_from_key() -> bool:
	if not is_active() or (_socket != null and _socket.is_busy()):
		return false
	var callback: Callable = _on_press_callback
	_on_area_pressed()
	if callback.is_valid():
		callback.call()
	return true

func _on_area_pressed() -> void:
	pressed.emit()
	if _socket != null:
		_socket.pulse()
	_sync.call_deferred()      # the spin has started: refuse further presses until the socket releases
