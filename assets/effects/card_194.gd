extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-194S Snow


func when_blocks(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward")))
	ctx.dull(targets)


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx) -> void:
	ctx.power_change([ctx.source], 2000, 1)
	ctx.add_status([ctx.source], "first_strike", 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Vendetta 《S》《Ice》: Until the end of the turn, Snow gains +2000 power and First Strike. Use only while Snow is blocking."
		cost = {"氷": 1}
		s_cost = true
		only_if_blocking = true

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)
