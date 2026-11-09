extends RefCounted
## A typed request for a multi-card selection: a pool query, a count range, and composable constraints.
##
## The pool query decides what appears. Constraints decide which of those cards remain selectable as the
## selection changes, and whether Confirm is legal. This is deliberately separate from a CardQuery: a
## "different Elements" rule is a property of the CURRENT SELECTION, not a property of a single card.

const CARD_FILTER := preload("res://scripts/core/card_filter.gd")
const UNIQUE_CONSTRAINT := preload("res://scripts/effects/unique_field_constraint.gd")
const TOTAL_COST_CONSTRAINT := preload("res://scripts/effects/total_cost_constraint.gd")

var query = null
var minimum: int = 1
var maximum: int = 1
var constraints: Array = []


func _init(p_query = null) -> void:
	query = p_query


func up_to(count: int):
	maximum = maxi(1, count)
	minimum = mini(minimum, maximum)
	return self


func at_least(count: int):
	minimum = maxi(0, count)
	return self


func exactly(count: int):
	minimum = maxi(0, count)
	maximum = minimum
	return self


## "each of a different <field>" — element, job, name, category.
func unique(field: String):
	constraints.append(UNIQUE_CONSTRAINT.new(field))
	return self


## Sum of printed costs, inclusive. Pass the same value twice for an exact total.
func total_cost(low: int, high: int):
	constraints.append(TOTAL_COST_CONSTRAINT.new(low, high))
	return self


func allows(id: int, selected: Array) -> bool:
	if selected.size() >= maximum:
		return false
	if not _in_pool(id):
		return false
	for constraint in constraints:
		if not constraint.allows(id, selected):
			return false
	return true


func valid(selected: Array) -> bool:
	if selected.size() < minimum or selected.size() > maximum:
		return false
	for constraint in constraints:
		if not constraint.valid(selected):
			return false
	return true


func reason(id: int, selected: Array) -> String:
	if selected.size() >= maximum:
		return "Maximum of %d selected" % maximum
	for constraint in constraints:
		var why: String = constraint.reason(id, selected)
		if why != "":
			return why
	return ""


func _in_pool(id: int) -> bool:
	if query == null:
		return true
	return CARD_FILTER.matches(CARD_FILTER.card_by_id(id), query.to_filter())
