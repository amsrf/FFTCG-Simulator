extends "res://scripts/effects/card_effect.gd"
## 1-034C Shiva


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _dull_all_opponent_forwards(ctx) -> void:
	ctx.dull(ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent"}))

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《氷》《氷》《氷》《Dull》: Dull all opponent Forwards."
		cost = {"氷": 3}
		tap = true

	func on_resolve(ctx) -> void:
		await _owner._dull_all_opponent_forwards(ctx)
