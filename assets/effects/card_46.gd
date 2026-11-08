extends "res://scripts/effects/card_effect.gd"
## Terra 1-046H: opponent's Summons cost 1 more.


func modify_cost_for(ctx: COST_CONTEXT, subject: Card, cost: Dictionary) -> Dictionary:
	if ctx.source == null or subject.controller == ctx.source.controller:
		return cost
	if subject.type != Card.SUMMON:
		return cost
	return ctx.adjust(cost, 1)

func prevents_being_chosen(ctx: TARGET_CONTEXT) -> bool:
	return ctx.from_opponent() and ctx.is_kind("Summon")
