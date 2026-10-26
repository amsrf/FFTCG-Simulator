extends "res://scripts/effects/card_effect.gd"
## Fang 1-020R: your Bahamut Summons cost 2 less.


func modify_cost_for(ctx, subject: Card, cost: Dictionary) -> Dictionary:
	if ctx.source == null or subject.controller != ctx.source.controller:
		return cost
	if subject.type != "Summon" or subject.card_name != "Bahamut":
		return cost
	return ctx.adjust(cost, -2)
