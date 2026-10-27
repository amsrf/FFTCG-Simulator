extends "res://scripts/effects/card_effect.gd"
## 1-205S Barret


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _damage_all_opponent_forwards(ctx) -> void:
	ctx.damage(ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent"}), 2000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Grenade Bomb 《S》: Deal 2000 damage to all opponent Forwards."
		s_cost = true
		cost = {}

	func on_resolve(ctx) -> void:
		await _owner._damage_all_opponent_forwards(ctx)
