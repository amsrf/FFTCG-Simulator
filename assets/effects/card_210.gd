extends "res://scripts/effects/card_effect.gd"
## Lightning 1-210R: costs 1 less for each other Category XIII Forward you control.


func modify_cost(ctx, _card: Card, cost: Dictionary) -> Dictionary:
	var count: int = ctx.cards_in_field(
		{"is_category": "XIII", "is_type": "Forward", "controller": "your"}, true).size()
	return ctx.adjust(cost, -count)


func keywords() -> Array[String]:
	return ["haste"]
