extends Node3D
class_name Hand
# The list of cards in the hand

const CARD_CHARGE = 2

var cards = []
@export var selected_cards_for_mana_conversion: Array[Card] = []
## "Choose a card in hand" state (triggered "may" abilities such as Auron).
var choose_card_criteria: Dictionary = {}
var selected_card_for_effect: Card = null
var card_width = GlobalVariables.get_card_width();
var card_spacing = GlobalVariables.get_card_spacing();
var charging_card
var start_x;
var grabbed_card_index = 0;
signal charge_start(card:Card)
signal selected_cards_for_mana_has_changed(amount:int, element:String)
signal effect_card_selection_changed(has_selection: bool)
@onready var graveyard: Node = get_parent().get_node("Graveyard")
@onready var stack: Stack = get_tree().current_scene.get_node("Stack") as Stack
@onready var field: Field = get_tree().current_scene.get_node("Field") as Field

func draw(card):
	add_card_to_tree(card)
	update_card_positions(cards.size() - 1)
	
	var tween = create_tween()
	var path = $Path3D
	var path_follow = $Path3D/PathFollow3D
	var curve = Curve3D.new()
	var target_position = calculate_card_position(cards.size() - 1)
	
	# Add points to the curve
	curve.add_point(card.position)  # Start point
	curve.add_point(card.position + Vector3(0, 0, -0.1))
	curve.add_point(Vector3(0, card.position.y / 2, -1))  # Mid point
	curve.add_point(Vector3(target_position.x + 1.2, 0, -0.9))
	curve.add_point(Vector3(target_position))
	curve.bake_interval = 50
	path.curve = curve
	
	# Reset PathFollow3D progress
	path_follow.progress_ratio = 0
	
	# Configure PathFollow3D
	path_follow.rotation_mode = PathFollow3D.ROTATION_NONE
	
	# Reparent the card to PathFollow3D for the animation
	card.reparent(path_follow)
	
	# Animate the card along the path
	tween.tween_property(path_follow, "progress_ratio", 1.0, 1.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(card, "scale", Vector3(1, 1, 1), 1.3)
	tween.parallel().tween_property(card, "rotation_degrees", Vector3.ZERO, 0.7)
	
	# Reparent the card back to its original parent after the animation
	tween.tween_callback(card.reparent.bind(self))
	tween.tween_callback(path_follow.set.bind("progress_ratio", 0))  # Reset PathFollow3D progress

func add_card_to_tree(card):
	cards.append(card)
	card.index = cards.size()-1
	var area = card.get_node("CardArea3D")
	if area.has_signal("card_released") and not area.card_released.is_connected(Callable(self, "_on_card_released")):
		area.connect("card_released", Callable(self, "_on_card_released"))
	if card.has_signal("card_dragged") and not card.card_dragged.is_connected(Callable(self, "_on_card_dragged")):
		card.connect("card_dragged", Callable(self, "_on_card_dragged"))
	# Store the card's global transform before reparenting
	
	# Reparent the card to the Hand
	var trans = card.global_transform
	if card.get_parent():
		card.reparent(self,false)
	else:
		add_child(card)
	card.global_transform = trans
	
	
func add_card(card):
	add_card_to_tree(card)
	update_card_positions()


func calculate_total_width():
	return (cards.size() * card_width) + ((cards.size() - 1) * card_spacing)

# Function to update the positions of the cards in the hand
func update_card_positions(ignore = -1):
	var total_width = calculate_total_width()
	start_x = -total_width / 2 + card_width / 2

	for i in range(cards.size()):
		if(i == ignore):
			continue
		var card = cards[i]
		if(card.is_dragging):
			continue
		card.index = i
		card.rotation = Vector3.ZERO
		animate_card(card, calculate_card_position(i)) # Position relative to the Hand
		
		
func last_card_position():
	return start_x + (card_width + card_spacing)*cards.size()
	
	
func calculate_card_position(i):
	var x_offset = start_x + i * (card_width + card_spacing)
	var y_offset = (i)*0.001
	return Vector3(x_offset, y_offset, 0)
	
	
func find_index(card):
	var total_width = calculate_total_width()
	var card_zone_width = total_width/cards.size()
	var index : int = floor((card.position.x + (total_width / 2))/card_zone_width)
	if(index <= 0):
		return 0
	if(index >= cards.size() -1):
		return cards.size() -1 
	return index

func move_element(arr: Array, from_index: int, to_index: int) -> Array:
	if from_index < 0 or from_index >= arr.size() or to_index < 0 or to_index >= arr.size():
		return arr
	var element = arr.pop_at(from_index)
	arr.insert(to_index, element)
	return arr
	
func _on_card_dragged(card: Variant) -> void:
	var new_index = find_index(card)
	if(card.index != new_index):
		move_element(cards,card.index,new_index)
		update_card_positions()
		card.index = new_index
	
func remove_card(card):
	cards.remove_at(card.index)
	
						
func charge(card):
	if card.type == 'Summon':
		# Summons cannot be cast unless a legal target exists (when the card
		# requires one). The card leaves the hand and is parked on the stack
		# visually, but it only legally enters the stack after the cost is
		# paid and the target is confirmed.
		var criteria: Dictionary = card.get_cast_target_criteria()
		if not criteria.is_empty() and not field.has_viable_target(criteria, card, "Summon"):
			push_error("No viable target for %s" % card.card_name)
			return
		remove_card(card)
		charging_card = card
		charge_start.emit(card)
		return
	remove_card(card)
	charge_start.emit(card)
	charging_card = card #keep reference

func finish_summon_cast(card: Card) -> void:
	# The summon left the hand when the cast began and has been parked on
	# the stack; committing it only clears the hand reference.
	if charging_card == card:
		charging_card = null

func cancel_summon_cast() -> void:
	# Return the parked summon to the hand. Nothing was paid or tapped.
	if charging_card != null and charging_card.get_parent() == stack:
		add_card(charging_card)
	charging_card = null

func has_card_matching_criteria(criteria: Dictionary) -> bool:
	for card in cards:
		if card.matches_criteria(criteria):
			return true
	return false

func begin_choose_card(criteria: Dictionary) -> void:
	clear_effect_card_selection()
	choose_card_criteria = criteria
	selected_card_for_effect = null

func end_choose_card() -> void:
	clear_effect_card_selection()
	choose_card_criteria = {}
	selected_card_for_effect = null

func clear_effect_card_selection() -> void:
	if selected_card_for_effect != null and selected_card_for_effect.crystal_instance != null:
		selected_card_for_effect.crystal_instance.queue_free()
		selected_card_for_effect.crystal_instance = null

func toggle_effect_card_selection(card: Card) -> void:
	# Single selection: picking another card unselects the previous one.
	if selected_card_for_effect == card:
		clear_effect_card_selection()
		selected_card_for_effect = null
	else:
		clear_effect_card_selection()
		selected_card_for_effect = card
		if card.crystal_scene != null:
			card.crystal_instance = card.crystal_scene.instantiate()
			card.add_child(card.crystal_instance)
			card.crystal_instance.position = Vector3(0, 0.05, -0.35)
	effect_card_selection_changed.emit(selected_card_for_effect != null)

func remove_card_for_free_play(card: Card) -> void:
	# Used by "may play for free" resolution: the chosen card leaves the hand.
	cards.erase(card)
	update_card_positions()

func discard_card(card: Card) -> void:
	# Special ability (S) cost: the chosen card goes from hand to the break zone.
	cards.erase(card)
	graveyard.add_card(card)
	update_card_positions()
	
func send_selected_cards_to_graveyard():
	cards = cards.filter(func(item): return not selected_cards_for_mana_conversion.has(item))
	for c in selected_cards_for_mana_conversion:
		c.reset()
		graveyard.add_card(c)
	selected_cards_for_mana_conversion = []
	

func add_card_to_mana_conversion(card:Card):
	# A card being cast (e.g. a Summon awaiting payment) cannot be used as
	# its own mana payment.
	if card == charging_card:
		return
	if  not selected_cards_for_mana_conversion.has(card):
		selected_cards_for_mana_conversion.push_back(card)
	# Owns the marker, so an agent paying a cost gets the same feedback as a click.
	card.show_mana_crystal()
	selected_cards_for_mana_has_changed.emit(2,card.element)
	
func remove_card_from_mana_conversion(card:Card):
	if selected_cards_for_mana_conversion.has(card):
		selected_cards_for_mana_conversion.erase(card)
	card.clear_mana_crystal()
	selected_cards_for_mana_has_changed.emit(-2,card.element)
			
func animate_card(card, target_position):
	# Create a Tween to animate the card's movement
	var tween = create_tween()
	tween.set_parallel(true) 
	tween.tween_property(card, "position", target_position, 0.15)
	tween.tween_property(card, "scale", Vector3.ONE, 0.15)


func _on_assistant_charge_complete() -> void:
	if stack.skill_mana_deferred_until_target_confirm or stack.summon_mana_deferred_until_target_confirm:
		return
	send_selected_cards_to_graveyard()
	selected_cards_for_mana_conversion = []
	# A summon being cast stays referenced until targeting is resolved.
	if stack.summon_casting_card == null:
		charging_card = null
	update_card_positions()

func apply_deferred_skill_mana_payment() -> void:
	send_selected_cards_to_graveyard()
	update_card_positions()

func _on_assistant_target_cancel() -> void:
	for c in selected_cards_for_mana_conversion:
		c.reset()
	selected_cards_for_mana_conversion.clear()


func _on_assistant_charge_cancelled() -> void:
	for c in selected_cards_for_mana_conversion:
		c.reset()
	selected_cards_for_mana_conversion = []
	if charging_card and charging_card.get_parent() == stack:
		add_card(charging_card)
	charging_card = null
