extends "res://scripts/effects/card_effect.gd"
## Tidus 1-213R: costs 1 less for each other Category X Forward you control.


func modify_cost(ctx, _card: Card, cost: Dictionary) -> Dictionary:
	var count: int = ctx.cards_in_field(
		{"is_category": "X", "is_type": "Forward", "controller": "your"}, true).size()
	return ctx.adjust(cost, -count)
