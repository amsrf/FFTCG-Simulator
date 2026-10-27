extends "res://scripts/effects/card_effect.gd"

func static_rules() -> Dictionary:
	return {"produces_any_element": true, "light_dark_exempt": "light"}

func generate_mana(ctx: EFFECT_CONTEXT) -> String:
	return str(await ctx.choose_crystal_in_circle(ctx.source.mana_elements()))

