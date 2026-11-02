extends "res://scripts/effects/card_effect.gd"

func shields_from_choice(ctx: TARGET_CONTEXT) -> bool:
	return ctx.candidate.card_name == "Snow" and ctx.from_opponent() and ctx.is_kind("Ability")
