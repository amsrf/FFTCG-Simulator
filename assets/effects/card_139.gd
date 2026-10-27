extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-139C Summoner


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _free_summon(ctx: EFFECT_CONTEXT) -> void:
	await ctx.cast_summon_for_free(CARD_QUERY.new().of_type("Summon").cost_at_most(6))

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》, put Summoner into the Break Zone: Cast 1 Summon of cost 6 or less from your hand for free."
		cost = {}
		tap = true
		sacrifice = {"is_source": true}

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._free_summon(ctx)
