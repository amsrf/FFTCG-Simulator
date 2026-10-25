extends RefCounted
## The explicit world handed to one card-effect invocation.
##
## It exists so card code never reads ambient instruction state (`_targets`, `_current_source_card`, ...) or reaches into
## autoloads. A context is short-lived: create it for an event/query, pass it to the effect, discard it afterwards.
##
## It deliberately wraps the systems rather than exposing them raw: card code asks for cards, choices and actions here,
## while Game/Field/Rules remain their owners.

var game: Node = null
var field = null
var source: Card = null
var controller: String = ""
var owner_id: int = 1
var event_name: String = ""
var event_data: Dictionary = {}


func _init(p_game: Node, p_source: Card, p_event: String = "static", p_data: Dictionary = {}) -> void:
	game = p_game
	source = p_source
	event_name = p_event
	event_data = p_data.duplicate(true)
	if p_source != null:
		controller = p_source.controller
		owner_id = 1 if controller == "player" else 2
	if game != null:
		field = game.get("field")


## Cards in one region, optionally filtered. `owner` is "self" (the source's controller), "opponent", or "any".
##
## Regions: field, hand, deck, break_zone, damage_zone, removed, stack, revealed.
func cards_in(region: String, criteria: Dictionary = {}, owner: String = "any") -> Array:
	var pools: Array = []
	match region:
		"field":
			pools = [field.get_all_cards()] if field != null else []
		"hand":
			for side in _sides(owner):
				pools.append(side.hand.cards)
		"deck":
			for side in _sides(owner):
				pools.append(side.deck.deck_cards)
		"break_zone":
			for side in _sides(owner):
				pools.append(side.graveyard.graveyard_cards)
		"damage_zone":
			for side in _sides(owner):
				pools.append(side.damage_zone.cards)
		"removed":
			for side in _sides(owner):
				var zone = game.get("player_removed" if side.controller == "player" else "opponent_removed")
				if zone != null:
					pools.append(zone.graveyard_cards)
		"stack":
			if game.get("stack") != null:
				pools.append(game.stack.cards)
		"revealed":
			pools.append(game.get("revealed_cards"))
		_:
			push_warning("[EffectContext] unknown region '%s'" % region)
			return []

	var out: Array = []
	for pool in pools:
		if pool == null:
			continue
		for card in pool:
			if card == null or not is_instance_valid(card):
				continue
			if criteria.is_empty() or card.matches_criteria(criteria, source):
				out.append(card)
	return out


## Ask the owner's agent to choose one of `cards`. Returns null when the list is empty or the choice is cancelled.
func choose(cards: Array, prompt: String = "Choose a card") -> Card:
	if cards.is_empty():
		return null
	var agent: Agent = game.agent_for(owner_id)
	if agent == null:
		return cards[0]
	var chosen: Card = await agent.choose_field_card(owner_id, cards, prompt)
	if chosen != null and cards.has(chosen):
		return chosen
	return null


func choose_element(options: Array, prompt: String = "Choose an Element") -> String:
	if options.is_empty():
		return ""
	var agent = game.agent_for(owner_id) if game != null else null
	if agent != null and agent.has_method("choose_element"):
		return str(await agent.choose_element(owner_id, options, prompt))
	return str(options[0])


## Damage all cards in `cards` from the effect's source. All damage goes through Field.cause_damage, the single
## entry point that applies damage modifiers and source-aware riders.
func damage(cards: Array, amount: int) -> void:
	if field == null or amount <= 0:
		return
	var origin: Card = source if source != null and is_instance_valid(source) else null
	for card in cards:
		if card == null or not is_instance_valid(card) or not card.is_on_field():
			continue
		field.cause_damage(card, amount, origin, "Ability", controller)
	game.enforce_game_state_rules()


func remove_from_game(cards: Array) -> void:
	if game == null:
		return
	for card in cards:
		if card == null or not is_instance_valid(card):
			continue
		game.remove_card_from_game(card)


func add_status(cards: Array, status: String, duration: int = 1, payload: Dictionary = {}) -> void:
	for card in cards:
		if card != null and is_instance_valid(card):
			card.add_status_effect(status, duration, payload)


func draw(player_id: int, count: int = 1) -> void:
	if game != null:
		game.draw_cards(count, player_id)


func _sides(owner: String) -> Array:
	if game == null:
		return []
	var self_side = game.side_for(owner_id)
	var other_side = game.side_for(3 - owner_id)
	match owner:
		"self":
			return [self_side]
		"opponent":
			return [other_side]
		_:
			return [self_side, other_side]
