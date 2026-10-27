extends "res://scripts/effects/card_effect.gd"
## Knight 1-165R: a Forward in this card's party takes no damage.


func modify_damage(ctx: DAMAGE_CONTEXT) -> int:
	if not ctx.target_is_owner() and ctx.target.is_type("Forward") and ctx.target_in_party_with_owner():
		return 0
	return ctx.amount
