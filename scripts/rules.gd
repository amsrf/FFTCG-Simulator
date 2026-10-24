extends RefCounted
## RULES — the continuous-effect QUERY layer.
##
## The board (Field) owns the cards; the rules that READ them live here. A rule can then be asked a question without
## caring how the board is laid out, precedence has one home, and the board stops growing every time a new kind of
## modifier appears.
##
## Registration stays on Field: it is the only thing that knows when a card enters or leaves, and the stateful ledgers
## (auras, power_per) still live there. This object only evaluates.
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
func effective_cost(card: Card) -> Dictionary:
	var paid: Dictionary = card.get_cost()
	var delta: int = 0
	for source in _cards():
		if source == null or not is_instance_valid(source):
			continue
		var rules = source.card_effects.get("cost_aura", [])
		if rules is Dictionary:
			rules = [rules]
		if not (rules is Array):
			continue
		for rule in rules:
			if not (rule is Dictionary):
				continue
			var for_type: String = str(rule.get("for", ""))
			if for_type != "" and card.type != for_type:
				continue
			# "…to cast [Card Name (Bahamut)]" — the modifier can name ONE card instead of a whole type.
			var for_name: String = str(rule.get("name", ""))
			if for_name != "" and card.card_name != for_name:
				continue
			var scope: String = str(rule.get("from", ""))
			if scope == "opponent" and card.controller == source.controller:
				continue
			if (scope == "own" or scope == "controller") and card.controller != source.controller:
				continue
			delta += int(rule.get("delta", 0))
	if delta != 0:
		var neutral: int = maxi(0, int(paid.get("neutral", 0)) + delta)
		if neutral > 0:
			paid["neutral"] = neutral
		else:
			paid.erase("neutral")
	return paid


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
		var rules = protector.card_effects.get("shields", [])
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
		var rules = protector.card_effects.get("protects", [])
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


## Damage modifiers applied BEFORE the damage lands, so a doubled hit counts as one hit for the break check.
##
##   "damage_double": {"is_type": "Forward", "min_cost": 4}      (Warrior of Light 5)
##
## `min_cost` is a rule field here rather than a Card predicate, so it is stripped before the criteria are evaluated —
## leaving it in would make matches_criteria() call a method named min_cost and refuse every target.
func modify_damage(source: Card, target: Card, amount: int) -> int:
	if source == null or target == null or amount <= 0:
		return amount
	var rule = source.card_effects.get("damage_double", null)
	if not (rule is Dictionary):
		return amount
	var minimum: int = int(rule.get("min_cost", -1))
	if minimum >= 0 and int(target.cost) < minimum:
		return amount
	var criteria: Dictionary = rule.duplicate()
	criteria.erase("min_cost")
	if not criteria.is_empty() and not target.matches_criteria(criteria, source):
		return amount
	print("[Damage] %s doubles its %d damage to %s" % [source.card_name, amount, target.card_name])
	return amount * 2
