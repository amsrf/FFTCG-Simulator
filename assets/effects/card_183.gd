extends "res://scripts/effects/card_effect.gd"

func produces_any_element() -> bool:
	return true


func light_dark_exemption() -> String:
	return "light"

func generate_mana(ctx: EFFECT_CONTEXT) -> String:
	return str(await ctx.choose_crystal_in_circle(ctx.source.mana_elements()))
