extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-126 Orlandeau: when it attacks, deal 3000 to every opponent Forward.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ATTACK: Callable(self, "when_attack"),
	}


func when_attack(ctx: EFFECT_CONTEXT) -> void:
	ctx.damage(ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)), 3000)


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx: EFFECT_CONTEXT) -> void:
	ctx.add_status([ctx.source], "haste", 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Lightning》《Lightning》: Orlandeau gains Haste until the end of the turn."
		cost = {"雷": 2}

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._skill_0(ctx)
