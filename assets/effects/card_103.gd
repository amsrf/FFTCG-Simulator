extends "res://scripts/effects/card_effect.gd"
## Kimahri 1-103C
##
## "Kimahri gains Elements of all the Characters opponent controls except Light and Dark."
##
## A CONTINUOUS QUERY, not an event: it is evaluated every time someone asks what Elements Kimahri currently has.

func current_elements(ctx, card) -> Array[String]:
	var out: Array[String] = []
	if card.element != "":
		out.append(card.element)
	for other in ctx.cards_in("field", {"is_character": true, "controller": "opponent"}):
		for element in other.current_elements():
			if element == "光" or element == "闇":
				continue
			if not out.has(element):
				out.append(element)
	return out
