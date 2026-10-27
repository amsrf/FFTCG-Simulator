extends "res://scripts/effects/card_effect.gd"
## 1-053C Summoner


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _cancel_summon(ctx) -> void:
	if not ctx.targets.is_empty():
		ctx.cancel_stack_card(ctx.targets[0])

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Ice》, put Summoner into the Break Zone: Choose 1 Summon. Cancel its effect."
		cost = {"氷": 1}
		sacrifice = {"is_source": true}
		targets = {"in": "stack", "is_type": "Summon"}

	func on_resolve(ctx) -> void:
		await _owner._cancel_summon(ctx)
