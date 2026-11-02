extends "res://scripts/effects/card_effect.gd"

func prevents_being_chosen(ctx: TARGET_CONTEXT) -> bool:
	return ctx.from_opponent() and ctx.kind_in(["Summon", "Ability"])
