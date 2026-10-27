extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-121C Red Mage


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _activate(ctx: EFFECT_CONTEXT) -> void:
	ctx.add_status(ctx.targets, "haste", 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《雷》《Dull》: Choose 1 Forward. It gains Haste until the end of the turn."
		cost = {"雷": 1}
		tap = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._activate(ctx)
