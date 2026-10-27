extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-066C Dancer


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _activate(ctx) -> void:
	ctx.damage(ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)), 1000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》: Deal 1000 damage to all opponent Forwards."
		cost = {}
		tap = true

	func on_resolve(ctx) -> void:
		await _owner._activate(ctx)
