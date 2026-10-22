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
		_run_ex_burst(card)
	damaged.emit(self)


## EX BURST. When a card becomes damage and it carries an `ex_burst` key, the effect named by that key runs
## IMMEDIATELY — no stack object and no priority round, so nobody gets to respond to it. The separate key exists
## because a card can have both a cast effect and a damage-zone one, and only the data knows which is which:
##
##     "4": { "ex_burst": "when_cast", "when_cast": { "choose_target": ..., "instructions": [...] } }
##
## The wait is for the damage zoom: "after the camera goes back" is when the player is meant to act on it.
const EX_BURST_DELAY := 2.0

func ex_burst_key(card: Card) -> String:
	if card == null or not card.card_effects.has("ex_burst"):
		return ""
	return str(card.card_effects["ex_burst"])

func has_ex_burst(card: Card) -> bool:
	return not ex_burst_key(card).is_empty()

func _run_ex_burst(card: Card) -> void:
	var keyword: String = ex_burst_key(card)
	if keyword.is_empty() or not is_inside_tree():
		return
	var game: Node = get_parent()
	if game == null or not game.has_method("run_ex_burst"):
		return
	await get_tree().create_timer(EX_BURST_DELAY).timeout
	game.call("run_ex_burst", self, card, keyword)

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
