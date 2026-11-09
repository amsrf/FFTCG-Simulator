extends Node
## Interactive Frozen-overlay demo.
##
## Run this scene with F6 from the editor (or:
##   Godot --path . res://tools/frozen_overlay_demo.tscn
## ). Two Forwards are placed on the player's field. F toggles Freeze on the
## left one, R re-applies it. The right card stays unfrozen for comparison.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _left: Card
var _right: Card
var _hud: Label


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = game.get("field")
	_left = game.create_card(41, "player")
	game.add_child(_left)
	field.play_card(_left, false, false)
	_right = game.create_card(25, "player")
	game.add_child(_right)
	field.play_card(_right, false, false)

	# Let the field layout and camera settle before showing the effect.
	await get_tree().create_timer(0.6).timeout
	_left.add_status_effect("frozen", 1)
	_build_hud()
	_update_hud()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F:
		if _left.is_frozen():
			_left.status_effects.erase("frozen")
			_left.refresh_status_visuals()
		else:
			_left.add_status_effect("frozen", 1)
		_update_hud()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R:
		_left.add_status_effect("frozen", 1)
		_update_hud()
		get_viewport().set_input_as_handled()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(28, 24)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_theme_font_size_override("font_size", 22)
	_hud.add_theme_color_override("font_color", Color(0.82, 0.93, 1.0))
	_hud.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_hud.add_theme_constant_override("outline_size", 6)
	_hud.add_theme_constant_override("line_spacing", 6)
	layer.add_child(_hud)


func _update_hud() -> void:
	if _hud == null:
		return
	var state: String = "FROZEN" if _left.is_frozen() else "NORMAL"
	_hud.text = "FROZEN OVERLAY DEMO\nF  toggle Freeze on the left Forward\nR  apply Freeze again\n\nLeft card: %s" % state
