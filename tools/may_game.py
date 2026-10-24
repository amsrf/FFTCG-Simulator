p = 'scripts/game.gd'
s = open(p, encoding='utf-8').read()

# ---- 1. the "may" gate, at the moment the instruction is reached --------------------------------------
old = '''	var instruction = _current_instructions.pop_front()
	var executor = _resolve_executor(instruction.executor, _current_source_card)'''
new = '''	var instruction = _current_instructions.pop_front()
	# "YOU MAY ..." is decided HERE: when the instruction is reached, i.e. at resolution and after targets are
	# locked. The decider is the effect's controller, unless the card says the OPPONENT decides (Leon 60), in which
	# case `may_by` moves it. A refusal is a normal no-op: the rest of the chain still runs, and
	# `if_last_did_not_succeed` sees the refusal.
	if instruction.may:
		var decider: int = _condition_owner()
		if instruction.may_by == "opponent":
			decider = 3 - decider
		var deciding_agent: Agent = agent_for(decider)
		var use_it: bool = true
		if deciding_agent != null:
			use_it = await deciding_agent.confirm_optional(decider, instruction.may_prompt)
		if not use_it:
			print("[May] P%d declined %s" % [decider, instruction.action])
			_last_action_succeeded = false
			_process_next_instruction()
			return
	var executor = _resolve_executor(instruction.executor, _current_source_card)'''
assert old in s
s = s.replace(old, new, 1)

# ---- 2. play a card from hand for free ----------------------------------------------------------------
anchor = '''## PLAY 1 CARD FROM A BREAK ZONE.'''
add = '''## PLAY 1 CARD FROM HAND FOR FREE. "Play 1 Wind Forward of cost 3 or less from your hand onto the field."
## (Vaan 63) or, with `by = "opponent"`, "your opponent may play 1 Character Card from his/her hand" (Leon 60).
##
## No cost is paid — the card's text says PLAY, not CAST — and the choice goes through the agent seam, so a human
## gets the same search window over their hand while an AI simply takes the first legal card.
func play_from_hand(criteria: Dictionary = {}, by: String = "self") -> void:
	var owner_id: int = 1 if _current_controller == "player" else 2
	if by == "opponent":
		owner_id = 3 - owner_id
	var owner_hand: Hand = hand_for(owner_id)
	if owner_hand == null:
		return
	var ids: Array = []
	var candidates: Array = []
	for card in owner_hand.cards:
		if card == null or not is_instance_valid(card):
			continue
		if not card.matches_criteria(criteria, _current_source_card):
			continue
		candidates.append(card)
		ids.append(card.id)
	if ids.is_empty():
		print("[Hand] no legal card to play")
		return
	var agent: Agent = agent_for(owner_id)
	if agent == null:
		return
	var chosen: int = await agent.choose_hand_card_to_play(owner_id, ids, criteria)
	if chosen < 0:
		print("[Hand] the free play was declined")
		return
	var picked: Card = null
	for card in candidates:
		if card.id == chosen:
			picked = card
			break
	if picked == null:
		return
	print("[Hand] P%d plays %s for free" % [owner_id, picked.card_name])
	owner_hand.remove_for_play(picked)
	picked.reset_for_field_arrival()
	field.play_card(picked, owner_id == 2, true)

'''
assert anchor in s
s = s.replace(anchor, add + anchor, 1)

# ---- 3. block triggers --------------------------------------------------------------------------------
old = '''	if card != null and is_instance_valid(card):
		card.set_blocker_status(true)'''
new = '''	if card != null and is_instance_valid(card):
		card.set_blocker_status(true)
		# "When this blocks or is blocked" (Squall 41). Declaring the block is the single moment both events become
		# true, so both sides' triggers are queued here — the blocker's `when_blocks`, and `when_blocked` for every
		# Forward that is attacking (a party included: each member was blocked).
		field.execute_card_effect(card, "when_blocks")
		for attacker in field.party_members():
			if attacker != null and is_instance_valid(attacker):
				field.execute_card_effect(attacker, "when_blocked")'''
assert old in s
s = s.replace(old, new, 1)

open(p, 'w', encoding='utf-8').write(s)
print('game patched')
d = open(p, 'rb').read().replace(b'\r\n', b'\n')
open(p, 'wb').write(d)
