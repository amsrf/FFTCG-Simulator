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
## The Game this side belongs to. Untyped on purpose: game.gd has no class_name (adding one would break headless
## runs until the editor rescans), and a direct, named call is discoverable — `grep run_ex_burst` finds it — whereas
## `call("run_ex_burst", ...)` hides the dependency from every tool.
@onready var game = get_parent()

## `source` is the card that CAUSED this damage (the attacker). It is optional because debug keys and some effects
## damage a player directly; Exdeath 122 needs it, so the player-damage paths pass it through.
func take_damage(amount: int = 1, source: Card = null) -> void:
	for _i in range(amount):
		if deck.deck_cards.is_empty():
			# Nothing left in the deck to absorb the damage: report it anyway so
			# the game can react (running out of deck is fatal).
			damaged.emit(self)
			return
		var card = deck.deck_cards.pop_front()
		damage_zone.draw(card)
		_run_ex_burst(card, source)
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
	if card == null:
		return ""
	return card.ex_burst_event()

func has_ex_burst(card: Card) -> bool:
	return not ex_burst_key(card).is_empty()

func _run_ex_burst(card: Card, source: Card = null) -> void:
	var keyword: String = ex_burst_key(card)
	if keyword.is_empty() or not is_inside_tree():
		return
	# EXDEATH 122: "Any card put in the Damage Zone due to Exdeath cannot use its EX Burst."
	# Checked against the SOURCE of the damage, not globally: another attacker's damage still bursts normally.
	if source != null and is_instance_valid(source) \
			and (source.card_effects.has("ex_burst_disabler") or source.status_effects.has("ex_burst_disabler")):
		print("[ExBurst] suppressed for %s (damage dealt by %s)" % [card.card_name, source.card_name])
		return
	if game == null or not game.has_method("run_ex_burst"):
		return
	await get_tree().create_timer(EX_BURST_DELAY).timeout
	game.run_ex_burst(self, card, keyword)

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
