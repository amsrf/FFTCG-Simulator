extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-100C Black Belt


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _activate(ctx: EFFECT_CONTEXT) -> void:
	ctx.power_change(ctx.targets, 1000, 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《土》《Dull》: Choose 1 Forward blocking. It gains +1000 power."
		cost = {"土": 1}
		tap = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").blocking(true))

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._activate(ctx)
