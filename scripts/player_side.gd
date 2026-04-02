extends Node3D
class_name PlayerSide

@export var controller: String = "player" # "player" or "opponent"

@onready var deck: Node = $Deck
@onready var hand: Node = $Hand
@onready var damage_zone: DamageZone = $DamageZone
@onready var graveyard: Node = $Graveyard

func take_damage(amount: int = 1) -> void:
	for _i in range(amount):
		if deck.deck_cards.is_empty():
			return
		var card = deck.deck_cards.pop_front()
		damage_zone.draw(card)
