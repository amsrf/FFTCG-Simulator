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
## The stack copy currently resolving, when there is one. Targeting arcs originate from this card, not from the
## source that may already have left the field.
var effect_card: Card = null
## Targets chosen when the trigger was put on the stack, in pick order. Code effects that declare target_criteria
## receive them here; effects that ask later can still use choose_target(s).
var targets: Array = []
var controller: String = ""
var owner_id: int = 1
var event_name: String = ""
var event_data: Dictionary = {}


func _init(p_game: Node, p_source: Card, p_event: String = "static", p_data: Dictionary = {}, p_effect_card: Card = null, p_targets: Array = []) -> void:
	game = p_game
	source = p_source
	effect_card = p_effect_card
	targets = p_targets.duplicate()
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
	return await choose_for(owner_id, cards, prompt)


## Choose on behalf of a specific player, for "each player chooses" effects.
func choose_for(player_id: int, cards: Array, prompt: String = "Choose a card") -> Card:
	if cards.is_empty() or game == null:
		return null
	var agent: Agent = game.agent_for(player_id)
	if agent == null:
		return cards[0]
	var chosen: Card = await agent.choose_field_card(player_id, cards, prompt)
	if chosen != null and cards.has(chosen):
		return chosen
	return null


## Open a targeting session and return every pick, in order. `count` maps to the existing `count` session key.
## `effect_card` is the stack copy whose top edge the arrow originates from.
func choose_targets(criteria: Variant, count: int = 1, allow_cancel: bool = false,
		source_kind: String = "Ability") -> Array:
	if field == null:
		return []
	var session: Variant = criteria
	if criteria is Dictionary:
		session = criteria.duplicate()
		if count > 1:
			session["count"] = count
	var origin: Card = effect_card if effect_card != null and is_instance_valid(effect_card) else source
	if not field.has_viable_target(session, origin, source_kind):
		return []
	field.request_target(session, origin, allow_cancel, source_kind)
	var assistant = game.get("assistant") if game != null else null
	# A non-local agent completes inside request_target(); only a local player leaves the list empty.
	if field.targeting_picked.is_empty() and assistant != null:
		await assistant.target_complete
	var picks: Array = field.targeting_picked.duplicate()
	field.finish_targeting_state()
	return picks


## Targets for a Summon's when_cast. A real cast already has them on the card; an EX BURST has none and asks now,
## at resolution. Keeping the fallback here lets one card file serve both paths.
func cast_targets(criteria: Variant, count: int = 1) -> Array:
	if not targets.is_empty():
		return targets
	return await choose_targets(criteria, count, false, "Summon")


## Single-target convenience over choose_targets().
func choose_target(criteria: Dictionary, prompt: String = "Choose a card") -> Card:
	var picks: Array = await choose_targets(criteria, 1)
	return picks[0] if not picks.is_empty() else null


## Resolve an optional "you may" clause through the owning agent.
func may(prompt: String) -> bool:
	return await may_for(owner_id, prompt)


## Ask a specific player, for effects that say "your opponent may...".
func may_for(player_id: int, prompt: String) -> bool:
	if game == null:
		return true
	var agent = game.agent_for(player_id)
	if agent == null:
		return true
	return bool(await agent.confirm_optional(player_id, prompt))


## Evaluate an existing engine condition string ("controls:Laguna", "cast_this_turn:Alexander") from this effect's
## perspective. This is a compatibility bridge while the instruction-string conditions are migrated to code.
func condition(expression: String) -> bool:
	_prime_game()
	return bool(game._condition_holds(expression))


func untap_all_matching(criteria: Dictionary) -> void:
	untap(cards_in("field", criteria))


func play_from_hand(criteria: Dictionary = {}, by: String = "self") -> void:
	_prime_game()
	await game.play_from_hand(criteria, by)


## Pick one card from an explicit list. Used by hand-play effects where the caller controls the shortlist.
func choose_hand_card(cards: Array, prompt: String = "Choose a card") -> Card:
	if cards.is_empty() or game == null:
		return null
	var agent: Agent = game.agent_for(owner_id)
	if agent == null:
		return null
	return await agent.choose_field_card(owner_id, cards, prompt)


## Play one already-chosen card from hand for free;  is the "onto the field dull" rider.
func play_from_hand_card(card: Card, dull: bool = false) -> void:
	if card == null or not is_instance_valid(card) or game == null:
		return
	var owner_hand: Hand = game.hand_for(1 if card.controller == "player" else 2)
	if owner_hand == null:
		return
	owner_hand.remove_for_play(card)
	card.reset_for_field_arrival()
	game.field.play_card(card, card.controller == "opponent", true)
	if dull:
		card.tap()


## The common "you may play a card from hand" shape: shortlist, ask, choose, play.
func may_play_from_hand(criteria: Dictionary, dull: bool = false,
		prompt: String = "Play a card") -> bool:
	var candidates: Array = cards_in("hand", criteria, "self")
	if candidates.is_empty():
		return false
	if not await may(prompt):
		return false
	var picked: Card = await choose_hand_card(candidates, prompt)
	if picked == null:
		return false
	await play_from_hand_card(picked, dull)
	return true


func break_zone_to_hand(filter: Dictionary = {}) -> void:
	_prime_game()
	await game.break_zone_to_hand(filter)


func choose_break_zone_card(criteria: Dictionary, chooser: String = "self",
		prompt: String = "Choose a card in your Break Zone") -> void:
	_prime_game()
	await game.choose_break_zone_card(criteria, chooser, prompt)


func put_card_into_hand() -> void:
	_prime_game()
	await game.put_card_into_hand()


func put_hand_card_on_bottom() -> void:
	_prime_game()
	await game.put_hand_card_on_bottom()


func search_deck(filter: Dictionary, destination: String = "hand", tapped: bool = false) -> void:
	if game != null:
		game.search_deck(filter, destination, tapped, owner_id)


func reveal_top(count: int = 1) -> void:
	if game != null:
		game.reveal_top(count, owner_id)


func mill(player_id: int, count: int = 1) -> void:
	if game != null:
		await game.mill_player(player_id, count)


func discard(player_id: int, count: int = 1) -> int:
	if game != null:
		return await game.discard_from(player_id, count)
	return 0


func set_element_until_end_of_turn(card: Card, element: String) -> void:
	if card != null and is_instance_valid(card):
		card.add_status_effect("element_override", 1, {"element": element})


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


func untap(cards: Array) -> void:
	for card in cards:
		if card != null and is_instance_valid(card):
			card.untap()


func dull(cards: Array) -> void:
	for card in cards:
		if card != null and is_instance_valid(card):
			card.tap()


func break_cards(cards: Array) -> void:
	if game == null:
		return
	for card in cards:
		if card != null and is_instance_valid(card) and card.is_on_field():
			game.break_card(card)


func power_change(cards: Array, amount: int, duration: int = 1) -> void:
	for card in cards:
		if card != null and is_instance_valid(card):
			card.power_change(amount, duration)


func opponent_discards(count: int = 1) -> void:
	await discard(3 - owner_id, count)


func opponent_mills(count: int = 1) -> void:
	await mill(3 - owner_id, count)


## The following helpers prime Game's ambient instruction state from this context before calling a Game instruction.
## They exist only for the instructions whose Game implementation still reads `_current_source_card`/`_current_controller`.
func _prime_game() -> void:
	if game == null:
		return
	game.set("_current_source_card", source)
	game.set("_current_controller", controller)


func play_from_break_zone(criteria: Dictionary = {}) -> void:
	_prime_game()
	await game.play_from_break_zone(criteria)


func cast_summon_for_free(criteria: Dictionary = {}) -> void:
	_prime_game()
	await game.cast_summon_for_free(criteria)


func look_top_may_bottom() -> void:
	_prime_game()
	await game.look_top_may_bottom()


func cancel_stack_card(target: Card) -> void:
	if game == null or target == null or not is_instance_valid(target):
		return
	var stack_node = game.get("stack")
	if stack_node != null:
		stack_node.cancel_stack_card(target)


func copy_skill(target: Card) -> void:
	if game == null or target == null or not is_instance_valid(target):
		return
	_prime_game()
	game.set("_targets", [target])
	await game.copy_skill()


func each_player_discards(count: int = 1) -> void:
	await discard(owner_id, count)
	await discard(3 - owner_id, count)


func draw(player_id: int, count: int = 1) -> void:
	if game != null:
		game.draw_cards(count, player_id)


func power_change_party(amount: int, duration: int = 1) -> void:
	if game == null or field == null:
		return
	power_change(field.party_members(), amount, duration)


func take_damage_to_controller(amount: int = 1) -> void:
	_prime_game()
	await game.take_damage_to_controller(amount)


func return_from_break_zone(tapped: bool = true) -> void:
	_prime_game()
	await game.return_from_break_zone(tapped)


func return_to_hand(cards: Array) -> void:
	if game == null:
		return
	# START EVERY RETURN FIRST, then wait. Awaiting each tween inside the loop serialises the cards, which is exactly
	# what a mass return must not do.
	var tweens: Array = []
	for card in cards:
		if card == null or not is_instance_valid(card) or not card.is_on_field():
			continue
		var owner_hand = game.hand_for(1 if card.controller == "player" else 2)
		if owner_hand == null:
			continue
		game.field.remove_card(card)
		var tween = owner_hand.begin_return_card(card)
		if tween != null:
			tweens.append(tween)
	for tween in tweens:
		await tween.finished


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
