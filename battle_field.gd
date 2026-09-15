extends Node3D
class_name Field


const CARD_CHARGE = 1
var front_cards: Array[Card] = []
var back_cards: Array[Card] = []
var opponent_front_cards: Array[Card] = []
var opponent_back_cards: Array[Card] = []
var target_card: Card = null
var source_card: Card = null
var attacker_card: Card = null
## The blocker declared for the current combat. Persisted on the Field because
## Game's transient `_current_blocker_card` is cleared as soon as the blocker's
## instructions finish, which is before DAMAGE_RESOLUTION reads it.
var blocker_card: Card = null
var arrow: BallisticArrow
## A SEPARATE arrow for the combat's block link. The targeting arrow above belongs to a
## targeting session and follows the mouse; sharing one instance would let either one
## re-aim or hide the other.
var block_arrow: BallisticArrow = null
## If false (e.g. ETB), targeting cannot be cancelled and stack effect is mandatory.
var targeting_allow_cancel: bool = false
signal selected_cards_for_mana_has_changed(amount:int, element:String)
signal add_card_effect_to_stack(card_id:int, keyword:String, source:Card)
signal request_target_confirmation(target_card: Card, allow_cancel: bool)
signal attacker_changed
signal blocker_changed
signal card_activated_ability(cost:Dictionary)
## Read-through to the match's phase (owned by `Game`); Field keeps no copy.
var phase: GlobalVariables.Phase:
	get:
		return get_parent().phase
@export var selected_cards_for_mana_conversion: Array[Card] = []
@onready var ballistic_arrow_scene = preload("res://ballistic_arrow.tscn")
@onready var assistant: Assistant = get_parent().get_node("Assistant")
@onready var stack: Stack = get_parent().get_node("Stack") as Stack
@onready var hand: Hand = get_parent().get_node("Player/Hand") as Hand

class AuraValue:
	var method: String
	var targets: Dictionary  # Changed from Array[String] to Dictionary
	var value: int

	func _init(p_method: String, p_targets: Dictionary, p_value: int = 0):
		method = p_method
		targets = p_targets
		value = p_value
		

var _auras: Dictionary[int, AuraValue] = {}
func add_aura(aura: Dictionary, id:int):
	var value = aura.get('value', 0)
	var aura_value = AuraValue.new(
	aura['method'],
	aura['targets'], 
	value,
)
	_auras[id] = aura_value
	
func activate_aura_in_field(aura:AuraValue):
	var all_cards: Array[Card] = get_all_cards()
	for card:Card in all_cards:
		add_aura_to_card(aura,card)

func add_aura_to_card(aura: AuraValue, card: Card):
	if card.does_card_match_target(aura.targets):
		if aura.method == 'power_change':
			# -1 = permanent modifier (does not expire at end of turn).
			card.power_change(aura.value, -1)
				
func add_all_auras_to_card(card:Card):
	for aura in _auras.values():
		add_aura_to_card(aura,card)		

func add_card_to_mana_conversion(card:Card):
	if  not selected_cards_for_mana_conversion.has(card):
		selected_cards_for_mana_conversion.push_back(card)
	# Owns the marker, so an agent paying a cost gets the same feedback as a click.
	card.show_mana_crystal()
	selected_cards_for_mana_has_changed.emit(1,card.element)
	
func remove_card_from_mana_conversion(card:Card):
	if selected_cards_for_mana_conversion.has(card):
		selected_cards_for_mana_conversion.erase(card)
	card.clear_mana_crystal()
	selected_cards_for_mana_has_changed.emit(-1,card.element)


func play_card(card, is_opponent: bool = false, animate = true) -> void:
	var trans = card.global_transform
	card.reparent(self, false)
	card.position = Vector3.ZERO
	card.global_transform = trans
	
	var target_node
	var target_array
	
	if card.type == 'Forward':
		target_array = opponent_front_cards if is_opponent else front_cards
		target_node = $OpponentFrontrowCard if is_opponent else $FrontrowCard
	else:  # Backup
		target_array = opponent_back_cards if is_opponent else back_cards
		target_node = $OpponentBackrowCard if is_opponent else $BackrowCard
	
	# Add card to appropriate array
	var n = target_array.size()
	target_array.append(card)
	register_conditional_effects(card)
	recompute_conditional_power()
	
	# Calculate position
	var target_position = target_node.position
	if n % 2 == 0:
		target_position -= (n/2) * Vector3(0.8, 0, 0)
	else:
		target_position += ((n+1)/2) * Vector3(0.8, 0, 0)
	
	# The card is entering the field: normalise its look first (rotation, scale and
	# the power/damage readout). Without this a card played from hand keeps the
	# hand's fan tilt, because the reparent above deliberately preserves the whole
	# global transform so the travel animation starts where the card was.
	card.enter_zone(Card.Zone.FIELD)

	if animate:
		var tween = create_tween().set_ease(Tween.EASE_OUT)
		tween.set_parallel(true)
		tween.tween_property(card, "position", target_position + Vector3(0, 0.8, 0), 0.3).set_delay(0.3)
		tween.set_trans(Tween.TRANS_BACK)
		# Same 1.2 as enter_zone: the pop must not leave the card at a different
		# size than a play that skipped the animation.
		tween.tween_property(card, "scale", Vector3.ONE*1.2, 0.5)
		tween.set_parallel(false)
		tween.tween_property(card, "position", target_position + Vector3(0, 2, 0), 0.6).set_delay(0.2)
		tween.tween_property(card, "position", target_position, 0.4)
		
		# Execute ETB after the ENTIRE tween sequence finishes
		tween.finished.connect(_on_tween_finished.bind(card))
	else:
		card.position = target_position
		GlobalVariables.refresh_mode()
	
func _on_tween_finished(card: Card):
	GlobalVariables.refresh_mode()
	#var instructions = card.create_instruction_from_json(card.card_effects['when_enter_field']['instructions'])
	execute_card_effect(card,"when_enter_field")
	#request_target_confirmation.emit()
	
func execute_card_attack():
	attacker_card.tap()
	execute_card_effect(attacker_card,'when_attack')
	
func end_phase_cleanup():
	# End Phase cleanup: remove all damage from every card on the field and
	# expire "until end of turn" effects. (No end-of-turn priority window
	# exists yet, so this runs immediately on entering the End Phase.)
	for c in get_all_cards():
		c.turn_end()
func try_activate_from_field(card: Card) -> void:
	if not "skill" in card.card_effects:
		return
	var skills: Array = card.card_effects["skill"]
	if skills.is_empty():
		return
	if skills.size() == 1:
		begin_skill_activation(card, 0)
	else:
		card.show_actions()

## True while the LOCAL player holds the window. Holding a card you *could* activate is not the
## same as being allowed to activate it: while the OPPONENT holds priority the input mode is
## still FREE/INSTANT_SPEED_TIME, so the mode alone cannot answer this question. A finished
## match is not a window either.
func has_priority() -> bool:
	var game: Node = get_parent()
	if game == null:
		return false
	if bool(game.get("match_over")):
		return false
	return int(game.get("priority_holder")) == 1

## The authoritative "this card's effect can be activated right now" gate: your card, YOUR
## WINDOW, untapped, with an activatable skill, in a moment where acting is allowed (FREE or
## INSTANT_SPEED_TIME — no targeting, payment or declaration modal open).
##
## begin_skill_activation() uses this as its precondition AND the green availability ring is
## driven from it, so the cue and the action can never disagree. Any condition added here
## therefore tightens both at once.
func can_activate_now(card: Card) -> bool:
	if card == null or card.controller != "player":
		return false
	if not has_priority():
		return false
	var mode = GlobalVariables.get_player_mode()
	if mode != GlobalVariables.Player_Mode.FREE and mode != GlobalVariables.Player_Mode.INSTANT_SPEED_TIME:
		return false
	if card.tapped:
		return false
	if not "skill" in card.card_effects:
		return false
	return not (card.card_effects["skill"] as Array).is_empty()

## Green ring: "you may activate this right now" — your cards only, and gone the moment a modal
## takes the moment away. It is DERIVED state with many causes (the input mode, a card's tapped
## state, which cards are on the field), so it is POLLED rather than hooked to one trigger; the
## card setters are guarded, so an unchanged card costs a bool comparison.
const AVAILABILITY_POLL := 0.15
var _availability_timer: float = 0.0

func _process(delta: float) -> void:
	_availability_timer += delta
	if _availability_timer < AVAILABILITY_POLL:
		return
	_availability_timer = 0.0
	refresh_available_effects()

func refresh_available_effects() -> void:
	for card in get_all_cards():
		card.set_available_highlight(can_activate_now(card))

func begin_skill_activation(card: Card, skill_index: int = 0) -> void:
	if not can_activate_now(card):
		return
	var skills: Array = card.card_effects["skill"]
	if skill_index < 0 or skill_index >= skills.size():
		return
	if not stack.add_skill_activation_proxy(card, skill_index):
		return
	assistant.clear_payment_accumulator()
	var def: Dictionary = skills[skill_index]
	if def.get("s_cost", false):
		# Special ability (S): first discard a card sharing a name with the
		# source, then the regular mana payment step follows.
		stack.begin_s_cost_selection(card, skill_index)
		return
	var cost: Dictionary = def.get("cost", {})
	card_activated_ability.emit(cost)

func continue_skill_activation_after_mana(_proxy: Card) -> void:
	if _proxy == null or _proxy.effect_source == null:
		return
	var src: Card = _proxy.effect_source
	var idx: int = _proxy.skill_activation_index
	if idx < 0 or not "skill" in src.card_effects:
		return
	var skills: Array = src.card_effects["skill"]
	if idx >= skills.size():
		return
	var def: Dictionary = skills[idx]
	var choose_target = def.get("choose_target", null)
	if choose_target:
		# The arc starts from the PROXY in the stack, not from the card on the field:
		# that is the object the player is actually resolving, and it is where the
		# arrow should appear to come from. The proxy carries the same controller, and
		# source_kind below is what the protection rules read, so targeting behaviour
		# is unchanged.
		request_target(choose_target, _proxy, true, "Ability")
	else:
		GlobalVariables.refresh_mode()
		assistant.generate_confirm_button(func(): stack.confirm_skill_without_target_then_priority())
	
func execute_card_effect(card,keyword):
	if( not card.is_key_word_in_card_effect(keyword)):
		return
	add_card_effect_to_stack.emit(card.id,keyword,card)
	# Most elegant single-line solution
	var choose_target_criteria = card.card_effects.get(keyword, {}).get('choose_target', null)
	
	# The effect RESOLVES as a card in the stack — Stack.create_card() makes that copy in
	# response to the signal above, synchronously, so it is already there. That copy is the
	# object the player is resolving, so the targeting arc must originate from IT and not
	# from the card sitting on the field.
	var stack_card: Card = _stack_effect_card_for(card)
	if choose_target_criteria:
		request_target(choose_target_criteria, stack_card if stack_card != null else card, false, "Ability")

## The stack's copy of the effect triggered by `source`, if it exists yet.
func _stack_effect_card_for(source: Card) -> Card:
	var game: Node = get_parent()
	if game == null:
		return null
	var s: Variant = game.get("stack")
	if s == null or s.cards == null:
		return null
	var found: Card = null
	for c in s.cards:
		if c.effect_source == source:
			found = c
	return found
func TEST_get_front_cards():
	return opponent_front_cards
func get_all_cards() -> Array[Card]:
	return front_cards + back_cards + opponent_front_cards + opponent_back_cards
func get_all_cards_from_player():
	return front_cards + back_cards

func get_front_cards_for(controller_name: String) -> Array[Card]:
	# Forwards of one side. Agents use this for attack / block decisions.
	return front_cards if controller_name == "player" else opponent_front_cards

func get_back_cards_for(controller_name: String) -> Array[Card]:
	# Backups of one side: the AI taps these to pay card costs.
	return back_cards if controller_name == "player" else opponent_back_cards

func untap_all_cards():
	for card in get_all_cards_from_player():
		card.untap()

func untap_cards_for(controller_name: String) -> void:
	# Active Phase untaps only the turn player's cards.
	var cards: Array[Card] = (front_cards + back_cards) if controller_name == "player" else (opponent_front_cards + opponent_back_cards)
	for card in cards:
		card.untap()
		
func request_target(targeting_criteria, card: Card, allow_cancel: bool = false, source_kind: String = ""):
	# Always start a targeting session fresh. Leftover target_card from a
	# previous session made set_target_card() ignore clicks (stuck UI).
	targeting_allow_cancel = allow_cancel
	target_card = null
	source_card = card
	if arrow:
		arrow.queue_free()
		arrow = null
	reset_targets()
	# The stack's review link draws the same arrow shape and paints the same aura, so it has to
	# let go of both before this session claims them.
	var stack_node = get_parent().get("stack")
	if stack_node != null:
		stack_node.release_target_display()
	print("[Targeting] request_target source=%s criteria=%s" % [card.card_name, targeting_criteria])
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.TARGET)
	set_viable_targets(targeting_criteria, card, source_kind)
	var ballistic_arrow = ballistic_arrow_scene.instantiate()
	arrow = ballistic_arrow
	add_child(ballistic_arrow)
	ballistic_arrow.set_is_aiming_from_card(true, card)
	if allow_cancel:
		assistant.prepare_targeting_phase_cancel()
	# A non-local owner resolves targeting through its agent instead of waiting
	# for clicks nobody will make (which would hang the turn).
	var owner_id: int = 1 if card.controller == "player" else 2
	var agent: Agent = get_parent().agent_for(owner_id)
	if agent != null and not (agent is LocalAgent):
		agent.choose_target(owner_id, card, targeting_criteria)

func set_target_card(card: Card):
	# A click only counts when the candidate is a legally valid target.
	# is_valid_target is set by set_viable_targets() (criteria + protection).
	if not card.is_valid_target:
		push_warning("[Targeting] %s is not a valid target" % card.card_name)
		return
	# Blue and orange are the LOCAL player's vocabulary: "legal" and "you picked this".
	# When the opponent is the one choosing, the picked card is shown in RED instead —
	# along with their arc, so an incoming effect is readable while it is on the stack.
	var local_chooser: bool = source_card == null or source_card.controller == "player"
	# Clicking another valid target MOVES the selection — and the ring with it — rather
	# than being ignored, so either player can change their mind.
	if target_card != null and is_instance_valid(target_card):
		target_card.set_selected_highlight(false)
		target_card.set_targeted_highlight(false)
	target_card = card
	if local_chooser:
		card.set_selected_highlight(true)
	else:
		card.set_targeted_highlight(true)
	print("[Targeting] target selected: ", card.card_name)
	arrow.lock_arc(card.get_global_face_centre())
	request_target_confirmation.emit(target_card, targeting_allow_cancel)
	
func set_viable_targets(target_criteria, source: Card = null, source_kind: String = ""):
	# The blue ring means "the game is asking YOU". When the OPPONENT is the one choosing,
	# their legal options are not our business. The flag still goes on — their agent selects
	# by it — but the glow stays off, so the only thing we see is the card they pick, which
	# set_target_card() marks red.
	var glow: bool = source == null or source.controller == "player"
	for card in get_all_cards():
		var is_targetable = _card_matches_criteria(card, target_criteria, source, source_kind)
		# A fresh session starts with nothing picked: clear any leftover ring.
		card.set_selected_highlight(false)
		card.set_targeted_highlight(false)
		# The prompt glow IS the indicator — no separate marker is spawned on top of
		# each candidate.
		card.set_valid_target(is_targetable, glow)

func has_viable_target(target_criteria, source: Card = null, source_kind: String = "") -> bool:
	# Used before casting a Summon: a targeted Summon cannot be cast unless
	# at least one legal target exists on the field.
	for card in get_all_cards():
		if _card_matches_criteria(card, target_criteria, source, source_kind):
			return true
	return false

func _card_matches_criteria(card: Card, target_criteria: Dictionary, source: Card = null, source_kind: String = "") -> bool:
	# Legality has two parts: the effect's choose_target criteria (properties of
	# the candidate) and the candidate's own protection against this source.
	# source_kind overrides the source card's own kind, because ability targeting
	# is requested with the field card, which carries no effect_kind.
	if not card.matches_criteria(target_criteria):
		return false
	return card.can_be_chosen_by(source, source_kind)
		
func reset_targets():
	# Every meaning a targeting session can leave behind: the blue prompt, the ORANGE pick, and
	# the opponent's red reveal. The orange is the one that leaked — it was set on the click and
	# only ever cleared by the *next* session starting, so an ability that resolved and was not
	# followed by another targeting left its target glowing orange for the rest of the match.
	for card in get_all_cards():
		# Through the setter, so the "targetable" glow clears with the flag.
		card.set_valid_target(false)
		card.set_selected_highlight(false)
		# ...and the opponent's red ring with it.
		card.set_targeted_highlight(false)

## Drop only the red "the opponent chose this" rings, leaving the selection state alone.
## Called when the stack has fully resolved — the reveal is spent — rather than never, which
## would leave the ring to outlive the effect.
func clear_targeted_highlights() -> void:
	for card in get_all_cards():
		card.set_targeted_highlight(false)

func remove_card(card):
	unregister_conditional_effects(card)
	front_cards.erase(card)
	back_cards.erase(card)
	opponent_front_cards.erase(card)
	opponent_back_cards.erase(card)
	recompute_conditional_power()

## Conditional continuous effects ("if you control X, this gains power").
## Re-evaluated only when the field composition changes: play_card/remove_card.
var _conditional_effects: Array[Dictionary] = []

func register_conditional_effects(card: Card) -> void:
	if "conditional_power" in card.card_effects:
		for effect in card.card_effects["conditional_power"]:
			_conditional_effects.append({
				"source": card,
				"condition": effect.get("condition", {}),
				"value": int(effect.get("value", 0)),
			})

func unregister_conditional_effects(card: Card) -> void:
	_conditional_effects = _conditional_effects.filter(func(e): return e["source"] != card)
	if card.current_conditional_bonus != 0:
		card.power -= card.current_conditional_bonus
		card.current_conditional_bonus = 0
		if card.power_label:
			card.power_label.changePower(card.power)

func recompute_conditional_power() -> void:
	for effect in _conditional_effects:
		var source: Card = effect["source"]
		if source == null or not is_instance_valid(source) or not source.is_inside_tree():
			continue
		var desired: int = int(effect["value"]) if _condition_met(effect["condition"]) else 0
		if desired != source.current_conditional_bonus:
			source.power += desired - source.current_conditional_bonus
			source.current_conditional_bonus = desired
			if source.power_label:
				source.power_label.changePower(source.power)

func _condition_met(condition: Dictionary) -> bool:
	if condition.is_empty():
		return false
	for card in get_all_cards():
		if card.matches_criteria(condition):
			return true
	return false
	
func get_breakable_cards():
	# Forwards whose accumulated damage is equal to or greater than their
	# current power. A card at 0 power is handled separately (it is put into
	# the Graveyard, not broken).
	var ans = []
	for card in (front_cards + opponent_front_cards):
		if card.has_zero_power():
			continue
		if card.is_broken():
			ans.append(card)
	return ans

func get_zero_power_cards():
	# Forwards whose current power is 0 or less. These are put into the
	# Graveyard without triggering break effects.
	var ans = []
	for card in (front_cards + opponent_front_cards):
		if card.has_zero_power():
			ans.append(card)
	return ans

func _tap_selected_cards():
	for c in selected_cards_for_mana_conversion:
		c.tap()
		
func set_attacker(card:Card):
	if(attacker_card == null):
		attacker_card = card
		attacker_card.set_attacker_status(true)
	elif(attacker_card == card):
		attacker_card.set_attacker_status(false)
		attacker_card = null
	elif(attacker_card != card):
		attacker_card.set_attacker_status(false)
		attacker_card = card
		attacker_card.set_attacker_status(true)
	attacker_changed.emit()
func reset_attacker():
	attacker_card = null

## Select/deselect a blocker for the current combat (human input only).
## Game.set_blocker() is what *declares* it (via the set_blocker instruction).
func set_blocker_card(card: Card) -> void:
	if card == null or card.controller != "player" or not card.can_attack():
		return
	if blocker_card == card:
		card.set_blocker_status(false)
		card.set_selected_highlight(false)
		blocker_card = null
		hide_block_arc()
	else:
		if blocker_card != null and is_instance_valid(blocker_card):
			blocker_card.set_blocker_status(false)
			blocker_card.set_selected_highlight(false)
		blocker_card = card
		card.set_blocker_status(true)
		# Same vocabulary as targeting: blue = legal, orange = the one you picked. So a
		# reselect before committing simply moves the orange and the arc.
		card.set_selected_highlight(true)
		show_block_arc(card)
	blocker_changed.emit()

## Mark every card that could legally block for `controller` with the prompt glow.
##
## Only ever called for the LOCAL defender: the ring means "the game is asking YOU to
## choose". An opponent's declaration shows the arc alone, because that cue is not a
## question addressed to the human.
func set_blockable(controller: String, enabled: bool) -> void:
	for card in get_all_cards():
		if card.controller != controller:
			continue
		card.set_valid_target(enabled and can_block(card))

## The block predicate: an untapped Forward. Deliberately the same rule the click gate
## applies in field_card_state.gd, so everything that glows is also clickable.
func can_block(card: Card) -> bool:
	return card != null and card.can_attack()

## The review link: the arc that shows what a card IN THE STACK was pointed at, re-drawn on
## demand as the player moves over the stack (see Stack.refresh_target_display).
##
## It is drawn by the FIELD, not by the stack, because `BallisticArrow` treats the points it is
## handed as LOCAL coordinates. The stack node is flipped and sits above the board, so an arrow
## parented to it and given global points lands wherever that transform carries it — which is
## exactly what "arrows in random places" was. The Field's frame is identity, as it is for the
## other two arrows, so global points are correct here.
var review_arrow: BallisticArrow = null

func show_review_link(source: Card, target: Card) -> void:
	if source == null or target == null:
		hide_review_link()
		return
	if not is_instance_valid(source) or not is_instance_valid(target):
		hide_review_link()
		return
	if review_arrow == null or not is_instance_valid(review_arrow):
		review_arrow = ballistic_arrow_scene.instantiate()
		add_child(review_arrow)
	# Same convention as the live targeting arrow — from the source's top edge to the target's
	# centre — so a link being reviewed looks exactly like the one that was drawn.
	review_arrow.set_is_aiming(true, source.get_global_top_centre())
	review_arrow.lock_arc(target.get_global_face_centre())

func hide_review_link() -> void:
	if review_arrow != null and is_instance_valid(review_arrow):
		review_arrow.set_is_aiming(false)

## The link from the blocker to the attacker, drawn CENTRE to CENTRE.
##
## Static by design: both cards are already on the field and neither moves while the
## declaration is open, so this aims once and locks. That is the opposite of the targeting
## arrow, which follows the mouse and a card that may still be tweening into the stack.
func show_block_arc(blocker: Card) -> void:
	if blocker == null or attacker_card == null:
		hide_block_arc()
		return
	if block_arrow == null or not is_instance_valid(block_arrow):
		block_arrow = ballistic_arrow_scene.instantiate()
		add_child(block_arrow)
		# Adjacent cards are the common case for a block, and the default floor exists to
		# stop a dot being drawn for a near-zero targeting drag.
		block_arrow.min_distance = 0.15
		# A block joins the two battle rows, so its chord runs up the screen. Bowing along
		# screen-up would put the arch along the chord (a 1.54 m path for an 0.85 m span);
		# perpendicular instead makes it a sideways link. Kept shallow — this is a link
		# between two cards, not a shot.
		block_arrow.bow_perpendicular = true
		block_arrow.peak_ratio = 0.22
	block_arrow.set_is_aiming(true, blocker.get_global_face_centre())
	block_arrow.lock_arc(attacker_card.get_global_face_centre())

func hide_block_arc() -> void:
	if block_arrow != null and is_instance_valid(block_arrow):
		block_arrow.set_is_aiming(false)

func reset_blocker():
	# The blocker may have broken in the clash, so only clear the marker while it
	# is still a card on the field.
	if blocker_card != null and is_instance_valid(blocker_card):
		if blocker_card.is_on_field():
			blocker_card.set_blocker_status(false)
		blocker_card.set_selected_highlight(false)
	blocker_card = null
	hide_block_arc()
func _on_assistant_charge_cancelled() -> void:
	for c in selected_cards_for_mana_conversion:
		c.reset()
	selected_cards_for_mana_conversion = []


func _on_assistant_charge_complete() -> void:
	if stack.skill_mana_deferred_until_target_confirm or stack.summon_mana_deferred_until_target_confirm:
		return
	for c in selected_cards_for_mana_conversion:
		c.reset()
	_tap_selected_cards()
	selected_cards_for_mana_conversion = []

func apply_deferred_skill_mana_payment() -> void:
	for c in selected_cards_for_mana_conversion:
		c.reset()
	_tap_selected_cards()
	selected_cards_for_mana_conversion = []


func _on_assistant_target_cancel() -> void:
	if stack.skill_mana_deferred_until_target_confirm or stack.summon_mana_deferred_until_target_confirm:
		for c in selected_cards_for_mana_conversion:
			c.reset()
		selected_cards_for_mana_conversion.clear()
	targeting_allow_cancel = false
	target_card = null
	source_card = null
	if arrow:
		arrow.queue_free()
		arrow = null
	reset_targets()
	# NOTE: the TARGET modal is popped by Assistant.on_target_cancel() /
	# on_target_complete(), which owns the modal it opened. Don't pop here too.


func _on_stack_execute_card_effect(card: Card) -> void:
	# Targeting session is over: clear all targeting state so the next
	# session starts fresh.
	if arrow:
		arrow.queue_free()
		arrow = null
	target_card = null
	source_card = null
	targeting_allow_cancel = false
	reset_targets()
