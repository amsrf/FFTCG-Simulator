extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-088C Archer


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _activate(ctx) -> void:
	ctx.break_cards(ctx.targets)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《風》《風》《Dull》, put Archer into the Break Zone: Break 1 Backup of cost 3 or less."
		cost = {"風": 2}
		tap = true
		sacrifice = {"is_source": true}
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Backup").cost_at_most(3))

	func on_resolve(ctx) -> void:
		await _owner._activate(ctx)
