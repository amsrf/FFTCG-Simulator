extends Node3D

@onready var player: PlayerSide = $Player
@onready var opponent: PlayerSide = $Opponent
@onready var deck = $Player/Deck
@onready var opponent_deck = $Opponent/Deck
@onready var hand = $Player/Hand
@onready var opponent_hand = $Opponent/Hand
@onready var field: Field = $Field
@onready var stack : Stack = $Stack
@onready var player_graveyard = $Player/Graveyard
@onready var opponent_graveyard = $Opponent/Graveyard
## REMOVED FROM THE GAME. A separate pile from the Break Zone on purpose: nothing that looks for a card in the
## Break Zone may find one here, and vice versa. Same scene, different exported `zone`.
@onready var player_removed = $Player/Removed
@onready var opponent_removed = $Opponent/Removed
@onready var opponent_front_row_card = $Field/OpponentFrontrowCard
@onready var opponent_damage_zone = $Opponent/DamageZone
@onready var assistant: Assistant = $Assistant
@onready var card_scene = preload("res://card.tscn")
@onready var turn_owner = 1

## The deck search window a card effect can open. Preloaded by PATH rather than referenced through its
## class_name, because a class_name added since Godot last scanned is not in the global cache — which bites
## on every headless run.
const DECK_SEARCH := preload("res://deck_search.tscn")
## The window's SCRIPT as well, because `DeckSearch.CHOOSE_NONE` needs the class and a class_name added since
## Godot last scanned the project is NOT in the global cache — naming the type is a parse error on every run.
const DECK_SEARCH_SCRIPT := preload("res://scripts/deck_search.gd")
## Search filters use the CardFilter vocabulary (name/type/category/job/element/any). Preloaded by path for the same
## reason as the two above.
const CARD_FILTER := preload("res://scripts/card_filter.gd")
const EVENTS := preload("res://scripts/effects/events.gd")

## REVEAL staging. Cards are taken off the top of the deck, shown one at a time, then hidden/inert and kept here
## until the effect moves them somewhere. This array is the search domain for reveal-style cards.
@export var reveal_lift_m: float = 0.5
@export var reveal_lift_seconds: float = 0.25
@export var reveal_flip_seconds: float = 0.30
@export var reveal_flip_back_seconds: float = 0.30
@export var reveal_back_hold_seconds: float = 0.5
@export var reveal_hold_seconds: float = 0.5
@export var reveal_scale: float = 1.3
var revealed_cards: Array[Card] = []
var revealed_owner_id: int = 0


## Emitted when an instruction CHAIN has really finished — not merely when its queue is empty, because an instruction
## that suspends on an animation or a modal leaves the queue empty while it is still running.
signal instructions_finished

var _current_instructions: Array[Instruction]
## True from the moment a fresh chain starts until its last instruction has actually completed.
var _instructions_running: bool = false
var _current_source_card: Card
var _current_controller: String
var _targets = []
## Cards selected by `choose_card` instructions in the current chain, so `apply_effect(..., exclude_chosen)` can
## remove them from a later mass target set. Cleared with the rest of the instruction state.
var _chosen_cards: Array = []
## AERITH 1-064. "When Aerith enters the field, choose up to 3 Backups you control other than Aerith. Activate them." —
## which here is simply: untap each one that was picked.
##
## The instruction carries NO argument, because the effect's TARGETS are the argument: `_targets` is filled from the
## effect card's own list when its instructions run (see _on_stack_execute_card_effect). It deliberately does NOT read
## `Field.targeting_picked` any more — that is the targeting UI's state, and another session can overwrite it before the
## effect resolves. The effect carries what it was given; nothing has to go looking for it afterwards.
## THE ONE LOOP. Every "do X to all of them" instruction is the same walk over _targets, so the walk lives here
## once and the instructions below are just verbs. Adding a verb is one line, not another copy of the loop.
##
## `action` is a Card method name, and `argument` is what to pass it — both come from the card data, which is what
## keeps the JSON readable: a card says dull_targets or damage_targets, not each_target("tap").
##
## is_on_field() is required rather than defensive: an effect that resolves after a card died must not call into it.
##
## STATE-BASED ACTIONS RUN AFTER ALL TARGETS, ALWAYS. There used to be a `settle` flag, on the assumption that only
## damage could kill. That is wrong: conditional_power already exists and is_tapped is already a criteria method, so
## a card like "tapped cards lose 3000 power" makes TAPPING lethal. Every verb has to settle; the flag only invited
## someone to add a verb and forget it.
##
## Once, outside the loop — never inside: a card destroyed by the first target must still receive the effect as
## that target, not vanish mid-iteration and change what the rest take.
## "Your opponent discards N cards from their hand."
##
## THE DISCARDER CHOOSES. That is the rule, and it is also why this is a seam rather than a one-liner: in a real
## player-vs-player match the victim is another PERSON, so the pick has to go to whoever owns the hand. The local
## player gets the hand-selection UI the S cost already uses; every other player is asked through its agent
## (choose_discard), so a RemoteAgent can answer it over the network later.
func opponent_discards(count: int = 1) -> void:
	# THE VICTIM IS THE OTHER SEAT. "player" is P1 and "opponent" is P2, so a card controlled by P1 makes P2
	# discard and vice versa. Getting this backwards is silent — the wrong hand loses a card and the human sees
	# nothing at all, which is exactly how it shipped the first time.
	var caster: int = 1 if _current_controller == "player" else 2
	await discard_from(3 - caster, count)

## The caster discards — "draw 1 card then discard 1 card from your hand" (Vaan). The mirror of opponent_discards(),
## and it goes through the same agent seam, so a human picks from their hand and the AI picks its cheapest.
func controller_discards(count: int = 1) -> void:
	var caster: int = 1 if _current_controller == "player" else 2
	await discard_from(caster, count)

## MILL — "your opponent puts the top card(s) of their deck into the Break Zone".
##
## ONE CARD AT A TIME, each animation awaited, because that is how it should read: a mill 3 is three separate mills,
## not a blur of three cards. The pile owns the flight (Graveyard.draw) so the timing and the arc live in one place.
func mill_player(player_id: int, count: int = 1) -> void:
	var d = deck if player_id == 1 else opponent_deck
	var side: PlayerSide = side_for(player_id)
	if d == null or side == null or side.graveyard == null:
		return
	for _i in range(maxi(0, count)):
		if d.deck_cards.is_empty():
			return
		var card = d.deck_cards.pop_front()
		print("[Mill] P%d mills %s" % [player_id, card.card_name])
		await side.graveyard.call("draw", card)

## The caster's opponent mills. Same seat logic as opponent_discards(): the victim is the other player.
## PLAY 1 CARD FROM HAND FOR FREE. "Play 1 Wind Forward of cost 3 or less from your hand onto the field."
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

## PLAY 1 CARD FROM A BREAK ZONE. "Choose 1 Forward of cost 4 or less from your Break Zone. Play it onto the field."
## (Devout 48/77).
##
## The window IS the deck search — same fan, hover and look — with the zone's own candidates. The choice goes through
## the agent seam so a human gets the window and the AI simply takes one; nothing can hang.
##
## The returning card is reset first (see Card.reset_for_field_arrival): it is a new permanent, not the broken
## object that went to the pile, so damage, statuses and temporary buffs must not ride back with it.
func play_from_break_zone(criteria: Dictionary = {}) -> void:
	var owner_id: int = 1 if _current_controller == "player" else 2
	var pile = player_graveyard if owner_id == 1 else opponent_graveyard
	if pile == null:
		return
	var ids: Array = []
	var candidates: Array = []
	for card in pile.graveyard_cards:
		if card == null or not is_instance_valid(card):
			continue
		if not card.matches_criteria(criteria, _current_source_card):
			continue
		candidates.append(card)
		ids.append(card.id)
	if ids.is_empty():
		print("[BreakZone] nothing in the pile matches")
		return
	var agent: Agent = agent_for(owner_id)
	if agent == null:
		return
	var chosen: int = await agent.choose_break_zone_card(owner_id, ids, criteria)
	if chosen < 0:
		print("[BreakZone] the choice was declined")
		return
	var picked: Card = null
	for card in candidates:
		if card.id == chosen:
			picked = card
			break
	if picked == null:
		return
	print("[BreakZone] plays %s from the Break Zone" % picked.card_name)
	pile.graveyard_cards.erase(picked)
	picked.reset_for_field_arrival()
	field.play_card(picked, owner_id == 2, true)

func opponent_mills(count: int = 1) -> void:
	var caster: int = 1 if _current_controller == "player" else 2
	await mill_player(3 - caster, count)

func discard_from(player_id: int, count: int = 1) -> int:
	var owner_hand: Hand = hand_for(player_id)
	if owner_hand == null:
		return 0
	var discarded: int = 0
	for _i in range(count):
		if owner_hand.cards.is_empty():
			print("[Discard] P%d has no cards to discard" % player_id)
			return discarded
		# ASK THE OWNER, whoever they are. Game does not know or care whether that player is the human at this
		# keyboard, an AI, or a remote opponent — LocalAgent draws a UI, AIAgent picks heuristically, and a future
		# RemoteAgent answers over the network. Special-casing LocalAgent here would have baked this machine's
		# setup into the rules layer, which is the thing the seam exists to prevent.
		var agent: Agent = agent_for(player_id)
		if agent == null:
			return discarded
		var picked: Card = await agent.choose_discard(player_id, owner_hand.cards)
		if picked == null:
			# Cancelled locally, or an agent with no opinion. Nothing more to do.
			return discarded
		print("[Discard] P%d discards %s" % [player_id, picked.card_name])
		owner_hand.discard_card(picked)
		discarded += 1
	return discarded

## "Draw 1 card, then discard 1 card from your hand." The discard is an INSTRUCTION, not a skill cost, so it needs its
## own entry point; and it must set the success latch because Bahamut Fury branches on whether the discard happened.
func discard_cards(count: int = 1) -> void:
	var owner_id: int = 1 if _current_controller == "player" else 2
	var discarded: int = await discard_from(owner_id, count)
	_last_action_succeeded = discarded > 0

## "Choose 1 Character Card in your Break Zone. Add it to your hand." The Break Zone is a pile, so the same search
## window the deck uses is the picker; the filter is a CardFilter block (type/category/job/name/...).
func break_zone_to_hand(filter: Dictionary = {}) -> void:
	_last_action_succeeded = false
	var owner_id: int = 1 if _current_controller == "player" else 2
	var side: PlayerSide = side_for(owner_id)
	var pile = side.graveyard if side != null else null
	if pile == null or pile.graveyard_cards.is_empty():
		return
	var ids: Array = []
	for card in pile.graveyard_cards:
		ids.append(card.id)
	var window = DECK_SEARCH.instantiate()
	add_child(window)
	window.open(ids, filter, "Choose a card in your Break Zone.")
	var chosen: int = await window.finished
	if chosen == DECK_SEARCH_SCRIPT.CHOOSE_NONE:
		return
	var found: Card = null
	for card in pile.graveyard_cards:
		if card.id == chosen:
			found = card
			break
	if found == null:
		return
	pile.graveyard_cards.erase(found)
	pile.update_card_positions()
	var owner_hand: Hand = hand_for(owner_id)
	if owner_hand != null:
		owner_hand.add_card(found)
	_last_action_succeeded = true

## Choose one card from a player's Break Zone. `chooser` is "self" or "opponent"; the pick is remembered in
## `_chosen_cards`. The picker is the same search window used for deck searching, because the Break Zone is a pile.
func choose_break_zone_card(criteria: Dictionary, chooser: String = "self", prompt: String = "Choose a card in your Break Zone") -> void:
	var caster_id: int = 1 if _current_controller == "player" else 2
	var chooser_id: int = 3 - caster_id if chooser == "opponent" else caster_id
	var side: PlayerSide = side_for(chooser_id)
	var pile = side.graveyard if side != null else null
	if pile == null or pile.graveyard_cards.is_empty():
		return
	var candidates: Array = []
	for card in pile.graveyard_cards:
		if _matches_search_filter(card, criteria):
			candidates.append(card)
	if candidates.is_empty():
		return
	var ids: Array = []
	for card in candidates:
		ids.append(card.id)
	var agent: Agent = agent_for(chooser_id)
	if agent == null:
		return
	var chosen_id: int = await agent.choose_break_zone_card(chooser_id, ids, {})
	var chosen: Card = null
	for card in candidates:
		if card.id == chosen_id:
			chosen = card
			break
	if chosen == null:
		return
	_chosen_cards.append(chosen)
	print("[Choose] P%d chose %s from the Break Zone" % [chooser_id, chosen.card_name])

## Put every card chosen by earlier choose_break_zone_card instructions into its owner's hand.
func put_card_into_hand(_argument = null) -> void:
	for card in _chosen_cards.duplicate():
		if card == null or not is_instance_valid(card):
			continue
		var owner_id: int = 1 if card.controller == "player" else 2
		var side: PlayerSide = side_for(owner_id)
		var pile = side.graveyard if side != null else null
		if pile == null or not pile.graveyard_cards.has(card):
			continue
		pile.graveyard_cards.erase(card)
		pile.update_card_positions()
		var owner_hand: Hand = hand_for(owner_id)
		if owner_hand != null:
			print("[Hand] P%d returns %s from the Break Zone" % [owner_id, card.card_name])
			owner_hand.add_card(card)
	_last_action_succeeded = true

## Generic "choose one card from the field" instruction. `chooser` is "self" (the effect's controller) or
## "opponent". Criteria are evaluated relative to the effect source, and the chosen card is remembered in
## `_chosen_cards` so a later apply_effect can exclude it.
func choose_card(criteria: Dictionary, chooser: String = "self", prompt: String = "Choose a card") -> void:
	var caster_id: int = 1 if _current_controller == "player" else 2
	var chooser_id: int = 3 - caster_id if chooser == "opponent" else caster_id
	var source: Card = _current_source_card
	var candidates: Array = []
	for card in field.get_all_cards():
		if card.matches_criteria(criteria, source):
			candidates.append(card)
	if candidates.is_empty():
		return
	var agent: Agent = agent_for(chooser_id)
	var chosen: Card = null
	if agent != null:
		chosen = await agent.choose_field_card(chooser_id, candidates, prompt)
	if chosen == null or not candidates.has(chosen):
		chosen = candidates[0]
	_chosen_cards.append(chosen)
	print("[Choose] P%d chose %s" % [chooser_id, chosen.card_name])

## Generic "set _targets from a criteria block" instruction. `exclude_chosen` removes cards selected by earlier
## choose_card instructions (Cloud of Darkness 158).
func apply_effect(criteria: Dictionary, exclude_chosen: bool = false) -> void:
	_targets = _cards_matching(criteria)
	if exclude_chosen:
		_targets = _targets.filter(func(c): return not _chosen_cards.has(c))
	_last_action_succeeded = not _targets.is_empty()

## PUT, not BREAK: triggers when_enter_break_from_field, never when_break.
func put_targets_into_break_zone(_argument = null) -> void:
	for card in _selected_targets(-1):
		if card == null or not is_instance_valid(card) or not card.is_on_field():
			continue
		print("[BreakZone] %s is put into the Break Zone" % card.card_name)
		put_card_into_graveyard(card)
	enforce_game_state_rules()
	_last_action_succeeded = true

## "Look at the top card of your deck. You may place it at the bottom." The card is named in the log; the choice goes
## through the agent seam so a remote player would get the same prompt.
func look_top_may_bottom() -> void:
	var owner_id: int = 1 if _current_controller == "player" else 2
	var d = deck if owner_id == 1 else opponent_deck
	if d == null or d.deck_cards.is_empty():
		_last_action_succeeded = false
		return
	var top: Card = d.deck_cards[0]
	print("[Deck] P%d looks at the top card: %s" % [owner_id, top.card_name])
	var agent: Agent = agent_for(owner_id)
	var put_bottom: bool = true
	if agent != null:
		put_bottom = await agent.confirm_optional(owner_id, "Put on bottom")
	if put_bottom:
		d.deck_cards.pop_front()
		d.deck_cards.append(top)
	_last_action_succeeded = true

## "Draw 1 card, then place 1 card from your hand at the bottom of your deck." Choosing the card is the agent's job;
## moving it is the rules layer's.
func put_hand_card_on_bottom() -> void:
	_last_action_succeeded = false
	var owner_id: int = 1 if _current_controller == "player" else 2
	var owner_hand: Hand = hand_for(owner_id)
	var d = deck if owner_id == 1 else opponent_deck
	if owner_hand == null or d == null or owner_hand.cards.is_empty():
		return
	var agent: Agent = agent_for(owner_id)
	if agent == null:
		return
	var picked: Card = await agent.choose_hand_card_to_bottom(owner_id, owner_hand.cards)
	if picked == null:
		return
	owner_hand.cards.erase(picked)
	owner_hand.update_card_positions()
	d.deck_cards.append(picked)
	picked.reparent(d, false)
	picked.enter_zone(Card.Zone.DECK)
	_last_action_succeeded = true

## "Cast 1 Summon of cost 6 or less from your hand without paying its cost." The card goes through the SAME charge
## path as a paid cast; we simply complete the payment stage immediately, with nothing selected. That keeps the
## Summon on the stack (so it can be countered) and its targeting flow intact.
func cast_summon_for_free(criteria: Dictionary = {}) -> void:
	_last_action_succeeded = false
	var owner_id: int = 1 if _current_controller == "player" else 2
	var owner_hand: Hand = hand_for(owner_id)
	if owner_hand == null or owner_hand.cards.is_empty():
		return
	var ids: Array = []
	for card in owner_hand.cards:
		ids.append(card.id)
	var chosen: int = await agent_for(owner_id).choose_hand_card_to_play(owner_id, ids, criteria)
	if chosen < 0:
		return
	var picked: Card = null
	for card in owner_hand.cards:
		if card.id == chosen:
			picked = card
			break
	if picked == null:
		return
	if not owner_hand.charge(picked):
		return
	# The Assistant pushed PAYING_COST during charge(); completing it with no mana selected is the "free" part.
	await get_tree().process_frame
	assistant.on_charge_complete()
	_last_action_succeeded = true

## Damage amounts chosen in the split window, waiting for the ability that asked for them to resolve. ONE SLOT is
## enough: the ability commits immediately after the split, so no other effect can claim it in between.
var _damage_division: Array = []

## "Divide 6000 damage among them as you like." The amounts were chosen BEFORE the ability committed (so Cancel
## could step back to targeting); this applies them to `_targets` in the order they were picked.
func divide_damage(_total: int = 0) -> void:
	var amounts: Array = _damage_division.duplicate()
	_damage_division.clear()
	for i in range(_targets.size()):
		var card = _targets[i]
		if card == null or not is_instance_valid(card) or not card.is_on_field():
			continue
		var amount: int = int(amounts[i]) if i < amounts.size() else 0
		if amount <= 0:
			continue
		print("[Divide] %s takes %d" % [card.card_name, amount])
		# Through the damage choke point, not suffer_damage directly: 160/171/165 are replacements and must see
		# every damage event, including divided damage.
		field.cause_damage(card, amount, _current_source_card, _effect_kind(), _current_controller)
	enforce_game_state_rules()

## The targets an instruction applies to: all of them, or the ONE at `index`. Staged effects (Hades: dull the
## Forward, return the Backup) need to say which pick they mean.
func _selected_targets(index: int = -1) -> Array:
	if index < 0:
		return _targets
	if index < _targets.size():
		return [_targets[index]]
	return []

func _each_target(action: String, argument: Array = [], index: int = -1) -> void:
	for card in _selected_targets(index):
		if card != null and is_instance_valid(card) and card.is_on_field():
			card.callv(action, argument)
	enforce_game_state_rules()

## KIMAHRI 102. Ronso Rage copies ONE Special Ability from the chosen Forward. With several S abilities the
## controller chooses through the same agent seam as normal skill selection; the copied text is stripped of every
## activation cost when installed on Kimahri.
func copy_skill(_argument = null) -> void:
	_last_action_succeeded = false
	var source: Card = _current_source_card
	if source == null or not is_instance_valid(source) or not source.is_on_field():
		return
	var target: Card = _targets[0] if not _targets.is_empty() else null
	if target == null or not is_instance_valid(target) or not target.is_on_field():
		print("[CopySkill] no valid target")
		return
	var specials: Array = target.special_ability_skills()
	if specials.is_empty():
		print("[CopySkill] %s has no Special Ability" % target.card_name)
		return
	var chosen: int = 0
	if specials.size() > 1:
		var owner_id: int = 1 if source.controller == "player" else 2
		var agent: Agent = agent_for(owner_id)
		if agent != null:
			chosen = await agent.choose_skill(owner_id, target, specials)
		if chosen < 0 or chosen >= specials.size():
			print("[CopySkill] choice cancelled")
			return
	source.set_copied_skill(specials[chosen], target.card_name)
	_last_action_succeeded = true
	print("[CopySkill] %s copies %s from %s" % [source.card_name, target.card_name, str(specials[chosen].get("text", ""))])


func untap_targets(index: int = -1) -> void:
	_each_target("untap", [], index)

## Wakka 216: the chosen Forward loses all its abilities until the end of the turn. The printed data is untouched;
## Card.card_effects becomes an empty view while the status is present.
func nullify_abilities(duration: int = 1) -> void:
	for card in _selected_targets(-1):
		if card == null or not is_instance_valid(card) or not card.is_on_field():
			continue
		card.add_status_effect("abilities_nullified", duration)
		print("[Nullify] %s loses its abilities" % card.card_name)
	# A nullified source stops granting auras/conditionals immediately, not at the next unrelated board change.
	field.refresh_continuous_effects()
	enforce_game_state_rules()


## Wakka 216: "power becomes 1000". Kept as a temporary delta so normal buffs still expire independently.
func set_targets_power(value: int = 1000, duration: int = 1) -> void:
	_each_target("set_power_value", [value, duration])


## "+1000 power for each Forward you control" (Wakka's attack trigger). The count is read at resolution.
func power_change_targets_per_forward(amount: int = 1000, duration: int = 1) -> void:
	var controller_name: String = _current_controller
	var count: int = field.get_front_cards_for(controller_name).size()
	if count <= 0 or amount == 0:
		return
	_each_target("power_change", [count * amount, duration])

## CANCEL THE CHOSEN STACK OBJECTS (Summoner 53). The target is a Summon that has not resolved yet, so this is not
## `_each_target` — it has no `is_on_field()` and the removal belongs to the Stack.
func cancel_targets(_argument = null) -> void:
	for card in _targets:
		if card != null and is_instance_valid(card):
			stack.call("cancel_stack_card", card)

## DULL. "Dull it", "Dull all Forwards", "Dull it and Freeze it".
##
## It deliberately does NOT go through Card.can_tap(): dulling is not a tap COST, it is the effect. A Frozen card,
## a summoning-sick card and a card that was just activated can all still be dulled by an opponent's effect.
func dull_targets(index: int = -1) -> void:
	_each_target("tap", [], index)

## DAMAGE TO EVERY TARGET. This is what "deal 3000 damage to all the Forwards opponent controls" needed: the target
## SET was already handled by apply_effect, but suffer_damage is a CARD method reached through author "target", so
## it could only ever hit one card.
func damage_targets(amount: int = 0, index: int = -1) -> void:
	if amount <= 0:
		return
	# THE CAUSE GOES WITH THE DAMAGE. Protection like Auron's is judged when the break happens — possibly later, in
	# the state-based sweep — so each card records who dealt this and with what. The SOURCE CARD is passed as well,
	# which is what lets "Warrior of Light doubles its damage" apply to effect damage too.
	for card in _selected_targets(index):
		if card != null and is_instance_valid(card) and card.is_on_field():
			field.cause_damage(card, amount, _current_source_card, _effect_kind(), _current_controller)
	enforce_game_state_rules()

## BREAK every target. "Choose 1 Forward. Break it." — 17 cards in the first hundred say this and none could be
## expressed until now.
##
## This does NOT go through _each_target, and the reason is not stylistic: breaking is a GAME operation, not a Card
## method. break_card() owns the whole path — the unbreakable guard, untapping, leaving the field, the Graveyard,
## and the "put from the field into the Break Zone" trigger — and none of that could be reached by calling a Card
## method through the shared loop. So this is its own walk, and it is short because break_card() does the work.
##
## is_on_field() is checked per card, so a card already broken earlier in the loop cannot be broken twice.
func break_targets(index: int = -1) -> void:
	for card in _selected_targets(index):
		if card != null and is_instance_valid(card) and card.is_on_field():
			print("[Break] ", card.card_name)
			break_card(card, _current_controller, _effect_kind())

## "Summon" when the effect's source card IS a Summon, otherwise "Ability". Used to describe a break/damage's cause so
## protection rules like "cannot be broken by opponent's Summons or abilities" can tell the difference.
func _effect_kind() -> String:
	if _current_source_card != null and is_instance_valid(_current_source_card) and _current_source_card.type == "Summon":
		return "Summon"
	return "Ability"

## Promise.all() for animations. Preloaded by path rather than referenced by class name: a class_name added since the
## editor last scanned is not in the global cache during a headless run, and this project has been bitten by that
## three times.
const ANIMATION_BATCH := preload("res://scripts/animation_batch.gd")

## RETURN TO ITS OWNER'S HAND. "Return the Backup to its owner's hand." / "Return it to its owner's hand."
##
## MULTIPLE CARDS ANIMATE AT THE SAME TIME. Every card's tween is STARTED in the loop and the batch is awaited once
## afterwards — the Godot spelling of Promise.all(). Awaiting inside the loop would put five 0.6 s animations end to
## end, which is what this used to do.
##
## The logical changes still happen immediately (field.remove_card before the loop moves on), so a follow-up
## instruction and a state-based check both see the correct board while the cards are still flying. Only the
## presentation lags, and the effect does not resolve until every animation has finished.
##
## Each card goes to ITS controller's hand, which matters as soon as one effect returns cards to different owners.
func return_targets_to_hand(index: int = -1) -> void:
	var batch = ANIMATION_BATCH.new()
	var source: Card = _current_source_card
	var kind: String = _effect_kind()
	for card in _selected_targets(index):
		if card == null or not is_instance_valid(card) or not card.is_on_field():
			continue
		# Gilgamesh 207: opponent's Summons and abilities cannot return him. The rule is printed on the target, so
		# it is asked here rather than at the call sites.
		if not card.can_be_returned_to_hand_by(source, kind):
			print("[ReturnToHand] %s is protected" % card.card_name)
			continue
		var owner_hand: Hand = hand_for(1 if card.controller == "player" else 2)
		if owner_hand == null:
			continue
		print("[ReturnToHand] ", card.card_name)
		field.remove_card(card)
		# STARTS it; do not await here.
		batch.add(owner_hand.begin_return_card(card))
	batch.close()
	await batch.wait()

## POWER TO EVERY TARGET. "All the Forwards you control gain +1000 power until end of turn."
##
## duration follows Card.power_change: -1 is permanent, N is N turns, so the card data carries it rather than this
## function having an opinion. A negative amount debuffs, which is the same call with a minus in front.
##
## The loop settles state-based actions afterwards like every other verb — which is exactly right here, because a
## power REDUCTION can put a card at 0 and move it to the Graveyard, and that check must happen before the next
## instruction sees the board.
func power_change_targets(amount: int = 0, duration: int = 1, index: int = -1) -> void:
	if amount == 0:
		return
	_each_target("power_change", [amount, duration], index)

## Golem 106: "It gains +2000 power. If it is blocking, it gains +4000 instead." The CHOICE is the same; only the
## number depends on the target's own state at resolution.
func power_change_targets_if_blocking(normal: int = 0, blocking: int = 0, duration: int = 1, index: int = -1) -> void:
	for card in _selected_targets(index):
		if card == null or not is_instance_valid(card) or not card.is_on_field():
			continue
		card.power_change(blocking if card.status_effects.has("blocking") else normal, duration)
	enforce_game_state_rules()

## Tidus 163: "Tidus can attack as many times as your points of damage this turn." The first attack is the normal one,
## so the extra allowance is damage_count - 1.
func extra_attacks_from_damage() -> void:
	var owner_id: int = 1 if _current_controller == "player" else 2
	var side: PlayerSide = side_for(owner_id)
	if _current_source_card == null or side == null:
		return
	_current_source_card.set_extra_attacks(maxi(0, side.damage_count() - 1))
	_last_action_succeeded = true

## Power change to every card matching `criteria`, with NO targeting session — "all the Forwards you control gain
## +1000" (Sylph). Sibling of untap_all_matching(): same evaluator, same source-relative reading, so the criteria may
## say "player"/"your" and still mean the caster's side.
func power_change_matching(criteria: Dictionary, amount: int = 0, duration: int = 1) -> void:
	if amount == 0:
		return
	for card in _cards_matching(criteria):
		if card != null and is_instance_valid(card) and card.is_on_field():
			card.power_change(amount, duration)
	enforce_game_state_rules()

## Draw `count` cards for the effect's controller. The generic "draw" instruction — every draw in the card pool goes
## through here so the empty-deck rule lives in one place.
func draw_cards(count: int = 1, player_id: int = 0) -> void:
	var owner_id: int = player_id if player_id in [1, 2] else (1 if _current_controller == "player" else 2)
	var d = deck if owner_id == 1 else opponent_deck
	var h: Hand = hand_for(owner_id)
	if d == null or h == null:
		return
	for _i in range(maxi(0, count)):
		if d.deck_cards.is_empty():
			return
		print("[Draw] P%d draws 1" % owner_id)
		h.draw(d.deck_cards.pop_front())

## Buff EVERY member of the attacking party — "Chocobo and all the Forwards forming a party with it gain +3000 power".
##
## A party trigger has no chosen target: the card's own text says "a party", so the party currently attacking IS the
## target set. Read at RESOLUTION, which is correct here — the trigger only queues while the attack is being
## declared, and the party cannot change between then and the top of the stack.
func power_change_party(amount: int = 0, duration: int = 1) -> void:
	if amount == 0:
		return
	for card in field.party_members():
		if card != null and is_instance_valid(card) and card.is_on_field():
			print("[Party] %s gains %+d power (until end of turn)" % [card.card_name, amount])
			card.power_change(amount, duration)
	enforce_game_state_rules()

## The "apply_effect" block of the ability this card is resolving, if it has one. A skill resolves through the PROXY it
## put on the stack, and the proxy carries the index of the skill it came from — so read it there first.
func _apply_effect_block(card: Card) -> Dictionary:
	if card == null:
		return {}
	# A stack copy carries a snapshot, so a copied ability's apply_effect survives its source being overwritten.
	if not card.skill_def_override.is_empty() and card.skill_def_override.get("apply_effect") is Dictionary:
		return card.skill_def_override["apply_effect"]
	var src: Card = card.effect_source
	if src != null and card.skill_activation_index >= 0 and "skill" in src.card_effects:
		var skills: Array = src.card_effects["skill"]
		if card.skill_activation_index < skills.size():
			var def: Dictionary = skills[card.skill_activation_index]
			if def.get("apply_effect") is Dictionary:
				return def["apply_effect"]
	if card.card_effects.get("apply_effect") is Dictionary:
		return card.card_effects["apply_effect"]
	return {}

## Every card on the field matching `block`, in field order — the same evaluator choose_target uses, so an apply_effect
## block and a choose_target block mean the same thing by the same keys.
##
## `source` is WHO the criteria are read from, and it defaults to the effect being resolved — because "your"/"player"
## mean the caster, not a fixed seat. Without it an AI-resolved "all the Backups you control" would hit ours.
func _cards_matching(block: Dictionary, source: Card = null) -> Array:
	var from: Card = source if source != null else _current_source_card
	var found: Array = []
	for c in field.get_all_cards():
		if c != null and is_instance_valid(c) and c.matches_criteria(block, from):
			found.append(c)
	return found

## Reveal the top `count` cards of the acting player's deck, one at a time. The card is lifted, turned face-up,
## held, then hidden and made inert; its Card object stays in `revealed_cards` for the following instruction. The
## animation is deliberately sequential: the next card only starts after the previous one has vanished.
func reveal_top(count: int = 1, player_id: int = 0) -> void:
	var owner_id: int = player_id if player_id in [1, 2] else (2 if _current_controller == "opponent" else 1)
	var d = opponent_deck if owner_id == 2 else deck
	if d == null:
		return
	revealed_owner_id = owner_id
	for _i in range(maxi(0, count)):
		if d.deck_cards.is_empty():
			break
		var card: Card = d.deck_cards.pop_front()
		if card == null or not is_instance_valid(card):
			continue
		if card.get_parent() != self:
			card.reparent(self, true)
		card.set_hidden(false)
		card.set_revealed(true)
		var start: Transform3D = card.global_transform
		var lifted_origin: Vector3 = start.origin + Vector3.UP * reveal_lift_m
		var lifted := Transform3D(start.basis, lifted_origin)
		if reveal_lift_seconds > 0.0:
			var lift_tween: Tween = create_tween()
			lift_tween.tween_property(card, "global_transform", lifted, reveal_lift_seconds)
			await lift_tween.finished
		else:
			card.global_transform = lifted
		var face := Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * reveal_scale), lifted_origin)
		if reveal_flip_seconds > 0.0:
			var flip_tween: Tween = create_tween()
			flip_tween.tween_property(card, "global_transform", face, reveal_flip_seconds)
			await flip_tween.finished
		else:
			card.global_transform = face
		if reveal_hold_seconds > 0.0:
			await get_tree().create_timer(reveal_hold_seconds).timeout
		# TURN IT BACK FACE-DOWN before it disappears: the player has read it, and the vanish should not look like
		# a card being discarded face-up.
		var back := Transform3D(start.basis, lifted_origin)
		if reveal_flip_back_seconds > 0.0:
			var back_tween: Tween = create_tween()
			back_tween.tween_property(card, "global_transform", back, reveal_flip_back_seconds)
			await back_tween.finished
		else:
			card.global_transform = back
		if reveal_back_hold_seconds > 0.0:
			await get_tree().create_timer(reveal_back_hold_seconds).timeout
		card.set_hidden(true)
		revealed_cards.append(card)

## Check one revealed card against criteria and publish the answer through the instruction latch. The next
## instruction can use condition "if_last_succeeded" or "if_last_did_not_succeed".
func check_revealed(index: int = 0, criteria: Dictionary = {}) -> void:
	if index < 0 or index >= revealed_cards.size():
		_last_action_succeeded = false
		return
	var card: Card = revealed_cards[index]
	_last_action_succeeded = card != null and is_instance_valid(card) 		and (criteria.is_empty() or card.matches_criteria(criteria, _current_source_card))

## Pick one card from the revealed staging area. The pick is recorded in `_chosen_cards`, exactly like choose_card,
## so the existing hand/play/bottom instructions can act on it.
func choose_revealed(criteria: Dictionary = {}, prompt: String = "Choose a revealed card") -> void:
	var owner_id: int = revealed_owner_id if revealed_owner_id != 0 else (2 if _current_controller == "opponent" else 1)
	var candidates: Array = []
	for card in revealed_cards:
		if card == null or not is_instance_valid(card):
			continue
		if _chosen_cards.has(card):
			continue
		if criteria.is_empty() or card.matches_criteria(criteria, _current_source_card):
			candidates.append(card)
	if candidates.is_empty():
		_last_action_succeeded = false
		return
	var picked: Card = await agent_for(owner_id).choose_field_card(owner_id, candidates, prompt)
	if picked == null or not candidates.has(picked):
		picked = candidates[0]
	_chosen_cards.append(picked)
	_last_action_succeeded = true

## Move the chosen revealed cards to their owner's hand. The card was hidden during the reveal, so restore it and
## let Hand own the arrival animation/layout.
func put_chosen_into_hand(_argument = null) -> void:
	var owner_hand: Hand = opponent_hand if revealed_owner_id == 2 else hand
	if owner_hand == null:
		return
	for card in _chosen_cards.duplicate():
		if card == null or not is_instance_valid(card) or not revealed_cards.has(card):
			continue
		revealed_cards.erase(card)
		card.set_hidden(false)
		owner_hand.add_card(card)
		_chosen_cards.erase(card)

## Play the chosen revealed cards. Characters use the normal play path; this is also the hook for Selh'teus-style
## reveal-to-play effects.
func play_revealed(_argument = null) -> void:
	for card in _chosen_cards.duplicate():
		if card == null or not is_instance_valid(card) or not revealed_cards.has(card):
			continue
		revealed_cards.erase(card)
		card.set_hidden(false)
		card.reset_for_field_arrival()
		field.play_card(card, revealed_owner_id == 2, true)
		_chosen_cards.erase(card)

## Put every revealed card that was NOT chosen on the bottom of its owner's deck, preserving reveal order.
func put_revealed_on_bottom(_argument = null) -> void:
	var d = opponent_deck if revealed_owner_id == 2 else deck
	if d == null:
		return
	for card in revealed_cards.duplicate():
		if card == null or not is_instance_valid(card):
			continue
		if _chosen_cards.has(card):
			continue
		revealed_cards.erase(card)
		card.set_hidden(false)
		card.enter_zone(Card.Zone.DECK)
		card.reparent(d, false)
		card.position = Vector3.ZERO
		d.deck_cards.append(card)
		d.update_card_positions()
	if revealed_cards.is_empty():
		revealed_owner_id = 0

## Remove a revealed card from the game (Gilgamesh/Cait Sith). Used after the reveal animation.
func remove_revealed_from_game(index: int = 0) -> void:
	if revealed_cards.is_empty():
		return
	if index < 0:
		index = 0
	if index >= revealed_cards.size():
		return
	var card: Card = revealed_cards.pop_at(index)
	if card != null and is_instance_valid(card):
		card.set_hidden(false)
		_send_card_to_removed(card)
	if revealed_cards.is_empty():
		revealed_owner_id = 0

## A generic instruction: open a targeting session in the middle of an instruction chain. The cards chosen become
## the current targets, so the next instruction (dull_targets, damage_targets, ...) acts on them. Used by delayed
## riders such as Rygdea's "when it is put into the Break Zone, choose an opponent Forward".
func choose_target(criteria: Dictionary) -> void:
	var source: Card = _current_source_card
	if source == null or not is_instance_valid(source):
		return
	if not field.has_viable_target(criteria, source, "Ability"):
		_last_action_succeeded = false
		return
	field.request_target(criteria, source, false, "Ability")
	# A non-local agent completes synchronously inside request_target(); only a local player leaves the list empty.
	if field.targeting_picked.is_empty():
		await assistant.target_complete
	_targets = field.targeting_picked.duplicate()
	_last_action_succeeded = not _targets.is_empty()

## Grant a status to EVERY target of the current effect. The multi-target twin of Card.add_status_effect, which an
## instruction can only reach one card with — see untap_targets above for the same shape and why it lives here.
##
## The duration is in TURNS: 1 means "until the end of this turn", expired by Card.turn_end() alongside attacking and
## blocking. A payload (Rygdea) rides with the status and is restored when the card reaches the Break Zone.
func add_status_to_targets(status: String, duration: int = 1, extra = null) -> void:
	var payload: Dictionary = extra.duplicate() if extra is Dictionary else {}
	if not payload.is_empty():
		# The rider remembers who created it, so a break-zone trigger can still ask "your opponent" correctly
		# and can point the targeting arrow back at the source card.
		payload["source"] = _current_source_card
		payload["controller"] = _current_controller
	for card in _targets:
		if card != null and is_instance_valid(card):
			card.add_status_effect(status, duration, payload)
			print("[Status] ", card.card_name, " gains ", status, " for ", duration, " turn(s)")
## Re-entrancy guard: true while a priority round is running. Prevents
## overlapping priority loops when Stack.request_priority fires mid-round.
var _priority_lock: bool = false
## Decision seams. The loop only calls these, so the human, the AI and (later) a
## networked player are interchangeable. Assigned in start_match().
var player_agent: Agent
var opponent_agent: Agent
## Match state. This is the single owner: `GlobalVariables` must not keep a
## copy, and `Field.phase` just reads through to here.
var phase: GlobalVariables.Phase
## Set when someone has won; stops the phase machine and sends us to the menu.
var match_over: bool = false
var priority_holder: int = 0

## How long an opponent's chosen blocker is shown before the damage step. The pick is drawn
## as soon as it is made; this only paces it so a human can actually read the link.
@export var block_announce_time: float = 1.2

## Shaders that only appear MID-ANIMATION, so they must be compiled before the player ever sees them.
##
## Godot compiles a shader the first time a material using it is actually rendered — lazily, on the spot. Under the
## Compatibility renderer that compile lands in the middle of a frame, so the first card to absorb a payment orb
## stutters exactly when the player is watching, and every later one is smooth. Warming them up here, at match start,
## moves that cost to a moment where nothing is moving.
##
## Anything added to the payment/absorb effects belongs in this list.
const EFFECT_SHADERS: Array[Shader] = [
	preload("res://shaders/orb_halo.gdshader"),
	preload("res://shaders/absorb_ring.gdshader"),
]

func _ready():
	start_match(MatchSetup.resolve_config())

## Forces each effect shader to compile by putting a 1-pixel quad using it on screen for one frame. The quads free
## themselves at the end of that frame, by which point the compile has happened, which is all this is for.
func _warm_up_effect_shaders() -> void:
	for shader in EFFECT_SHADERS:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var plane := QuadMesh.new()
		plane.size = Vector2(0.001, 0.001)
		var quad := MeshInstance3D.new()
		quad.name = "ShaderWarmup"
		quad.mesh = plane
		quad.material_override = mat
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(quad)
		quad.queue_free()

func start_match(config: Dictionary) -> void:
	# Everything a match needs comes from its config (see MatchSetup presets);
	# the same scene serves the menu, the practice board, and future self-play.
	priority_holder = 0
	_warm_up_effect_shaders()
	# DECIDE THE VIEW EXPLICITLY. game.tscn marks no camera current, so Godot activates the FIRST Camera3D in the
	# tree — and once a damage camera exists it is easy to place one ABOVE the board camera, at which point the
	# match starts looking through a snapshot camera aimed at a damage zone. That is not hypothetical: it happened,
	# it showed an upside-down board, and it broke every test that measures screen positions. The board view is the
	# camera that is NOT one of the damage cameras, and it is made current here so scene order stops mattering.
	var damage_names: Array = DAMAGE_CAMERAS.values()
	for node in find_children("*", "Camera3D", true, false):
		# A DAMAGE CAMERA IS IDENTIFIED BY WHERE IT IS, NOT BY ITS NAME. It lives inside a DamageZone, so any
		# camera there is one. Names were tried first and failed twice — the node was built as
		# "CameraPlayerDamage" while the code looked for "CameraDamagePlayer", and then renamed to plain "Camera"
		# — whereas position is something the scene cannot get wrong by typing.
		var walker: Node = node.get_parent()
		var in_damage_zone: bool = false
		while walker != null:
			if str(walker.name) == "DamageZone":
				in_damage_zone = true
				break
			walker = walker.get_parent()
		if in_damage_zone:
			continue
		var board_cam: Camera3D = node as Camera3D
		board_cam.current = true
		_board_camera = board_cam
		print("[Camera] board view is '%s'" % board_cam.name)
		break

	player_agent = LocalAgent.new()
	player_agent.bind(self)
	match str(config.get("opponent_type", "mock")):
		"ai":
			opponent_agent = AIAgent.new()
		_:
			opponent_agent = MockAgent.new()
	opponent_agent.bind(self)

	for id in config.get("player_hand", []):
		hand.add_card(create_card(int(id), 'player'))
	for id in config.get("opponent_hand", []):
		opponent_hand.add_card(create_card(int(id), 'opponent'))

	var player_deck_cards := []
	for id in config.get("player_deck", []):
		player_deck_cards.append(create_card(int(id), 'player'))
	deck.add_cards(player_deck_cards)

	var opponent_deck_cards := []
	for id in config.get("opponent_deck", []):
		opponent_deck_cards.append(create_card(int(id), 'opponent'))
	opponent_deck.add_cards(opponent_deck_cards)

	var opponent_field_cards: Array = config.get("opponent_field", [])
	var player_field_cards: Array = config.get("player_field", [])
	_place_field_cards(opponent_field_cards, true)
	_place_field_cards(player_field_cards, false)

	# PRE-FILL THE ZONES for a test board, so the zone viewer (click a card in the zone, or press V / G) has
	# something to show without playing a match first. add_card is the INSTANT path on purpose: a setup board
	# should already be in place, not dropping cards in front of the player before the first frame.
	for zone_setup in [
			[config.get("player_graveyard", []), false, "Player", "Graveyard"],
			[config.get("opponent_graveyard", []), true, "Opponent", "Graveyard"],
			[config.get("player_damage", []), false, "Player", "DamageZone"],
			[config.get("opponent_damage", []), true, "Opponent", "DamageZone"],
	]:
		var ids: Array = zone_setup[0]
		var zone: Node = get_node_or_null("%s/%s" % [zone_setup[2], zone_setup[3]])
		if zone == null:
			continue
		for id in ids:
			var card = create_card(int(id), 'opponent' if zone_setup[1] else 'player')
			# add_child FIRST: add_card reparents, and a node with no parent has no meaningful transform.
			add_child(card)
			zone.call("add_card", card)

	match str(config.get("first_phase", "first_main")):
		"active":
			phase_index = 0
			_enter_phase(GlobalVariables.Phase.ACTIVE_PHASE)
		_:
			phase_index = 2
			_enter_phase(GlobalVariables.Phase.FIRST_MAIN_PHASE)

func controller_for(player_id: int) -> String:
	return "player" if player_id == 1 else "opponent"

func side_for(player_id: int) -> PlayerSide:
	return player if player_id == 1 else opponent

func agent_for(player_id: int) -> Agent:
	return player_agent if player_id == 1 else opponent_agent

func hand_for(player_id: int) -> Hand:
	return hand if player_id == 1 else opponent_hand

## Play `card` from `player_id`'s hand. The human finishes the payment by
## clicking the payment modal; any other player pays through its agent.
## Returns whether the cost ended up paid.
func play_card_for(player_id: int, card: Card) -> bool:
	var owner_hand: Hand = hand_for(player_id)
	var agent: Agent = agent_for(player_id)
	if owner_hand == null or card == null or agent == null:
		return false
	# charge() leaves the hand and emits charge_start: Stack parks the card and
	# Assistant opens the payment modal + sets mana_cost from the card. It
	# returns false when the play is illegal (a Character off-turn, or with a
	# non-empty stack) — nothing was charged, so there is nothing to pay.
	if not owner_hand.charge(card):
		return false
	if agent is LocalAgent:
		return true  # the human pays by selecting backups in the modal
	# The human must never interact with another player's payment modal.
	assistant.hide_buttons()
	var paid: bool = await agent.pay_cost(player_id, assistant.mana_cost)
	if paid:
		assistant.on_charge_complete()
	else:
		assistant.on_charge_cancelled()
	return paid

func _place_field_cards(cards: Array, is_opponent: bool) -> void:
	# Pre-placed board cards (practice preset). Empty for a standard match.
	for card_data in cards:
		var card = create_card(int(card_data.get("id", 0)), 'opponent' if is_opponent else 'player')
		opponent_front_row_card.get_parent().add_child(card)
		card.transform = opponent_front_row_card.transform
		field.play_card(card, is_opponent, false, false)
		if card_data.get("tapped", false):
			card.tap()

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_ESCAPE:
		# Only leave when nothing modal is mid-resolution, so we don't free the
		# scene out from under a pending await.
		var pm = GlobalVariables.get_player_mode()
		if pm == GlobalVariables.Player_Mode.FREE or pm == GlobalVariables.Player_Mode.INSTANT_SPEED_TIME:
			MatchSetup.go_to_menu()
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_D:
		var card = deck.deck_cards.pop_front()
		hand.draw(card)
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_F:
		var card = opponent_deck.deck_cards.pop_front()
		opponent_hand.draw(card)
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_C:
		# DEBUG: press C to look through the next camera. "What will this camera actually see" is otherwise only
		# answerable by editing the scene, running, looking, and editing again — and the answer is a picture, not
		# a transform. The list is rebuilt on every press from the live tree, so it cannot go stale when a camera
		# is added, moved, renamed or put inside a zone. The next one is worked out from whichever is active now,
		# so nothing has to remember a counter.
		var cams: Array = find_children("*", "Camera3D", true, false)
		if not cams.is_empty():
			var here: int = cams.find(get_viewport().get_camera_3d())
			var next_cam: Camera3D = cams[(here + 1) % cams.size()]
			next_cam.current = true
			print("[Camera] looking through '%s' | fov %.0f | pos %s" % [
				next_cam.name, next_cam.fov, str(next_cam.global_position)])
			if $PhaseText:
				$PhaseText.text = "CAMERA: %s  (C to cycle)" % next_cam.name
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_T:
		# DEBUG: the REAL damage path. take_damage() is what emits `damaged` and therefore what fires the damage
		# zoom. The old version called the zone directly, so a card appeared in the damage zone but nothing
		# counted it as damage and the camera never moved — which is exactly how it looked when the AI attacked.
		opponent.take_damage(1)
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_Y:
		# DEBUG: the same, on OURSELVES. T damages the opponent (their zone, their camera); Y damages the player,
		# so the player's own damage zone and its camera can be looked at without waiting for the AI to land an
		# attack through the block step. Same real path, so it counts.
		#
		# Worth knowing: it counts toward the defeat total like any other damage. Seven presses of Y and you lose,
		# which is correct rather than a bug — the debug key uses the real rules on purpose.
		player.take_damage(1)
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_V:
		_show_zone_view(player.damage_zone, "Damage Zone")
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_G:
		_show_zone_view(player.graveyard, "Graveyard")


## READ-ONLY VIEW of a zone's contents, in the same fan window the deck search uses — so a card reads the same way
## wherever it is inspected, and there is no second viewer to drift from it.
##
## One helper for both zones because of an asymmetry that would bite if copied to two call sites: the damage zone
## keeps its cards in `cards`, the graveyard in `graveyard_cards`.
##
## V = your damage zone, G = your graveyard. Left/right click on the zones themselves comes next; the keys make
## this usable and testable now.
func _show_zone_view(zone: Node, title: String) -> void:
	if zone == null:
		return
	var raw: Variant = zone.get("cards")
	if raw == null:
		raw = zone.get("graveyard_cards")
	if raw == null:
		return
	var ids: Array = []
	for c in raw:
		if c != null and is_instance_valid(c):
			ids.append(int(c.id))
	if ids.is_empty():
		# An empty zone has nothing to show, and an empty window would look broken rather than empty.
		print("[ZoneView] %s is empty" % title)
		if $PhaseText:
			$PhaseText.text = "%s — empty" % title
		return
	var window = DECK_SEARCH.instantiate()
	add_child(window)
	window.call("open_view", ids, "%s — %d card%s" % [title, ids.size(), "" if ids.size() == 1 else "s"])
	print("[ZoneView] %s: %d cards" % [title, ids.size()])


func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# RIGHT-CLICK WHILE TARGETING IS ONE STEP BACK, not a cancel: from "a target is picked, the arc is locked and
		# Confirm is offered" to "aiming again, the arc follows the mouse". Cancel is still the way out of the effect
		# entirely. Anything else it might mean is left alone.
		if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET:
			field.clear_target_selection()
		if($FocusCard):
			$FocusCard.visible = false

func create_card(id, controller):
	var card = card_scene.instantiate()  
	card.initialize(id,controller) 
	if card.has_signal("execute_instructions"):
		card.execute_instructions.connect(_execute_instructions)
	return card

func _execute_instructions(instructions: Array[Instruction]) -> void:
	# FRESH CHAIN? Asked BEFORE the concatenation, because that is the only moment the answer exists.
	#
	# A `condition: "if_last_succeeded"` instruction may only read the instruction immediately before it IN THIS
	# CHAIN. Without this reset the flag survives from an earlier effect's search and "if you do so" would wrongly
	# run. Only a genuinely empty queue counts as fresh: triggered abilities PREPEND their instructions mid-chain,
	# and a naive reset would wipe a flag the current chain still needs.
	var fresh_chain: bool = _current_instructions.is_empty()
	# Concatenate arrays (new instructions go in front)
	_current_instructions = instructions + _current_instructions
	if fresh_chain:
		_last_action_succeeded = false
		_instructions_running = true
	_process_next_instruction()

## The awaitable form of the instruction chain, for callers that must know it has really finished. Safe when the chain
## runs synchronously: `_instructions_running` is already false, so there is nothing to wait for.
func _execute_instructions_and_wait(instructions: Array[Instruction]) -> void:
	_execute_instructions(instructions)
	while _instructions_running:
		await instructions_finished

## TURN HISTORY. Deliberately a plain ledger, not a rules engine: `turn_history[turn_number]` is the list of things
## that happened during that turn, in order, so a condition can ask "have I cast Alexander this turn?".
##
## Each entry: { actor: 1|2, activity: String, targets: Array }. `activity` is a short human-readable line ("Casted
## Ifrit", "Forward Squall was played") and doubles as the key that lookups match on — stringly-typed on purpose for
## now, because the shapes of what cards ask for are still unknown. When they become clearer, replace the strings with
## an enum plus a data dictionary rather than growing this into a query language.
##
## Turns are KEPT, not cleared: the array for an old turn costs nothing and "this turn" is a filter, not a deletion.
var turn_number: int = 1
var turn_history: Dictionary = {}
## once_per_turn event triggers, keyed by card instance + trigger index + turn_number. The turn number is part of the
## key, so a new turn starts with a clean slate without any reset pass.
var _event_triggers_fired: Dictionary = {}

func record_action(activity: String, targets: Array = [], actor: int = 0) -> void:
	# actor 0 = "whoever's turn it is", which is right for anything the turn player initiates. Effects that fire on
	# their own (a triggered ability during the opponent's turn) should pass their controller explicitly.
	var who: int = actor if actor != 0 else turn_owner
	if not turn_history.has(turn_number):
		turn_history[turn_number] = []
	turn_history[turn_number].append({
		"actor": who,
		"activity": activity,
		"targets": targets.duplicate(),
	})
	print("[History] T%d P%s: %s" % [turn_number, who, activity])

func actions_this_turn() -> Array:
	return turn_history.get(turn_number, [])

## "If you have cast [X] this turn" — owner_id 0 means either player.
func cast_this_turn(card_name: String, owner_id: int = 0) -> bool:
	var wanted: String = "Casted %s" % card_name
	for entry in actions_this_turn():
		if str(entry.get("activity", "")) == wanted:
			if owner_id == 0 or int(entry.get("actor", 0)) == owner_id:
				return true
	return false

## "If a Forward was played this turn" (any Forward), used by effects that count plays rather than a named card.
func played_this_turn(type_name: String, owner_id: int = 0) -> bool:
	for entry in actions_this_turn():
		var activity: String = str(entry.get("activity", ""))
		if not activity.begins_with("%s " % type_name) or not activity.ends_with(" was played"):
			continue
		if owner_id == 0 or int(entry.get("actor", 0)) == owner_id:
			return true
	return false

func _clean_instruction_stack():
	_current_source_card = null
	_targets = []
	_chosen_cards = []

## Whether the instruction that just ran accomplished something. Read by `condition: "if_last_succeeded"` — the
## "search ... and if you do so, return Vanille" shape, where the second half must not happen after a cancel.
var _last_action_succeeded: bool = true

## CONDITION EVALUATION for `Instruction.condition`. Stringly-typed on purpose — the shapes cards ask for are still
## being discovered, so this is a small parser plus predicates rather than a data structure:
##
##   ""                        unconditional (every instruction written before conditions existed)
##   "if_last_succeeded"       the instruction immediately before this one reported success
##   "if_last_did_not_succeed" ...or was SKIPPED / failed. Pair it with a guarded instruction above to get an
##                             if/else: "deal 4000 if Brynhildr was cast, otherwise deal 2000".
##   "cast_this_turn:<name>"   the ability's controller cast that card this turn (reads the turn ledger)
##   "controls:<name|type>"    the ability's controller controls a card with that name, or of that type
##
## Unknown conditions are treated as TRUE and printed, so a typo shows up in the log instead of silently deleting an
## effect — the failure mode that hurts least.
func _condition_holds(condition: String) -> bool:
	match condition:
		"", "always":
			return true
		"if_last_succeeded":
			return _last_action_succeeded
		"if_last_did_not_succeed":
			return not _last_action_succeeded
	if condition.begins_with("cast_this_turn:"):
		return cast_this_turn(condition.trim_prefix("cast_this_turn:").strip_edges(), _condition_owner())
	if condition.begins_with("controls:"):
		return _controls(condition.trim_prefix("controls:").strip_edges())
	# "forms a party WITH <name> and attacks" (Queen of Eblan + King of Eblan, Chelinka + Yuri). Judged against the
	# party that is currently attacking, because a party only exists while it attacks.
	if condition.begins_with("party_has_named:"):
		var wanted_name: String = condition.trim_prefix("party_has_named:").strip_edges()
		for member in field.party_members():
			if member != null and is_instance_valid(member) and member.card_name == wanted_name:
				return true
		return false
	print("[Condition] unknown condition '%s' — treated as true" % condition)
	return true

## Whose perspective a condition is judged from: the controller of the ability being resolved. `_current_controller`
## is set when the effect goes on the stack; fall back to the turn player if a condition is evaluated outside one.
func _condition_owner() -> int:
	if _current_controller == "player":
		return 1
	if _current_controller == "opponent":
		return 2
	return turn_owner

## "controls:Laguna" (by name) or "controls:Forward"/"controls:Backup" (by type), for the ability's controller.
func _controls(spec: String) -> bool:
	var wanted: String = "player" if _condition_owner() == 1 else "opponent"
	for card in field.get_all_cards():
		if card.controller != wanted:
			continue
		if spec == "Forward" or spec == "Backup":
			if card.type == spec:
				return true
		elif card.card_name == spec:
			return true
	return false

## UNTAP EVERYTHING MATCHING CRITERIA — not just the chosen targets. "Activate all the Backups you control."
## Deliberately separate from untap_targets(), whose scope is `_targets`; a card that says "all" must not depend on
## what the player happened to pick.
func untap_all_matching(criteria: Dictionary = {}) -> void:
	for card in _cards_matching(criteria):
		if card != null and is_instance_valid(card) and card.is_on_field():
			card.untap()

## EACH PLAYER DISCARDS. The ability's controller chooses first, then the other player — the usual order for a
## symmetric discard, and each side goes through its own agent so a human gets a picker and the AI picks its cheapest.
func each_player_discards(count: int = 1) -> void:
	var starter: int = 1 if _current_controller == "player" else 2
	await discard_from(starter, count)
	await discard_from(3 - starter, count)

func _process_next_instruction() -> void:
	if _current_instructions.is_empty():
		# All instructions resolved: apply state-based actions so a card
		# whose accumulated damage has reached its power is broken now.
		enforce_game_state_rules()
		# THE CHAIN IS FINISHED, and this is the only place that knows it. An instruction that suspends on an
		# animation or a modal leaves the queue empty WHILE IT IS STILL RUNNING, so emptiness alone cannot mean done.
		_clean_instruction_stack()
		_instructions_running = false
		instructions_finished.emit()
		return

	# CONDITIONAL GUARD. Checked BEFORE the instruction is resolved, and it consumes no state of its own: the flag is
	# whatever the previous instruction left behind.
	var next_instruction = _current_instructions[0]
	if not _condition_holds(next_instruction.condition):
		print("[Instruction] skipped ", next_instruction.action,
			" (condition '%s' is false)" % next_instruction.condition)
		_current_instructions.pop_front()
		# A SKIPPED INSTRUCTION DID NOT SUCCEED. This is what makes `if_last_did_not_succeed` usable as the
		# else-branch of the guarded instruction above it; without it the negation would read a stale `true`.
		_last_action_succeeded = false
		_process_next_instruction()
		return

	var instruction = _current_instructions.pop_front()
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
	var executor = _resolve_executor(instruction.executor, _current_source_card)
	if executor == null:
		push_error("Instruction failed: unknown executor '%s' for action '%s'" % [instruction.executor, instruction.action])
		_process_next_instruction()
		return
	if not executor.has_method(instruction.action):
		push_error("Instruction failed: executor '%s' has no method '%s'" % [executor, instruction.action])
		_process_next_instruction()
		return

	var args = []
	if instruction.value != null:
		if instruction.value is Array:
			args = instruction.value
		else:
			args.append(instruction.value)
	# OPTIMISTIC SUCCESS, so `if_last_did_not_succeed` can act as an else-branch. A verb that RAN is treated as
	# having done something unless it says otherwise (search_deck sets false on a cancel); a verb that was SKIPPED
	# already wrote false. Without this line an unguarded instruction would leave the latch at the chain-start
	# `false` and the else-branch would run on top of it.
	_last_action_succeeded = true
	# AWAITED, so an action that suspends for a player decision — search_deck's window — genuinely holds up
	# the rest of the instruction list rather than letting the game run on behind it. Awaiting a plain
	# method's return value is a no-op, so actions that do not suspend cost nothing for this. It does make
	# `_process_next_instruction` a coroutine, which is fine: its callers do not need to wait for it.
	await executor.callv(instruction.action, args)
	_process_next_instruction()

func _resolve_executor(executor_key: String, source_card: Card = null) -> Node:
	match executor_key:
		"card":
			return source_card
		"hand":
			return $Player/Hand
		"deck":
			return $Player/Deck
		"assistant":
			return $Assistant
		"field":
			return $Field
		"player":
			return $Player
		"opponent":
			return $Opponent
		"opponent_damage_zone":
			return $Opponent/DamageZone
		"game":
			return self
		"target":
			if _targets.is_empty() or _targets[0] == null:
				push_error("Instruction targets no card")
				return null
			return _targets[0]
		"targets":
			return _targets
		_:
			var node: Node = get_node_or_null(executor_key)
			if node == null:
				push_error("Unknown executor: %s" % executor_key)
			return node

func cause_damage():
	# WHO CAUSED IT travels with the damage. Exdeath 122 ("any card put in the Damage Zone due to Exdeath cannot use
	# its EX Burst") is judged against the dealer, and a party's damage is dealt by the whole party — so if any
	# member suppresses EX Burst, the damage it puts in the zone is covered.
	var source: Card = field.attacker_card
	for member in field.party_members():
		if member != null and is_instance_valid(member) 				and (member.static_rule("ex_burst_disabler", false) == true or member.status_effects.has("ex_burst_disabler")):
			source = member
			break
	# The DEFENDING player (whoever isn't taking the turn) takes the damage, so
	# an opponent attack actually hurts the human.
	side_for(3 - turn_owner).take_damage(1, source)
	# Triggered auto-ability: "when this card deals damage to the opponent".
	if field.attacker_card != null:
		var attacker: Card = field.attacker_card
		if attacker.abilities_enabled() and attacker.effect_handles_event(EVENTS.Event.CAUSE_DAMAGE_TO_PLAYER):
			stack.enqueue_code_trigger(attacker, EVENTS.Event.CAUSE_DAMAGE_TO_PLAYER)
		else:
			stack.begin_triggered_ability(attacker, "when_cause_damage_to_player")
	
func cause_attacking_damage():
	if field.blocker_card == null:
		cause_damage()
		# "When a party you control deals damage to your opponent" (Andoria, Boko). Only an UNBLOCKED attack deals
		# player damage, and only a real party has the trigger.
		if field.is_party():
			field.trigger_party_deals_damage(controller_for(turn_owner))

## A side took damage. Checking the threshold here means every damage source —
## attacks and effects alike — shares one win condition.
func _on_player_side_damaged(side: PlayerSide) -> void:
	# THE ZOOM RUNS FOR EVERY HIT, so it is called BEFORE the guard below — that guard returns early for
	# ordinary damage and only lets a defeat through, so hooking after it would zoom only on the losing blow.
	_zoom_to_damage(side)
	# "For each point of damage you have received" (Dark Knight, Gabranth): the damage zone just grew, so every
	# count-based power rule has to be re-evaluated — on BOTH sides' cards, since one player's damage feeds their own
	# cards only, but the recompute is cheap and idempotent.
	field.refresh_continuous_effects()
	if not match_over:
		field.trigger_event(EVENTS.Event.DAMAGE_RECEIVED, {"player_id": 1 if side == player else 2})
	if match_over or not side.is_defeated():
		return
	# Compare against the node, like side_for(), so there is only one definition
	# of which side is P1 (the exported `controller` must not be a second one).
	_end_match(2 if side == player else 1)


# ------------------------------------------------------------------
# Damage zoom
# ------------------------------------------------------------------
## When a side takes damage the view cuts to that side's damage zone for a moment, so the card landing there
## is actually seen rather than inferred from a number.
##
## THE CAMERAS ARE PLACED BY HAND, and that is deliberate: angle, height and distance are taste decisions, so
## the scene owns them and this only decides WHEN to look and for how long. What it adds is TRACKING — "the
## centre of where the damage card is going to be placed" is a moving target, because the row grows as cards
## accumulate, so the camera is translated by however far that slot has drifted from the first one. Parked
## over the first slot it reproduces the hand-placed framing exactly.
##
## A missing camera is skipped silently. A match must never depend on a node existing, and these two are
## optional decoration — the game is fully playable with neither built.
##
## THE NAMES ARE THE SCENE'S, NOT MINE. The first version looked for "CameraDamagePlayer" and the node was
## built as "CameraPlayerDamage" — the same words in the other order — so the camera existed, was placed, was
## saved, and was never once used, silently, because that is exactly what a missing camera does. Matching the
## scene's own convention rather than insisting on mine is the fix; the silence is the reason it took a
## round trip to find.
const DAMAGE_CAMERAS := {
	"player": "CameraPlayerDamage",
	"opponent": "CameraOpponentDamage",
}

@export var damage_zoom_in_seconds: float = 0.35
@export var damage_zoom_hold_seconds: float = 1.0
@export var damage_zoom_out_seconds: float = 0.4

## The board view to come back to. Captured on the first zoom, because at that moment it IS the board view.
var _board_camera: Camera3D = null
var _damage_tween: Tween = null
## Each damage camera's HAND-PLACED pose, remembered the first time it is used. The return leg must go back to
## THIS, not to the board's pose: tweening a damage camera onto the board view parks it there, so the next zoom
## reads its position from the board, computes a target beside the board, and the view never leaves the board
## again. That is precisely "it zoomed once and then stopped".
var _damage_home: Dictionary = {}


## The world point the NEXT damage card will occupy in `zone` — the same formula the zone uses for an incoming
## card, evaluated at the slot after the last one, in the zone's own space.
func _damage_slot_world(zone: Node3D, index: int) -> Vector3:
	return zone.global_transform * (zone.call("calculate_card_position", index) as Vector3)


func _zoom_to_damage(side: PlayerSide) -> void:
	if side == null or match_over:
		return
	var zone: Node3D = side.get_node_or_null("DamageZone") as Node3D
	if zone == null:
		return
	# DECLARED HERE, not inside the fallback below: the print further down reports which side was zoomed, and
	# scoping it to the fallback is what turned this function into a parse error for a whole run.
	var which: String = "player" if side == player else "opponent"
	# THE CAMERA LIVES IN THE ZONE, and its NAME DOES NOT MATTER: whatever Camera3D sits inside this side's damage
	# zone IS this side's damage camera. That is the arrangement the game uses, and position is something a scene
	# cannot get wrong by typing the name differently. The old names remain as a fallback so a camera left at the
	# scene root keeps working.
	var cam: Camera3D = null
	for child in zone.find_children("*", "Camera3D", true, false):
		cam = child as Camera3D
		break
	if cam == null:
		cam = find_child(str(DAMAGE_CAMERAS[which]), true, false) as Camera3D
	if cam == null:
		return
	if _board_camera == null or not is_instance_valid(_board_camera):
		# NOT simply "whatever is currently active". The damage cameras live in the same scene, Godot activates
		# whichever camera is FIRST in the tree, and if one of those is first it is current from the first frame.
		# Capturing it would make the return trip a no-op AND stop the zoom happening at all, because of the
		# guard below. So the board view is found as a camera that is NOT one of the damage cameras, and the
		# active one is only a fallback for a scene with nothing else in it.
		var damage_names: Array = DAMAGE_CAMERAS.values()
		for node in find_children("*", "Camera3D", true, false):
			if not (str(node.name) in damage_names):
				_board_camera = node as Camera3D
				break
		if _board_camera == null:
			_board_camera = get_viewport().get_camera_3d()
		print("[DamageZoom] board view captured as '%s'" % (
			_board_camera.name if _board_camera != null else "<none>"))
	if _board_camera == null or _board_camera == cam:
		return

	var cards: Array = zone.get("cards")
	var next_index: int = cards.size() if cards != null else 0
	# THE CAMERA'S OWN POSE, REMEMBERED ON FIRST USE. Reading its LIVE position — which is what this did — works
	# exactly once: the return leg parks the camera on the board view, so on the second zoom this would read the
	# board's position and aim the shot at the board. The first zoom is the only moment the camera is guaranteed
	# to still be in its hand-placed pose.
	if not _damage_home.has(cam):
		_damage_home[cam] = cam.global_transform
	var home: Transform3D = _damage_home[cam]
	# The pose to land on: the hand-placed framing, shifted by the slot's drift from slot zero.
	var drift: Vector3 = _damage_slot_world(zone, next_index) - _damage_slot_world(zone, 0)
	var slot: Vector3 = _damage_slot_world(zone, next_index)
	var target: Transform3D = home
	target.origin = home.origin + drift
	# TURN TO FACE THE SLOT. Translating alone only centres the shot if the hand-placed rotation happened to point
	# at the first slot; as the row grows the camera would slide sideways while still looking where slot zero was.
	# looking_at() aims the camera at the slot and leaves the position alone, and it takes the camera's own up
	# vector so a deliberately rolled camera keeps its roll. Godot cameras look down -Z, which looking_at handles.
	if target.origin.distance_to(slot) > 0.01:
		target = target.looking_at(slot, home.basis.y)

	var board_pose: Transform3D = _board_camera.global_transform
	if _damage_tween != null and _damage_tween.is_valid():
		_damage_tween.kill()
	# Tweening the DAMAGE camera rather than the board one means the board's own transform is never touched.
	cam.global_transform = board_pose
	cam.current = true
	print("[DamageZoom] %s -> %s (slot %d)" % [which, cam.name, next_index])

	_damage_tween = create_tween()
	_damage_tween.set_trans(Tween.TRANS_SINE)
	_damage_tween.tween_property(cam, "global_transform", target, damage_zoom_in_seconds).set_ease(Tween.EASE_OUT)
	_damage_tween.tween_interval(damage_zoom_hold_seconds)
	# BACK TO ITS OWN POSE, not the board's. Ending on the board pose was half of the "works once" bug: it puts the
	# board view back on screen (correct) but leaves THIS camera parked there, which poisons the next zoom's
	# read-back. The handoff to the board view happens in the callback below; this just puts it back where it lives.
	_damage_tween.tween_property(cam, "global_transform", home, damage_zoom_out_seconds).set_ease(Tween.EASE_IN)
	_damage_tween.tween_callback(_end_damage_zoom)


## Run a damage card's EX BURST.
##
## IMMEDIATELY means no stack object and no priority round: nobody can respond to it, and it does not wait behind
## anything. The instructions go straight into the same instruction machine every other effect uses — what is
## skipped is the stack, not the resolution.
##
## TARGETING IS THE NORMAL FLOW, and the source is the card sitting in the damage zone, so the arrow comes FROM
## the damage card. There is no stack copy to point at here, because there is no stack object at all — that is the
## whole feature. The await is what makes targeting work: the instructions must not run until a target is picked,
## exactly like the stack-routed path resolves after its target rather than before it.
func run_ex_burst(side: PlayerSide, card: Card, event: int) -> void:
	if card == null or not is_instance_valid(card):
		return
	var event_key: String = EVENTS.name_of(event)
	var code_event: bool = card.abilities_enabled() and card.effect_handles_event(event)
	var effect: Dictionary = card.card_effects.get(event_key, {})
	if not code_event and effect.is_empty():
		return
	print("[ExBurst] %s -> '%s' (P%s)" % [card.card_name, event_key, 1 if side == player else 2])

	# THE FAKE STACK CARD, and it is the user's design, which is better than the one it replaces.
	#
	# execute_card_effect() does exactly what an ability does: it makes the effect copy on the stack - purely a
	# graphical matter, the damage card is not a stack object - and starts the NORMAL targeting flow. That is what
	# makes the arrows clean up after themselves: the cleanup runs when a stack effect resolves, and the previous
	# version, which skipped the stack entirely, left the arc on screen forever.
	#
	# It is safe because nothing else is on the stack at this moment: a card becoming damage cannot happen while
	# anything is resolving.
	field.execute_card_effect(card, event)

	# TARGETED BURSTS WAIT FOR THE PICK; NO-TARGET BURSTS HAVE NOTHING TO WAIT FOR. Either way the effect copy is now
	# on the stack and must be resolved HERE, because a burst bypasses the priority loop entirely — leaving a no-target
	# burst on the stack would make Moogle or Gippal do nothing until some later priority round.
	# CODE-DEFINED ETBs CHOOSE THEIR TARGET DURING RESOLUTION. The JSON branch below still chooses before the
	# resolution starts, so only that branch waits for the pick here. Waiting for a code ETB's target before resolving
	# it would block forever: the code handler has not run yet.
	if effect.has("choose_target") and not code_event:
		await assistant.target_complete
	# IMMEDIATELY: no priority round, nobody responds. The stack's own resolution does the work - the same code every
	# other effect goes through, so instructions, targets and cleanup all behave identically.
	if stack.stack_length() > 0:
		await stack.resolve_top_effect()

	# The burst is spent; leave nothing behind for the next effect to inherit.
	_targets = []


func _end_damage_zoom() -> void:
	if _board_camera != null and is_instance_valid(_board_camera):
		_board_camera.current = true

func _end_match(winner_id: int) -> void:
	if match_over:
		return
	match_over = true
	print("Match over — P%s wins" % winner_id)
	if $PhaseText:
		$PhaseText.text = "YOU WIN" if winner_id == 1 else "YOU LOSE"
	assistant.hide_buttons()
	# Let the result register, then hand control back to the menu.
	_return_to_menu_after_delay()

func _return_to_menu_after_delay() -> void:
	await get_tree().create_timer(2.5).timeout
	MatchSetup.go_to_menu()

func take_damage_to_controller(amount: int = 1) -> void:
	# Controller-relative damage for effects (e.g. Dark Knight death trigger).
	if _current_source_card == null:
		return
	if _current_source_card.controller == "player":
		player.take_damage(amount, _current_source_card)
	else:
		opponent.take_damage(amount, _current_source_card)

func set_blocker(card):
	# Persist it on the Field: the instruction chain ends before DAMAGE_RESOLUTION reads the blocker, so a transient
	# on Game would already be gone by then.
	field.blocker_card = card
	# AND MARK THE CARD ITSELF. is_blocking — the criteria behind "choose a blocking Forward" — reads the card's own
	# status, and only Field.set_blocker_card() (the human's CLICK selection) used to set it. So a blocker declared
	# by anyone other than a clicking human, the AI included, was never "blocking" to any card effect, and effects
	# that target a blocking Forward found nothing. The declaration is the moment the block becomes true for both
	# sides, so it belongs here. Field.reset_blocker() clears it at the end of combat.
	if card != null and is_instance_valid(card):
		card.set_blocker_status(true)
		# "When this blocks or is blocked" (Squall 41). Declaring the block is the single moment both events become
		# true, so both sides' triggers are queued here — the blocker's `when_blocks`, and `when_blocked` for every
		# Forward that is attacking (a party included: each member was blocked).
		field.execute_card_effect(card, EVENTS.Event.BLOCKS)
		for attacker in field.party_members():
			if attacker != null and is_instance_valid(attacker):
				field.execute_card_effect(attacker, EVENTS.Event.BLOCKED)

## One simultaneous damage step: both cards deal their power to each other. State-based actions are checked after,
## because a card that died here must not deal damage in a later step.
func clash_cards(card1:Card,card2:Card):
	if card1 != null and card2 != null and card1.is_on_field() and card2.is_on_field():
		# Each card is the SOURCE of the damage the other takes, so per-dealer modifiers (Warrior of Light) apply.
		field.cause_damage(card1, card2.power, card2, "", card2.controller)
		field.cause_damage(card2, card1.power, card1, "", card1.controller)
		enforce_game_state_rules()

## FIRST STRIKE.
##
## If exactly ONE of the two cards has it, combat is two damage steps with a PRIORITY ROUND between them. If both
## have it or neither does, it is one simultaneous step. The second step happens only if both cards are still alive
## after the first — hence the is_on_field() checks on either side of the priority window, since a player may cast
## something during it.
func clash_attacker_blocker() -> void:
	var blocker: Card = field.blocker_card
	if blocker == null or field.party_members().is_empty():
		return
	# A PARTY has First Strike only if EVERY member does; a party of one is just the old single-attacker rule.
	var party_fs: bool = field.party_has_first_strike()
	var blocker_fs: bool = blocker.is_first_strike()
	if party_fs == blocker_fs:
		# SIMULTANEOUS. Both damage assignments are made before ANY state-based action runs: settling in between
		# would break a blocker that died first and rob it of its damage, which is exactly what the first version of
		# this did (party dealt, blocker broke, blocker dealt nothing).
		var party_total: int = field.party_power()
		var at_once: Array = await _blocker_split(blocker)
		if party_total > 0 and blocker.is_on_field():
			print("[Combat] party deals %d to %s" % [party_total, blocker.card_name])
			# No single source card: the party deals its SUMMED power, so damage doubling must not apply. The
			# prevention replacements (160/171) still need to see this event, hence the choke point.
			field.cause_damage(blocker, party_total)
		_apply_blocker_split(at_once)
		enforce_game_state_rules()
		return

	# Otherwise the side with First Strike deals first, the other answers only if still alive.
	if party_fs:
		_apply_party_damage(blocker)
		if not _combat_still_live(blocker):
			return
		await priority_round_only()
		if not _combat_still_live(blocker):
			return
		_apply_blocker_split(await _blocker_split(blocker))
		enforce_game_state_rules()
	else:
		_apply_blocker_split(await _blocker_split(blocker))
		enforce_game_state_rules()
		if not _combat_still_live(blocker):
			return
		await priority_round_only()
		if not _combat_still_live(blocker):
			return
		_apply_party_damage(blocker)

## Both sides still in the fight? The blocker can die to First Strike, and so can every member of the party.
func _combat_still_live(blocker: Card) -> bool:
	return blocker != null and blocker.is_on_field() and not field.party_members().is_empty()

## THE PARTY'S DAMAGE: the SUM of its members' power, to the blocker. A party of one is just that card's power, so
## this covers the single-attacker case too. Settles immediately — only call it when this is its own damage step.
func _apply_party_damage(blocker: Card) -> void:
	if blocker == null or not blocker.is_on_field():
		return
	var total: int = field.party_power()
	if total <= 0:
		return
	print("[Combat] party deals %d to %s" % [total, blocker.card_name])
	var leader: Card = field.attacker_card
	field.cause_damage(blocker, total, leader, "", leader.controller if leader != null else "")
	enforce_game_state_rules()

## How the blocker's power is divided across the party, WITHOUT applying it. Split out so the simultaneous step can
## compute both sides and then apply them together — and so the human's arrow window can be awaited before any
## damage lands.
func _blocker_split(blocker: Card) -> Array:
	if blocker == null or not blocker.is_on_field():
		return []
	var members: Array = field.party_members()
	if members.is_empty():
		return []
	if members.size() == 1:
		return [blocker.power]
	var owner_id: int = 1 if blocker.controller == "player" else 2
	var split: Array = await agent_for(owner_id).choose_party_damage_split(owner_id, members, blocker.power)
	print("[Combat] %s distributes %d across %d: %s" % [
		blocker.card_name, blocker.power, members.size(), str(split)])
	return split

## Apply a split produced by _blocker_split(). No settle — the caller decides when state-based actions run.
func _apply_blocker_split(split: Array) -> void:
	var members: Array = field.party_members()
	for i in range(mini(split.size(), members.size())):
		var card: Card = members[i]
		if card == null or not is_instance_valid(card) or not card.is_on_field():
			continue
		var amount: int = int(split[i])
		if amount <= 0:
			continue
		var blocker_source: Card = field.blocker_card
		field.cause_damage(card, amount, blocker_source, "", blocker_source.controller if blocker_source != null else "")


## A priority pass chain that does NOT advance the phase.
##
## priority() ends with next_phase(); a between-damage-step window must not, so this is the same loop with that tail
## removed. KEEP THE TWO IN STEP if either changes — this is a deliberate copy rather than a refactor of the live
## priority loop, because the loop is load-bearing and a variant is cheaper to reason about than a shared one
## parametrised by "should I advance".
func priority_round_only() -> void:
	if _priority_lock:
		print("[Priority] between-steps round skipped: one is already running")
		return
	_priority_lock = true
	var holder: int = turn_owner
	var passed_since_action: bool = false
	while true:
		priority_holder = holder
		var acted: bool = await agent_for(holder).take_priority(holder)
		if acted:
			passed_since_action = false
			holder = 3 - holder
			continue
		if not passed_since_action:
			passed_since_action = true
			holder = 3 - holder
			continue
		if stack.stack_length() > 0:
			await stack.resolve_top_effect()
			passed_since_action = false
			holder = turn_owner
			continue
		break
	_priority_lock = false
	print("[Priority] between-steps round over")
	
	

var phases = [
	GlobalVariables.Phase.ACTIVE_PHASE,           # 2.1 0
	GlobalVariables.Phase.DRAW_PHASE,             # 2.2   1
	GlobalVariables.Phase.FIRST_MAIN_PHASE,       # 2.3 2 
	GlobalVariables.Phase.ATTACK_PREPARATION_STEP,   # 2.5 3
	GlobalVariables.Phase.ATTACK_DECLARATION_STEP,   # 2.6 4
	GlobalVariables.Phase.BLOCKER_DECLARATION_STEP,  # 2.7 5
	GlobalVariables.Phase.DAMAGE_RESOLUTION_STEP,    # 2.8 6
	GlobalVariables.Phase.SECOND_MAIN_PHASE,       # 2.10 7
	GlobalVariables.Phase.END_PHASE                # 2.11 8
]
var phase_index = 0


func next_phase():
	# Advance to the next phase. Called by priority() when both players pass
	# on an empty stack, and by phases that don't use priority.
	if match_over:
		return  # the match has ended — stop advancing
	match phases[phase_index]:
		GlobalVariables.Phase.ATTACK_DECLARATION_STEP:
			# If no attacker was declared, skip the remaining combat steps.
			if field.attacker_card:
				phase_index = 5  # BLOCKER_DECLARATION_STEP
			else:
				phase_index = 7  # SECOND_MAIN_PHASE
			_enter_phase(phases[phase_index])
			return
		GlobalVariables.Phase.DAMAGE_RESOLUTION_STEP:
			# Loop back to attack preparation so the turn player can declare
			# additional attackers (FF-style combat loop).
			phase_index = 3  # ATTACK_PREPARATION_STEP
			_enter_phase(phases[phase_index])
			return

	phase_index += 1
	if phase_index >= phases.size():
		phase_index = 0
		# Hand the turn over. The new turn owner untaps and draws in ACTIVE/DRAW.
		turn_owner = 3 - turn_owner
		# THE TURN BOUNDARY, and the only place turn_number moves. `actions_this_turn()` is a filter on
		# turn_number, so this is what makes "this turn" mean this turn.
		turn_number += 1
		print("Turn completed — now P%s (%s)" % [turn_owner, controller_for(turn_owner)])

	# Enter new phase
	_enter_phase(phases[phase_index])

func _enter_phase(phase_enum: GlobalVariables.Phase):
	print("Entering: ", phase_enum) # This will print the integer value
	# Phase is match state: Game owns it and derives the input mode's base from
	# it, so every phase starts from its default (modals are pushed on top).
	phase = phase_enum
	GlobalVariables.set_base_mode(GlobalVariables.default_mode_for(phase_enum))
	$PhaseText.text = "%s — P%s" % [phase_to_string(phase_enum), turn_owner]
	
	match phase_enum:
		GlobalVariables.Phase.ACTIVE_PHASE:
			field.untap_cards_for(controller_for(turn_owner))
			next_phase()
		GlobalVariables.Phase.DRAW_PHASE:
			var draw_deck = deck if turn_owner == 1 else opponent_deck
			var draw_hand = hand if turn_owner == 1 else opponent_hand
			if not draw_deck.deck_cards.is_empty():
				draw_hand.draw(draw_deck.deck_cards.pop_front())
			next_phase()
		GlobalVariables.Phase.FIRST_MAIN_PHASE:
			await priority()
			print('PASSED PRIORITY')
			pass
		GlobalVariables.Phase.ATTACK_PREPARATION_STEP:
			# "When your Attack Phase starts" is checked here, before priority. A code effect can queue its stack object
			# in this window; the ordinary priority loop then gives both players a chance to respond.
			field.trigger_event(EVENTS.Event.ATTACK_PHASE_START, {"player_id": turn_owner})
			await priority()
			# Signal UI to enable attacker selection
			pass
		GlobalVariables.Phase.ATTACK_DECLARATION_STEP:
			# Only the local human drives attacker selection through the UI; an
			# AI/remote turn owner answers decide_attacker() instead. The mode is
			# left at the phase default (INSTANT_SPEED_TIME) so the other
			# player can still hold priority / respond.
			var attacker_agent: Agent = agent_for(turn_owner)
			var local_attack: bool = attacker_agent is LocalAgent
			if local_attack:
				GlobalVariables.push_modal(GlobalVariables.Player_Mode.ATTACKING)
				assistant.set_declare_attack_button('No Attack')
			# A PARTY IS A LIST. The human's clicks already formed theirs; the AI's list has to be applied. Both go
			# through the same rebuild so there is one definition of "what is attacking".
			var attackers: Array = await attacker_agent.decide_attackers(turn_owner)
			if local_attack:
				GlobalVariables.pop_modal(GlobalVariables.Player_Mode.ATTACKING)
			field.reset_attacker()
			if not attackers.is_empty() and attackers[0] != null:
				field.set_attacker(attackers[0])
				for i in range(1, attackers.size()):
					field.add_party_member(attackers[i])
				field.execute_card_attack()
			await priority()
			#await declare_attacker()
			#await priority() #must be something different perhaps, becaus
			# Signal UI to enable attacker selection
			pass
		GlobalVariables.Phase.BLOCKER_DECLARATION_STEP:
			# The defender (not the turn owner) decides whether to block. The mode
			# is pushed only for the local human, mirroring ATTACKING, and only for
			# as long as the declaration is open — so the pass button comes back
			# for the priority round that follows.
			var defender_id: int = 3 - turn_owner
			var defender_agent: Agent = agent_for(defender_id)
			var local_defence: bool = defender_agent is LocalAgent
			# Start from a clean slate: the previous combat's reset_blocker() runs
			# late, only after the phase it advanced into has finished.
			field.reset_blocker()
			if local_defence:
				GlobalVariables.push_modal(GlobalVariables.Player_Mode.BLOCKING)
				# Blue ring on everything that could block, because the game is asking the
				# human to choose one. Clicking turns it orange and draws the arc.
				field.set_blockable(controller_for(defender_id), true)
				assistant.set_declare_block_button('No Block')
			var blocker: Card = await defender_agent.decide_blocker(defender_id, field.attacker_card)
			if local_defence:
				GlobalVariables.pop_modal(GlobalVariables.Player_Mode.BLOCKING)
				field.set_blockable(controller_for(defender_id), false)
			if blocker != null:
				if not local_defence:
					# The human is watching the opponent declare. Show the link for their
					# pick and hold it long enough to be read: the choice happens before the
					# damage step, and without this the block stays invisible until it
					# resolves. No blue ring here — that cue means "your choice".
					field.show_block_arc(blocker)
					await get_tree().create_timer(block_announce_time).timeout
				blocker.declare_blocker()
			await priority()
			pass
		GlobalVariables.Phase.DAMAGE_RESOLUTION_STEP:
			# A blocked attack clashes instead of damaging the player. This is
			# the ONLY clash — Card.declare_blocker() just records the blocker.
			if field.blocker_card != null:
				# AWAITED: First Strike may open a priority window between its two damage steps, and that window
				# must finish before this phase continues into its own priority round. Without the await the clash
				# runs detached and two priority loops fight over _priority_lock.
				await clash_attacker_blocker()
			else:
				# cause_attacking_damage(), not cause_damage(): it also fires "when a party you control deals
				# damage" (Andoria/Boko). Calling the inner function directly left that trigger dead in real play.
				cause_attacking_damage()
			await priority()
			field.reset_blocker()
			field.reset_attacker()
			
		GlobalVariables.Phase.COMBAT_END_STEP:
			pass
		GlobalVariables.Phase.SECOND_MAIN_PHASE:
			await priority()
			pass
		GlobalVariables.Phase.END_PHASE:
			# End Phase cleanup: all accumulated damage is removed and
			# "until end of turn" effects expire.
			# NOTE: there is no end-of-turn priority window yet, so cleanup
			# runs immediately on entering the phase. Once end-of-turn
			# auto-abilities exist, a priority round must run first.
			field.end_phase_cleanup()
			next_phase()
			pass
	
## Emitted when the LOCAL player's priority window ends. `acted` is true when
## they performed an action; the rules hand priority to the opponent at that
## point, so it must not be treated as a pass.
signal priority_window_ended(acted: bool)

## The human pressed pass (`pressed_pass_priority` comes from the Assistant).
func _on_priority_passed() -> void:
	priority_window_ended.emit(false)

## Called by the action choke points in `Stack` (a card was played, an ability
## activated). When an *agent* acts nobody is awaiting this signal — the agent
## reports the action through its `take_priority()` return value instead.
func note_action_taken() -> void:
	priority_window_ended.emit(true)

func priority() -> void:
	# One round of priority at a time. Extra requests (e.g. Stack.request_priority
	# while a round is running) are no-ops; the running loop picks up the change.
	if _priority_lock:
		# LOUD, because this is where a request can disappear. The running loop only notices a new stack object when it
		# comes back round to its own checks — so a request arriving while the loop is parked on a player is picked up
		# only if that player then does something. A stall here is otherwise completely silent, which is what makes this
		# printed rather than reasoned about.
		print("[Priority] a round is ALREADY RUNNING — request absorbed (stack=%d, mode=%s)" % [
			stack.stack_length(), GlobalVariables.get_player_mode()])
		return
	_priority_lock = true
	print("[Priority] round begins — turn_owner=P%s | stack=%d | mode=%s" % [
		turn_owner, stack.stack_length(), GlobalVariables.get_player_mode()])

	# Priority model (FF TCG): the turn player receives priority first in a phase
	# or step. A player with priority either performs an action — which hands
	# priority to the OTHER player — or passes. The game only moves on when both
	# players pass consecutively with no action in between: with a non-empty
	# stack the top item resolves (after which the TURN player has priority
	# again); with an empty stack the next phase/step begins.
	var holder: int = turn_owner
	var passed_since_action: bool = false
	while true:
		priority_holder = holder
		# WHO IS BEING ASKED, and in what state. With the two lines at the top of this function and the mode log, a stall can
		# be read off the console: the last "asking" line names the player the game is waiting on, and if it is never followed
		# by a line for the other player, that one never answered.
		print("[Priority] asking P%s | stack=%d | mode=%s" % [
			holder, stack.stack_length(), GlobalVariables.get_player_mode()])
		var acted: bool = await agent_for(holder).take_priority(holder)
		if acted:
			passed_since_action = false
			holder = 3 - holder
			continue
		if not passed_since_action:
			# First pass of this round: the other player gets their chance.
			passed_since_action = true
			holder = 3 - holder
			continue
		if stack.stack_length() > 0:
			# Both passed with something waiting: resolve the top. The call may
			# await an interactive modal (e.g. Auron's "may play a Backup").
			await stack.resolve_top_effect()
			passed_since_action = false
			holder = turn_owner
			continue
		break

	# Release the lock before advancing so the next phase can start its own
	# priority round.
	_priority_lock = false
	next_phase()

func enforce_game_state_rules() -> void:
	# State-based actions, checked after any damage/power change.
	# UNIQUE NAMES are enforced at the ENTRY CHOKE POINT (Field.play_card), not swept here: the only way a Character
	# legally reaches the field is play_card, and setup boards/probes may deliberately contain duplicates that never
	# entered. If a future effect changes a card's name in place, this sweep is where that conflict would go.
	# 1) Power reduced to 0 (or less): the card is put into the Graveyard.
	#    This is NOT a break, so "when put into the Break Zone" effects do
	#    not trigger. (Break Zone and Graveyard share a container here, but
	#    the removal events are distinct.)
	for card in field.get_zero_power_cards():
		put_card_into_graveyard(card)
	# 2) Accumulated damage greater than current power: the card is broken.
	# THE SWEEP HAS NO IDEA WHAT DEALT THE DAMAGE, so the card carries it (Card.last_damage_kind/controller) and the
	# same protection question an explicit break asks can be answered here too.
	for card in field.get_breakable_cards():
		break_card(card, card.last_damage_controller, card.last_damage_kind)

## THE FIELD -> BREAK ZONE CHOKE POINT, and therefore the place where a REPLACEMENT effect belongs.
##
## Returns true when the card was EXILED instead of buried, so the caller knows the Break Zone event did not happen.
##
## FRAGILE ("if they are put from the field into the Break Zone this turn, remove them from the game instead") has to
## intercept the transition itself — the card never reaches the Break Zone, so nothing that watches for a card
## arriving there can see it. Implementing it as a trigger that reacts afterwards would be a different (wrong) rule.
func _send_card_to_graveyard(card: Card) -> bool:
	# CAPTURED BEFORE THE MOVE. Graveyard.add_card() sets current_zone to GRAVEYARD, and this flag decides whether the
	# board-wide card_left_field event fires; a card that never was on the field must not trigger it.
	var from_field: bool = card.current_zone == Card.Zone.FIELD
	if card.status_effects.has("fragile"):
		print("[Fragile] %s is removed from the game instead" % card.card_name)
		card.status_effects.erase("fragile")
		_send_card_to_removed(card)
		return true
	# 176 Yuna: "If a Character is put from the field into the Break Zone, you may remove it from the game instead."
	# SIMPLIFICATION: the "may" is auto-accepted. This transition has to stay synchronous for the break/removal call
	# sites; a real optional prompt belongs at a higher-level pre-break step. `current_zone` still says FIELD here,
	# because the caller removes the card from the field before sending it; that is what keeps the rule off cards
	# that never entered (a unique-name duplicate from hand/stack).
	if card.current_zone == Card.Zone.FIELD and card.is_character() and _yuna_exiles_break_zone():
		print("[Yuna] %s is removed from the game instead of the Break Zone" % card.card_name)
		_send_card_to_removed(card)
		return true
	if card.controller == "player":
		player_graveyard.add_card(card)
	else:
		opponent_graveyard.add_card(card)
	if from_field:
		field.trigger_event(EVENTS.Event.CARD_LEFT_FIELD, {"card": card})
	return false

func _yuna_exiles_break_zone() -> bool:
	for other in field.get_all_cards():
		if other != null and other.static_rule("break_zone_exile", false) == true:
			return true
	return false

func _send_card_to_removed(card: Card) -> void:
	if card.controller == "player":
		player_removed.add_card(card)
	else:
		opponent_removed.add_card(card)

## REMOVE FROM THE GAME. "Your opponent removes it from the game." Unlike a break or a discard, this is NOT a
## Graveyard event: the card leaves play and nothing that watches the Break Zone sees it.
## Public single-card form for code effects. Same two steps as the instruction, but without touching ambient `_targets`.
func remove_card_from_game(card: Card) -> void:
	if card == null or not is_instance_valid(card):
		return
	print("[RemoveFromGame] ", card.card_name)
	if card.is_on_field():
		field.remove_card(card)
	_send_card_to_removed(card)


func remove_targets_from_game(_argument = null) -> void:
	for card in _targets:
		if card == null or not is_instance_valid(card):
			continue
		print("[RemoveFromGame] ", card.card_name)
		if card.is_on_field():
			field.remove_card(card)
		_send_card_to_removed(card)

## True when `card`'s controller already controls a Character with the same name. Used BEFORE a card is parented onto
## the field, so the duplicate never enters and no enter-the-field trigger runs for it.
func would_be_unique_name_conflict(card: Card) -> bool:
	if card == null or not is_instance_valid(card) or not card.is_character():
		return false
	var side_name: String = "player" if card.controller == "player" else "opponent"
	for other in field.get_front_cards_for(side_name) + field.get_back_cards_for(side_name):
		if other != null and other != card and other.is_character() and other.card_name == card.card_name:
			return true
	return false

## A unique-name duplicate never reached the field, so this is NOT a break and the Break Zone arrival triggers must not
## run (Graveyard.add_card gates them on `from_field`). `broken` stays false for the same reason.
func send_off_field_card_to_break_zone(card: Card) -> void:
	if card == null or not is_instance_valid(card):
		return
	card.broken = false
	_send_card_to_graveyard(card)

## Rule 7.7.5: normally only one Light or Dark card may be on a side. Cosmos (Light) and Chaos (Dark) print the
## exception: they may enter next to one of their own element, and while one is on the field that element may have
## two or more cards. This is a board query, so it stops applying the moment the exceptional card leaves.
func would_break_light_dark_limit(card: Card) -> bool:
	if card == null or not is_instance_valid(card) or not card.is_character():
		return false
	var kind: String = card.light_dark_kind()
	if kind.is_empty():
		return false
	var side_name: String = "player" if card.controller == "player" else "opponent"
	var same_kind: bool = false
	var other_kind: bool = false
	var enabled_by_field: bool = false
	for other in field.get_front_cards_for(side_name) + field.get_back_cards_for(side_name):
		if other == null or not is_instance_valid(other) or other == card:
			continue
		if not other.is_light_or_dark():
			continue
		if other.light_dark_kind() == kind:
			same_kind = true
		else:
			other_kind = true
		if str(other.static_rule("light_dark_exempt", "")) == kind:
			enabled_by_field = true
	# The exceptional card itself may enter beside cards of its OWN kind, never beside the opposite kind. While it
	# is on the field it lifts the limit for that kind (the "you can play 2 or more Light Characters" clause).
	if str(card.static_rule("light_dark_exempt", "")) == kind:
		return other_kind
	if enabled_by_field:
		return false
	return same_kind or other_kind

func put_card_into_graveyard(card: Card) -> void:
	# Removal that is NOT a break (e.g. power reduced to 0). The "unbreakable" status does not apply, because the
	# card did not break — but it still ARRIVES in the Break Zone, so `when_enter_break_from_field` fires and
	# `when_break` does not. That difference is carried by the flag, not by a separate code path.
	if not card.is_on_field():
		return
	card.broken = false
	card.untap()
	field.remove_card(card)
	_send_card_to_graveyard(card)

## Break `card`. `source_kind`/`source_controller` describe the CAUSE ("Summon"/"Ability" and who controlled it), so
## continuous protection rules can be asked before anything moves; the state-based sweep passes the card's recorded
## last damage source, and combat passes an empty kind.
func break_card(card: Card, source_controller: String = "", source_kind: String = ""):
	if not card.is_on_field():
		return
	if 'unbreakable' in card.status_effects:
		return
	if field.is_protected_from_break(card, source_controller, source_kind):
		print("[Protect] %s cannot be broken by that effect" % card.card_name)
		return
	# MARK IT, then move it. The flag is what distinguishes a BREAK from an ordinary removal, and it is set here
	# because this is the only function that knows the damage reached the power.
	card.broken = true
	card.untap()
	field.remove_card(card)
	_send_card_to_graveyard(card)

## Fired BY THE BREAK ZONE once a card has arrived in it and been laid out — never from here, and never while the
## card is still on the field. Both keywords go on the stack, in this order, so `when_break` resolves second.
##
## `when_enter_break_from_field` fires for ANY card that came from the field (broken or not); `when_break` only for
## one that actually broke. An exiled card fires neither, because it never reaches this pile.
func trigger_break_zone_keywords(card: Card, was_broken: bool) -> void:
	if card == null or not is_instance_valid(card):
		return
	# execute_card_effect() is the single gate: it knows both code effects and JSON keywords. Emitting the signal
	# directly here skipped every code-defined Break Zone trigger.
	if card.card_effects.has("when_enter_break_from_field") or card.effect_handles_event(EVENTS.Event.ENTER_BREAK_FROM_FIELD):
		print("[BreakZone] ", card.card_name, " -> when_enter_break_from_field")
		field.execute_card_effect(card, EVENTS.Event.ENTER_BREAK_FROM_FIELD)
	if was_broken and (card.card_effects.has("when_break") or card.effect_handles_event(EVENTS.Event.BREAK)):
		print("[BreakZone] ", card.card_name, " -> when_break")
		field.execute_card_effect(card, EVENTS.Event.BREAK)
	# A STATUS CAN CARRY ITS OWN BREAK TRIGGER. Cid's "the Forward that took damage from Cid" is remembered on the
	# damaged card, so it fires here — the same choke point as the printed keywords, and only for cards arriving FROM
	# THE FIELD (Graveyard.add_card gates that call).
	_trigger_status_break_zone_effects(card)

## Runs the one-shot trigger a status carries when its card reaches the Break Zone (see
## Field._apply_damage_caused_riders). The status is erased first, so the trigger cannot run twice, and the controller
## recorded with it is restored around the chain so "your opponent mills" still means the right player.
func _trigger_status_break_zone_effects(card: Card) -> void:
	for status in card.status_effects.keys():
		var payload = card.status_effects[status]
		if not (payload is Dictionary) or not payload.has("on_enter_break_zone"):
			continue
		var entries: Array = payload["on_enter_break_zone"]
		card.status_effects.erase(status)
		var instructions: Array[Instruction] = []
		for entry in entries:
			if entry is Dictionary:
				instructions.append(Instruction.new(
					str(entry.get("name", "")), str(entry.get("author", "game")), entry.get("argument", [])))
		if instructions.is_empty():
			return
		var previous: String = _current_controller
		var previous_source: Card = _current_source_card
		var payload_source = payload.get("source", null)
		if payload_source is Card and is_instance_valid(payload_source):
			_current_source_card = payload_source
		_current_controller = str(payload.get("controller", previous))
		print("[BreakZone] ", card.card_name, " -> status trigger ", status)
		_execute_instructions(instructions)
		_current_controller = previous
		_current_source_card = previous_source
		return

## A TARGETING SESSION WAS CONFIRMED. This is the first moment the chosen set is real, so it is where "when chosen"
## triggers are announced (Kuja 37). Connected AFTER the Stack's target handler, so an ability triggered by the choice
## lands ABOVE the summon/ability that caused it and resolves first.
func _on_targets_confirmed() -> void:
	if field != null:
		field.notify_targets_chosen()

static func phase_to_string(phase):
	match phase:
		GlobalVariables.Phase.ACTIVE_PHASE:
			return "ACTIVE_PHASE"
		GlobalVariables.Phase.DRAW_PHASE:
			return "DRAW_PHASE"
		GlobalVariables.Phase.FIRST_MAIN_PHASE:
			return "FIRST_MAIN_PHASE"
		GlobalVariables.Phase.ATTACK_PREPARATION_STEP:
			return "ATTACK_PREPARATION_STEP"
		GlobalVariables.Phase.ATTACK_DECLARATION_STEP:
			return "ATTACK_DECLARATION_STEP"
		GlobalVariables.Phase.BLOCKER_DECLARATION_STEP:
			return "BLOCKER_DECLARATION_STEP"
		GlobalVariables.Phase.DAMAGE_RESOLUTION_STEP:
			return "DAMAGE_RESOLUTION_STEP"
		GlobalVariables.Phase.COMBAT_END_STEP:
			return "COMBAT_END_STEP"
		GlobalVariables.Phase.SECOND_MAIN_PHASE:
			return "SECOND_MAIN_PHASE"
		GlobalVariables.Phase.END_PHASE:
			return "END_PHASE"
		_:
			return "UNKNOWN_PHASE"
	

## Resolve a board-wide event trigger that was enqueued by Field.trigger_event(). It is a normal stack object, so
## priority has already passed around it; this is the RESOLUTION half: may -> choose target -> instructions.
func _resolve_code_effect(card: Card) -> void:
	var source: Card = card.effect_source
	if source == null or not is_instance_valid(source):
		return
	var effect_obj = source.effect()
	if effect_obj == null:
		return
	var picks: Array = card.effect_targets.duplicate()
	if picks.is_empty() and card.effect_target != null:
		picks = [card.effect_target]
	var ctx = source.make_effect_context(card.effect_event, card.effect_event_data, card, picks)
	# dispatch() maps the typed event id to the card's method in one place.
	await effect_obj.dispatch(card.effect_event, ctx)


func _resolve_event_trigger(card: Card) -> void:
	var trigger: Dictionary = card.event_trigger
	var context: Dictionary = card.event_context
	var source: Card = card.effect_source
	if source == null or not is_instance_valid(source):
		return
	# "if it is active" is checked at resolution, not when the trigger was put on the stack.
	if bool(trigger.get("requires_active", false)) and (not source.is_on_field() or source.tapped):
		return
	if bool(trigger.get("may", false)):
		var owner_id: int = 1 if source.controller == "player" else 2
		var agent: Agent = agent_for(owner_id)
		var use_it: bool = true
		if agent != null:
			use_it = await agent.confirm_optional(owner_id, str(trigger.get("may_prompt", "")))
		if not use_it:
			return
	var targets: Array = field.call("_event_targets", trigger, source, context)
	_current_source_card = source
	_current_controller = card.controller
	_targets = targets
	var criteria = trigger.get("choose_target", null)
	if criteria:
		# The stack copy is the source of the arrow: this is the effect the player is resolving.
		if not field.has_viable_target(criteria, card, "Ability"):
			return
		field.request_target(criteria, card, false, "Ability")
		# A non-local agent completes inside request_target(); only a local player leaves the list empty.
		if field.targeting_picked.is_empty():
			await assistant.target_complete
		targets = field.targeting_picked.duplicate()
		_targets = targets
	var instructions_json = trigger.get("instructions", [])
	if instructions_json is Array and not instructions_json.is_empty():
		var instructions: Array[Instruction] = source.create_instruction_from_json(instructions_json)
		await _execute_instructions_and_wait(instructions)
	else:
		_clean_instruction_stack()

func _on_stack_execute_card_effect(card: Card) -> void:
	# A code-defined triggered ability. The stack copy names the event; the effect object does the work with a fresh
	# EffectContext. Targeting state is cleared around it for the same reason as the event-trigger path below.
	if card.effect_event != EVENTS.Event.NONE:
		# Do NOT clear targeting BEFORE resolving: request_target() starts a new session and owns that state. The
		# old pre-clear could wipe the very session the code handler had just opened.
		await _resolve_code_effect(card)
		field.call("finish_targeting_state")
		card.queue_free()
		stack._mark_resolution_complete()
		return
	# A real Summon whose when_cast is code-owned. Its targets were chosen at cast time and live on this same card,
	# so resolution is just the handler plus the normal trip to the Break Zone.
	if card.type == "Summon" and card.effect_source == null and card.abilities_enabled() \
			and card.effect_handles_event(EVENTS.Event.CAST):
		var summon_picks: Array = card.effect_targets.duplicate()
		if summon_picks.is_empty() and card.effect_target != null:
			summon_picks = [card.effect_target]
		var summon_ctx = card.make_effect_context(EVENTS.Event.CAST, {}, card, summon_picks)
		await card.effect().dispatch(EVENTS.Event.CAST, summon_ctx)
		field.call("finish_targeting_state")
		if card.controller == "player":
			player_graveyard.add_card(card)
		else:
			opponent_graveyard.add_card(card)
		stack._mark_resolution_complete()
		return
	# A code-defined ACTIVATED ability. Costs and targets were settled during activation; the proxy carries the
	# AbilitySpec snapshot, so resolution is just the handler with those targets.
	if card.ability_spec != null:
		var ability_source: Card = card.effect_source
		if ability_source != null:
			var ability_picks: Array = card.effect_targets.duplicate()
			if ability_picks.is_empty() and card.effect_target != null:
				ability_picks = [card.effect_target]
			var ability_ctx = ability_source.make_effect_context("activated_ability", {}, card, ability_picks)
			await card.ability_spec.resolve(ability_ctx)
		field.call("finish_targeting_state")
		card.queue_free()
		stack._mark_resolution_complete()
		return
	# A board-wide event trigger is a stack object with its own resolution path; its copied card data has no
	# `__event_trigger` keyword to resolve.
	if not card.event_trigger.is_empty():
		# Clear anything a previous targeting session left behind, resolve, then clear the session this one opened.
		field.call("finish_targeting_state")
		await _resolve_event_trigger(card)
		field.call("finish_targeting_state")
		card.queue_free()
		stack._mark_resolution_complete()
		return
	# Resolution may await an interactive modal (e.g. Auron's "may play a
	# Backup" choice). Stack.resolve_top_effect() waits for our
	# _mark_resolution_complete() signal at the end of this function.
	var instructions = card.get_card_effect_instructions()
	# THE EFFECT'S OWN TARGETS. `effect_targets` is the whole list (see Card) and `effect_target` is still the last one
	# for consumers that want a single card. A targetless effect keeps the one-element list it always had.
	var targets: Array = card.effect_targets.duplicate()
	if targets.is_empty():
		targets = [card.effect_target]
	# "apply_effect" — THE ABILITY SELECTS ITS OWN TARGETS, so the player is not asked. The set is worked out HERE, at
	# resolution, and never re-evaluated: a Forward that arrives later in the turn does not gain the effect. That snapshot
	# is the whole point of doing it at resolution rather than hanging it off the field changing, and it is the rule for
	# an ability that affects "all Forwards you control" — it means the ones on the field when it resolved.
	var applied_from: Dictionary = _apply_effect_block(card)
	if not applied_from.is_empty():
		targets = _cards_matching(applied_from)
		print("[ApplyEffect] ", card.card_name, " applies to ", targets.size(), " card(s)")
	_current_source_card = card.effect_source if card.effect_source != null else card
	_current_controller = card.controller
	_targets = targets

	# Triggered "may" abilities resolve NOW: open the choose-card modal and,
	# if the player confirms, pass the chosen hand card to may_play_for_free.
	for instruction in instructions:
		if instruction.action == "may_play_for_free" and instruction.value == null:
			var chosen: Card = await _resolve_may_play_for_free(card, instruction)
			if chosen == null:
				instructions.erase(instruction)
			else:
				instruction.value = chosen
			break

	# AWAITED. Resolution is not complete until every instruction has finished, including the ones that suspend on an
	# animation (return to hand) or on a modal — otherwise the next effect can resolve while this one is still moving
	# cards, and resolve_top_effect() returns before the board has changed.
	await _execute_instructions_and_wait(instructions)

	if card.effect_source == null:
		# A real card cast from hand (Summon) resolves to its controller's
		# graveyard instead of being freed.
		if card.controller == "player":
			player_graveyard.add_card(card)
		else:
			opponent_graveyard.add_card(card)
	else:
		# Stack copy (triggered ability / skill proxy): discard after use.
		card.queue_free()

	stack._mark_resolution_complete()

func _resolve_may_play_for_free(effect_card: Card, instruction: Instruction) -> Card:
	# Opens the choose-card-in-hand modal (Play card / Don't play card).
	# Returns the chosen card, or null when declined / no legal card exists.
	var criteria: Dictionary = _get_trigger_choose_card_criteria(effect_card)
	if criteria.is_empty() or not hand.has_card_matching_criteria(criteria):
		return null

	GlobalVariables.push_modal(GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND)
	hand.begin_choose_card(criteria)
	assistant.show_choose_card_buttons()

	var play: bool = await assistant.choose_card_finished
	var chosen: Card = hand.selected_card_for_effect

	hand.end_choose_card()
	assistant.hide_buttons()
	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND)
	assistant.show_pass_priority_button()

	if play and chosen != null:
		return chosen
	return null

func _get_trigger_choose_card_criteria(effect_card: Card) -> Dictionary:
	var keyword: String = effect_card.key_word_effect
	if keyword.is_empty() or not effect_card.card_effects.has(keyword):
		return {}
	var entry = effect_card.card_effects[keyword]
	if entry is Array and entry.size() > 0:
		return entry[0].get("choose_card", {})
	if entry is Dictionary:
		return entry.get("choose_card", {})
	return {}


func _on_stack_request_priority() -> void:
	# Guarded by _priority_lock: if a round is already running, this is a
	# no-op and the running loop picks up the new stack item.
	priority()


func _on_assistant_pressed_next_phase() -> void:
	next_phase()
	pass # Replace with function body.


func _on_field_attacker_changed() -> void:
	# The attacker also changes during the OPPONENT's turn (their attacker is
	# recorded on the same Field), so only touch the button while the local
	# player is the one declaring attackers — i.e. the ATTACKING modal is open.
	if GlobalVariables.get_player_mode() != GlobalVariables.Player_Mode.ATTACKING:
		return
	if field.attacker_card != null:
		assistant.set_declare_attack_button('Attack')
	else:
		assistant.set_declare_attack_button('No Attack')

func _on_field_blocker_changed() -> void:
	# Same guard as the attacker button: blocker_card changes for both sides, so
	# only touch the button while the local defender's declaration is open.
	if GlobalVariables.get_player_mode() != GlobalVariables.Player_Mode.BLOCKING:
		return
	assistant.set_declare_block_button('Block' if field.blocker_card != null else 'No Block')

# --- deck search -------------------------------------------------------------

## Agrias 1-151R: look through your deck, take one matching card, then shuffle.
##
## A COROUTINE, and `_process_next_instruction` awaits it — so the game genuinely stops here while the player
## is choosing, instead of running on behind the window.
##
## The order is the spec, and it matters: the chosen card goes to the TOP of the deck, is drawn from there,
## and only THEN is the deck shuffled. Drawing before shuffling is what makes "taken from the deck" literally
## true rather than a card appearing from nowhere.
## SEARCH THE DECK. `destination` decides where the found card goes, because the same search text appears with
## different endings: "add it to your hand" (the default), "remove it from the game" (Vanille), and cards that put
## the card back on top.
##
## Sets _last_action_succeeded so `condition: "if_last_succeeded"` can act on "and if you do so". A cancelled search
## counts as not succeeding, which is the whole point of that guard.
func search_deck(filter: Dictionary, destination: String = "hand", tapped: bool = false, player_id: int = 0) -> void:
	# Untyped on purpose: `Deck` has no class_name, so naming the type here would be a parse error — and a
	# script that fails to parse takes the whole game scene down with it, which is exactly what happened.
	_last_action_succeeded = false
	# DEFAULT TO P1 when no controller has been set: direct/test callers have no effect source, and the old
	# implementation was always the Player deck. An explicit "opponent" still selects P2.
	var owner_id: int = player_id if player_id in [1, 2] else (2 if _current_controller == "opponent" else 1)
	var deck_node = deck if owner_id == 1 else opponent_deck
	var hand_node: Hand = hand_for(owner_id)
	if deck_node == null or hand_node == null:
		push_warning("[Game] search_deck needs the owner's deck and hand")
		return
	if deck_node.deck_cards.is_empty():
		return

	# FILTER FIRST, then hand only the matches to the agent. The window used to filter for display while the
	# selection came back by id; a filter with is_named (older data) is a Card predicate, not a CardFilter key,
	# so the two vocabularies are bridged in one helper.
	var candidates: Array = []
	for card in deck_node.deck_cards:
		if _matches_search_filter(card, filter):
			candidates.append(card)
	if candidates.is_empty():
		return
	var ids: Array = []
	for card in candidates:
		ids.append(card.id)

	var agent: Agent = agent_for(owner_id)
	if agent == null:
		return
	var chosen: int = await agent.choose_deck_card(owner_id, ids, {})
	if chosen < 0:
		return

	var found: Card = null
	for card in candidates:
		if card.id == chosen:
			found = card
			break
	if found == null:
		push_warning("[Game] search_deck picked %d, which is not in the filtered deck" % chosen)
		return

	deck_node.deck_cards.erase(found)
	match destination:
		"removed":
			print("[Search] ", found.card_name, " is removed from the game")
			_send_card_to_removed(found)
		"graveyard":
			_send_card_to_graveyard(found)
		"top":
			# The deck's array order IS the deck, so the front is the next card drawn.
			deck_node.deck_cards.push_front(found)
		"field", "field_dull":
			# The Emperor 185: search it and play it onto the field DULL.
			found.reset_for_field_arrival()
			field.play_card(found, owner_id == 2, true)
			if tapped or destination == "field_dull":
				found.tap()
		_:
			# "hand" — the default, and what every existing search card uses.
			hand_node.draw(found)
	shuffle_deck(deck_node)
	_last_action_succeeded = true

## Two filter vocabularies meet here: CardFilter (name/type/category/job/element/any) and Card criteria
## (is_named/is_type/...). Older search data uses both, so the shape of the filter picks the reader.
func _matches_search_filter(card: Card, filter: Dictionary) -> bool:
	if filter.is_empty():
		return true
	var filter_keys: Array = ["name", "exact_name", "type", "category", "job", "element",
		"min_power", "max_power", "min_cost", "max_cost", "any"]
	for key in filter.keys():
		if key in filter_keys:
			return CARD_FILTER.matches(CARD_FILTER.card_by_id(card.id), filter)
	return card.matches_criteria(filter)

## RETURN THE SOURCE CARD FROM THE BREAK ZONE TO THE FIELD.
##
## "If you do so, return Vanille onto the field dull." The card that comes back is the ability's own source, which is
## reachable as _current_source_card even though it is sitting in the pile. It leaves that pile first so the two
## lists never both own it.
##
## The zone change runs BEFORE it is placed, so it arrives with the field's scale, rotation and readout rather than
## whatever it was wearing in the pile — the same order Graveyard.add_card uses in the other direction.
func return_from_break_zone(tapped: bool = true) -> void:
	var card: Card = _current_source_card
	if card == null or not is_instance_valid(card):
		return
	var home = null
	if card.controller == "player":
		home = player_graveyard
	else:
		home = opponent_graveyard
	if home != null and home.graveyard_cards.has(card):
		home.graveyard_cards.erase(card)
	print("[ReturnFromBreakZone] ", card.card_name)
	field.play_card(card, card.controller != "player")
	card.broken = false
	if tapped:
		card.tap()

## Fisher-Yates with a dedicated RNG. NOT `Array.shuffle()`, which uses the global generator and so cannot be
## reproduced from a seed — the same reason MatchSetup hand-rolls its own.
##
## Untyped parameter for the same reason as search_deck: `Deck` has no class_name.
func shuffle_deck(deck_node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var cards: Array = deck_node.deck_cards
	for i in range(cards.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Variant = cards[i]
		cards[i] = cards[j]
		cards[j] = swap
