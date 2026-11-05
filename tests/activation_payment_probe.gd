extends Node
## Regression probe for two reported bugs:
##
##   1. BLACK BELT 1-100C may only be activated when there is a Forward with the "blocking"
##      status. Before this, the ability was offered and started even with no legal target.
##   2. Cancelling a charged mana source must re-disable the Confirm button. The selection signal
##      carries negative amounts on deselect, and the old handlers only ever ENABLED.

const GAME_SCENE := preload("res://game.tscn")

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

	_finish()

func _finish() -> void:
	print("[ActivationPayment] %d checks | failures: %d" % [_checks, _fails])
	print("[ActivationPayment] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
