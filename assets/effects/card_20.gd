extends "res://scripts/effects/card_effect.gd"
## Fang 1-020R: your Bahamut Summons cost 2 less.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ATTACK: Callable(self, "when_attack"),
	}


func modify_cost_for(ctx: COST_CONTEXT, subject: Card, cost: Dictionary) -> Dictionary:
	if ctx.source == null or subject.controller != ctx.source.controller:
		return cost
	if subject.type != "Summon" or subject.card_name != "Bahamut":
		return cost
	return ctx.adjust(cost, -2)

func when_attack(ctx: EFFECT_CONTEXT) -> void:
	ctx.add_status([ctx.source], "first_strike", 1)
