extends Node3D
class_name Stack

var cards = []
var card_width = GlobalVariables.get_card_width() * 2;
var card_spacing = -0.2
var player_mode = GlobalVariables.get_player_mode();
var start_x: float = 0.0
var casting_card: Card
## Stack copy for skill activation. The node exists early for UI; the activation is not
## de facto committed until commit_skill_activation_costs_if_pending runs (after final Confirm).
var skill_activation_proxy: Card = null
## While true, mana/hand discard and JSON tap on source are deferred until stack commit (final Confirm).
var skill_mana_deferred_until_target_confirm: bool = false
## Summon being cast from hand. The card stays in hand until the cost is paid
## and targets are chosen; only then does it enter the stack.
var summon_casting_card: Card = null
## While true, summon mana payment is deferred until the target is confirmed.
var summon_mana_deferred_until_target_confirm: bool = false
## True while an effect resolution is still running (it may await a modal).
var resolution_pending: bool = false
## Special ability (S) cost state: a card sharing a name with the source,
## selected from hand and discarded at the final skill commit.
var s_cost_active: bool = false
var s_cost_source: Card = null
var s_cost_skill_index: int = -1
var s_cost_selected_card: Card = null
@onready var field: Field = get_parent().get_node("Field") as Field
@onready var hand: Hand = get_parent().get_node("Player/Hand") as Hand
@onready var assistant: Assistant = get_parent().get_node("Assistant") as Assistant
@onready var card_scene = preload("res://card.tscn")

signal execute_card_effect(card:Card)
signal request_priority()
## Emitted by the game when a stack effect has fully finished resolving.
signal resolution_complete

func _ready() -> void:
	assistant.choose_card_finished.connect(_on_choose_card_finished)

## Cards to lay out: the legal stack objects plus the parked card (if any).
## Positioning MUST go through this — using `cards` alone leaves the parked card
## out of the row width, which offsets every card. That is why a card awaiting
## payment used to sit visibly off-centre.
func layout_cards() -> Array:
	var list: Array = cards.duplicate()
	var parked = summon_casting_card if summon_casting_card != null else casting_card
	if parked != null:
		list.append(parked)
	return list

func calculate_total_width():
	var n: int = layout_cards().size()
	return (n * card_width) + ((n - 1) * card_spacing)
	
func stack_length() -> int:
	return len(cards)

## The stack hangs to the LEFT, like a hand: the TOP of the stack (the last card put there,
## `cards.back()`) is the leftmost card and each earlier card steps to the right of it.
## `_slot_for()` is the only place that knows this, so the arc, the tilt and the stacking height
## can never disagree about which end is which.
func _slot_for(i: int) -> int:
	return layout_cards().size() - 1 - i

## Shallow arc and per-card tilt, mirroring the hand: a plain row collapsed into one unreadable
## overlap as soon as a third card arrived.
const FAN_RADIUS := 3.0
## How much of the card pitch each neighbour advances along the arc. Below 1.0 the fan is TIGHTER
## than the old row was — a stack should read as one group, not as a spread-out row.
const FAN_TIGHTNESS := 0.5
## Height between neighbours, so the card in front is visibly in front.
const FAN_HEIGHT_STEP := 0.006
## Extra height for the card the player has selected. It has to clear FAN_HEIGHT_STEP times the
## number of cards, or a selected card at the back would still sit behind the front of the fan.
const FAN_RAISE := 0.06
## The review link's arrow, kept separate from the live targeting arrow and the block arc so the
## three can never re-aim or hide each other.
const LINK_ARROW_SCENE := preload("res://ballistic_arrow.tscn")

## Tilt/arc angle for a SLOT (0 = leftmost). Same shape as the hand's fan.
func fan_angle_for(slot: int) -> float:
	var n: int = layout_cards().size()
	var t: float = slot - (n - 1) / 2.0
	return -t * (card_width + card_spacing) * FAN_TIGHTNESS / FAN_RADIUS

## ----- reviewing the stack's targets ---------------------------------------------------------
## Every card in the stack keeps the target it was given (`Card.effect_target`), so the stack can
## re-draw any of those links on demand. That is the only way to see what an older ability was
## pointed at once a newer one has been put on top.
##
## The card on display is the one the mouse is OVER, and otherwise the TOP of the stack. Hovering
## is transient, so leaving a card restores the top with no "clicked elsewhere?" rule to remember.
var hovered_card: Card = null

func displayed_card() -> Card:
	if hovered_card != null and is_instance_valid(hovered_card) and cards.has(hovered_card):
		return hovered_card
	return cards.back() if not cards.is_empty() else null

func set_hovered(card: Card, entered: bool) -> void:
	if entered:
		hovered_card = card
	elif hovered_card == card:
		hovered_card = null
	refresh_target_display()

## Draw — or clear — the link for `displayed_card()`. DISPLAY ONLY: it opens no session and
## changes no game state; it exists so the player can look at what is already on the stack.
func refresh_target_display() -> void:
	# Never draw over a live targeting session. While one is open the arrow and the rings belong
	# to the choice being made, and a review link would fight them.
	var mode = GlobalVariables.get_player_mode()
	if mode == GlobalVariables.Player_Mode.TARGET \
			or mode == GlobalVariables.Player_Mode.PAYING_COST \
			or mode == GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND:
		return
	var card: Card = displayed_card()
	var target: Card = card.effect_target if card != null else null
	var field = get_parent().get("field")
	if field == null:
		return
	if target == null or not is_instance_valid(target):
		_clear_target_display()
		return
	# The FIELD draws it, not the stack: BallisticArrow's points are LOCAL, and the stack node is
	# flipped and lifted, so an arrow parented here and given global points lands wherever that
	# transform carries it ("arrows in random places").
	field.show_review_link(card, target)
	# NOTE: the link draws the ARROW ONLY — it deliberately does NOT paint the target's aura.
	# The aura already has an owner (the live pick, and the reveal that holds until the stack
	# resolves). An earlier version painted it here too, and because "clear only what I lit" is
	# indistinguishable when both writers light the SAME card, the review link stole the reveal's
	# ring and then cleared it. The arrowhead lands exactly on the target, so the link needs no
	# second signal to be readable.
	# If a hover aura is wanted later, the right change is to make the aura DERIVED in one place
	# that decides which card is marked and why — not to add a third writer of the same flags.

func _clear_target_display() -> void:
	var field = get_parent().get("field")
	if field != null:
		field.hide_review_link()

## Hide the review arrow before a live session opens: it draws the same arrow shape, and the
## session is about to draw its own from the same card. Done deterministically at the START of the
## session so "there is only ever one arrow on screen" does not depend on who refreshes first.
func release_target_display() -> void:
	hovered_card = null
	_clear_target_display()

## Which card the player is looking at. null means "the top of the stack"; see select_card().
var selected_card: Card = null

func selected_or_top() -> Card:
	if selected_card != null and is_instance_valid(selected_card) and cards.has(selected_card):
		return selected_card
	return cards.back() if not cards.is_empty() else null

## Clicking a card in the fan raises it, and makes it the card whose targeting is displayed.
func select_card(card: Card) -> void:
	if card == null or not cards.has(card):
		return
	selected_card = card
	update_card_positions()

## Back to the top of the stack — what any click outside the stack does.
func select_top() -> void:
	selected_card = null
	update_card_positions()

func update_card_positions():
	var list: Array = layout_cards()
	for i in range(list.size()):
		var card = list[i]
		card.index = i
		animate_card(card, calculate_card_position(i))
	# The stack just changed, so what is on display may have too: the default display is the TOP
	# of the stack, and after an add or a resolve that is a different card.
	refresh_target_display()
		
func calculate_card_position(i: int) -> Vector3:
	var card = layout_cards()[i]
	var slot: int = _slot_for(i)
	var angle: float = -fan_angle_for(slot)
	var x_offset: float = FAN_RADIUS * sin(angle)
	var z_offset: float = FAN_RADIUS * (1.0 - cos(angle))
	# `i` counts the other way to `slot`, so the top of the stack ends up in FRONT as well as on
	# the left: the higher the index, the higher the card.
	var y_offset: float = i * FAN_HEIGHT_STEP
	if selected_card != null and card == selected_card:
		y_offset += FAN_RAISE
	return Vector3(x_offset, y_offset, z_offset)
	
func animate_card(card, target_position):
	# Create a Tween to animate the card's movement
	var tween = create_tween()
	tween.set_parallel(true) 
	tween.tween_property(card, "position", target_position, 0.3)
	# Card.STACK_CARD_SCALE is a WORLD size and this node is scaled 2.305, so it is divided by that to land the card at
	# the size the constant promises — the same size the hand grows a hovered card to. Writing the constant straight
	# into `scale` made stack cards 2.3x too big, which is what "a hovered hand card and a stack card are different
	# sizes" turned out to be.
	tween.tween_property(card, "scale", Vector3.ONE * (Card.STACK_CARD_SCALE / Card.STACK_CONTAINER_SCALE), 0.3)
	# The fan tilt is tweened too, so a card added to the stack rotates into place rather than
	# snapping straight and then leaning.
	tween.tween_property(card, "rotation", Vector3(0.0, fan_angle_for(_slot_for(card.index)), 0.0), 0.3)
	

func add_card_to_tree(card):
	cards.append(card)
	card.index = cards.size()-1
	var trans = card.global_transform
	card.reparent(self,false)
	card.global_transform = trans
	_clear_top_energized()

## THE ENERGIZED GLOW ENDS WHEN THE CARD IS PLAYED.
##
## A glowing card is one the mana was spent on. The moment it sits on top of the stack it IS the signal — it needs no
## badge saying it was paid for — so the glow has done its job and stops there. On a Character, which never enters the
## stack at all, the zone change clears it instead (Card.enter_zone).
##
## Safe to call anywhere: it only clears a flag that is already set.
func _clear_top_energized() -> void:
	if cards.is_empty():
		return
	var top: Card = cards.back()
	if top != null:
		top.set_energized_highlight(false)
	
func add_created_card_to_tree(card:Card):
	cards.append(card)
	card.index = cards.size()-1
	var trans = card.global_transform
	add_child(card)
	if(card.key_word_effect):
		print("Adding effect to the stack")
	card.global_transform = trans
	
func cast_card():
	# It is being played, so it is public now, whichever branch runs.
	reveal_parked(casting_card)
	if casting_card.type == 'Summon':
		# Summons stay on the stack and resolve as effects. Resolution
		# (game._on_stack_execute_card_effect) sends them to the graveyard.
		casting_card.key_word_effect = "when_cast"
		# HISTORY AT THE CAST, not at resolution: "if you have cast X this turn" becomes true the moment the card is
		# played, and a Summon that is invalidated before it resolves was still cast.
		get_parent().record_action("Casted %s" % casting_card.card_name, [],
			1 if casting_card.controller == "player" else 2)
		# Board-wide "when a Summon is cast" triggers (Yuna 214, Lenne 215) fire at the cast, not at resolution.
		field.trigger_event("summon_cast", {"card": casting_card})
	else:
		# Character cards go straight to the field: they are never stack objects,
		# so nothing is popped and no stack slot is consumed. play_card() needs
		# the side explicitly — it cannot infer it from card.controller.
		#
		# THE MANA LANDS FIRST. Payment orbs fly to this card, so it must not move
		# until they have arrived — otherwise it is already on the field, with every
		# ring cleared, when they get there. Awaiting the shatter here is what gives
		# the orbs their flight, and what lets the energized glow actually be seen:
		# while the card is still in hand there is a ring for it to light.
		#
		# CAPTURED BEFORE THE AWAIT. While this function is suspended the caller runs on
		# and clears `casting_card` (the line right after its own _shatter_paid_cost()),
		# so reading the member afterwards dereferences null — which is exactly how this
		# crashed once the await was added. It is the only use of the member after the
		# suspension, so capturing it here is the whole fix.
		var landing: Card = casting_card
		await _shatter_paid_cost()
		field.play_card(landing, landing.controller != "player")
		# Playing a Character is a priority action even though the stack never
		# changed: priority must move to the opponent.
		get_parent().note_action_taken()
	
	
func _on_assistant_charge_complete() -> void:
	if summon_casting_card != null:
		_continue_summon_after_mana(summon_casting_card)
		return
	if casting_card:
		cast_card()
		# A Character going to the field, or a Summon being cast: this IS the play. See _shatter_paid_cost().
		_shatter_paid_cost()
		casting_card = null
		# The parked card left this node (played to the field): re-lay out the row.
		update_card_positions()
	elif skill_activation_proxy != null:
		field.continue_skill_activation_after_mana(skill_activation_proxy)

func _continue_summon_after_mana(card: Card) -> void:
	# Payment is only committed when the summon actually enters the stack
	# (after target confirmation). If the summon needs a target, target
	# selection happens now and may still be cancelled.
	var criteria = card.get_cast_target_criteria()
	if criteria.is_empty():
		_commit_summon_to_stack()
		request_priority.emit()
		return
	field.request_target(criteria, card, true, "Summon")

## The Hand that owns `card`. The `hand` member above is the LOCAL player's
## hand, which is the wrong one for an opponent's card now that agents can cast
## Summons too: committing through the wrong hand would leave a stale
## `charging_card` there, which can later pull the card back off the stack.
func _owner_hand(card: Card) -> Hand:
	return get_parent().hand_for(1 if card.controller == "player" else 2)

func _commit_summon_to_stack() -> void:
	if summon_casting_card == null:
		return
	var card: Card = summon_casting_card
	var owner_hand: Hand = _owner_hand(card)
	# Target is confirmed: finalize mana payment now (discard hand mana,
	# tap backup mana), then put the summon on the stack.
	field.apply_deferred_skill_mana_payment()
	owner_hand.apply_deferred_skill_mana_payment()
	# It is entering the stack from here on, so it becomes public.
	reveal_parked(card)
	summon_mana_deferred_until_target_confirm = false
	summon_casting_card = null
	card.key_word_effect = "when_cast"
	card.effect_kind = "Summon"
	owner_hand.finish_summon_cast(card)
	# The card is already parked on the stack node; now it legally enters
	# the stack list and resolves as a normal stack object.
	cards.append(card)
	card.index = cards.size() - 1
	update_card_positions()
	# Casting a Summon is a priority action: it is on the stack now, so priority
	# moves to the opponent. (Emitting in the Agent's case is harmless — no one
	# is awaiting the signal; the agent reports through take_priority().)
	get_parent().note_action_taken()


func begin_triggered_ability(source: Card, keyword: String) -> void:
	## Triggered auto-abilities go on the stack during rules processing,
	## before a player receives priority. Any "may" choice (e.g. Auron's
	## "play a Fire Backup") is made when the ability RESOLVES.
	if source == null or not source.card_effects.has(keyword):
		return
	_add_triggered_effect_to_stack(source, keyword)
	request_priority.emit()

func _add_triggered_effect_to_stack(source: Card, keyword: String) -> void:
	create_card(source.id, source.controller, keyword, source)
	update_card_positions()

func _mark_resolution_complete() -> void:
	resolution_pending = false
	resolution_complete.emit()

## Special ability (S) cost step 1: choose a card in hand that shares a name
## with the source. The actual discard is deferred until the skill commits.
func begin_s_cost_selection(source: Card, skill_index: int) -> void:
	var criteria: Dictionary = {"is_named": source.card_name}
	if not hand.has_card_matching_criteria(criteria):
		# Cannot pay the S cost: abort the whole activation.
		_clear_skill_proxy()
		GlobalVariables.refresh_mode()
		assistant.show_pass_priority_button()
		return
	s_cost_active = true
	s_cost_source = source
	s_cost_skill_index = skill_index
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND)
	hand.begin_choose_card(criteria)
	assistant.show_choose_card_buttons("Discard", "Cancel")

func _on_choose_card_finished(play: bool) -> void:
	if not s_cost_active:
		return
	s_cost_active = false
	var chosen: Card = hand.selected_card_for_effect
	hand.end_choose_card()
	assistant.hide_buttons()
	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND)
	assistant.show_pass_priority_button()

	if not play or chosen == null:
		_clear_skill_proxy()
		return

	s_cost_selected_card = chosen
	# S cost chosen. The mana stage follows ONLY if there is mana to pay: when the cost is empty the discarded card WAS the
	# whole payment, so asking for a Confirm on an empty screen is a button that exists only to be pressed.
	var def: Dictionary = s_cost_source.activation_skill(s_cost_skill_index)
	var cost: Dictionary = def.get("cost", {})
	if field.cost_is_free(cost):
		field.continue_skill_activation_after_mana(skill_activation_proxy)
		return
	field.card_activated_ability.emit(cost)

func add_skill_activation_proxy(source: Card, skill_index: int) -> bool:
	## Physical stack object for UI (pay + target). Costs apply later at de facto stack commit.
	if skill_activation_proxy != null:
		return false
	var definition: Dictionary = source.activation_skill(skill_index)
	if definition.is_empty():
		return false
	var proxy: Card = card_scene.instantiate()
	proxy.initialize(source.id, source.controller)
	proxy.skill_activation_index = skill_index
	# Snapshot the definition. The source's copied-skill slot may be overwritten or cleared while this object is
	# still on the stack, and an ability already on the stack must resolve independently of its source.
	proxy.skill_def_override = definition.duplicate(true)
	proxy.ability_spec = source.activation_ability_spec(skill_index)
	proxy.copied_skill_activation = bool(definition.get("copied", false))
	proxy.copied_skill_token = source.copied_skill_token if proxy.copied_skill_activation else 0
	proxy.key_word_effect = "skill"
	proxy.effect_source = source
	proxy.effect_kind = "Ability"
	skill_activation_proxy = proxy
	skill_mana_deferred_until_target_confirm = true
	add_created_card_to_tree(proxy)
	update_card_positions()
	# Activating an ability is a priority action.
	get_parent().note_action_taken()
	return true

func _apply_skill_source_tap_from_proxy() -> void:
	## Part of stack commit: JSON "tap" is a cost, not tied to resolution (instructions run in game._on_stack_execute_card_effect).
	if skill_activation_proxy == null:
		return
	var src: Card = skill_activation_proxy.effect_source
	if src == null or not src.is_inside_tree():
		return
	var def: Dictionary = skill_activation_proxy.skill_def_override
	if def.is_empty():
		def = src.activation_skill(skill_activation_proxy.skill_activation_index)
	if def.is_empty():
		return
	if def.get("tap", false):
		src.tap()

## Skill stack commit: activation is legally complete (costs paid, target on proxy if required).
## Resolution (execute instructions) happens later in resolve_top_effect -> game._on_stack_execute_card_effect.
func commit_skill_activation_costs_if_pending() -> void:
	if not skill_mana_deferred_until_target_confirm:
		return
	field.apply_deferred_skill_mana_payment()
	hand.apply_deferred_skill_mana_payment()
	_apply_skill_source_tap_from_proxy()
	# Special ability (S) cost: discard the card chosen from hand.
	if s_cost_selected_card != null:
		hand.discard_card(s_cost_selected_card)
		s_cost_selected_card = null
	# The copied-skill permission is one use. Consume only the exact permission this proxy was created from; a newer
	# Ronso Rage may have replaced the slot while this activation was waiting.
	if skill_activation_proxy != null and skill_activation_proxy.copied_skill_activation:
		var copied_source: Card = skill_activation_proxy.effect_source
		if copied_source != null:
			copied_source.consume_copied_skill(skill_activation_proxy.copied_skill_token)
	skill_mana_deferred_until_target_confirm = false

func _clear_skill_proxy() -> void:
	# WAS THIS ACTIVATION STILL PENDING? If so its cost never committed, and the tap that
	# begin_skill_activation() applied has to be refunded — otherwise a cancelled ability leaves the card tapped and
	# silently spent for the rest of the turn.
	#
	# `skill_mana_deferred_until_target_confirm` is exactly that flag: set when the proxy is created, cleared by
	# commit_skill_activation_costs_if_pending(). So it is still true here only when the player backed out.
	var was_pending: bool = skill_mana_deferred_until_target_confirm
	s_cost_active = false
	s_cost_source = null
	s_cost_skill_index = -1
	s_cost_selected_card = null
	if skill_activation_proxy == null:
		return
	var p = skill_activation_proxy
	skill_activation_proxy = null
	skill_mana_deferred_until_target_confirm = false
	# A damage split chosen for THIS ability must not outlive it: the next divide-damage ability would inherit it.
	get_parent()._damage_division.clear()
	if was_pending:
		var src: Card = p.effect_source
		if src != null and is_instance_valid(src) and src.tapped:
			src.untap()
	cards.erase(p)
	if is_instance_valid(p):
		p.queue_free()
	update_card_positions()


## A card awaiting its cost is only PARKED on this node — a visual placeholder.
## It is not in `cards`, so it is not legally on the stack, and it is not public
## knowledge yet: only its owner sees which card it is. A character card
## (Forward/Backup) never enters `cards` at all: once paid it goes straight to
## the field. Only a Summon becomes a stack card, and only at
## _commit_summon_to_stack().
func park_card(card: Card) -> void:
	var trans = card.global_transform
	card.reparent(self, false)
	card.global_transform = trans
	# Parked cards are flat and plain: no hand tilt and no field readout.
	card.enter_zone(Card.Zone.STACK)
	# Face-down for anyone but the owning player. Every exit from this node must
	# call reveal_parked().
	card.set_revealed(card.controller == "player")
	# update_card_positions() now includes the parked card (layout_cards()), so
	# it already places it in the row — no separate positioning here.
	update_card_positions()

## A parked card is leaving this node (committed to the stack, played to the
## field, or handed back to its owner), so it becomes public again.
func reveal_parked(card: Card) -> void:
	if card != null:
		card.set_revealed(true)

func _on_hand_charge_start(card: Card) -> void:
	if card.type == 'Summon':
		# Paid for (and targeted) before it legally enters the stack.
		summon_casting_card = card
		summon_mana_deferred_until_target_confirm = true
	else:
		casting_card = card
	park_card(card)


func _on_assistant_charge_cancelled() -> void:
	if skill_activation_proxy != null:
		# BACK ONE STEP, NOT OUT. A special ability is a TWO-STEP payment — pick the card that shares its name, then pay
		# the mana — so backing out of the MANA step returns to the s-cost step inside the same activation. The proxy is
		# kept, and with it the tap: cancelling AT the s-cost step is what abandons the activation, which is the branch
		# below. The previous pick is redone from scratch — its pink ring goes with it and begin_s_cost_selection()
		# re-prompts.
		if s_cost_selected_card != null:
			var src: Card = s_cost_source
			var idx: int = s_cost_skill_index
			if is_instance_valid(s_cost_selected_card):
				s_cost_selected_card.set_s_cost_highlight(false)
			s_cost_selected_card = null
			begin_s_cost_selection(src, idx)
			return
		_clear_skill_proxy()
		return
	if summon_casting_card != null:
		# It goes back to its owner's hand, so it must be face-up again.
		reveal_parked(summon_casting_card)
		summon_casting_card = null
		summon_mana_deferred_until_target_confirm = false
		return
	if casting_card != null:
		reveal_parked(casting_card)
		# Only ever parked, never in `cards`. Its own Hand takes it back
		# (Assistant.charge_cancelled → Hand._on_assistant_charge_cancelled).
		casting_card = null
		update_card_positions()
		return
	if cards.is_empty():
		return
	var card = cards.pop_back()
	if card.is_effect_card():
		card.queue_free()
	update_card_positions()


func _on_field_add_card_effect_to_stack(card_id: int, keyword: String, source: Card) -> void:
	create_card(card_id, source.controller, keyword, source)
	update_card_positions()

func create_card(id, controller, keyword, source) -> Card:
	var card: Card = card_scene.instantiate()  
	card.initialize(id,controller)
	card.key_word_effect = keyword
	card.effect_source = source
	card.effect_kind = "Ability"
	add_created_card_to_tree(card)
	update_card_positions()
	
	return card

## Enqueue a board-wide event trigger as a normal stack object. It must be a Card so the UI can show it and the
## ordinary priority loop can let either player respond; `event_trigger`/`event_context` make it resolve differently.
## A code-defined triggered ability. Its effect object is stateless; the stack copy carries the event name and a small
## event payload until Game resolves it through CardEffect.dispatch.
func enqueue_code_trigger(source: Card, event: String, data: Dictionary = {}) -> Card:
	var card: Card = create_card(source.id, source.controller, "__code_event", source)
	card.effect_event = event
	card.effect_event_data = data.duplicate(true)
	card.effect_kind = "Ability"
	update_card_positions()
	return card

func enqueue_event_trigger(source: Card, trigger: Dictionary, context: Dictionary) -> Card:
	var card: Card = create_card(source.id, source.controller, "__event_trigger", source)
	card.event_trigger = trigger.duplicate(true)
	card.event_context = context.duplicate()
	card.effect_kind = "Ability"
	update_card_positions()
	return card

## CANCEL a stack object without resolving it (Summoner 53 countering a Summon). It was already paid for, so the card
## goes to its owner's Break Zone. Removing it from `cards` is enough to stop it resolving — the priority loop takes
## the top of that list — and the fan is re-laid out immediately.
func cancel_stack_card(card: Card) -> void:
	if card == null or not is_instance_valid(card):
		return
	if not cards.has(card):
		return
	print("[Counter] %s is cancelled" % card.card_name)
	cards.erase(card)
	if summon_casting_card == card:
		summon_casting_card = null
	if casting_card == card:
		casting_card = null
	var game: Node = get_parent()
	var pile = game.get("player_graveyard") if card.controller == "player" else game.get("opponent_graveyard")
	if pile != null:
		pile.add_card(card)
	update_card_positions()

func resolve_top_effect() -> void:
	## Stack resolution: run effect instructions only; costs were applied at
	## commit for skills. The effect handler may await a modal (e.g. Auron's
	## "may play a Backup" choice), so resolution waits for the game to signal
	## resolution_complete before continuing.
	if cards.is_empty():
		return
	var card: Card = cards.pop_back()
	# CLOSE THE GAP. A card leaving the stack is the same event as a card leaving the hand: the remaining fan has to
	# reflow, or every resolved effect leaves a hole where its card used to be. Same call the skill-proxy teardown
	# above already makes, and it also refreshes the hover/review link (update_card_positions ends with
	# refresh_target_display).
	update_card_positions()
	if card == skill_activation_proxy:
		skill_activation_proxy = null
		skill_mana_deferred_until_target_confirm = false
	print('Resolve ', card.card_name)
	resolution_pending = true
	execute_card_effect.emit(card)
	if resolution_pending:
		await resolution_complete
	resolution_pending = false
	if len(cards) == 0:
		# The stack is done, so any "the opponent chose this" reveal is spent. Clearing it
		# here — rather than never — is what stops the red ring from outliving the effect.
		field.clear_targeted_highlights()
		GlobalVariables.refresh_mode()

	


func _on_field_request_target_confirmation(target_card: Card, _allow_cancel: bool = false) -> void:
	if summon_casting_card != null:
		# A STAGED SUMMON records every pick, not just the last (Hades: Forward + Backup). The single-target
		# assignment stays for the ordinary case.
		var summon_picks: Array = get_parent().field.targeting_picked
		if summon_picks.size() > 1:
			summon_casting_card.set_effect_targets(summon_picks)
		else:
			summon_casting_card.effect_target = target_card
		return
	# AN EMPTY STACK IS NOT AN ERROR HERE. A multi-target session emits this once per pick, and by a later pick the effect
	# may already have resolved and been popped — there is simply no stack object left to record a target on, and
	# `cards[-1]` on an empty array is what threw "Invalid access of index '-1' on a base object of type: 'Array'".
	# NOTE for whoever reads this next: `effect_target` can only ever hold ONE card, so it is the LAST pick. An effect
	# that wants all of them reads Field.targeting_picked instead (see Game.untap_targets for 1-064).
	if cards.is_empty():
		return
	var effect_card: Card = cards[-1]
	# THE WHOLE SESSION, not just the card this call carries. A multi-target session calls this once per pick, so
	# assigning the single card would leave only the last one — which is exactly the wall this had. The session's picks
	# are captured HERE, at the moment of the pick: from then on the EFFECT owns them, and nothing downstream has to go
	# looking in the targeting UI's state, which the next session overwrites.
	var picks: Array = get_parent().field.targeting_picked
	if picks.size() > 1:
		effect_card.set_effect_targets(picks)
	else:
		effect_card.effect_target = target_card

## THE PLAY HAS LANDED, so break the crystals that paid for it — and take the row down with them.
##
## This is the moment a play becomes legal, and it is deliberately NOT Assistant.on_charge_complete(): that fires when
## the payment modal is confirmed, which for a Summon is BEFORE its target is chosen, and for an ability is BEFORE its
## activation is committed. Both of those steps can still be cancelled — and cancelling REFUNDS the mana — so
## breaking the crystals there meant they shattered for a play that never happened.
##
## The row is HELD on screen between those two moments (Assistant.cost_row_hold) precisely so the crystals are still
## visible here. Breaking them while they are up is the whole point: the shards come out of something the player can
## see, instead of appearing out of nothing after the crystals have already gone.
##
## Called from the three places a play actually lands: a Character going to the field (cast_card(), which AWAITS this so
## the orbs can fly before the card moves), a Summon entering the stack, and an ability whose costs are paid and whose
## target, if any, is chosen.
##
## AWAITED, so the payment orbs are not fire-and-forget: the caller is waiting for them, and they finish only when the
## last one reaches the card. The other two call sites simply do not need to wait, so they let it run.
func _shatter_paid_cost() -> void:
	if assistant != null:
		await assistant.commit_cost_readout(_paid_for_card())

## The card this payment is being spent on, which is where the shatter orbs fly: the top of the stack, or the Character
## being played when there is no stack card at all.
##
## A CHARACTER NEVER ENTERS THE STACK, so for one of those "the card being paid for" is the card itself — casting_card,
## which is set while it is being played. Either way the orbs have something to be swallowed by, which is the point of
## the effect.
func _paid_for_card() -> Card:
	if not cards.is_empty():
		return cards.back()
	return casting_card

func _on_assistant_target_complete() -> void:
	# AN EX BURST IS NOT A SKILL ACTIVATION. With no Summon parked and no skill proxy there is nothing to commit:
	# the target belonged to a damage card's ex burst, which resolves itself and never touches this node. Without
	# this guard the handler hid the buttons and emitted request_priority, which reads exactly like "the effect
	# went to the stack" - and it never set the Game's _targets, so the ex burst's damage then resolved against
	# nothing at all. That was both halves of the report.
	#
	# BUT A TRIGGERED ABILITY CAN HAVE SEVERAL TARGETS ("choose up to 5 Backups you control", Rikku). A single target
	# is already attached by request_target_confirmation as each pick is made; a LIST has to be copied onto the stack
	# object here, or the effect resolves against only the last one.
	if summon_casting_card == null and skill_activation_proxy == null:
		var chosen: Array = get_parent().field.targeting_picked
		var top: Card = cards.back() if not cards.is_empty() else null
		if top != null and chosen.size() > 1:
			top.set_effect_targets(chosen)
		return
	if summon_casting_card != null:
		_commit_summon_to_stack()
		_shatter_paid_cost()      # the Summon is on the stack
		request_priority.emit()
		return
	# DIVIDE DAMAGE IS CHOSEN BEFORE THE ABILITY COMMITS. "Divide 6000 damage among them as you like" (Yuffie's
	# Bloodfest) is part of PLAYING the ability, not of resolving it — which is exactly what lets Cancel on the
	# distribution screen step back to target selection instead of stranding a committed effect.
	var pool: int = _divide_damage_total(skill_activation_proxy)
	if pool >= 0:
		var field_ref = get_parent().field
		var picks: Array = field_ref.targeting_picked.duplicate()
		var owner_id: int = 1 if skill_activation_proxy.controller == "player" else 2
		var agent: Agent = get_parent().agent_for(owner_id)
		var split: Array = await agent.choose_damage_split(owner_id, picks, pool)
		if split.is_empty():
			# BACK ONE STEP. The targeting session was never torn down — picks and arcs are intact — so the only thing
			# missing is the TARGET modal and its Confirm button. Costs already paid stay paid: the ability is still
			# being activated, the player is only redoing this choice.
			GlobalVariables.push_modal(GlobalVariables.Player_Mode.TARGET)
			field_ref.request_target_confirmation.emit(
				picks.back() if not picks.is_empty() else null, field_ref.targeting_allow_cancel)
			return
		get_parent()._damage_division = split
	commit_skill_activation_costs_if_pending()
	_shatter_paid_cost()          # activation committed: costs paid, target chosen
	# Same as the no-target path below: clear the button that got us here, then put the player's pass button back. Hiding the
	# rack alone leaves the parked priority round with nothing to be answered by.
	assistant.hide_buttons()
	assistant.show_pass_priority_button()
	request_priority.emit()

## The damage pool for an ability that says "divide N damage among them", or -1 when it says no such thing.
## Read from the SKILL DEF of the source, because the stack object is a proxy with no skill array of its own.
func _divide_damage_total(proxy: Card) -> int:
	if proxy == null:
		return -1
	var def: Dictionary = proxy.skill_def_override
	if def.is_empty():
		if proxy.skill_activation_index < 0:
			return -1
		var src: Card = proxy.effect_source
		if src == null:
			return -1
		def = src.activation_skill(proxy.skill_activation_index)
	if def.is_empty():
		return -1
	for instruction in def.get("instructions", []):
		if str(instruction.get("name", "")) == "divide_damage":
			var args: Array = instruction.get("argument", [])
			return int(args[0]) if not args.is_empty() else 0
	return -1

func confirm_skill_without_target_then_priority() -> void:
	commit_skill_activation_costs_if_pending()
	_shatter_paid_cost()          # activation committed: a skill with no target needs no confirmation
	# REPLACE THE CONFIRM WITH THE PASS BUTTON — do not just clear the rack.
	#
	# The confirm that got here came from generate_confirm_button() and shares the rack with the pass button. Left standing,
	# it hides the pass button and the player has no control. But HIDING THE WHOLE RACK IS JUST AS BAD, and worse in a way
	# that is easy to miss: the priority round that is PARKED on the human is still waiting for a pass, and clearing the
	# buttons takes away the very button it is waiting for. That version of this fix left the player staring at an empty
	# screen with the effect on the stack — which is exactly what happened.
	#
	# hide_buttons() then show_pass_priority_button(): the first removes the stale confirm, the second puts the player's
	# only remaining control back. Both skill paths do this so neither can forget.
	assistant.hide_buttons()
	assistant.show_pass_priority_button()
	request_priority.emit()

func _on_assistant_target_cancel() -> void:
	## Only activated-ability (skill) flow may abort and remove the stack copy; ETB is mandatory.
	if skill_activation_proxy != null:
		_clear_skill_proxy()
	elif summon_casting_card != null:
		# Payment was deferred and is now refunded: nothing is discarded or
		# tapped, and the summon returns to hand without entering the stack.
		var cancelled: Card = summon_casting_card
		summon_casting_card = null
		summon_mana_deferred_until_target_confirm = false
		# It is going back to its owner's hand, so reveal it again.
		reveal_parked(cancelled)
		_owner_hand(cancelled).cancel_summon_cast()
