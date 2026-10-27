extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-019C Black Mage


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _untap_target(ctx: EFFECT_CONTEXT) -> void:
	ctx.untap(ctx.targets)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《火》《Dull》: Choose 1 Fire Backup you control. Activate it."
		cost = {"火": 1}
		tap = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Backup").of_element("Fire").controlled_by(CARD_QUERY.Controller.PLAYER))

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._untap_target(ctx)
