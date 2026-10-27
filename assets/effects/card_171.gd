extends "res://scripts/effects/card_effect.gd"
## Minwu 1-171R: damage below the Forward's power is prevented.


func modify_damage(ctx: DAMAGE_CONTEXT) -> int:
	if ctx.target.is_type("Forward") \
			and ctx.target.controller == ctx.rule_owner.controller \
			and ctx.amount < ctx.target.power:
		return 0
	return ctx.amount
