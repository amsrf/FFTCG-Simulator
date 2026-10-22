extends Node3D
class_name DamageZone
# The list of cards in the hand

const CARD_CHARGE = 2

var cards = []
var deck: Node = null
var card_width = GlobalVariables.get_card_width();
var card_spacing = -0.3
var start_x;
var grabbed_card_index = 0;
# Relative on purpose. `get_tree().current_scene` is only set to the game when the game IS
# the top-level scene, so it silently yields null for anything that instantiates it
# elsewhere (the headless probe, a future self-play or preview). Walking the tree works
# wherever the scene is mounted.
@onready var field: Field = get_node("../../Field")
@onready var assistant: Assistant = get_node("../../Assistant")

func set_deck(deck_node: Node) -> void:
	deck = deck_node

## How far above its slot a damage card starts its fall, in metres, and how long the fall takes. See draw().
const DROP_HEIGHT := 0.9
const DROP_SECONDS := 0.35

func draw(card):
	add_card_to_tree(card)
	update_card_positions(cards.size() - 1)

	# THE DROP. A card entering the damage zone falls onto it from above — no arc, and nothing that passes below
	# the board. The old path travelled through y = 0 to get from the deck to the slot; damage cards are drawn at
	# 1.2x and the zone sits at y = 0.1, so the middle of that move was visibly UNDER the board and the card
	# appeared to climb back out at the end.
	var target_position: Vector3 = calculate_card_position(cards.size() - 1)
	card.position = target_position + Vector3.UP * DROP_HEIGHT

	var tween = create_tween()
	# EASE_IN because a fall ACCELERATES: slow at the release, quickest at the landing.
	tween.tween_property(card, "position", target_position, DROP_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# The damage card's resting size, reached on the way down.
	tween.parallel().tween_property(card, "scale", Vector3(1.2, 1.2, 1.2), DROP_SECONDS)

func add_card_to_tree(card):
	cards.append(card)
	card.index = cards.size()-1
	var trans = card.global_transform
	if card.get_parent():
		card.reparent(self,false)
	else:
		add_child(card)
	card.global_transform = trans
	
	
func add_card(card):
	# Damage-zone cards are laid flat and must not show the field readout.
	card.enter_zone(Card.Zone.DAMAGE)
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
	# start_x is only set by update_card_positions(), so before this zone has ever laid a card out it is null
	# and the arithmetic below fails with "Invalid operands 'Nil' and 'float'". The damage zoom asks for a slot
	# position to aim a camera at, and it can legitimately ask before the first card lands — so the fallback is
	# the row's own centre, which is where a single card would sit anyway. Without this, aiming at an empty
	# zone is a crash rather than a miss.
	var base: float = 0.0
	if start_x != null:
		base = float(start_x)
	elif card_width != null:
		base = -float(card_width) * 0.5
	var x_offset = base + i * (card_width + card_spacing)
	var y_offset = (i)*0.001
	return Vector3(x_offset, y_offset, 0)
	
func remove_card(card):
	cards.remove_at(card.index)
	

		
func animate_card(card, target_position):
	# Create a Tween to animate the card's movement
	var tween = create_tween()
	tween.tween_property(card, "position", target_position, 0.15)
