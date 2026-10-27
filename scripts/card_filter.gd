extends RefCounted
class_name CardFilter
## Matching cards against a filter dictionary. One predicate, used by the deck editor's UI AND by cards
## whose effects search a deck — so "cards named X with power at least Y" means the same thing in both places
## and cannot drift apart.
##
## The cards passed in are DATABASE DICTIONARIES (the entries of `CardDatabase.card_database`), not `Card`
## nodes. That is what lets a search run over a deck list, a graveyard, or the whole database without any of
## them having to be instantiated first.
##
## A filter may contain any of:
##   name       substring, case-insensitive, matched against the card's code OR its English name
##   min_power  inclusive lower bound on `power`
##   max_power  inclusive upper bound on `power`
##   category   exact match on `category_1` — the Final Fantasy title (VII, XIV, …)
##   type       exact match on `type_en` (Forward / Backup / Summon)
##   job        substring, case-insensitive, matched against `job_en`
##   element    the card has this element. Accepts the database's own key ("火") or its English name ("fire")
##
## An ABSENT key means "no constraint", and so does an empty string. Unknown keys are ignored rather than
## rejected: a caller passing extra context should not get an empty result for it.

## English element names, so a card effect can say "fire" while the database says "火".
const ELEMENT_ALIASES: Dictionary = {
	"fire": "火", "ice": "氷", "wind": "風", "earth": "土",
	"lightning": "雷", "water": "水", "light": "光", "dark": "闇",
}

static func matches(card: Dictionary, filter: Dictionary) -> bool:
	if card.is_empty():
		return false

	# --- any: OR. "search for Lightning OR Snow" — each entry is a complete filter and ONE match is enough. ----
	# The rest of the keys still apply, so `{"any": [...], "type": "Forward"}` reads as "one of those, and a Forward".
	var any_clauses: Array = filter.get("any", [])
	if not any_clauses.is_empty():
		var hit: bool = false
		for clause in any_clauses:
			if clause is Dictionary and matches(card, clause):
				hit = true
				break
		if not hit:
			return false

	# --- exact_name: the Card.matches_criteria("is_named") spelling, used by typed searches ----------
	var exact: String = str(filter.get("exact_name", "")).strip_edges()
	if not exact.is_empty() and str(card.get("name_en", "")) != exact:
		return false

	# --- name: the code OR the English name, because a player may search for either -------------------
	var needle: String = str(filter.get("name", "")).strip_edges().to_lower()
	if not needle.is_empty():
		var code: String = str(card.get("code", "")).to_lower()
		var title: String = str(card.get("name_en", "")).to_lower()
		if not (needle in code or needle in title):
			return false

	if not _exact(card, "type_en", filter, "type"):
		return false
	if not _exact(card, "category_1", filter, "category"):
		return false

	# Job is "contains" rather than equality: there are hundreds of distinct jobs, so anything exact would be
	# unusable as a search.
	var job: String = str(filter.get("job", "")).strip_edges().to_lower()
	if not job.is_empty() and not (job in str(card.get("job_en", "")).to_lower()):
		return false

	var element: String = str(filter.get("element", "")).strip_edges()
	if not element.is_empty() and not has_element(card, element):
		return false

	# Power is stored as a STRING in the database, and is absent on cards that have none — so it is read
	# through one helper rather than being trusted to be an int.
	var power: int = power_of(card)
	if filter.has("min_power") and power < int(filter["min_power"]):
		return false
	if filter.has("max_power") and power > int(filter["max_power"]):
		return false

	return true

## The subset of `cards` that satisfies `filter`, in the original order.
static func filter_cards(cards: Array, filter: Dictionary) -> Array:
	var out: Array = []
	for card in cards:
		if card is Dictionary and matches(card, filter):
			out.append(card)
	return out

## The same thing for card IDS, which is what a deck list and a graveyard actually hold.
static func filter_ids(ids: Array, filter: Dictionary) -> Array:
	var out: Array = []
	for id in ids:
		var card: Dictionary = card_by_id(int(id))
		if matches(card, filter):
			out.append(int(id))
	return out

## The card's power, or 0 when it has none. Values are strings in the database.
static func power_of(card: Dictionary) -> int:
	return int(str(card.get("power", "0")).strip_edges())

## True when the card has `wanted`, which may be the database's own key ("火") or an English name ("fire").
## The card's `element` is a LIST, and any one of its entries matching is enough.
static func has_element(card: Dictionary, wanted: String) -> bool:
	var target: String = str(ELEMENT_ALIASES.get(wanted.to_lower(), wanted))
	var value: Variant = card.get("element")
	if value is Array:
		for entry in value:
			if str(entry) == target:
				return true
		return false
	return str(value) == target

## A database entry by its 1-based id, or {} when there is no such card. Kept here so every caller shares one
## answer to "what is card 115" rather than each indexing the array itself.
static func card_by_id(id: int) -> Dictionary:
	var db: Array = CardDatabase.card_database
	if id < 1 or id > db.size():
		return {}
	var card: Variant = db[id - 1]
	return card if card is Dictionary else {}

## Exact match on a text field, skipped when the filter omits the key or leaves it empty.
static func _exact(card: Dictionary, field: String, filter: Dictionary, key: String) -> bool:
	var wanted: String = str(filter.get(key, "")).strip_edges()
	if wanted.is_empty():
		return true
	return str(card.get(field, "")) == wanted
