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
	tween.tween_property(card, "scale", Vector3.ONE*1.4, 0.3)
	# The fan tilt is tweened too, so a card added to the stack rotates into place rather than
	# snapping straight and then leaning.
	tween.tween_property(card, "rotation", Vector3(0.0, fan_angle_for(_slot_for(card.index)), 0.0), 0.3)
	

func add_card_to_tree(card):
	cards.append(card)
	card.index = cards.size()-1
	var trans = card.global_transform
	card.reparent(self,false)
	card.global_transform = trans
	
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
	else:
		# Character cards go straight to the field: they are never stack objects,
		# so nothing is popped and no stack slot is consumed. play_card() needs
		# the side explicitly — it cannot infer it from card.controller.
		field.play_card(casting_card, casting_card.controller != "player")
		# Playing a Character is a priority action even though the stack never
		# changed: priority must move to the opponent.
		get_parent().note_action_taken()
	
	
func pop_stack():
	return cards.pop_back()

func _on_assistant_charge_complete() -> void:
	if summon_casting_card != null:
		_continue_summon_after_mana(summon_casting_card)
		return
	if casting_card:
		cast_card()
		casting_card = null
		# The parked card left this node (played to the field): re-lay out the row.
		update_card_positions()
	elif skill_activation_proxy != null:
		field.continue_skill_activation_after_mana(skill_activation_proxy)

func _continue_summon_after_mana(card: Card) -> void:
	# Payment is only committed when the summon actually enters the stack
	# (after target confirmation). If the summon needs a target, target
	# selection happens now and may still be cancelled.
	var criteria: Dictionary = card.get_cast_target_criteria()
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
	# S cost chosen: proceed to the regular mana payment step.
	var def: Dictionary = s_cost_source.card_effects["skill"][s_cost_skill_index]
	field.card_activated_ability.emit(def.get("cost", {}))

func add_skill_activation_proxy(source: Card, skill_index: int) -> bool:
	## Physical stack object for UI (pay + target). Costs apply later at de facto stack commit.
	if skill_activation_proxy != null:
		return false
	var proxy: Card = card_scene.instantiate()
	proxy.initialize(source.id, source.controller)
	proxy.skill_activation_index = skill_index
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
	var idx: int = skill_activation_proxy.skill_activation_index
	if src == null or not src.is_inside_tree():
		return
	if not "skill" in src.card_effects:
		return
	var skills: Array = src.card_effects["skill"]
	if idx < 0 or idx >= skills.size():
		return
	var def: Dictionary = skills[idx]
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
	skill_mana_deferred_until_target_confirm = false

func _clear_skill_proxy() -> void:
	s_cost_active = false
	s_cost_source = null
	s_cost_skill_index = -1
	s_cost_selected_card = null
	if skill_activation_proxy == null:
		return
	var p = skill_activation_proxy
	skill_activation_proxy = null
	skill_mana_deferred_until_target_confirm = false
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

func resolve_top_effect() -> void:
	## Stack resolution: run effect instructions only; costs were applied at
	## commit for skills. The effect handler may await a modal (e.g. Auron's
	## "may play a Backup" choice), so resolution waits for the game to signal
	## resolution_complete before continuing.
	if cards.is_empty():
		return
	var card: Card = cards.pop_back()
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
	
func process_next_effect():
	await get_tree().create_timer(1.0).timeout
	var card: Card = cards.pop_back()
	execute_card_effect.emit(card)
	if len(cards) > 0:
		process_next_effect()
	


func _on_field_request_target_confirmation(target_card: Card, _allow_cancel: bool = false) -> void:
	if summon_casting_card != null:
		summon_casting_card.effect_target = target_card
		return
	var effect_card: Card = cards[-1]
	effect_card.effect_target = target_card

func _on_assistant_target_complete() -> void:
	if summon_casting_card != null:
		_commit_summon_to_stack()
		request_priority.emit()
		return
	commit_skill_activation_costs_if_pending()
	request_priority.emit()

func confirm_skill_without_target_then_priority() -> void:
	commit_skill_activation_costs_if_pending()
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
