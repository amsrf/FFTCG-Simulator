extends Node3D
class_name DamageZones

@onready var damage_zone: DamageZone = $DamageZone
@onready var opponent_damage_zone: DamageZone = $OpponentDamageZone
@onready var deck: Node = get_parent().get_node("Deck")
@onready var opponent_deck: Node = get_parent().get_node("OpponentDeck")

func _ready() -> void:
	# Provide the correct deck reference so later effects can “draw into damage zone”
	# using the stored source deck.
	if damage_zone:
		damage_zone.set_deck(deck)
	if opponent_damage_zone:
		opponent_damage_zone.set_deck(opponent_deck)

func add_card(card: Card) -> void:
	# Route cards into the correct player's damage zone.
	if card.controller == "player":
		damage_zone.draw(card)
	else:
		opponent_damage_zone.draw(card)
