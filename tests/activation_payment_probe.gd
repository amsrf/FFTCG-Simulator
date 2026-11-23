extends Node
## Regression probe for two reported bugs:
##
##   1. BLACK BELT 1-100C may only be activated when there is a Forward with the "blocking"
##      status. Before this, the ability was offered and started even with no legal target.
##   2. Cancelling a charged mana source must re-disable the Confirm button. The selection signal
##      carries negative amounts on deselect, and the old handlers only ever ENABLED.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _checks: int = 0
var _fails: int = 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[ActivationPayment] ok   %s" % what)
	else:
		_fails += 1
		print("[ActivationPayment] FAIL %s" % what)

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	await get_tree().process_frame
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var field: Node = game.get("field")
	var black_belt: Card = null
	for card in field.get("back_cards"):
		if card != null and is_instance_valid(card) and int(card.id) == 100:
			black_belt = card
			break
	_expect(black_belt != null, "Black Belt is on the debug board")
	if black_belt == null:
		_finish()
		return

	# No Forward is blocking at the start of the debug board.
	for card in field.get_all_cards():
		if card != null and is_instance_valid(card):
			card.status_effects.erase("blocking")
	field.refresh_continuous_effects()
	field.refresh_available_effects()
	print("[ActivationPayment] can activate without a blocker: %s" % field.can_activate_now(black_belt))
	_expect(not field.can_activate_now(black_belt),
		"Black Belt is NOT activatable while no Forward is blocking")

	# Give one Forward the blocking status.
	var blocking_forward: Card = null
	for card in field.get("front_cards"):
		if card != null and is_instance_valid(card):
			blocking_forward = card
			break
	_expect(blocking_forward != null, "the debug board has a Forward to mark blocking")
	if blocking_forward != null:
		blocking_forward.status_effects["blocking"] = 1
		field.refresh_continuous_effects()
		field.refresh_available_effects()
		print("[ActivationPayment] can activate with a blocker: %s" % field.can_activate_now(black_belt))
		_expect(field.can_activate_now(black_belt),
			"Black Belt IS activatable once a Forward is blocking")

	# ---------------------------------------------------------------- payment confirm state
	var assistant: Node = game.get_node("Assistant")
	var confirm: Node = assistant.get("confirmButton")
	_expect(confirm != null, "the assistant has a Confirm button")
	if confirm != null:
		assistant.call("_on_field_card_activated_ability", {"土": 1})
		await get_tree().process_frame
		print("[ActivationPayment] after opening payment: disabled=%s" % str(confirm.get("_disabled")))
		_expect(bool(confirm.get("_disabled")),
			"Confirm is disabled before any mana source is charged")

		assistant.call("charge", 1, "土")
		await get_tree().process_frame
		print("[ActivationPayment] after charging 1 earth: disabled=%s" % str(confirm.get("_disabled")))
		_expect(not bool(confirm.get("_disabled")),
			"Confirm enables when the cost is covered")

		assistant.call("_on_field_selected_cards_for_mana_has_changed", -1, "土")
		await get_tree().process_frame
		print("[ActivationPayment] after cancelling the charge: disabled=%s" % str(confirm.get("_disabled")))
		_expect(bool(confirm.get("_disabled")),
			"Confirm disables again when the charged source is cancelled")

		# The hand path uses -2 per source; it must behave the same way.
		assistant.call("charge", 1, "土")
		await get_tree().process_frame
		_expect(not bool(confirm.get("_disabled")), "Confirm enables again after re-charging")
		assistant.call("_on_hand_selected_cards_for_mana_has_changed", -2, "土")
		await get_tree().process_frame
		_expect(bool(confirm.get("_disabled")),
			"Confirm disables again when a HAND source is cancelled")

		assistant.call("on_charge_cancelled")
		await get_tree().process_frame

	# ---------------------------------------------------------------- the ability badge (one ability: confirm first)
	# Clicking a field card with ONE ability it can activate shows a badge with that ability's cost and text; nothing
	# starts until the badge itself is clicked. Two or more abilities go to the skill picker instead, with no badge.
	var badge_stack: Node = game.get("stack")
	game.priority_holder = 1
	var red_mage: Card = null
	for card in field.get_back_cards_for(Card.PLAYER):
		if int(card.id) == 3:
			red_mage = card
	_expect(red_mage != null and field.can_activate_now(red_mage), "Red Mage (one ability) can activate on the debug board")
	if red_mage != null:
		red_mage.untap()
		await get_tree().create_timer(0.35).timeout
		field.try_activate_from_field(red_mage)
		await get_tree().process_frame
		var badge = field.ability_badge()
		_expect(badge != null and field.ability_badge_card() == red_mage and badge_stack.get("skill_activation_proxy") == null,
			"clicking Red Mage shows its ability badge, and nothing is activated yet")
		if badge != null:
			_expect(badge.shown_text() == "Choose 1 Forward. It cannot block this turn.",
				"the badge shows the ability's text without the printed cost (%s)" % badge.shown_text())
			var chips: Array = badge.cost_chips(red_mage.activation_skill(0))
			_expect(chips.size() == 3 and chips[0]["element"] and chips[1]["text"] == "1" and chips[2]["text"] == "Dull",
				"and its cost as chips: one Fire, a 1, Dull (%s)" % str(chips.map(func(c): return c["text"] if not c["element"] else "element")))
			# On the empty wood past the end of the row: it covers none of the row's cards.
			var camera := get_viewport().get_camera_3d()
			var plate: Rect2 = badge.plate_rect()
			var overlaps := 0
			for other in field.get_back_cards_for(Card.PLAYER):
				if badge._screen_rect(other, camera).intersects(plate):
					overlaps += 1
			_expect(overlaps == 0, "the badge sits past the end of the row, over none of its cards (%d overlapped)" % overlaps)
			# While it is up a full-screen catcher takes the pointer: nothing hovers, nothing behind it can be clicked.
			var catcher := badge.get_node("BadgeCatcher") as Control
			var view := get_viewport().get_visible_rect().size
			_expect(catcher != null and catcher.mouse_filter == Control.MOUSE_FILTER_STOP
				and catcher.get_rect().size.is_equal_approx(view),
				"while the badge is up a full-screen catcher takes every pointer event (no hover, no other click)")
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = badge._screen_rect(red_mage, camera).get_center()
			badge._on_catcher_input(click)
			await get_tree().process_frame
			_expect(field.ability_badge() != null, "a click on the card itself leaves the badge up")
			# The hover preview must not open over the badge (the badge lets the pointer over its own card).
			field.on_card_hovered(red_mage, true)
			_expect(field.preview_card() == null, "hovering the card while its ability badge is up shows no card preview")
			# A click on ANOTHER card only closes the badge: that card does not answer it.
			var other_card: Card = field.get_front_cards_for(Card.PLAYER)[0]
			click.position = badge._screen_rect(other_card, camera).get_center()
			badge._on_catcher_input(click)
			await get_tree().process_frame
			_expect(field.ability_badge() == null and badge_stack.get("skill_activation_proxy") == null
				and field.preview_card() == null,
				"a click anywhere else only closes the badge: nothing activates, nothing else answers it")
		field.try_activate_from_field(red_mage)
		await get_tree().process_frame
		badge = field.ability_badge()
		var had_badge: bool = badge != null
		if had_badge:
			badge.confirm()
			await get_tree().process_frame
		var started_proxy = badge_stack.get("skill_activation_proxy")
		_expect(had_badge and started_proxy != null and started_proxy.effect_source == red_mage,
			"clicking the badge starts Red Mage's activation")
		badge_stack.call("_clear_skill_proxy")
		assistant.call("on_charge_cancelled")
		await get_tree().process_frame
		GlobalVariables.refresh_mode()
		# A modal taking the window away closes a badge that is up.
		field.try_activate_from_field(red_mage)
		await get_tree().process_frame
		game.priority_holder = 2
		field.refresh_available_effects()
		_expect(field.ability_badge() == null, "the badge goes when the card stops being activatable (priority moved on)")
		game.priority_holder = 1

	# ---------------------------------------------------------------- the last cost confirmed = done
	# Firion 22, "《1》: Firion gains First Strike": mana and nothing else to choose. Confirming the payment is the LAST
	# step, so it must put the ability on the stack at once - no second Confirm after the payment Confirm. (Same rule as
	# Aerith's S cost in s_cost_probe: whichever cost is confirmed last, the activation is done.)
	var stack: Node = game.get("stack")
	game.priority_holder = 1
	var firion: Card = game.create_card(22, "player")
	field.add_child(firion)
	field.play_card(firion, false, false)
	await get_tree().process_frame
	field.begin_skill_activation(firion, 0)
	await get_tree().process_frame
	var proxy: Card = stack.get("skill_activation_proxy")
	_expect(proxy != null and stack.get("skill_mana_deferred_until_target_confirm")
		and GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.PAYING_COST,
		"Firion's mana ability opens the payment stage")
	var payer: Card = null
	for b in field.get_back_cards_for(Card.PLAYER):
		if not b.tapped and not stack.is_reserved_for_cost(b):
			payer = b
			break
	_expect(payer != null, "an untapped Backup can pay the 《1》")
	if proxy != null and payer != null:
		field.add_card_to_mana_conversion(payer, payer.mana_element())
		await get_tree().process_frame
		assistant.call("on_charge_complete")   # what the payment's Confirm does
		await get_tree().process_frame
		await get_tree().process_frame
		print("[ActivationPayment] after the payment Confirm: committed=%s on stack=%s mode=%s confirm visible=%s" % [
			not stack.get("skill_mana_deferred_until_target_confirm"), stack.get("cards").has(proxy),
			GlobalVariables.get_player_mode(), str(confirm.get("visible")) if confirm != null else "?"])
		_expect(not stack.get("skill_mana_deferred_until_target_confirm") and stack.get("cards").has(proxy),
			"confirming the payment, the last cost, commits the ability onto the stack")
		_expect(GlobalVariables.get_player_mode() != GlobalVariables.Player_Mode.PAYING_COST
			and (confirm == null or not bool(confirm.get("visible")) or bool(confirm.get("_disabled"))),
			"and no second Confirm is waiting: the payment Confirm was the last thing to press")

	_finish()

func _finish() -> void:
	print("[ActivationPayment] %d checks | failures: %d" % [_checks, _fails])
	print("[ActivationPayment] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
