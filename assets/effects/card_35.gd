extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-035C Shiva


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _dull_target(ctx: EFFECT_CONTEXT) -> void:
	ctx.dull(ctx.targets)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《氷》《氷》《Dull》: Choose 1 Forward. Dull it."
		cost = {"氷": 2}
		tap = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._dull_target(ctx)
