extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-149R Lulu


func activated_abilities() -> Array:
	return [Ability0.new(self), Ability1.new(self)]
func _damage_5000(ctx) -> void:
	ctx.damage(ctx.targets, 5000)

func _damage_10000(ctx) -> void:
	ctx.damage(ctx.targets, 10000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》, put 1 Backup into the Break Zone: Choose 1 Forward. Deal it 5000 damage."
		cost = {}
		tap = true
		sacrifice = {"is_type": "Backup", "controller": "player"}
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))

	func on_resolve(ctx) -> void:
		await _owner._damage_5000(ctx)

class Ability1 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Thundaga 《S》《Lightning》《Dull》: Choose 1 Forward. Deal it 10000 damage."
		s_cost = true
		cost = {"雷": 1}
		tap = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))

	func on_resolve(ctx) -> void:
		await _owner._damage_10000(ctx)
