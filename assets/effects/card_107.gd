extends "res://scripts/effects/card_effect.gd"
## Shantotto 1-107L
##
## "If Shantotto is on the field, it gains Elements of Fire, Ice, Wind, Earth, Lightning and Water."
## "When Shantotto enters the field, remove all the Forwards from the game."
##
## The element grant is a continuous query. The removal is a triggered auto-ability, so it goes through the stack via
## Field.execute_card_effect and this hook runs only when that stack object resolves.

const SIX_ELEMENTS: Array[String] = ["火", "氷", "風", "土", "雷", "水"]


func current_elements(ctx, card) -> Array[String]:
	var out: Array[String] = []
	if card.element != "":
		out.append(card.element)
	for element in SIX_ELEMENTS:
		if not out.has(element):
			out.append(element)
	return out


func when_enter_field(ctx) -> void:
	ctx.remove_from_game(ctx.cards_in("field", {"is_type": "Forward"}))
