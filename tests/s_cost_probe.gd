extends Node
## THE S COST — a special ability's two-step payment: discard a card sharing the source's NAME, then pay mana.
##
## Most of this flow already existed (begin_s_cost_selection, the chooser, the deferred discard); what was missing was
## the pink ring, the exclusion of the already-spent card from the mana pool, and stepping BACK from the mana step to the
## s-cost step instead of abandoning the activation. All three are checked here.
##
## The whole flow is driven directly — there is no clicking to do headlessly — so this asserts on Stack's own state
## rather than on anything visual.
##
##   godot --headless res://tests/s_cost_probe.tscn --quit-after 900

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const AERITH := 64

var _checks: int = 0
var _fails: int = 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[SCost] ok   ", what)
	else:
		_fails += 1
		print("[SCost] FAIL ", what)

func _an_aerith_in_hand(hand) -> Card:
	for c in hand.cards:
		if c.card_name == "Aerith":
			return c
	return null

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = game.field
	var hand = game.hand
	var stack = game.stack
	# Activating an ability is a priority action, and can_activate_now() checks that it is OUR window.
	game.priority_holder = 1

	# Aerith on the FIELD (the source of the skill) and one in HAND (the card the S cost asks for).
	var source: Card = game.create_card(AERITH, "player")
	field.add_child(source)
	field.play_card(source, false, false)
	var sacrifice: Card = _an_aerith_in_hand(hand)
	print("[SCost] source=%s (on field) | hand Aerith=%s" % [
		source.card_name, sacrifice.card_name if sacrifice != null else "<none>"])
	_expect(sacrifice != null, "the debug hand holds a card sharing the source's name")
	if sacrifice == null:
		_finish()
		return

	# --- the s-cost step ----------------------------------------------------------------------------------------------
	field.begin_skill_activation(source, 0)
	print("[SCost] after activation: s_cost_active=%s proxy=%s" % [
		stack.s_cost_active, stack.skill_activation_proxy != null])
	_expect(stack.s_cost_active, "activating an s_cost skill opens the s-cost step first")
	_expect(stack.skill_activation_proxy != null, "and the activation has its stack proxy")
	# The 《Dull》 is paid at COMMIT with the other costs; until then the source is only reserved for it.
	_expect(not source.tapped and stack.is_reserved_for_cost(source),
		"the source is NOT dulled while the costs are chosen, only reserved for its dull cost")

	# Picking the card marks it PINK, not orange: it is a payment, not a targeting pick.
	hand.toggle_effect_card_selection(sacrifice)
	print("[SCost] picked %s: pink=%s orange=%s" % [
		sacrifice.card_name, sacrifice.ring_s_cost(), sacrifice.ring_selected()])
	_expect(sacrifice.ring_s_cost(), "the picked card wears the PINK s-cost ring")
	_expect(not sacrifice.ring_selected(), "and not the orange targeting one")

	# --- cancelling AT the s-cost step abandons the activation, and costs nothing -------------------------------------
	stack._on_choose_card_finished(false)
	print("[SCost] after cancelling the s-cost step: proxy=%s source tapped=%s" % [
		stack.skill_activation_proxy != null, source.tapped])
	_expect(stack.skill_activation_proxy == null, "cancelling the s-cost step abandons the activation")
	_expect(not source.tapped and not stack.is_reserved_for_cost(source) and hand.cards.has(sacrifice),
		"and nothing was spent: the source was never dulled and is free again, the picked card is still in hand")
	_expect(not sacrifice.ring_s_cost(), "the pink ring came off with the pick")

	# --- CONFIRMING THE PICK IS THE LAST STEP -------------------------------------------------------------------------
	# Aerith's mana cost is {} and her ability chooses no target: the discarded card IS the whole payment, so confirming
	# the pick commits the ability at once. A second Confirm on an empty screen (the reported annoyance) or a payment stage
	# would be a button that exists only to be pressed.
	field.begin_skill_activation(source, 0)
	hand.toggle_effect_card_selection(sacrifice)
	var proxy: Card = stack.skill_activation_proxy
	stack._on_choose_card_finished(true)
	await get_tree().process_frame
	var mode_after: int = GlobalVariables.get_player_mode()
	var assistant_node = game.get_node("Assistant")
	print("[SCost] after confirming the pick: mode=%s proxy committed=%s s-cost card in hand=%s confirm visible=%s" % [
		mode_after, not stack.skill_mana_deferred_until_target_confirm, hand.cards.has(sacrifice),
		assistant_node.confirmButton.visible])
	_expect(proxy != null and stack.cards.has(proxy) and not stack.skill_mana_deferred_until_target_confirm,
		"confirming the S-cost pick commits the ability straight onto the stack")
	_expect(not hand.cards.has(sacrifice), "the picked card is discarded as the cost")
	_expect(mode_after != GlobalVariables.Player_Mode.PAYING_COST and not assistant_node.confirmButton.visible,
		"no payment stage and no second Confirm: there is nothing left to decide")
	_expect(source.tapped == bool(source.activation_skill(0).get("tap", false)),
		"the source is dulled at commit exactly when its cost says so")
	_expect(field.cost_is_free({}), "an empty cost counts as free")
	_expect(field.cost_is_free({"neutral": 0}), "as does one listing zero")
	_expect(not field.cost_is_free({"neutral": 1}), "while any real mana does not")

	# --- THE REPORTED BUG: an s cost you cannot pay must not be offered at all ----------------------------------------
	# It used to be activatable, which TAPPED the source and then aborted silently — and because the abort untaps again,
	# every further click re-tapped it. The card reads as broken: it taps, nothing happens, and clicking it taps it more.
	if hand.cards.has(sacrifice):
		hand.discard_card(sacrifice)
	print("[SCost] with the last matching card discarded from hand: can_activate_now=%s tapped=%s" % [
		field.can_activate_now(source), source.tapped])
	_expect(not field.can_activate_now(source),
		"an ability whose S cost cannot be paid is not offered — no green ring, no tap")
	var before_tap: bool = source.tapped
	field.begin_skill_activation(source, 0)
	_expect(source.tapped == before_tap,
		"and starting it anyway does NOT tap the source: nothing half-happens")

	_finish()

func _finish() -> void:
	print("[SCost] %d checks | failures: %d" % [_checks, _fails])
	print("[SCost] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0)
