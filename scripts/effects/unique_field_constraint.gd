extends "res://scripts/effects/selection_constraint.gd"
## "Each of a different <field>": a card is unavailable when any of its values for `field_name` is already
## represented in the selection. Element and Job are arrays/sets in the database; name and category are scalar-ish.

var field_name: String = "element"


func _init(p_field: String = "element") -> void:
	field_name = p_field


func allows(id: int, selected: Array) -> bool:
	var mine: Array = values_of(id)
	for other_id in selected:
		for value in values_of(int(other_id)):
			if value in mine:
				return false
	return true


func reason(id: int, _selected: Array) -> String:
	var mine: Array = values_of(id)
	if mine.is_empty():
		return ""
	return "%s already chosen" % str(mine[0])


## The values this card contributes to the uniqueness rule.
func values_of(id: int) -> Array:
	var card: Dictionary = CARD_FILTER.card_by_id(id)
	match field_name:
		"element":
			var raw = card.get("element", [])
			if raw is Array:
				return _clean(raw)
			return _clean([str(raw)])
		"job":
			# job_en can be a single job or a comma-separated list; both count as occupied jobs.
			var raw_job: String = str(card.get("job_en", ""))
			var jobs: Array = []
			for part in raw_job.split(","):
				var value: String = part.strip_edges().to_lower()
				if value != "":
					jobs.append(value)
			return jobs
		"category":
			var categories: Array = []
			for key in ["category_1", "category_2", "category_3"]:
				var value: String = str(card.get(key, "")).strip_edges().to_lower()
				if value != "" and not categories.has(value):
					categories.append(value)
			return categories
		"name":
			return _clean([str(card.get("name_en", ""))])
		_:
			return _clean([str(card.get(field_name, ""))])


func _clean(values: Array) -> Array:
	var out: Array = []
	for value in values:
		var text: String = str(value).strip_edges()
		if text != "" and not out.has(text):
			out.append(text)
	return out
