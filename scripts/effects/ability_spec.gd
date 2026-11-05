extends RefCounted
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
const TARGET_SEQUENCE := preload("res://scripts/effects/target_sequence.gd")
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
## "Put this card into the Break Zone as a cost" normally happens at activation. Set this to pay it at commit instead,
## after the mana stage, so backing out of payment does not lose the source (Tama 111).
var defer_sacrifice: bool = false
var divide_total: int = 0
var return_self: bool = false
## 《X》 — the player declares X before paying, and the cost becomes {"neutral": X}.
var x_cost: bool = false
var x_min: int = 0

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
	defer_sacrifice = bool(data.get("defer_sacrifice", false))
	divide_total = int(data.get("divide_total", 0))
	x_cost = bool(data.get("x_cost", false))
	x_min = maxi(0, int(data.get("x_min", 0)))
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
		"defer_sacrifice": defer_sacrifice,
		"divide_total": divide_total,
		"return_self": return_self,
		"x_cost": x_cost,
		"x_min": x_min,
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
		var criteria = targets
		if criteria is Object and criteria.has_method("to_legacy"):
			criteria = criteria.to_legacy()
		if criteria is Dictionary:
			var block: Dictionary = criteria.duplicate(true)
			if target_count > 1 and not block.has("count"):
				block["count"] = target_count
			out["choose_target"] = block
		else:
			out["choose_target"] = criteria
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
		"defer_sacrifice": defer_sacrifice,
		"divide_total": divide_total,
		"return_self": return_self,
		"x_cost": x_cost,
		"x_min": x_min,
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


static func stack_wording(definition: Dictionary) -> String:
	var wording := str(definition.get("text", "")).strip_edges()
	var cost_end := wording.find(":")
	if cost_end >= 0:
		var prefix := wording.left(cost_end)
		if prefix.contains("《") or prefix.to_lower().begins_with("dull") or prefix.to_lower().begins_with("put "):
			wording = wording.substr(cost_end + 1).strip_edges()
	return wording
