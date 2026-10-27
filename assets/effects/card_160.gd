extends "res://scripts/effects/card_effect.gd"
## 1-160C Gordon


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _next_damage_zero(ctx) -> void:
	ctx.add_status([ctx.source], "next_receiving_damage", 1, {"operation": "set", "value": 0})

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》: The next damage dealt to Gordon becomes 0 this turn."
		cost = {}
		tap = true

	func on_resolve(ctx) -> void:
		await _owner._next_damage_zero(ctx)
