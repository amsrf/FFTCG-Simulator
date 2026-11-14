extends "res://scripts/effects/card_effect.gd"
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
		text = "Ronso Rage 《S》《Earth》《Earth》: Choose 1 Forward opponent controls. Kimahri gains its Special Ability until the end of the turn. You can use this ability without paying any cost but only once."
		s_cost = true
		cost = {"土": 2}
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT).with_special_ability(true))

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._copy_special(ctx)
