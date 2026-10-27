extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-145C Ramza
## 《Dull》: Choose 1 Backup. Activate it.


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _activate_backup(ctx) -> void:
	ctx.untap(ctx.targets)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》: Choose 1 Backup. Activate it."
		cost = {}
		tap = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Backup"))

	func on_resolve(ctx) -> void:
		await _owner._activate_backup(ctx)
