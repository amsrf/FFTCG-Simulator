extends Node3D
class_name PlayerSide

@export var controller: String = "player" # "player" or "opponent"

@onready var deck: Node = $Deck
@onready var hand: Hand = $Hand
@onready var damage_zone: DamageZone = $DamageZone
@onready var graveyard: Node = $Graveyard

func take_damage(amount: int = 1) -> void:
	for _i in range(amount):
		if deck.deck_cards.is_empty():
			return
		var card = deck.deck_cards.pop_front()
		damage_zone.draw(card)

func may_play_for_free(card: Card) -> void:
	# "You may play ... from your hand onto the field dull" resolution.
	if card == null or card.get_parent() != hand:
		return
	hand.remove_card_for_free_play(card)
	var field: Field = get_parent().get_node("Field") as Field
	field.play_card(card, false, true)
	card.tap()
