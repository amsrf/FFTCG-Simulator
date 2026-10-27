extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")

func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _shot(ctx: EFFECT_CONTEXT) -> void:
	ctx.damage(ctx.targets, 2000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《火》《1》《Dull》: Choose 1 Forward of cost 3 or less. Deal it 2000 damage."
		cost = {"火": 1, "neutral": 1}
		tap = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").cost_at_most(3))
		target_count = 1

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._shot(ctx)
