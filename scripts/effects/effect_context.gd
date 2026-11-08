extends RefCounted
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
const TARGET_SEQUENCE := preload("res://scripts/effects/target_sequence.gd")
## Multi-target effect damage hits the cards in order. The card reaction is a
## local visual, so the delay is passed down to Card.suffer_damage().
const DAMAGE_REACTION_STAGGER_SECONDS := 0.20
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
var event_name = ""
var event_data: Dictionary = {}


## Typed access to the event payload. Cards should read these instead of poking at event_data.
func event_card() -> Card:
	var value = event_data.get("card", null)
	return value if value is Card and is_instance_valid(value) else null


func event_to_zone() -> int:
	return int(event_data.get("to_zone", Card.Zone.NONE))


func event_player_id() -> int:
	return int(event_data.get("player_id", 0))


## The X the player declared for an 《X》 activated ability. -1 if this resolution is not an X ability.
func ability_x() -> int:
	if effect_card != null and is_instance_valid(effect_card):
		if effect_card.ability_x_value >= 0:
			return effect_card.ability_x_value
		return int(effect_card.skill_def_override.get("x_value", -1))
	return -1


func _init(p_game: Node, p_source: Card, p_event = "static", p_data: Dictionary = {}, p_effect_card: Card = null, p_targets: Array = []) -> void:
	game = p_game
	source = p_source
	effect_card = p_effect_card
	targets = p_targets.duplicate()
	event_name = p_event
	event_data = p_data.duplicate(true)
	if p_source != null:
		controller = p_source.controller
		owner_id = 1 if controller == Card.PLAYER else 2
	if game != null:
		field = game.get("field")


## Cards in one region, optionally filtered. `owner` is "self" (the source's controller), "opponent", or "any".
##
## Regions: field, hand, deck, break_zone, damage_zone, removed, stack, revealed.
## Damage the effect's controller has received. Used by dynamic power/property queries.
func damage_received(player_id: int = 0) -> int:
	if game == null:
		return 0
	var pid: int = player_id if player_id in [1, 2] else owner_id
	var side = game.side_for(pid)
	return side.damage_count() if side != null else 0


func cards_in(region: String, criteria: CARD_QUERY = null, owner: String = "any") -> Array:
	var criteria_block: Dictionary = _criteria_block(criteria)
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
				var zone = game.get("player_removed" if side.controller == Card.PLAYER else "opponent_removed")
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
			if criteria_block.is_empty() or card.matches_criteria(criteria_block, source):
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
	var session: Variant = _legacy_targets(criteria, count)
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


## Typed target requests are converted at the boundary; the Field/Agent targeting session still consumes the
## existing dictionary blocks.
func _legacy_targets(criteria: Variant, count: int = 1) -> Variant:
	if criteria is Object and criteria.has_method("to_legacy"):
		var legacy = criteria.to_legacy()
		if legacy is Dictionary and count > 1 and not legacy.has("count"):
			legacy["count"] = count
		return legacy
	# A CardQuery is a pool, not a TargetRequest; the Field still consumes its to_block() form.
	if criteria is Object and criteria.has_method("to_block"):
		var block: Dictionary = criteria.to_block()
		if count > 1:
			block["count"] = count
		return block
	if criteria is Dictionary:
		var block: Dictionary = criteria.duplicate()
		if count > 1:
			block["count"] = count
		return block
	return criteria


## Single-target convenience over choose_targets().
## Convert a CardQuery (or a legacy block) for code that asks Card.matches_criteria().
func _criteria_block(criteria: Variant) -> Dictionary:
	if criteria is Object and criteria.has_method("to_block"):
		return criteria.to_block()
	return criteria if criteria is Dictionary else {}


## Convert a CardQuery (or a legacy filter) for the deck-search window.
func _criteria_filter(criteria: Variant) -> Dictionary:
	if criteria is Object and criteria.has_method("to_filter"):
		return criteria.to_filter()
	return criteria if criteria is Dictionary else {}


func choose_target(criteria: CARD_QUERY, _prompt: String = "Choose a card") -> Card:
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


func untap_all_matching(criteria: CARD_QUERY) -> void:
	untap(cards_in("field", criteria))


func play_from_hand(criteria: CARD_QUERY = null, by: String = "self") -> void:
	_prime_game()
	await game.play_from_hand(_criteria_block(criteria), by)


## Pick one card from an explicit list. Used by hand-play effects where the caller controls the shortlist.
func choose_hand_card(cards: Array, prompt: String = "Choose a card") -> Card:
	if cards.is_empty() or game == null:
		return null
	var agent: Agent = game.agent_for(owner_id)
	if agent == null:
		return null
	return await agent.choose_field_card(owner_id, cards, prompt)


## Play one already-chosen card from hand for free; `enter_dull` is the "onto the field dull" rider.
func play_from_hand_card(card: Card, enter_dull: bool = false) -> void:
	if card == null or not is_instance_valid(card) or game == null:
		return
	var owner_hand: Hand = game.hand_for(1 if card.controller == Card.PLAYER else 2)
	if owner_hand == null:
		return
	owner_hand.remove_for_play(card)
	card.reset_for_field_arrival()
	game.field.play_card(card, card.controller == Card.OPPONENT, true)
	if enter_dull:
		card.tap()


## The common "you may play a card from hand" shape: shortlist, ask, choose, play.
func may_play_from_hand(criteria: CARD_QUERY, enter_dull: bool = false,
		prompt: String = "Play a card") -> bool:
	var candidates: Array = cards_in("hand", criteria, "self")
	if candidates.is_empty():
		return false
	if not await may(prompt):
		return false
	var picked: Card = await choose_hand_card(candidates, prompt)
	if picked == null:
		return false
	play_from_hand_card(picked, enter_dull)
	return true


func break_zone_to_hand(filter: CARD_QUERY = null) -> void:
	_prime_game()
	await game.break_zone_to_hand(_criteria_filter(filter))


func choose_break_zone_card(criteria: CARD_QUERY, chooser: String = "self",
		prompt: String = "Choose a card in your Break Zone") -> void:
	_prime_game()
	await game.choose_break_zone_card(_criteria_block(criteria), chooser, prompt)


func put_card_into_hand() -> void:
	_prime_game()
	await game.put_card_into_hand()


func put_hand_card_on_bottom() -> void:
	_prime_game()
	await game.put_hand_card_on_bottom()


func search_deck(filter: CARD_QUERY, destination: String = "hand", tapped: bool = false) -> void:
	if game != null:
		# The search opens a window and awaits the agent; this must be awaited or the effect resolves
		# while the picker is still open.
		await game.search_deck(_criteria_filter(filter), destination, tapped, owner_id)


## Multi-card search with dynamic selection rules (Golbez 135). `request` is a SelectionRequest; its query
## supplies the pool filter, and its constraints control what stays selectable as the pick grows.
func search_deck_multi(request, destination: String = "field", suppress_auto: bool = true,
		prompt: String = "Choose cards") -> void:
	if game != null:
		await game.search_deck_multi(request, {}, destination, suppress_auto, owner_id, prompt)


func reveal_top(count: int = 1) -> void:
	if game != null:
		# MUST AWAIT: reveal_top animates the card and only appends it to
		# `revealed_cards` after the flip finishes. Calling it fire-and-forget
		# makes check_revealed() read an empty array and take the wrong branch.
		await game.reveal_top(count, owner_id)


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


## Ask which colour a multi-colour source produces. The Field owns the crystal UI; this context call is the seam
## card code uses. A one-element list is answered without opening anything.
## Engine queries card code is allowed to ask, so a card never reaches into ctx.game itself.
func turn_number() -> int:
	return int(game.get("turn_number")) if game != null else 0


func cast_this_turn(card_name: String, player_id: int = 0) -> bool:
	return bool(game.cast_this_turn(card_name, player_id)) if game != null else false


func choose_crystal_in_circle(elements: Array) -> String:
	if elements.is_empty():
		return ""
	if elements.size() == 1:
		return str(elements[0])
	var agent = game.agent_for(owner_id) if game != null else null
	if agent != null and agent.has_method("choose_mana_color"):
		return str(await agent.choose_mana_color(owner_id, source, elements))
	return str(elements[0])


## Damage all cards in `cards` from the effect's source. All damage goes through Field.cause_damage, the single
## entry point that applies damage modifiers and source-aware riders.
func damage(cards: Array, amount: int, mode: String = "") -> void:
	var visuals: Dictionary = Vfx.capture_damage_visuals(cards)
	var hits: Array = _apply_damage_to_cards(cards, amount)
	if hits.is_empty():
		return
	var spread: String = mode if not mode.is_empty() else ("single" if hits.size() == 1 else "multi")
	var origin: Card = source if source != null and is_instance_valid(source) else null
	Vfx.damage(hits, amount, origin.element if origin != null else "", origin, spread, visuals)


## Convenience for effects that explicitly hit the whole board. The director
## can then choose a board wave preset instead of N single-target impacts.
func board_damage(cards: Array, amount: int, mode: String = "radial") -> void:
	var visuals: Dictionary = Vfx.capture_damage_visuals(cards)
	var hits: Array = _apply_damage_to_cards(cards, amount)
	if hits.is_empty():
		return
	var origin: Card = source if source != null and is_instance_valid(source) else null
	Vfx.board_damage(hits, amount, origin.element if origin != null else "",
		origin, "radial" if mode.is_empty() else mode, visuals)


func _apply_damage_to_cards(cards: Array, amount: int) -> Array:
	if field == null or amount <= 0:
		return []
	var origin: Card = source if source != null and is_instance_valid(source) else null
	var hits: Array = []
	for card in cards:
		if card == null or not is_instance_valid(card) or not card.is_on_field():
			continue
		var reaction_delay: float = float(hits.size()) * DAMAGE_REACTION_STAGGER_SECONDS
		field.cause_damage(card, amount, origin, "Ability", controller, -1, reaction_delay)
		hits.append(card)
	game.enforce_game_state_rules()
	return hits


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


## Divide `total` damage among `cards` through the agent seam. Used by Yuffie 85.
func divide_damage(cards: Array, total: int) -> void:
	if cards.is_empty() or total <= 0 or game == null:
		return
	var agent = game.agent_for(owner_id)
	if agent == null:
		return
	var split: Array = await agent.choose_damage_split(owner_id, cards, total)
	for i in range(cards.size()):
		var card: Card = cards[i]
		if card == null or not is_instance_valid(card) or not card.is_on_field():
			continue
		var amount: int = int(split[i]) if i < split.size() else 0
		if amount > 0:
			game.field.cause_damage(card, amount, source, "Ability", controller, -1,
				float(i) * DAMAGE_REACTION_STAGGER_SECONDS)


## Apply the split chosen during ability activation (before commit) to ctx.targets. Used by Yuffie 85.
func apply_damage_division(_total: int) -> void:
	if game == null or targets.is_empty():
		return
	var amounts = game.get("_damage_division")
	if amounts == null or amounts.is_empty():
		amounts = []
	for i in range(targets.size()):
		var card: Card = targets[i]
		if card == null or not is_instance_valid(card) or not card.is_on_field():
			continue
		var amount: int = int(amounts[i]) if i < amounts.size() else 0
		if amount > 0:
			game.field.cause_damage(card, amount, source, "Ability", controller, -1,
				float(i) * DAMAGE_REACTION_STAGGER_SECONDS)
	game.set("_damage_division", [])


## Look at the staging area without moving the card. The count/limit checks live here so a card handler does not
## need to know the Game's reveal internals.
## Reveal staging stays owned by Game; these are the card-facing names so an effect never calls Game directly.
func choose_revealed(criteria: CARD_QUERY = null, prompt: String = "Choose a revealed card") -> void:
	if game == null:
		return
	await game.choose_revealed(_criteria_block(criteria), prompt)


func put_chosen_into_hand() -> void:
	if game == null:
		return
	game.put_chosen_into_hand()


func put_revealed_on_bottom() -> void:
	if game == null:
		return
	game.put_revealed_on_bottom()


func check_revealed(index: int = 0, criteria: CARD_QUERY = null) -> bool:
	if game == null:
		return false
	var staged = game.get("revealed_cards")
	if staged == null or index < 0 or index >= staged.size():
		return false
	var card: Card = staged[index]
	var block: Dictionary = _criteria_block(criteria)
	return card != null and is_instance_valid(card) \
		and (block.is_empty() or card.matches_criteria(block, source))


func remove_revealed_from_game(index: int = 0) -> void:
	if game != null:
		game.remove_revealed_from_game(index)


## Make a card's power exactly `value` for `duration` turns.
func set_power(cards: Array, value: int, duration: int = 1) -> void:
	for card in cards:
		if card != null and is_instance_valid(card) and card.is_on_field():
			card.set_power_value(value, duration)


## Tidus 163: this Forward may attack as many times as its controller's damage count.
func extra_attacks_from_damage() -> void:
	if game != null:
		game.extra_attacks_from_damage()


func opponent_mills(count: int = 1) -> void:
	await mill(3 - owner_id, count)


## The following helpers prime Game's ambient instruction state from this context before calling a Game instruction.
## They exist only for the instructions whose Game implementation still reads `_current_source_card`/`_current_controller`.
func _prime_game() -> void:
	if game == null:
		return
	game.set("_current_source_card", source)
	game.set("_current_controller", controller)


func play_from_break_zone(criteria: CARD_QUERY = null) -> void:
	_prime_game()
	await game.play_from_break_zone(_criteria_block(criteria))


func cast_summon_for_free(criteria: CARD_QUERY = null) -> void:
	_prime_game()
	await game.cast_summon_for_free(_criteria_block(criteria))


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


func return_to_hand(cards: Array, source_kind: String = "") -> void:
	if game == null:
		return
	# START EVERY RETURN FIRST, then wait. Awaiting each tween inside the loop serialises the cards, which is exactly
	# what a mass return must not do.
	var tweens: Array = []
	var kind: String = source_kind
	if kind.is_empty():
		kind = "Summon" if source != null and source.type == Card.SUMMON else "Ability"
	for card in cards:
		if card == null or not is_instance_valid(card) or not card.is_on_field():
			continue
		if not card.can_be_returned_to_hand_by(source, kind):
			continue
		var owner_hand = game.hand_for(1 if card.controller == Card.PLAYER else 2)
		if owner_hand == null:
			continue
		var tween = game.move_card_from_field(card, Card.Zone.HAND, "RETURN",
			func(c): return owner_hand.begin_return_card(c))
		if tween is Tween:
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
