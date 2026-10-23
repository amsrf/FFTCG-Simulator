extends Node3D
## The Graveyard / Break Zone pile.
##
## It is a STACK: the most recent card lies on top of the pile and the older ones
## are tucked underneath. Every card in it is presented as a plain, untilted card
## with no field readout, which is what Card.enter_zone() guarantees — without it
## a card arriving from the field keeps the field's scale, its rotation and its
## power/accumulated-damage readout.
var card_offset = Vector3(0, 0.005, 0)
var randomness_range = Vector3(0.015, 0.005, 0.015)
@export var graveyard_cards = []
## Which zone a card is in once it lands here. The Break Zone and "removed from the game" are the same KIND of pile
## but not the same place, and the difference matters: a card removed from the game must not be findable by anything
## that looks in the Break Zone. Defaults to GRAVEYARD so the existing nodes keep working untouched.
@export var zone: Card.Zone = Card.Zone.GRAVEYARD
		
func add_card(card):
	graveyard_cards.append(card)
	card.reparent(self, false)
	# Normalise the look BEFORE placing it. (The old version only set position,
	# so the card kept whatever it was wearing in the zone it came from.)
	card.enter_zone(zone)
	update_card_positions()

## Lay the pile out, newest on top.
##
## Positions are ABSOLUTE: the old version did `position += ...`, so every extra
## call drifted the pile further away. The scatter is derived from the card's
## index instead of a live RNG, so re-laying out (which happens whenever a card is
## added) cannot make the whole pile jitter — and the top card is kept un-scattered
## so the pile always reads as sitting on its anchor.
func update_card_positions():
	var rng := RandomNumberGenerator.new()
	for i in range(graveyard_cards.size()):
		var card = graveyard_cards[i]
		var is_top: bool = i == graveyard_cards.size() - 1
		var scatter := Vector3.ZERO
		if not is_top:
			rng.seed = i * 7919
			scatter = Vector3(
				rng.randf_range(-randomness_range.x, randomness_range.x),
				0.0,
				rng.randf_range(-randomness_range.z, randomness_range.z)
			)
		card.position = card_offset * i + scatter
