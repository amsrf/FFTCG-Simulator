extends AIAgent
## A SEAT DRIVEN BY THE TRAILER SCRIPT. The real rules run the turn (phases, priority, damage, EX BURST); this agent
## only answers the questions a player would, from queues the shot fills in:
##   steps    [{when: Callable(game) -> bool, do: Callable(agent, player_id) -> bool}]  checked on each priority; the
##            first whose `when` holds runs ONCE, and its return value is whether the player acted
##   attacks  [[card ids], ...]   one entry per attack declaration ([] = no attack); unset = never attacks
##   blocks   [card id, ...]      one entry per block declaration (0 = no block)
##   targets  ["p:29", "o:41", "s:4", ...]  consumed in order: p = player 1's field card, o = player 2's, s = a card on
##            the STACK (by id); an empty queue falls back to the AI's choice
## Costs are FREE (the trailer is not about the payment): pay_cost charges exactly what was asked, so the crystal row
## still appears and shatters.

var steps: Array = []
var attacks: Array = []
var blocks: Array = []
var targets: Array = []
## Seconds a priority answer takes, so the script reads at a watchable pace.
var pace: float = 0.3
## Held until the camera rolls: the match boots and settles for a moment before filming, and a seat that acted then
## would play its first card off camera (Kain's entry, a Summon's flight to the stack).
var held: bool = true


func _settle() -> void:
	while held:
		await game.get_tree().process_frame
	await super()


func take_priority(player_id: int) -> bool:
	await _settle()
	await game.get_tree().create_timer(pace).timeout
	for i in steps.size():
		var step: Dictionary = steps[i]
		if (step.when as Callable).call(game):
			steps.remove_at(i)
			var acted = await (step.do as Callable).call(self, player_id)
			return bool(acted)
	return false


func decide_attackers(player_id: int) -> Array:
	await _settle()
	await game.get_tree().create_timer(pace).timeout
	var out: Array = []
	if attacks.is_empty():
		return out
	for id in attacks.pop_front():
		var card: Card = field_card(player_id, int(id))
		if card != null and card.can_attack():
			out.append(card)
	return out


func decide_attacker(player_id: int) -> Card:
	var list: Array = await decide_attackers(player_id)
	return list[0] if not list.is_empty() else null


func decide_blocker(player_id: int, _attacker: Card) -> Card:
	await _settle()
	await game.get_tree().create_timer(pace).timeout
	if blocks.is_empty():
		return null
	var id := int(blocks.pop_front())
	if id == 0:
		return null
	var card: Card = field_card(player_id, id)
	if card == null or not game.field.can_block(card):
		push_error("[TrailerAgent] P%d cannot block with %d" % [player_id, id])
		return null
	return card


func choose_target(owner_id: int, source: Card, criteria: Dictionary) -> void:
	if targets.is_empty():
		await super(owner_id, source, criteria)
		return
	# NO think time here: while a target is being chosen the arrow is in "aiming" mode and follows the POINTER (that is
	# how a human aims), so any pause films an arrow chasing the real mouse. The game's AI picks at once too.
	await _settle()
	var ref := str(targets.pop_front())
	var chosen: Card = find(ref)
	print("[TrailerAgent] P%d picks %s -> %s (legal: %s)" % [owner_id, ref,
		chosen.card_name if chosen != null else "none", str(chosen != null and chosen.is_valid_target)])
	if chosen == null or not chosen.is_valid_target:
		push_error("[TrailerAgent] P%d: scripted target is not legal; falling back" % owner_id)
		await super(owner_id, source, criteria)
		return
	game.field.set_target_card(chosen)
	game.assistant.on_target_complete()


func pay_cost(_owner_id: int, cost: Dictionary) -> bool:
	await _settle()
	var assistant = game.assistant
	# Generic CP must come from a real element: "neutral" is not a mana SOURCE. Any element pays it; use the cost's
	# own element when it has one.
	var wild := "火"
	for key in cost:
		if str(key) != "neutral" and int(cost[key]) > 0:
			wild = str(key)
			break
	for key in cost:
		var amount := int(cost[key])
		if amount > 0:
			assistant.charge(amount, wild if str(key) == "neutral" else str(key))
	return assistant.can_pay_cost()


## "p:29" / "o:41" (a field card of player 1 / 2) or "s:4" (a card on the stack).
func find(ref: String) -> Card:
	var parts := ref.split(":")
	if parts.size() != 2:
		return null
	var id := int(parts[1])
	match parts[0]:
		"p":
			return field_card(1, id)
		"o":
			return field_card(2, id)
		"s":
			for card in game.stack.cards:
				if int(card.id) == id:
					return card
	return null


func field_card(player_id: int, id: int) -> Card:
	var controller: String = game.controller_for(player_id)
	for card in game.field.get_all_cards():
		if int(card.id) == id and card.controller == controller:
			return card
	return null


func hand_card(player_id: int, id: int) -> Card:
	for card in game.hand_for(player_id).cards:
		if int(card.id) == id:
			return card
	return null
