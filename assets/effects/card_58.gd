extends "res://scripts/effects/card_effect.gd"
## 1-058L Laguna


func when_cause_damage_to_player(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward", "is_tapped": true})
	if targets.is_empty():
		return
	if await ctx.may("Deal 7000"):
		ctx.damage(targets, 7000)


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	ctx.damage(targets, 9000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Desperado 《S》《Ice》《Ice》: Choose 1 dull Forward. Deal it 9000 damage."
		cost = {"氷": 2}
		s_cost = true
		targets = {"is_type": "Forward", "is_tapped": true}
		target_count = 1

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)
