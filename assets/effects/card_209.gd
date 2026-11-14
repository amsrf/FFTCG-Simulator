extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-209C Red Mage


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _first_strike_target(ctx: EFFECT_CONTEXT) -> void:
	ctx.add_status(ctx.targets, "first_strike", 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Lightning》《Dull》: Choose 1 attacking Lightning Forward. It gains First Strike until the end of the turn."
		cost = {"雷": 1}
		tap = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").attacking(true).of_element("雷"))

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._first_strike_target(ctx)
