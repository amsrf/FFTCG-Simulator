extends Node
## Interactive demo for the 雷 damage VFX.
##
## Run it directly (F6 in the editor, or):
##   Godot --path . res://tools/lightning_demo.tscn
##
## It boots the real game, places three cards on the field and drives the same
## `EffectContext.damage()` path a card effect uses. Nothing here is wired into
## normal play; this is only a viewing harness.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")

const TARGET_IDS: Array[int] = [41, 12, 43]
const AUTO_REPLAY_SECONDS := 2.15
const DEMO_DAMAGE: Array[int] = [3000, 5000, 8000, 12000]
const DEMO_TIER_NAMES: Array[String] = ["weak", "medium", "high", "maximum"]

var _game: Node = null
var _field: Node = null
var _targets: Array[Card] = []
var _source: Card = null
var _selected: int = 1
var _damage_index: int = 1
var _hud: Label = null
var _labels: Array[Label3D] = []
var _auto_timer: Timer = null
var _last_action: String = "ready"
var _last_strike_ms: int = 0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var tier_arg: int = args.find("--tier")
	if tier_arg >= 0 and tier_arg + 1 < args.size():
		_damage_index = clampi(int(args[tier_arg + 1]), 0, DEMO_DAMAGE.size() - 1)
	MatchSetup.config = MatchSetup.build_config("clean")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	_field = _game.get("field")
	for id in TARGET_IDS:
		var card: Card = _game.create_card(id, "player")
		_game.add_child(card)
		_field.play_card(card, false, false)
		_targets.append(card)

	# A source card with the 雷 element, kept off the field. The context only
	# reads its element to decide which preset the director resolves. Hide it:
	# a Card added to the tree outside a zone sits at the world origin, which the
	# camera projects right above the middle target as a ghost card.
	# --source <card id>: strike with another element's card instead (41 = Ice), to view that element's cue on the
	# same real board, hit recoil included.
	var source_id: int = 121
	var source_arg: int = args.find("--source")
	if source_arg >= 0 and source_arg + 1 < args.size():
		source_id = int(args[source_arg + 1])
	_source = _game.create_card(source_id, "player")
	_game.add_child(_source)
	_source.visible = false

	_build_hud()
	# The phase banner is part of the real game, but in a three-card viewing
	# harness it only competes with the controls.
	var phase_text: Node = _game.get_node_or_null("PhaseText")
	if phase_text != null:
		phase_text.visible = false

	# Let the field layout settle before placing the target numbers; the numbers
	# are global-space labels, so they must be positioned after the cards arrive.
	await get_tree().create_timer(0.20).timeout
	_sort_targets_by_screen_x()
	_create_target_labels()
	_select(1)

	# Then show the effect once without requiring a key press.
	await get_tree().create_timer(0.55).timeout
	# --break: the source's effect BREAKS the selected card outright (no damage) - the staged break, through the real
	# EffectContext.break_cards() path. The card really goes to the Break Zone, so this is a one-shot.
	if args.has("--break"):
		_break_selected()
	else:
		_strike_selected()
	# --freeze <seconds>: stop time that long after the strike starts, so the shot harness can capture that moment.
	var freeze_arg: int = args.find("--freeze")
	if freeze_arg >= 0 and freeze_arg + 1 < args.size():
		await get_tree().create_timer(float(args[freeze_arg + 1])).timeout
		Engine.time_scale = 0.0


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1, KEY_KP_1:
			_select(0)
		KEY_2, KEY_KP_2:
			_select(1)
		KEY_3, KEY_KP_3:
			_select(2)
		KEY_SPACE, KEY_ENTER:
			_strike_selected()
		KEY_M:
			_strike_multi()
		KEY_B:
			_board_strike()
		KEY_A:
			_toggle_auto()
		KEY_T:
			_cycle_damage_tier()
		KEY_R:
			_strike_selected()
		_:
			return
	get_viewport().set_input_as_handled()


## Number the targets in the order the eye reads them. The field assigns slots
## by card type, so array order is not necessarily left-to-right.
func _sort_targets_by_screen_x() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	_targets.sort_custom(func(a: Card, b: Card) -> bool:
		return cam.unproject_position(a.global_position).x < cam.unproject_position(b.global_position).x
	)


func _create_target_labels() -> void:
	for i in _targets.size():
		var card: Card = _targets[i]
		if card == null or not is_instance_valid(card):
			continue
		var label := Label3D.new()
		label.text = str(i + 1)
		label.font_size = 96
		label.pixel_size = 0.0018
		label.outline_size = 18
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.render_priority = 120
		label.modulate = Color(0.84, 0.92, 1.0, 1.0)
		label.outline_modulate = Color(0.02, 0.03, 0.10, 0.95)
		# A little above the card face, on the side nearest the board camera.
		# Add first: a detached node has no meaningful global transform.
		_game.add_child(label)
		label.global_position = card.global_position + Vector3.UP * 0.48
		_labels.append(label)


func _select(index: int) -> void:
	if index < 0 or index >= _targets.size():
		return
	_selected = index
	for i in _targets.size():
		var card: Card = _targets[i]
		if card != null and is_instance_valid(card):
			card.set_selected_highlight(i == _selected)
		if i < _labels.size() and is_instance_valid(_labels[i]):
			if i == _selected:
				_labels[i].modulate = Color(1.0, 0.68, 0.18, 1.0)
			else:
				_labels[i].modulate = Color(0.84, 0.92, 1.0, 1.0)
	_update_hud()


func _break_selected() -> void:
	var card: Card = _targets[_selected]
	if card == null or not is_instance_valid(card) or not card.is_on_field():
		return
	_last_action = "break by effect on Card %d (one-shot: the card goes to the Break Zone)" % [_selected + 1]
	_update_hud()
	EFFECT_CONTEXT.new(_game, _source, "demo", {}, _source, [card]).break_cards([card])


func _strike_selected() -> void:
	if _is_cooling_down():
		return
	var card: Card = _targets[_selected]
	if card == null or not is_instance_valid(card):
		return
	_last_strike_ms = Time.get_ticks_msec()
	_last_action = "single strike on Card %d — %d (%s)" % [
		_selected + 1, _damage_amount(), _damage_tier_name()]
	_update_hud()
	# This is a viewing harness. Emit the semantic event directly: a 12000
	# tier would break a 6000-power card and the shatter would hide the effect.
	Vfx.damage([card], _damage_amount(), _source.element, _source, "single")


func _strike_multi() -> void:
	if _is_cooling_down():
		return
	_last_strike_ms = Time.get_ticks_msec()
	_last_action = "multi-target — %d (%s)" % [_damage_amount(), _damage_tier_name()]
	_update_hud()
	Vfx.damage(_targets, _damage_amount(), _source.element, _source, "multi")


func _board_strike() -> void:
	if _is_cooling_down():
		return
	_last_strike_ms = Time.get_ticks_msec()
	_last_action = "board presentation — %d (%s)" % [_damage_amount(), _damage_tier_name()]
	_update_hud()
	Vfx.board_damage(_targets, _damage_amount(), _source.element, _source)


func _damage_amount() -> int:
	return DEMO_DAMAGE[clampi(_damage_index, 0, DEMO_DAMAGE.size() - 1)]


func _damage_tier_name() -> String:
	return DEMO_TIER_NAMES[clampi(_damage_index, 0, DEMO_TIER_NAMES.size() - 1)]


func _cycle_damage_tier() -> void:
	_damage_index = (_damage_index + 1) % DEMO_DAMAGE.size()
	_last_action = "damage set to %d (%s)" % [_damage_amount(), _damage_tier_name()]
	_update_hud()
	_strike_selected()


func _is_cooling_down() -> bool:
	return Time.get_ticks_msec() - _last_strike_ms < 650


func _toggle_auto() -> void:
	if _auto_timer == null:
		_auto_timer = Timer.new()
		_auto_timer.wait_time = AUTO_REPLAY_SECONDS
		_auto_timer.timeout.connect(_on_auto_tick)
		add_child(_auto_timer)
	if _auto_timer.is_stopped():
		_auto_timer.start()
		_last_action = "auto replay on"
	else:
		_auto_timer.stop()
		_last_action = "auto replay off"
	_update_hud()


func _on_auto_tick() -> void:
	_strike_selected()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	var panel := ColorRect.new()
	panel.position = Vector2(16, 14)
	panel.size = Vector2(900, 560)
	panel.color = Color(0.015, 0.020, 0.070, 0.58)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)

	_hud = Label.new()
	_hud.position = Vector2(38, 28)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_theme_font_size_override("font_size", 26)
	_hud.add_theme_color_override("font_color", Color(0.84, 0.94, 1.0))
	_hud.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.10, 0.92))
	_hud.add_theme_constant_override("outline_size", 7)
	_hud.add_theme_constant_override("line_spacing", 8)
	layer.add_child(_hud)


func _update_hud() -> void:
	if _hud == null:
		return
	var auto_state: String = "off"
	if _auto_timer != null and not _auto_timer.is_stopped():
		auto_state = "on"
	_hud.text = "\n".join(PackedStringArray([
		"LIGHTNING DAMAGE VFX  (雷)",
		"VFX-only viewer — cards are not damaged",
		"",
		"SPACE / R — Strike selected card",
		"1 / 2 / 3 — Select target",
		"M — Strike all three",
		"B — Board presentation",
		"A — Auto replay: %s" % auto_state,
		"T — Damage: %d (%s)" % [_damage_amount(), _damage_tier_name()],
		"",
		"Selected: Card %d" % (_selected + 1),
		"Last: %s" % _last_action,
	]))
