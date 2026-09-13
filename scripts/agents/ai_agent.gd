extends MockAgent
class_name AIAgent
## Heuristics (roadmap phase 3).
##
## Judgement is mostly about the tap economy: an attacking Forward taps, so it
## cannot block during the opponent's next turn. The AI therefore keeps a
## blocker home instead of swinging with everything, and only attacks where the
## trade is not strictly bad.
##
## Summons are cast now (targets go through choose_target()), but a card whose
## enter-the-field effect needs a target is still skipped: ETB targeting runs
## while the card resolves, and a miss there is not recoverable yet.

func take_priority(player_id: int) -> bool:
	await game.get_tree().create_timer(think_time).timeout
	# It also receives priority on the opponent's turn — only act on its own.
	if player_id != game.turn_owner:
		return false
	# Only main phases allow playing cards.
	var phase = game.phase
	if phase != GlobalVariables.Phase.FIRST_MAIN_PHASE and phase != GlobalVariables.Phase.SECOND_MAIN_PHASE:
		return false
	for card in game.hand_for(player_id).cards:
		if not _is_safe_to_play(card):
			continue
		if not _can_afford(card, player_id):
			continue
		if await game.play_card_for(player_id, card):
			return true  # an action: priority moves to the opponent
	return false

func _is_safe_to_play(card: Card) -> bool:
	# Summons are cast now: the card is parked while the cost is paid, then the
	# target is chosen through Agent.choose_target() (Field.request_target
	# delegates to it for a non-local owner). Only cast one when a legal target
	# actually exists, otherwise the targeting session opens with nothing valid.
	if card.type == "Summon":
		var criteria: Dictionary = card.get_cast_target_criteria()
		if criteria.is_empty():
			return true
		return game.field.has_viable_target(criteria, card, "Summon")
	# Characters may only be played by the turn player with an EMPTY stack.
	# Hand.charge() enforces it, but the AI should not even begin the attempt.
	if game.stack.stack_length() > 0:
		return false
	# Skip anything whose enter-the-field effect asks for a target: ETB targeting
	# runs while the card resolves, and a miss there is not recoverable yet.
	if card.card_effects.has("when_enter_field"):
		var etb = card.card_effects["when_enter_field"]
		if etb is Dictionary and etb.has("choose_target"):
			return false
	return true

func _can_afford(card: Card, player_id: int) -> bool:
	# Mirrors Assistant.can_pay_cost() so the AI never starts a payment it cannot
	# finish (a cancelled payment is avoidable churn). Each untapped Backup
	# produces 1 of its own element; element keys come from the same source as
	# Card.get_cost(), so they match.
	var element_cost: Dictionary = card.get_cost()
	var mana: Dictionary = {}
	for backup in game.field.get_back_cards_for(game.controller_for(player_id)):
		if backup.tapped:
			continue
		mana[backup.element] = mana.get(backup.element, 0) + 1
	var leftover: int = 0
	for element in mana:
		leftover += mana[element]
	for element in element_cost:
		if element == "neutral":
			continue
		var need: int = element_cost[element]
		if mana.get(element, 0) < need:
			return false
		leftover -= need
	return leftover >= element_cost.get("neutral", 0)

func pay_cost(player_id: int, cost: Dictionary) -> bool:
	# Tap this player's untapped Backups until the assistant agrees the cost is
	# covered. Field.add_card_to_mana_conversion() feeds Assistant.mana_acc, and
	# Field._on_assistant_charge_complete() taps whatever ended up selected.
	#
	# Element-matching Backups go first: any Backup can also pay generic
	# "neutral" cost, so spending an off-element one early would starve a later
	# play (the AI gets to spend its mana once per turn).
	var controller: String = game.controller_for(player_id)
	var field = game.field
	var assistant = game.assistant
	var matching: Array = []
	var rest: Array = []
	for card in field.get_back_cards_for(controller):
		if card.tapped:
			continue
		if cost.has(card.element):
			matching.append(card)
		else:
			rest.append(card)
	for card in matching + rest:
		field.add_card_to_mana_conversion(card)
		if assistant.can_pay_cost():
			return true
	return assistant.can_pay_cost()

# ------------------------------------------------------------------
# Combat
# ------------------------------------------------------------------

## Untapped Forwards of a side: the only cards that can attack or block.
## can_attack() is this codebase's "untapped Forward" predicate and has no
## controller check, so it works for either side.
func _untapped_forwards(player_id: int) -> Array[Card]:
	var out: Array[Card] = []
	for card in game.field.get_front_cards_for(game.controller_for(player_id)):
		if card.can_attack():
			out.append(card)
	return out

func _strongest(cards: Array[Card]) -> Card:
	var best: Card = null
	for card in cards:
		if best == null or card.power > best.power:
			best = card
	return best

func _best_forward_power(player_id: int) -> int:
	var best: int = 0
	for card in _untapped_forwards(player_id):
		if card.power > best:
			best = card.power
	return best

func decide_attacker(player_id: int) -> Card:
	# The opponent's untapped Forwards are both their blockers now and their
	# attackers next turn, so this one number drives the whole decision.
	var defender_best: int = _best_forward_power(3 - player_id)
	var mine: Array[Card] = _untapped_forwards(player_id)
	if mine.is_empty():
		return null

	# Reserve one Forward to defend with. Prefer the cheapest that could still
	# beat their best attacker; if nothing can, keep the strongest home anyway.
	var reserved: Card = null
	if defender_best > 0:
		for card in mine:
			if card.power > defender_best:
				if reserved == null or card.power < reserved.power:
					reserved = card
		if reserved == null:
			reserved = _strongest(mine)

	# Attack with the strongest that does not trade down. Equal power is allowed
	# (a mutual break is an even trade); strictly smaller would just lose the
	# attacker for nothing, so skip those.
	var best: Card = null
	for card in mine:
		if card == reserved or card.power < defender_best:
			continue
		if best == null or card.power > best.power:
			best = card
	return best

func decide_blocker(player_id: int, attacker: Card) -> Card:
	# Blocking with a strictly bigger Forward is free: the blocker takes the
	# attacker's power as damage (less than its own) and breaks the attacker.
	# Prefer the smallest such Forward so the larger ones stay available.
	if attacker == null:
		return null
	var best: Card = null
	for card in _untapped_forwards(player_id):
		if card.power <= attacker.power:
			continue
		if best == null or card.power < best.power:
			best = card
	return best

func choose_target(owner_id: int, _source: Card, _criteria: Dictionary) -> void:
	# Groundwork: pick the strongest legal target, which is a sensible default
	# for the damage/dull style effects in the database. Not reachable yet
	# because _is_safe_to_play() keeps the AI off cards that need a target.
	var field = game.field
	var chosen: Card = null
	for card in field.get_all_cards():
		if not card.is_valid_target:
			continue
		if chosen == null or card.power > chosen.power:
			chosen = card
	if chosen == null:
		game.assistant.on_target_cancel()
		return
	print("[AIAgent] P%s chose target %s" % [owner_id, chosen.card_name])
	field.set_target_card(chosen)
	game.assistant.on_target_complete()
