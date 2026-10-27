extends "res://scripts/effects/card_effect.gd"


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx: EFFECT_CONTEXT) -> void:
	await ctx.opponent_mills(2)

func damage_caused_riders() -> Array:
	return [{
		"status": "cid_verdict",
		"duration": 1,
		"on_enter_break_zone": [{"name": "opponent_mills", "author": "game", "argument": [2]}],
	}]

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Highwind 《S》《Dull》: Your opponent puts the top 2 cards of their deck into the Break Zone."
		cost = {}
		tap = true
		s_cost = true

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._skill_0(ctx)
