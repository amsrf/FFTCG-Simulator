extends "res://scripts/effects/card_effect.gd"
## 1-128R Gilgamesh


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _morphing_time(ctx: EFFECT_CONTEXT) -> void:
	ctx.source.double_power(1)
	ctx.add_status([ctx.source], "first_strike", 1)
	ctx.add_status([ctx.source], "brave", 1)
	ctx.source.set_extra_attacks(1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Gilgamesh Morphing Time 《S》《雷》《雷》: Double its power, gain First Strike and Brave, and attack twice."
		s_cost = true
		cost = {"雷": 2}
		only_your_turn = true

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._morphing_time(ctx)
