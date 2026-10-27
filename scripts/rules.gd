extends RefCounted
const DAMAGE_CONTEXT := preload("res://scripts/effects/damage_context.gd")
## RULES — the continuous-effect QUERY layer.
##
## The board (Field) owns the cards; the rules that READ them live here. A rule can then be asked a question without
## caring how the board is laid out, precedence has one home, and the board stops growing every time a new kind of
## modifier appears.
##
## Registration stays on Field: it is the only thing that knows when a card enters or leaves, and the stateful ledgers
## (auras, dynamic power) still live there. This object only evaluates.
##
## Field keeps thin forwarders (`effective_cost`, `modify_damage`, `is_protected_from_being_chosen`,
## `is_protected_from_break`) so existing call sites and probes do not care where the implementation lives.

## The BOARD this rulebook reads. No Game reference: these queries only need the cards, and keeping the dependency to
## one object is what makes the layer honestly separable.
var field: Node = null


func bind(board: Node) -> void:
	field = board


func _cards() -> Array:
	if field == null:
		return []
	return field.get_all_cards()


## The cost ACTUALLY paid for `card`, after the board's modifiers. `Card.get_cost()` stays the printed cost.
##
## Data on the modifier's source:
##   "cost_aura": {"for": "Summon", "name": "Bahamut", "from": "opponent", "delta": 1}
## `from` is read from the aura card's perspective; `delta` is added to the NEUTRAL part (any element may pay it) and
## the result is floored at 0, so a negative delta is a reduction.
##
## One function, because there are exactly two cost readers — the payment modal and the AI's affordability check — and
## they must agree.
const COST_CONTEXT := preload("res://scripts/effects/cost_context.gd")


## The cost ACTUALLY paid for `card`, after every continuous modifier. `Card.get_cost()` remains the printed cost.
##
## The calculation is a QUERY, not a mutation:
##   1. the subject card's own effect gets `modify_cost()`
##   2. every ability-enabled card on the field gets `modify_cost_for()`
##   3. the accumulated minimum is applied once
##
## Both readers — Assistant's payment modal and AIAgent's affordability check — call this, so they cannot disagree.
func effective_cost(card: Card, purpose: String = "cast") -> Dictionary:
	if card == null:
		return {}
	var ctx = COST_CONTEXT.new(card, purpose, field)
	var paid: Dictionary = card.get_cost()

	# Self modifiers ("while you control Ovelia, this costs 1 less").
	var own = card.effect() if card.abilities_enabled() else null
	if own != null and own.has_method("modify_cost"):
		paid = own.modify_cost(ctx, card, paid)
	else:
		paid = _json_self_cost(card, ctx, paid)

	# External modifiers ("your Water Summons cost 1 less", "opponent Summons cost 1 more").
	for source in _cards():
		if source == null or not is_instance_valid(source):
			continue
		if not source.is_on_field() or not source.abilities_enabled():
			continue
		var effect_obj = source.effect()
		if effect_obj != null and effect_obj.has_method("modify_cost_for"):
			ctx.source = source
			paid = effect_obj.modify_cost_for(ctx, card, paid)
		else:
			paid = _json_cost_aura(source, card, ctx, paid)

	return ctx.apply_floor(paid)


## Fallback for a card that has not been migrated yet.
func _json_self_cost(card: Card, ctx, paid: Dictionary) -> Dictionary:
	var rule = card.card_effects.get("self_cost", {})
	if not (rule is Dictionary) or rule.is_empty():
		return paid
	var delta: int = 0
	var per = rule.get("per", {})
	if per is Dictionary and not per.is_empty():
		delta += int(rule.get("delta", 0)) * ctx.cards_in_field(per, true).size()
	else:
		var condition = rule.get("if_controls", {})
		if condition is Dictionary and not condition.is_empty() and ctx.controls(condition):
			delta += int(rule.get("delta", 0))
		elif not (condition is Dictionary) or condition.is_empty():
			delta += int(rule.get("delta", 0))
	return ctx.adjust(paid, delta, int(rule.get("min", 0)))


## Fallback for a source that still carries a JSON cost_aura.
func _json_cost_aura(source: Card, subject: Card, ctx, paid: Dictionary) -> Dictionary:
	var rules = source.card_effects.get("cost_aura", [])
	if rules is Dictionary:
		rules = [rules]
	if not (rules is Array):
		return paid
	for rule in rules:
		if not (rule is Dictionary):
			continue
		var for_type: String = str(rule.get("for", ""))
		if for_type != "" and subject.type != for_type:
			continue
		var for_name: String = str(rule.get("name", ""))
		if for_name != "" and subject.card_name != for_name:
			continue
		var for_element: String = str(rule.get("element", ""))
		if for_element != "" and not subject.is_element(for_element):
			continue
		var scope: String = str(rule.get("from", ""))
		if scope == "opponent" and subject.controller == source.controller:
			continue
		if (scope == "own" or scope == "controller") and subject.controller != source.controller:
			continue
		paid = ctx.adjust(paid, int(rule.get("delta", 0)), int(rule.get("min", 0)))
	return paid


func _cost_total(cost: Dictionary) -> int:
	var total: int = 0
	for value in cost.values():
		total += int(value)
	return total


## GRANTED CHOICE PROTECTION — "The Card Name Sazh you control cannot be chosen by your opponent's Summons or
## abilities" (Dajh). Asked from the TARGETING gate only: a set effect ("all the Backups") still hits the card,
## because it was never chosen.
##
##   "shields": {"targets": {"is_named": "Sazh"}, "from": "opponent", "by": ["Summon", "Ability"]}
func is_protected_from_being_chosen(card: Card, source: Card, source_kind: String) -> bool:
	if card == null or source == null:
		return false
	for protector in _cards():
		if protector == null or not is_instance_valid(protector):
			continue
		var rules = protector.static_rule("shields", [])
		if rules is Dictionary:
			rules = [rules]
		if not (rules is Array):
			continue
		for rule in rules:
			if not (rule is Dictionary):
				continue
			var targets: Dictionary = rule.get("targets", {})
			if not card.matches_criteria(targets, protector):
				continue
			var scope: String = str(rule.get("from", ""))
			if scope == "opponent" and source.controller == protector.controller:
				continue
			if (scope == "own" or scope == "controller") and source.controller != protector.controller:
				continue
			var kinds: Array = rule.get("by", [])
			# An empty kind is combat; a Summon/Ability list never contains it, so it is refused below.
			if not kinds.is_empty() and not (source_kind in kinds):
				continue
			return true
	return false


## BREAK PROTECTION — "The Backups you control cannot be broken by your opponent's Summons or abilities" (Auron).
##
##   "protects": {"targets": {"is_type": "Backup", "controller": "player"},
##                "from": "opponent", "by": ["Summon", "Ability"]}
## `targets` is read from the PROTECTOR's perspective, and `by` may be omitted to mean any effect.
func is_protected_from_break(card: Card, source_controller: String, source_kind: String) -> bool:
	if card == null or source_kind.is_empty():
		# An empty kind is combat damage — no Summon or ability to be protected from.
		return false
	for protector in _cards():
		if protector == null or not is_instance_valid(protector):
			continue
		var rules = protector.static_rule("protects", [])
		if rules is Dictionary:
			rules = [rules]
		if not (rules is Array):
			continue
		for rule in rules:
			if not (rule is Dictionary):
				continue
			var targets: Dictionary = rule.get("targets", {})
			if not card.matches_criteria(targets, protector):
				continue
			var scope: String = str(rule.get("from", ""))
			if scope == "opponent" and source_controller == protector.controller:
				continue
			if (scope == "own" or scope == "controller") and source_controller != protector.controller:
				continue
			var kinds: Array = rule.get("by", [])
			if not kinds.is_empty() and not (source_kind in kinds):
				continue
			return true
	return false


## DAMAGE MODIFIERS, applied BEFORE the damage lands, so a doubled or prevented hit is one event for the break check.
##
## A card may carry:
##
##   "damage_modifiers": [{
##       "targets": {...},                 CardTarget criteria; evaluated with THIS card as source
##       "conditions": [...],              named predicates or {"compare_values": {...}}
##       "operation": "set|multiply|add|subtract",
##       "value": 0,                       literal or a context reference
##       "consume_status": "..."           optional status erased when the rule applies
##   }]
##
## Every rule on every card on the field is asked. The CONTEXT is a generic dictionary:
##   self              the card whose rule is being evaluated
##   source            the card that caused the damage (may be null)
##   target            the card receiving it
##   amount            the CURRENT amount, updated after each modifier
##   source_kind       "Summon"/"Ability"/"" from the caller
##   source_controller the controller of the damage source, if known
##
## `targets` is evaluated with `self` as the source, so `is_source` means "target == this card" and
## `controller: "player"` means "the same controller as this card". Numeric relations go through
## `compare_values`; see _condition_holds() for the named predicates.
func modify_damage(source: Card, target: Card, amount: int, source_kind: String = "",
		source_controller: String = "", damage_kind: int = -1) -> int:
	if target == null or not is_instance_valid(target) or amount <= 0:
		return amount
	if damage_kind < 0:
		if source_kind == "Summon":
			damage_kind = DAMAGE_CONTEXT.Kind.SUMMON
		elif source_kind == "Ability":
			damage_kind = DAMAGE_CONTEXT.Kind.ABILITY
		else:
			damage_kind = DAMAGE_CONTEXT.Kind.EFFECT
	var current: int = amount
	var context: Dictionary = {
		"amount": current,
		"source": source,
		"target": target,
		"source_kind": source_kind,
		"source_controller": source_controller if source_controller != "" or source == null else source.controller,
	}
	# PENDING STATUS MODIFIERS FIRST. A status payload with operation/value is a one-shot rule on the receiving card
	# ("the next damage becomes 0", "the next damage is reduced by 2000"). The status NAME is irrelevant; applying it
	# consumes it unless the payload says once: false, and turn_end() expires it if it was never used.
	context["self"] = target
	current = _apply_status_damage_modifiers(target, current, context)
	context["amount"] = current
	if current <= 0:
		return 0

	# ONE DAMAGE CONTEXT, every field card gets a chance to modify it. Code modifiers are pure: they return a number
	# and never add damage themselves. The source/target cards are ordinary participants, which is what lets a future
	# receiver-side rule and a field-wide replacement rule use the same hook.
	var damage_ctx = DAMAGE_CONTEXT.new()
	damage_ctx.original_amount = amount
	damage_ctx.source = source
	damage_ctx.source_controller = str(context["source_controller"])
	damage_ctx.source_kind = source_kind
	damage_ctx.target = target
	damage_ctx.kind = damage_kind
	damage_ctx.field = field
	for owner in _cards():
		if owner == null or not is_instance_valid(owner):
			continue
		damage_ctx.amount = current
		damage_ctx.rule_owner = owner
		var effect_obj = owner.effect() if owner.abilities_enabled() else null
		if effect_obj != null and effect_obj.has_method("modify_damage") and not owner.card_effects.has("damage_modifiers"):
			var next: int = int(effect_obj.modify_damage(damage_ctx))
			if next != current:
				print("[DamageMod] %s -> %d (%s)" % [owner.card_name, next, target.card_name])
			current = next
			context["amount"] = current
			if current <= 0:
				return 0
			continue
		# Legacy fallback for a card that still carries a static damage_modifiers block.
		var rules = owner.static_rule("damage_modifiers", [])
		if rules is Dictionary:
			rules = [rules]
		if not (rules is Array):
			continue
		for rule in rules:
			if not (rule is Dictionary):
				continue
			context["self"] = owner
			if not _damage_modifier_applies(rule, owner, context):
				continue
			var operation: String = str(rule.get("operation", ""))
			var value: Variant = _resolve_value(rule.get("value", 0), context)
			var next: int = _apply_damage_operation(current, operation, value)
			if next != current:
				print("[DamageMod] %s %s -> %d (%s)" % [owner.card_name, operation, next, target.card_name])
			current = next
			context["amount"] = current
			if rule.has("consume_status"):
				target.status_effects.erase(str(rule["consume_status"]))
			if current <= 0:
				return 0
	return current

func _damage_modifier_applies(rule: Dictionary, owner: Card, context: Dictionary) -> bool:
	var target: Card = context.get("target")
	if target == null or not is_instance_valid(target):
		return false
	if not target.matches_criteria(rule.get("targets", {}), owner):
		return false
	return _conditions_hold(rule.get("conditions", []), context)

func _conditions_hold(conditions: Variant, context: Dictionary) -> bool:
	if conditions is Dictionary:
		conditions = [conditions]
	if conditions == null:
		return true
	if not (conditions is Array):
		push_warning("[DamageMod] conditions must be a block or an array of blocks")
		return false
	for condition in conditions:
		if not (condition is Dictionary) or not _condition_holds(condition, context):
			return false
	return true

func _condition_holds(condition: Dictionary, context: Dictionary) -> bool:
	if condition.has("compare_values"):
		var comparison: Dictionary = condition["compare_values"]
		var left: Variant = _resolve_value(comparison.get("left"), context)
		var right: Variant = _resolve_value(comparison.get("right"), context)
		return _compare(left, str(comparison.get("op", "")), right)
	if condition.has("source_is_self"):
		return bool(condition["source_is_self"]) == (context.get("source") == context.get("self"))
	if condition.has("in_party_with_self"):
		var members: Array = field.party_members() if field != null else []
		var together: bool = members.has(context.get("self")) and members.has(context.get("target"))
		return together == bool(condition["in_party_with_self"])
	if condition.has("status"):
		var target: Card = context.get("target")
		return target != null and is_instance_valid(target) \
			and target.status_effects.has(str(condition["status"]))
	if condition.has("source_kind"):
		var wanted: Variant = condition["source_kind"]
		var actual: String = str(context.get("source_kind", ""))
		if wanted is Array:
			return wanted.has(actual)
		return actual == str(wanted)
	push_warning("[DamageMod] unknown condition key '%s'" % str(condition.keys()))
	return false

## Read a value reference. A literal number/string/bool is returned as-is; a dictionary names a CONTEXT key:
##   {"context": "amount"}                       -> the current damage
##   {"context": "target", "property": "power"}  -> the target's current power
##   {"context": "self", "property": "cost"}     -> the rule owner's cost
## The `property` form only works on Card-valued context entries, and only for the whitelist below.
func _resolve_value(ref: Variant, context: Dictionary) -> Variant:
	if ref is int or ref is float or ref is bool or ref is String:
		return ref
	if ref == null:
		return null
	if not (ref is Dictionary):
		push_warning("[DamageMod] a value must be a literal or a context reference")
		return null
	var key: String = str(ref.get("context", ""))
	if key.is_empty() or not context.has(key):
		push_warning("[DamageMod] unknown context key '%s'" % key)
		return null
	var value: Variant = context[key]
	var prop: String = str(ref.get("property", ""))
	if prop.is_empty():
		return value
	if not (value is Card):
		push_warning("[DamageMod] context '%s' is not a Card; cannot read .%s" % [key, prop])
		return null
	return _card_value(value, prop)

func _card_value(card: Card, prop: String) -> Variant:
	match prop:
		"power":
			return card.power
		"cost":
			return int(card.cost)
		"accumulated_damage":
			return card.accumulated_damage
		"tapped":
			return card.tapped
		"card_name":
			return card.card_name
		"type":
			return card.type
		"controller":
			return card.controller
		_:
			push_warning("[DamageMod] unknown Card property '%s'" % prop)
			return null

func _compare(left: Variant, op: String, right: Variant) -> bool:
	if left == null or right == null:
		return false
	match op:
		"eq":
			return left == right
		"neq":
			return left != right
		"lt", "lte", "gt", "gte":
			if not ((left is int or left is float) and (right is int or right is float)):
				push_warning("[DamageMod] '%s' needs two numbers" % op)
				return false
			var a: float = float(left)
			var b: float = float(right)
			match op:
				"lt":
					return a < b
				"lte":
					return a <= b
				"gt":
					return a > b
				_:
					return a >= b
		_:
			push_warning("[DamageMod] unknown comparison operator '%s'" % op)
			return false

func _apply_damage_operation(current: int, operation: String, value: Variant) -> int:
	if not (value is int or value is float):
		push_warning("[DamageMod] operation '%s' needs a numeric value" % operation)
		return current
	match operation:
		"set":
			return int(value)
		"multiply":
			return int(round(float(current) * float(value)))
		"add":
			return current + int(value)
		"subtract":
			return maxi(0, current - int(value))
		_:
			push_warning("[DamageMod] unknown operation '%s'" % operation)
			return current

## Status payloads that modify incoming damage. The status NAME is deliberately irrelevant: anything carrying
## operation/value is a rule. `once` defaults to true (the usual "next damage" wording); set once:false for a shield
## that lasts for the status's duration. `conditions` may use the same context as static modifiers.
func _apply_status_damage_modifiers(target: Card, amount: int, context: Dictionary) -> int:
	var current: int = amount
	for status in target.status_effects.keys():
		var payload = target.status_effects[status]
		if not (payload is Dictionary):
			continue
		if not payload.has("operation") or not payload.has("value"):
			continue
		if not _conditions_hold(payload.get("conditions", []), context):
			continue
		var operation: String = str(payload["operation"])
		var value: Variant = _resolve_value(payload["value"], context)
		var next: int = _apply_damage_operation(current, operation, value)
		if next != current:
			print("[DamageMod] status %s %s -> %d (%s)" % [status, operation, next, target.card_name])
		current = next
		context["amount"] = current
		if bool(payload.get("once", true)):
			target.status_effects.erase(status)
		if current <= 0:
			break
	return current
