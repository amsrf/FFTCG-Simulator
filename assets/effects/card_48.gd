extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-048C Devout


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _play_from_break_zone(ctx: EFFECT_CONTEXT) -> void:
	await ctx.play_from_break_zone(CARD_QUERY.new().of_type("Forward").where({"is_cost_lower_than": 5}))

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Dull, put Devout into the Break Zone: Play 1 Forward of cost 4 or less from your Break Zone."
		cost = {}
		tap = true
		sacrifice = {"is_source": true}
		only_your_turn = true

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._play_from_break_zone(ctx)
