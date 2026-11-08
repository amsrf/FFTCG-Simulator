extends Node
## Interactive test mode for the OPPONENT SUMMON FLIGHT.
##
## Boots the real debug board, deals a hand of Valefors, and lets the flight be
## replayed without playing a match. This drives the SAME path the AI uses:
##   Hand.charge() -> Stack._on_hand_charge_start() -> park_card() -> _fly_opponent_summon()
##
## Controls:
##   1  cast Valefor from the opponent's hand
##   2  reset / replay
##   3  toggle slow motion (0.35x)
##   4  toggle the help panel

const GAME_SCENE := preload("res://game.tscn")
const SUMMON_ID := 62          # Valefor: a Summon with no target, so the flight is uninterrupted.
const SLOW_SCALE := 0.35

var game: Node
var stack: Stack
var opponent_hand: Hand
var _local_preview: Card
var _paused := false
var _casting: bool = false
var _slow: bool = false
var _help_visible: bool = true
var _hud_panel: PanelContainer
var _hud_label: Label
var _hud_timer: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	MatchSetup.config = MatchSetup.build_config("debug")
	var opening: Array = MatchSetup.config["opponent_hand"]
	opening.fill(SUMMON_ID)
	await get_tree().process_frame
	game = GAME_SCENE.instantiate()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	stack = game.get("stack") as Stack
	opponent_hand = game.get_node("Opponent/Hand") as Hand
	# This preview holds each cast on the stack for inspection. Skip payment and priority.
	var assistant := game.get_node("Assistant")
	opponent_hand.charge_start.disconnect(assistant._on_hand_charge_start)
	_build_hud()
	_update_hud()
	# Headless automation: --auto-cast runs the flight once so the scene can be checked without
	# a keyboard. Interactive use ignores it.
	if OS.get_cmdline_user_args().has("--auto-cast"):
		await get_tree().create_timer(0.5).timeout
		_cast()

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_hud_panel = PanelContainer.new()
	_hud_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hud_panel.offset_left = 24.0
	_hud_panel.offset_right = 600.0
	_hud_panel.offset_top = -310.0
	_hud_panel.offset_bottom = -24.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.05, 0.80)
	style.border_color = Color(0.35, 0.70, 1.0, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	_hud_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(_hud_panel)
	_hud_label = Label.new()
	_hud_label.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
	_hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hud_label.add_theme_constant_override("outline_size", 6)
	_hud_label.add_theme_font_size_override("font_size", 19)
	_hud_panel.add_child(_hud_label)

func _cast() -> void:
	if _casting or opponent_hand == null or opponent_hand.cards.is_empty():
		return
	var card: Card = opponent_hand.cards[opponent_hand.cards.size() / 2]
	_casting = true
	if opponent_hand.charge(card):
		# Move the parked card into the persistent preview fan. The normal flight
		# owns the transform and reveals the card on landing if it is in Stack.cards.
		stack.summon_casting_card = null
		stack.summon_mana_deferred_until_target_confirm = false
		opponent_hand.finish_summon_cast(card)
		stack.cards.append(card)
		# Reserve the new top slot immediately so the existing fan moves down as the card flies.
		stack.update_card_positions()
		var flight := stack._opponent_summon_flight
		if flight != null:
			await flight.finished
		stack.reveal_parked(card)
		stack.update_card_positions()
	_casting = false
	_update_hud()

func _preview_ability(card_id: int) -> void:
	if _casting or stack == null:
		return
	if stack.cards.is_empty():
		await _cast()
	for source in game.get_node("Field").get_all_cards():
		if source.id == card_id and source.controller == "player":
			stack.create_skill_proxy(source, 0, source.activation_skill(0))
			_update_hud()
			return

## Preview the local cast without selecting payment cards every replay.
## Confirm drives the production commit, dissolve and flight functions.
func _stage_local_summon() -> void:
	if _casting or is_instance_valid(_local_preview):
		return
	var local_hand: Hand = game.get_node("Player/Hand")
	_local_preview = game.create_card(SUMMON_ID, "player")
	local_hand.add_card(_local_preview)
	local_hand.set_hovered(_local_preview, true)
	local_hand.begin_character_drag(_local_preview)
	var size := get_viewport().get_visible_rect().size
	local_hand._character_drag_start_pointer_y = size.y * 0.95
	local_hand.update_character_drag(_local_preview, size * Vector2(0.5, 0.6))
	local_hand.remove_card(_local_preview)
	local_hand.charging_card = _local_preview
	stack._on_hand_charge_start(_local_preview)
	local_hand.begin_character_charge(_local_preview)
	_update_hud()

func _confirm_local_summon() -> void:
	if _casting or not is_instance_valid(_local_preview):
		return
	_casting = true
	_local_preview = null
	stack._commit_summon_to_stack()
	await stack.local_summon_landed
	_casting = false
	_update_hud()

func _toggle_pause() -> void:
	_paused = not _paused
	get_tree().paused = _paused
	_update_hud()

func _step_frame() -> void:
	if not _paused:
		return
	# The printed card's fade first, then the stack card's entrance flight.
	var card: Card = stack._local_summon_fading
	if card != null and is_instance_valid(card) and card.teleport.tween != null and card.teleport.tween.is_valid():
		card.teleport.tween.custom_step(1.0 / 60.0)
	elif stack._opponent_summon_flight != null:
		stack._opponent_summon_flight.custom_step(1.0 / 60.0)
	_update_hud()

func _reset() -> void:
	if stack != null:
		get_tree().paused = false
		get_tree().reload_current_scene()

func _toggle_slow() -> void:
	_slow = not _slow
	Engine.time_scale = SLOW_SCALE if _slow else 1.0
	_update_hud()

func _toggle_help() -> void:
	_help_visible = not _help_visible
	_hud_panel.visible = _help_visible

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_8:
			_stage_local_summon()
		KEY_9:
			_confirm_local_summon()
		KEY_P:
			_toggle_pause()
		KEY_PERIOD:
			_step_frame()
		KEY_7:
			if not _casting and stack != null:
				for source in game.get_node("Field").get_all_cards():
					if source.id == 31 and source.controller == "player":
						stack.enqueue_code_trigger(source, "when_enter_field")
						break
			get_viewport().set_input_as_handled()
		KEY_6:
			_preview_ability(100)
			get_viewport().set_input_as_handled()
		KEY_5:
			_preview_ability(3)
			get_viewport().set_input_as_handled()
		KEY_1:
			_cast()
			get_viewport().set_input_as_handled()
		KEY_2:
			_reset()
			get_viewport().set_input_as_handled()
		KEY_3:
			_toggle_slow()
			get_viewport().set_input_as_handled()
		KEY_4:
			_toggle_help()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_hud_timer -= delta
	if _hud_timer > 0.0:
		return
	_hud_timer = 0.10
	_update_hud()

func _update_hud() -> void:
	if _hud_label == null:
		return
	var state := "FLYING" if _casting else "READY"
	if not _casting and opponent_hand.cards.is_empty():
		state = "HAND EMPTY"
	_hud_label.text = "\n".join([
		"SUMMON FLIGHTS — TEST MODE",
		"[1] Cast next Valefor onto the stack",
		"[8] Stage local Summon    [9] Confirm / fly",
		"[P] Pause: %s    [.] Step 1/60 second" % ("ON" if _paused else "OFF"),
		"[2] Reset / replay",
		"[3] Slow motion: %s" % ("ON (0.35x)" if _slow else "OFF"),
		"[4] Toggle this panel",
		"[5] Red Mage    [6] Black Belt    [7] Chemist trigger",
		"",
		"State: %s    Hand: %d    Stack: %d" % [state, opponent_hand.cards.size(), stack.cards.size()],
	])

func _exit_tree() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
