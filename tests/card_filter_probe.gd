extends Node
## Verifies CardFilter against REAL cards from the database, because the whole point of the predicate is that
## a card effect and the deck editor's UI agree about what "power at least 5000" means. Guessing at a fixture
## would test my assumptions instead of the data.
##
## Run: godot --headless res://tests/card_filter_probe.tscn --quit-after 400

const FILTER := preload("res://scripts/card_filter.gd")
const CARD_DATABASE := "res://assets/card_database.json"

## 1-115C, Geomancer: a Backup of category III, job "Standard Unit", element 土.
const GEOMANCER := 115

var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	var db: Array = _load_database()
	if db.is_empty():
		push_error("[CardFilterProbe] no card database")
		get_tree().quit(1)
		return

	var geo: Dictionary = FILTER.card_by_id(GEOMANCER)
	_expect(not geo.is_empty(), "card_by_id finds a real card")
	_expect(str(geo.get("code", "")) == "1-115C", "and it is the card we think it is (%s)" % str(geo.get("code", "")))
	_expect(FILTER.card_by_id(0).is_empty(), "id 0 is not a card")
	_expect(FILTER.card_by_id(db.size() + 1).is_empty(), "nor is an id past the end")

	# --- an empty filter is not a filter ---------------------------------------------------
	_expect(FILTER.filter_cards(db, {}).size() == db.size(),
		"an empty filter keeps every card (%d)" % FILTER.filter_cards(db, {}).size())
	_expect(not FILTER.matches({}, {}), "and an empty CARD never matches, even with no filter")

	# --- name: the code or the English name, either casing ---------------------------------
	var by_name: Array = FILTER.filter_cards(db, {"name": "geomancer"})
	_expect(by_name.size() >= 1, "name matches the English name, case-insensitively (%d)" % by_name.size())
	_expect(_ids_of(by_name).has(GEOMANCER), "and that includes 1-115C")
	var by_code: Array = FILTER.filter_cards(db, {"name": "1-115"})
	_expect(_ids_of(by_code).has(GEOMANCER), "and the printed code works too")
	_expect(FILTER.filter_cards(db, {"name": "zzzznope"}).is_empty(), "a name nobody has matches nothing")

	# --- the exact fields ------------------------------------------------------------------
	var backups: Array = FILTER.filter_cards(db, {"type": "Backup"})
	_expect(backups.size() > 0, "type matches exactly (%d Backups)" % backups.size())
	_expect(FILTER.filter_cards(db, {"type": "backup"}).is_empty(),
		"but type is case-SENSITIVE, because it comes from a dropdown rather than a text box")
	var iii: Array = FILTER.filter_cards(db, {"category": "III"})
	_expect(_ids_of(iii).has(GEOMANCER), "category matches the FF title")
	var standard: Array = FILTER.filter_cards(db, {"job": "standard unit"})
	_expect(_ids_of(standard).has(GEOMANCER), "job matches as a substring, case-insensitively")

	# --- element, by key or by English name ------------------------------------------------
	var by_key: Array = FILTER.filter_ids(_ids_of(db), {"element": "土"})
	var by_alias: Array = FILTER.filter_ids(_ids_of(db), {"element": "earth"})
	# filter_ids returns IDS, so these compare ids directly — running them through _ids_of() would ask a
	# dictionary-shaped question of an int.
	_expect(by_key.has(GEOMANCER), "element matches the database key")
	_expect(by_key.size() == by_alias.size(),
		"and the English alias gives the same answer (%d vs %d)" % [by_key.size(), by_alias.size()])
	_expect(not by_key.is_empty(), "and there are earth cards to find (%d)" % by_key.size())

	# --- power bounds, inclusive -----------------------------------------------------------
	var big: Array = FILTER.filter_cards(db, {"min_power": 9000})
	_expect(big.size() > 0 and big.size() < db.size(), "min_power narrows the field (%d of %d)" % [big.size(), db.size()])
	for card in big:
		if FILTER.power_of(card) < 9000:
			_expect(false, "min_power let through a %d" % FILTER.power_of(card))
			break
	_expect(FILTER.filter_cards(db, {"min_power": 9000, "max_power": 9000}).size() > 0,
		"a min and max that are equal still matches — the bounds are INCLUSIVE")
	var none: Array = FILTER.filter_cards(db, {"min_power": 99000})
	_expect(none.is_empty(), "an impossible min_power matches nothing")

	# --- combining, which is the case a card effect actually uses ---------------------------
	var combo: Array = FILTER.filter_cards(db, {
		"type": "Backup", "element": "earth", "job": "standard unit", "max_power": 0,
	})
	_expect(_ids_of(combo).has(GEOMANCER), "every constraint is ANDed together (%d matched)" % combo.size())
	var narrowed: Array = FILTER.filter_cards(db, {"max_power": 0})
	_expect(narrowed.size() < db.size(), "max_power 0 matches the cards with no power (%d)" % narrowed.size())

	# --- unknown keys are ignored, not fatal -----------------------------------------------
	_expect(FILTER.filter_cards(db, {"nonsense": 1}).size() == db.size(),
		"an unknown key is ignored rather than rejecting everything")

	# --- filter_ids, which is what a deck list actually needs -------------------------------
	var deck := [GEOMANCER, 1, 2, 3]
	var hits: Array = FILTER.filter_ids(deck, {"name": "geomancer"})
	_expect(hits == [GEOMANCER], "filter_ids keeps the ids, in order (%s)" % str(hits))

	print("[CardFilterProbe] %d checks | failures: %d" % [_checks, _failures])
	print("[CardFilterProbe] RESULT: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)

func _load_database() -> Array:
	var file := FileAccess.open(CARD_DATABASE, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary) or not parsed.has("cards"):
		return []
	return parsed["cards"]

## The database ids of a list of card dictionaries, so a check can ask "is this card in there".
func _ids_of(cards: Array) -> Array:
	var out: Array = []
	for card in cards:
		out.append(int(card.get("id", 0)))
	return out

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[CardFilterProbe] ok   %s" % what)
	else:
		_failures += 1
		print("[CardFilterProbe] FAIL %s" % what)
