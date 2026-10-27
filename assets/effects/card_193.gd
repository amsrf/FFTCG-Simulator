extends "res://scripts/effects/card_effect.gd"
## 1-193S Jihl Nabaat


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward"}, 2)
	ctx.add_status(targets, "frozen", 1)


func ex_burst_event() -> String:
	return "when_enter_field"


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	ctx.dull(targets)
	ctx.add_status(targets, "frozen", 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Sadistic Surge 《S》《Ice》《Dull》: Choose 1 Forward. Dull it and Freeze it."
		cost = {"氷": 1}
		tap = true
		s_cost = true
		targets = {"is_type": "Forward"}
		target_count = 1

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)
