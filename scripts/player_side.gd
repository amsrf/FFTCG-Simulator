extends Node3D
class_name PlayerSide

@export var controller: String = "player" # "player" or "opponent"

## A player loses once their damage zone holds this many cards (FF TCG: 7).
const DEFEAT_DAMAGE := 7

## Emitted after this side's damage zone changes. Carries the side itself so the
## game can tell which player was hit — and listening to it means a loss is
## caught without every damage source having to remember to check.
signal damaged(side: PlayerSide)

@onready var deck: Node = $Deck
@onready var hand: Hand = $Hand
@onready var damage_zone: DamageZone = $DamageZone
@onready var graveyard: Node = $Graveyard

func take_damage(amount: int = 1) -> void:
	for _i in range(amount):
		if deck.deck_cards.is_empty():
			# Nothing left in the deck to absorb the damage: report it anyway so
			# the game can react (running out of deck is fatal).
			damaged.emit(self)
			return
		var card = deck.deck_cards.pop_front()
		damage_zone.draw(card)
	damaged.emit(self)

func damage_count() -> int:
	return damage_zone.cards.size()

func is_defeated() -> bool:
	return damage_count() >= DEFEAT_DAMAGE

func may_play_for_free(card: Card) -> void:
	# "You may play ... from your hand onto the field dull" resolution.
	if card == null or card.get_parent() != hand:
		return
	hand.remove_card_for_free_play(card)
	var field: Field = get_parent().get_node("Field") as Field
	field.play_card(card, false, true)
	card.tap()
