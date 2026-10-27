extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-157C Scholar


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _return_target(ctx) -> void:
	ctx.return_to_hand(ctx.targets)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》, put Scholar into the Break Zone: Choose 1 Forward you control. Return it to its owner's hand."
		cost = {}
		tap = true
		sacrifice = {"is_source": true}
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.PLAYER))

	func on_resolve(ctx) -> void:
		await _owner._return_target(ctx)
