extends "res://scripts/effects/card_effect.gd"
## 1-036C Bard


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _activate(ctx) -> void:
	await ctx.opponent_discards(1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《氷》《Dull》, put Bard into the Break Zone: Your opponent discards 1 card."
		cost = {"氷": 1}
		tap = true
		sacrifice = {"is_source": true}

	func on_resolve(ctx) -> void:
		await _owner._activate(ctx)
