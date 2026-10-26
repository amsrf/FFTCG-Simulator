extends Node
## SKILL CHOICE probe — the picker for a card with more than one ability (Rikku 89).
##
## Drives the modal directly (selection, border, confirm, cancel, disabled entries) and then through the real entry
## point, `Field.begin_skill_activation(card)` with no index, which must open the picker instead of activating ability 0.

const GAME_SCENE := preload("res://game.tscn")
const SKILL_CHOICE := preload("res://skill_choice.tscn")

const RIKKU := 89
const RED_MAGE := 3

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[SkillChoice] ok   %s" % what)
	else:
		_fails += 1
		print("[SkillChoice] FAIL %s" % what)


func _find_window() -> Node:
	for child in _game.get_children():
		if is_instance_valid(child) and child.has_method("skill_button_count"):
			return child
	return null


func _open_window(skills: Array, usable: Array) -> Node:
	var window = SKILL_CHOICE.instantiate()
	_game.add_child(window)
	# The card is only needed for the title.
	var rikku: Card = _game.call("create_card", RIKKU, "player")
	_game.add_child(rikku)
	window.call("open", rikku, skills, usable)
	return window


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": RIKKU}],
		"player_hand": [RIKKU],          # the S cost's discard fodder
		"player_deck": range(101, 121),
		"opponent_deck": range(141, 161),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	var rikku: Card = null
	for c in _field.get_back_cards_for("player"):
		if c.id == RIKKU:
			rikku = c
	_expect(rikku != null, "the board has Rikku")
	if rikku == null:
		print("[SkillChoice] RESULT: cannot continue")
		get_tree().quit()
		return

	var skills: Array = rikku.activation_skills()
	_expect(skills.size() == 2, "Rikku has two abilities (%d)" % skills.size())
	_expect(skills.size() == 2 and not str(skills[0].get("text", "")).is_empty()
			and not str(skills[1].get("text", "")).is_empty(),
		"and both carry display text")

	# --- the modal, driven directly -------------------------------------------------------------------------
	var window: Node = _open_window(skills, [true, true])
	_expect(window.call("skill_button_count") == 2, "the picker shows one container per ability")
	_expect(window.call("selected_index") == -1, "nothing is selected when it opens")
	_expect(not window.call("confirm_enabled"), "so Confirm starts disabled")
	var idle: Color = window.call("skill_border_colour", 0)
	_expect(idle.is_equal_approx(window.IDLE_BORDER), "the idle border is the neutral one (%s)" % idle)

	window.call("select_skill", 1)
	_expect(window.call("selected_index") == 1, "clicking the second container selects it")
	_expect(window.call("confirm_enabled"), "which enables Confirm")
	var picked: Color = window.call("skill_border_colour", 1)
	_expect(picked.is_equal_approx(window.SELECTED_BORDER),
		"and that container gets the accent border (%s)" % picked)
	_expect(not window.call("skill_border_colour", 0).is_equal_approx(picked),
		"while the other one stays neutral")

	var got: Array = []
	window.finished.connect(func(index: int) -> void: got.append(index))
	window.call("confirm_choice")
	await get_tree().process_frame
	_expect(got == [1], "Confirm reports the chosen index (%s)" % str(got))

	# --- cancel, and select-then-cancel ---------------------------------------------------------------------
	var window_b: Node = _open_window(skills, [true, true])
	var got_b: Array = []
	window_b.finished.connect(func(index: int) -> void: got_b.append(index))
	window_b.call("select_skill", 0)
	window_b.call("cancel_choice")
	await get_tree().process_frame
	_expect(got_b == [-1], "Cancel reports -1 even after a selection (%s)" % str(got_b))

	# --- an unpayable S ability is shown but disabled --------------------------------------------------------
	var window_c: Node = _open_window(skills, [true, false])
	_expect(not window_c.call("skill_is_enabled", 1), "an unpayable S ability is disabled")
	window_c.call("select_skill", 1)
	_expect(window_c.call("selected_index") == -1, "and it cannot be selected")
	_expect(not window_c.call("confirm_enabled"), "so Confirm stays disabled")
	window_c.call("cancel_choice")
	await get_tree().process_frame

	# --- through the real entry point -----------------------------------------------------------------------
	_expect(_field.can_activate_now(rikku), "Rikku can be activated right now")
	_field.begin_skill_activation(rikku)          # no index: this must ASK
	await get_tree().process_frame
	var live: Node = _find_window()
	_expect(live != null, "activating a two-ability card opens the picker")
	_expect(not rikku.tapped and _game.get("stack").stack_length() == 0,
		"and nothing is spent before the choice is confirmed")
	if live != null:
		live.call("cancel_choice")
	await get_tree().process_frame
	_expect(_find_window() == null, "cancelling closes the picker")
	_expect(not rikku.tapped, "and leaves the card untapped")

	# --- one ability does NOT open the picker ---------------------------------------------------------------
	var red_mage: Card = _game.call("create_card", RED_MAGE, "player")
	_game.add_child(red_mage)
	_field.play_card(red_mage, false, false, false)
	_field.begin_skill_activation(red_mage)
	await get_tree().process_frame
	_expect(_find_window() == null, "a single-ability card activates without the picker")

	print("[SkillChoice] %d checks | failures: %d" % [_checks, _fails])
	print("[SkillChoice] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
