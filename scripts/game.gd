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
@onready var opponent_front_row_card = $Field/OpponentFrontrowCard
@onready var opponent_damage_zone = $Opponent/DamageZone
@onready var select_arrow: BallisticArrow  = $BallisticArrow
@onready var assistant: Assistant = $Assistant
@onready var card_scene = preload("res://card.tscn")
@onready var turn_owner = 1


var _current_instructions: Array[Instruction]
var _current_source_card: Card
var _current_controller: String
var _current_attacker_card: Card
var _current_blocker_card: Card
var _targets = []
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



func _ready():
	start_match(MatchSetup.resolve_config())

func start_match(config: Dictionary) -> void:
	# Everything a match needs comes from its config (see MatchSetup presets);
	# the same scene serves the menu, the practice board, and future self-play.
	priority_holder = 0

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
	# Assistant opens the payment modal + sets mana_cost from the card.
	owner_hand.charge(card)
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
		field.play_card(card, is_opponent, false)
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
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_T:
		var card = opponent_deck.deck_cards.pop_front()
		opponent_damage_zone.draw(card)

func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if($FocusCard):
			$FocusCard.visible = false

func create_card(id, controller):
	var card = card_scene.instantiate()  
	card.initialize(id,controller) 
	if card.has_signal("execute_instructions"):
		card.execute_instructions.connect(_execute_instructions)
	if card.has_signal("on_target"):
		card.on_target.connect(_on_target_selected)
	return card

func _execute_instructions(instructions: Array[Instruction]) -> void:
	# Concatenate arrays (new instructions go in front)
	_current_instructions = instructions + _current_instructions
	_process_next_instruction()
	if(_current_instructions.is_empty()):
		_clean_instruction_stack()
	
func _clean_instruction_stack():
	_current_source_card = null
	_current_attacker_card = null
	_current_blocker_card = null
	_targets = []

func _process_next_instruction() -> void:
	if _current_instructions.is_empty():
		# All instructions resolved: apply state-based actions so a card
		# whose accumulated damage has reached its power is broken now.
		enforce_game_state_rules()
		return

	var instruction = _current_instructions.pop_front()
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
	executor.callv(instruction.action, args)
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
		_:
			var node: Node = get_node_or_null(executor_key)
			if node == null:
				push_error("Unknown executor: %s" % executor_key)
			return node

func _on_target_selected(card: Card):
	if(card.is_valid_target):
		_targets.append(card)
		select_arrow.lock_arc(card.get_global_center())
		var cancelTarget = func():
			_targets = []
			select_arrow.unlock_arc()
			assistant.hide_buttons()
		if(check_target_requirements()):
			assistant.set_confirm_button(finish_target)
			assistant.set_cancel_button(cancelTarget)
			assistant.set_confirm_text('Confirm')
			assistant.set_cancel_text('Cancel')
			assistant.show_buttons()
		else:
			assistant.hide_buttons()
	else:
		assistant.hide_buttons()
		_targets = []
		select_arrow.unlock_arc()

func check_target_requirements():
	if len(_targets) >= 1:
		return true

func request_target(targeting_criteria):
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.TARGET)
	$Field.set_viable_targets(targeting_criteria, _current_source_card)
	select_arrow.set_is_aiming(true, _current_source_card.global_position)

func finish_target():
	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.TARGET)
	select_arrow.set_is_aiming(false)
	$Field.reset_targets()
	_process_next_instruction()

func pass_priority():
	TEST_blocker()
	await get_tree().create_timer(2.0).timeout
	return []
func TEST_blocker():
	var front_cards = field.TEST_get_front_cards()
	var blocker: Card = front_cards[0] if front_cards.size() > 0 else null
	if(blocker != null):
		blocker.declare_blocker()
func _await_player_response():
	await get_tree().create_timer(1.0).timeout
	return null

func cause_damage():
	# The DEFENDING player (whoever isn't taking the turn) takes the damage, so
	# an opponent attack actually hurts the human.
	side_for(3 - turn_owner).take_damage(1)
	# Triggered auto-ability: "when this card deals damage to the opponent".
	if field.attacker_card != null:
		stack.begin_triggered_ability(field.attacker_card, "when_cause_damage_to_player")
	
func cause_damage_to_player(player_argument):
	if player_argument == 'controller':
		pass
	
	
	
func cause_attacking_damage():
	if field.blocker_card == null:
		cause_damage()

## A side took damage. Checking the threshold here means every damage source —
## attacks and effects alike — shares one win condition.
func _on_player_side_damaged(side: PlayerSide) -> void:
	if match_over or not side.is_defeated():
		return
	# Compare against the node, like side_for(), so there is only one definition
	# of which side is P1 (the exported `controller` must not be a second one).
	_end_match(2 if side == player else 1)

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
		player.take_damage(amount)
	else:
		opponent.take_damage(amount)

func damage_player(amount: int = 1) -> void:
	# Damages the opponent of the effect's source controller.
	if _current_source_card == null:
		return
	if _current_source_card.controller == "player":
		opponent.take_damage(amount)
	else:
		player.take_damage(amount)

func damage_forward(damage):
	var card: Card = _targets[0]
	card.suffer_damage(damage)
	enforce_game_state_rules()
	
func set_attacker(card):
	_current_attacker_card = card
func set_blocker(card):
	_current_blocker_card = card
	# Persist it on the Field: _clean_instruction_stack() nulls the transient
	# _current_blocker_card as soon as these instructions finish, which happens
	# BEFORE DAMAGE_RESOLUTION reads it.
	field.blocker_card = card

func clash_cards(card1:Card,card2:Card):
	if card1.is_on_field() and card2.is_on_field():
		card1.suffer_damage(card2.power)
		card2.suffer_damage(card1.power)
		enforce_game_state_rules()
	pass
func clash_attacker_blocker():
	clash_cards(field.attacker_card, field.blocker_card)
	
	

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
			var attacker: Card = await attacker_agent.decide_attacker(turn_owner)
			if local_attack:
				GlobalVariables.pop_modal(GlobalVariables.Player_Mode.ATTACKING)
			if attacker != null:
				if field.attacker_card != attacker:
					field.set_attacker(attacker)
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
				assistant.set_declare_block_button('No Block')
			var blocker: Card = await defender_agent.decide_blocker(defender_id, field.attacker_card)
			if local_defence:
				GlobalVariables.pop_modal(GlobalVariables.Player_Mode.BLOCKING)
			if blocker != null:
				blocker.declare_blocker()
			await priority()
			pass
		GlobalVariables.Phase.DAMAGE_RESOLUTION_STEP:
			# A blocked attack clashes instead of damaging the player. This is
			# the ONLY clash — Card.declare_blocker() just records the blocker.
			if field.blocker_card != null:
				clash_attacker_blocker()
			else:
				cause_damage()
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
	
func priority() -> void:
	# Only one priority round may run at a time. Extra requests (e.g. from
	# Stack.request_priority while a round is already running) are no-ops;
	# the running loop detects the stack growth and restarts the round.
	if _priority_lock:
		return
	_priority_lock = true

	while true:
		# Each round, both players get priority: turn owner first. If the
		# stack grows while someone has priority, the round restarts so the
		# new effect can be responded to.
		var stack_len_at_round_start: int = stack.stack_length()
		var both_passed := true

		for holder in [turn_owner, 3 - turn_owner]:
			priority_holder = holder
			await agent_for(holder).take_priority(holder)

			if stack.stack_length() > stack_len_at_round_start:
				both_passed = false
				break

		if not both_passed:
			continue

		if stack.stack_length() > 0:
			# Resolve the top effect. The call may await an interactive modal
			# (e.g. Auron's "may play a Backup" choice at resolution).
			await stack.resolve_top_effect()
			continue

		break

	# Release the lock before advancing so the next phase can start its own
	# priority round.
	_priority_lock = false
	next_phase()

func _exit_phase(phase_name: String):
	match phase_name:
		"End Phase":
			pass

func MOCK_opponent_pass_piority():
	await get_tree().create_timer(0.5).timeout

func enforce_game_state_rules() -> void:
	# State-based actions, checked after any damage/power change.
	# 1) Power reduced to 0 (or less): the card is put into the Graveyard.
	#    This is NOT a break, so "when put into the Break Zone" effects do
	#    not trigger. (Break Zone and Graveyard share a container here, but
	#    the removal events are distinct.)
	for card in field.get_zero_power_cards():
		put_card_into_graveyard(card)
	# 2) Accumulated damage greater than current power: the card is broken.
	for card in field.get_breakable_cards():
		break_card(card)

func _send_card_to_graveyard(card: Card) -> void:
	if card.controller == "player":
		player_graveyard.add_card(card)
	else:
		opponent_graveyard.add_card(card)

func put_card_into_graveyard(card: Card) -> void:
	# Removal that is not a break (e.g. power reduced to 0). No break-zone
	# triggers fire and the "unbreakable" status does not apply.
	if not card.is_on_field():
		return
	card.untap()
	field.remove_card(card)
	_send_card_to_graveyard(card)

func break_card(card: Card):
	if not card.is_on_field():
		return
	if 'unbreakable' in card.status_effects:
		return
	# Trigger "when this card is put from the field into the break zone"
	# effects before the card leaves the field.
	if card.is_key_word_in_card_effect("when_enter_break_from_field"):
		field.execute_card_effect(card, "when_enter_break_from_field")
	card.untap()
	field.remove_card(card)
	_send_card_to_graveyard(card)

func pop_stack():
	var card = stack.pop_stack()
	player_graveyard.add_card(card)

func _on_assistant_process_next_instruction() -> void:
	_process_next_instruction()

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
	

func _on_stack_execute_card_effect(card: Card) -> void:
	# Resolution may await an interactive modal (e.g. Auron's "may play a
	# Backup" choice). Stack.resolve_top_effect() waits for our
	# _mark_resolution_complete() signal at the end of this function.
	var instructions = card.get_card_effect_instructions()
	var target = card.effect_target
	_current_source_card = card.effect_source if card.effect_source != null else card
	_current_controller = card.controller
	_targets = [target]

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

	_execute_instructions(instructions)

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
