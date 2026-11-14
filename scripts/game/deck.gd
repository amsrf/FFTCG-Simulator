extends Node3D
## The deck pile. The node is turned over (pi about X in game.tscn), so the cards lie face down and local +Y points
## DOWN in the world.
##
## The node's origin is the BOTTOM of the pile: it rests on the felt of a deck-station well
## (Blender/build_deck_stations.py), so the pile grows up out of the well rather than hanging down from a point
## in the air. deck_cards[0] is the top card; drawing pops it without a re-layout, so the rest stay put and the
## pile simply gets one card lower.
## Per-card rise (local; x1.4 in world = 2.5 mm): a 50-card deck is 0.126 m, which stays below the wood.
var card_offset = Vector3(0, 0.0018, 0)
var randomness_range = Vector3(0.008, 0.0018, 0.008)
@export var deck_cards = []

func add_cards(cards: Array):
	for card in cards:
		deck_cards.append(card)
		add_child(card)
		# The pile size lives in Card.ZONE_PRESENTATION. Without this a freshly built deck kept scale 1.0 inside this
		# 1.4 node and was drawn at 1.4 in world, bigger than its well and every other pile.
		if card.has_method("enter_zone"):
			card.enter_zone(Card.Zone.DECK)
	update_card_positions()


func update_card_positions():
	var count: int = deck_cards.size()
	var rng := RandomNumberGenerator.new()
	for i in range(count):
		var card: Node3D = deck_cards[i]
		# Scatter keyed to the card, not to a live RNG or its index, so a re-layout (a card put on the bottom) lifts
		# the pile without making every card jump sideways.
		rng.seed = card.get_instance_id()
		var random_offset = Vector3(
			rng.randf_range(-randomness_range.x, randomness_range.x),
			0,
			rng.randf_range(-randomness_range.z, randomness_range.z)
		)
		# ABSOLUTE, never `+=`. Local -Y is world UP: the bottom card (last) sits on the origin.
		card.position = -card_offset * (count - 1 - i) + random_offset
