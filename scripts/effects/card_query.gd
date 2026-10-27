extends RefCounted
## Typed card criteria. The engine's old dictionary blocks remain the internal exchange format, but card code should
## describe targets with this object instead of building a predicate dictionary by hand.
##
## `extra` is the escape hatch for predicates that do not have a builder method yet. It is merged last.

enum Controller { ANY, YOUR, OPPONENT, PLAYER }

var type_filter: String = ""
var element_filter: String = ""
var name_filter: String = ""
var controller_filter: Controller = Controller.ANY
var tapped_filter: Variant = null
var min_cost: int = -1
var max_cost: int = -1
var exclude_source: bool = false
var excludes: Array = []
var extra: Dictionary = {}


func of_type(value: String):
	type_filter = value
	return self


func of_element(value: String):
	element_filter = value
	return self


func named(value: String):
	name_filter = value
	return self


func controlled_by(value: Controller):
	controller_filter = value
	return self


func tapped(value: bool):
	tapped_filter = value
	return self


func cost_at_least(value: int):
	min_cost = value
	return self


func cost_at_most(value: int):
	max_cost = value
	return self


func excluding_source():
	exclude_source = true
	return self


func excluding(query):
	excludes.append(query)
	return self


func where(block: Dictionary):
	extra.merge(block, true)
	return self


## The legacy predicate block consumed by CardTarget.matches().
func to_block() -> Dictionary:
	var block: Dictionary = extra.duplicate(true)
	if not type_filter.is_empty():
		block["is_type"] = type_filter
	if not element_filter.is_empty():
		block["is_element"] = element_filter
	if not name_filter.is_empty():
		block["is_named"] = name_filter
	match controller_filter:
		Controller.YOUR:
			block["controller"] = "your"
		Controller.OPPONENT:
			block["controller"] = "opponent"
		Controller.PLAYER:
			block["controller"] = "player"
	if tapped_filter != null:
		block["is_tapped"] = bool(tapped_filter)
	if min_cost >= 0:
		block["is_cost_at_least"] = min_cost
	if max_cost >= 0:
		block["is_cost_at_most"] = max_cost
	if exclude_source:
		block["is_source"] = false
	if not excludes.is_empty():
		var list: Array = []
		for query in excludes:
			if query != null and query.has_method("to_block"):
				list.append(query.to_block())
		if not list.is_empty():
			block["exclude"] = list
	return block
