extends "res://scripts/effects/card_effect.gd"
## Yuna 1-177R: your Water Summons cost 1 less, but never below 1.


func modify_cost_for(ctx, subject: Card, cost: Dictionary) -> Dictionary:
	if ctx.source == null or subject.controller != ctx.source.controller:
		return cost
	if subject.type != "Summon" or not subject.is_element("水"):
		return cost
	return ctx.adjust(cost, -1, 1)
