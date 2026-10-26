extends "res://scripts/effects/card_effect.gd"
## Alma 1-153R: this card costs 1 less while you control Ovelia.


func modify_cost(ctx, _card: Card, cost: Dictionary) -> Dictionary:
	if ctx.controls({"is_named": "Ovelia"}):
		return ctx.adjust(cost, -1)
	return cost
