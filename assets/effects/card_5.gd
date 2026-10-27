extends "res://scripts/effects/card_effect.gd"
## Warrior of Light 1-005R: damage dealt to a cost-4-or-more Forward is doubled.


func modify_damage(ctx: DAMAGE_CONTEXT) -> int:
	if ctx.source_is_owner() and ctx.target.is_type("Forward") and int(ctx.target.cost) >= 4:
		return ctx.amount * 2
	return ctx.amount
