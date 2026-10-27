extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-054C Dark Knight


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _activate(ctx: EFFECT_CONTEXT) -> void:
	ctx.damage(ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)), 1000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《氷》《氷》《Dull》: Deal 1000 damage to all opponent Forwards."
		cost = {"氷": 2}
		tap = true

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._activate(ctx)
