extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-102H Kimahri


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _copy_special(ctx: EFFECT_CONTEXT) -> void:
	if not ctx.targets.is_empty():
		await ctx.copy_skill(ctx.targets[0])

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Ronso Rage 《S》《土》《土》: Choose 1 opponent Forward with a Special Ability. Kimahri gains it, usable once for free."
		s_cost = true
		cost = {"土": 2}
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT).with_special_ability(true))

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._copy_special(ctx)
