extends RefCounted
## One activated ability: text, costs, target timing and the effect handler in a single object. The activation
## pipeline still consumes a dictionary-shaped ability (costs, tap, choose_target, ...); as_skill_dict() is that
## bridge, while the object itself is snapshotted onto the stack so resolution can call run().
##
## Activated abilities choose targets at activation, so the chosen cards arrive in the handler as ctx.targets.

var text: String = ""
var cost: Dictionary = {}
var tap: bool = false
var s_cost: bool = false
var discard: int = 0
var sacrifice: Dictionary = {}
var return_self: bool = false

var targets = null              # choose_target criteria; Dictionary or Array
var target_count: int = 1
var target_chooser: String = "self"
var target_timing: String = "activation"

var only_your_turn: bool = false
var only_if_blocking: bool = false
var only_if_damage_received: int = 0
var once_per_turn: bool = false

var copied: bool = false
var free_activation: bool = false
var copied_from: String = ""
var run: Callable


func _init(data: Dictionary = {}) -> void:
	text = str(data.get("text", ""))
	cost = data.get("cost", {})
	tap = bool(data.get("tap", false))
	s_cost = bool(data.get("s_cost", false))
	discard = int(data.get("discard", 0))
	sacrifice = data.get("sacrifice", {})
	targets = data.get("targets", null)
	target_count = maxi(1, int(data.get("target_count", 1)))
	target_chooser = str(data.get("target_chooser", "self"))
	target_timing = str(data.get("target_timing", "activation"))
	only_your_turn = bool(data.get("only_your_turn", false))
	only_if_blocking = bool(data.get("only_if_blocking", false))
	only_if_damage_received = int(data.get("only_if_damage_received", 0))
	once_per_turn = bool(data.get("once_per_turn", false))
	copied = bool(data.get("copied", false))
	free_activation = bool(data.get("free_activation", false))
	copied_from = str(data.get("copied_from", ""))
	run = data.get("run", Callable())


## The dictionary the existing activation/payment pipeline understands.
func as_skill_dict() -> Dictionary:
	var out: Dictionary = {
		"text": text,
		"cost": cost,
		"tap": tap,
		"s_cost": s_cost,
		"discard": discard,
		"sacrifice": sacrifice,
		"return_self": return_self,
		"only_your_turn": only_your_turn,
		"only_if_blocking": only_if_blocking,
		"only_if_damage_received": only_if_damage_received,
		"once_per_turn": once_per_turn,
		"copied": copied,
		"free_activation": free_activation,
		"copied_from": copied_from,
	}
	if targets != null:
		# The activation engine reads `count` from inside the criteria block, not from the ability dictionary.
		if targets is Dictionary:
			var criteria: Dictionary = targets.duplicate(true)
			if target_count > 1:
				criteria["count"] = target_count
			out["choose_target"] = criteria
		else:
			out["choose_target"] = targets
		out["target_chooser"] = target_chooser
	out["_ability_spec"] = self
	return out


func duplicate_spec() -> RefCounted:
	var copy = get_script().new({
		"text": text,
		"cost": cost.duplicate(true),
		"tap": tap,
		"s_cost": s_cost,
		"discard": discard,
		"sacrifice": sacrifice.duplicate(true),
		"return_self": return_self,
		"targets": targets.duplicate(true) if targets is Dictionary or targets is Array else targets,
		"target_count": target_count,
		"target_chooser": target_chooser,
		"target_timing": target_timing,
		"only_your_turn": only_your_turn,
		"only_if_blocking": only_if_blocking,
		"only_if_damage_received": only_if_damage_received,
		"once_per_turn": once_per_turn,
		"copied": copied,
		"free_activation": free_activation,
		"copied_from": copied_from,
		"run": run,
	})
	return copy
