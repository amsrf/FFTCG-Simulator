extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
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
		targets = TARGET_REQUEST.stack(CARD_QUERY.new().of_type("Summon"))

	func on_resolve(ctx) -> void:
		await _owner._cancel_summon(ctx)
