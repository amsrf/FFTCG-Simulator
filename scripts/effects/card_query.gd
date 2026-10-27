extends RefCounted
## Typed card criteria. The engine's old dictionary blocks remain the internal exchange format, but card code should
## describe targets with this object instead of building a predicate dictionary by hand.
##
## `extra` is the escape hatch for predicates that do not have a builder method yet. It is merged last.

enum Controller { ANY, YOUR, OPPONENT, PLAYER }

var type_filter: String = ""
var element_filter: String = ""
var name_filter: String = ""
var name_exact: bool = true
var category_filter: String = ""
var job_filter: String = ""
var controller_filter: Controller = Controller.ANY
var tapped_filter: Variant = null
var min_cost: int = -1
var max_cost: int = -1
var min_power: int = -1
var max_power: int = -1
var any_queries: Array = []
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
	name_exact = true
	return self


func name_contains(value: String):
	name_filter = value
	name_exact = false
	return self


func of_category(value: String):
	category_filter = value
	return self


func with_job(value: String):
	job_filter = value
	return self


func power_at_least(value: int):
	min_power = value
	return self


func power_at_most(value: int):
	max_power = value
	return self


func any_of(queries: Array):
	for query in queries:
		if query != null:
			any_queries.append(query)
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


func of_any_type(values: Array):
	extra["is_type_any"] = values
	return self


func character(value: bool = true):
	extra["is_character"] = value
	return self


func blocking(value: bool = true):
	extra["is_blocking"] = value
	return self


func attacking(value: bool = true):
	extra["is_attacking"] = value
	return self


func damaged(value: bool = true):
	extra["is_damaged"] = value
	return self


func with_special_ability(value: bool = true):
	extra["has_special_ability"] = value
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


## The deck-search filter vocabulary. Used by search_deck/break_zone windows, which match database dictionaries.
func to_filter() -> Dictionary:
	var out: Dictionary = {}
	if not name_filter.is_empty():
		out["exact_name" if name_exact else "name"] = name_filter
	if not type_filter.is_empty():
		out["type"] = type_filter
	if not category_filter.is_empty():
		out["category"] = category_filter
	if not job_filter.is_empty():
		out["job"] = job_filter
	if not element_filter.is_empty():
		out["element"] = element_filter
	if min_power >= 0:
		out["min_power"] = min_power
	if max_power >= 0:
		out["max_power"] = max_power
	if not any_queries.is_empty():
		var any_list: Array = []
		for query in any_queries:
			if query != null and query.has_method("to_filter"):
				any_list.append(query.to_filter())
		if not any_list.is_empty():
			out["any"] = any_list
	return out


## The legacy predicate block consumed by CardTarget.matches().
func to_block() -> Dictionary:
	var block: Dictionary = extra.duplicate(true)
	if not type_filter.is_empty():
		block["is_type"] = type_filter
	if not element_filter.is_empty():
		block["is_element"] = element_filter
	if not name_filter.is_empty():
		block["is_named"] = name_filter
	if not category_filter.is_empty():
		block["is_category"] = category_filter
	if not job_filter.is_empty():
		block["is_job"] = job_filter
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
	if not any_queries.is_empty():
		var any_list: Array = []
		for query in any_queries:
			if query != null and query.has_method("to_block"):
				any_list.append(query.to_block())
		if not any_list.is_empty():
			block["any"] = any_list
	if not excludes.is_empty():
		var list: Array = []
		for query in excludes:
			if query != null and query.has_method("to_block"):
				list.append(query.to_block())
		if not list.is_empty():
			block["exclude"] = list
	return block
