extends "res://scripts/effects/card_effect.gd"

func shields_from_choice(ctx: TARGET_CONTEXT) -> bool:
	return ctx.candidate.card_name == "Sazh" and ctx.from_opponent() and ctx.kind_in(["Summon", "Ability"])
