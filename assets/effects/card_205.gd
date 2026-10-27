extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-205S Barret


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _damage_all_opponent_forwards(ctx: EFFECT_CONTEXT) -> void:
	ctx.damage(ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)), 2000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Grenade Bomb 《S》: Deal 2000 damage to all opponent Forwards."
		s_cost = true
		cost = {}

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._damage_all_opponent_forwards(ctx)
