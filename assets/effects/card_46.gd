extends "res://scripts/effects/card_effect.gd"
## Terra 1-046H: opponent's Summons cost 1 more.


func modify_cost_for(ctx, subject: Card, cost: Dictionary) -> Dictionary:
	if ctx.source == null or subject.controller == ctx.source.controller:
		return cost
	if subject.type != "Summon":
		return cost
	return ctx.adjust(cost, 1)
