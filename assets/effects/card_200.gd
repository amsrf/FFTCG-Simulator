extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-200C Baralai


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _untap_targets(ctx: EFFECT_CONTEXT) -> void:
	ctx.untap(ctx.targets)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》, put Baralai into the Break Zone: Choose up to 2 Forwards. Activate them."
		cost = {}
		tap = true
		sacrifice = {"is_source": true}
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))
		target_count = 2

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._untap_targets(ctx)
