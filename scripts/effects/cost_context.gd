extends RefCounted
## The world handed to one COST calculation. Cost modifications are continuous queries: no stack, no resolution, and
## no mutation of the printed cost. A modifier asks this object what the board looks like and returns a new dictionary.

var subject: Card = null
var controller: String = ""
var owner_id: int = 1
var purpose: String = "cast"
## The source granting an external modifier. For a self modifier this is the subject itself.
var source: Card = null
var field: Node = null
## The floor is accumulated across every modifier and applied ONCE at the end.
var min_total: int = 0


func _init(p_subject: Card, p_purpose: String = "cast", p_field: Node = null) -> void:
	subject = p_subject
	purpose = p_purpose
	field = p_field
	if p_subject != null:
		controller = p_subject.controller
		owner_id = 1 if controller == "player" else 2
		source = p_subject


## Cards on the field matching `criteria`, with "your"/"opponent" interpreted from the subject. `exclude_subject`
## covers "another Forward"/"other than this card" counts.
func cards_in_field(criteria: Dictionary = {}, exclude_subject: bool = false) -> Array:
	var out: Array = []
	if field == null:
		return out
	for card in field.get_all_cards():
		if card == null or not is_instance_valid(card):
			continue
		if exclude_subject and card == subject:
			continue
		if not card.matches_criteria(criteria, subject):
			continue
		out.append(card)
	return out


func controls(criteria: Dictionary) -> bool:
	return not cards_in_field(criteria, true).is_empty()


## Shift the NEUTRAL part of a cost. This preserves the existing payment model: elemental points are untouched, and a
## reduction/increase is paid by the any-colour part. The floor is recorded but not applied here.
func adjust(cost: Dictionary, delta: int, minimum: int = 0) -> Dictionary:
	min_total = maxi(min_total, int(minimum))
	if delta == 0:
		return cost.duplicate()
	var out: Dictionary = cost.duplicate()
	var neutral: int = maxi(0, int(out.get("neutral", 0)) + int(delta))
	if neutral > 0:
		out["neutral"] = neutral
	else:
		out.erase("neutral")
	return out


## Apply the accumulated minimum once, after every modifier has run. A cost already below the floor is not raised.
func apply_floor(cost: Dictionary) -> Dictionary:
	if min_total <= 0:
		return cost
	var total: int = 0
	for value in cost.values():
		total += int(value)
	if total < min_total:
		cost = cost.duplicate()
		cost["neutral"] = int(cost.get("neutral", 0)) + (min_total - total)
	return cost
