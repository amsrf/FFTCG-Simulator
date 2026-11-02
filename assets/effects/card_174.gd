extends "res://scripts/effects/card_effect.gd"

func must_be_chosen(ctx: TARGET_CONTEXT) -> bool:
	return ctx.from_opponent() and ctx.kind_in(["Summon", "Ability"])
