extends Node
## EFFECTS DATA probe — coverage report + a validator for the silent-failure class.
##
## A typo in card_effects.json is invisible: the entry parses, the card loads, and the instruction only fails when
## that card actually resolves, as a push_error nobody reads. This walks every entry and checks that each
## instruction's (author, name) pair actually exists on the thing it will be dispatched to.
##
## It also prints coverage for 1-100 so progress is measurable rather than remembered.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _executors: Dictionary = {}


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Effects] ok   %s" % what)
	else:
		_fails += 1
		print("[Effects] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	var sample: Card = _game.create_card(1, "player")
	_executors = {
		"game": _game,
		"field": _game.get("field"),
		"hand": _game.get("hand"),
		"deck": _game.get_node("Player/Deck"),
		"assistant": _game.get("assistant"),
		"player": _game.get_node("Player"),
		"opponent": _game.get_node("Opponent"),
		"card": sample,
		"target": sample,
	}

	var effects: Dictionary = CardDatabase.card_effects
	var db = CardDatabase.card_database

	# --- coverage ----------------------------------------------------------------------------------------
	# Two ranges, because they are tracked separately: 1-100 is finished; 100-216 is in progress and its
	# "still to write" list is the roadmap of cards that need new engine vocabulary.
	for span in [Vector2i(1, 100), Vector2i(101, 216)]:
		var covered: Array = []
		var vanilla: Array = []
		var missing: Array = []
		for i in range(span.x, span.y + 1):
			if effects.has(str(i)):
				covered.append(i)
			elif str(db[i - 1].get("text_en", "")).strip_edges().is_empty():
				vanilla.append(i)
			else:
				missing.append(i)
		print("[Effects] %d-%d coverage: %d have an entry, %d are vanilla (no text), %d still to write" % [
			span.x, span.y, covered.size(), vanilla.size(), missing.size()])
		if span.x == 101:
			print("[Effects] 101-216 still to write: %s" % str(missing))

	# --- validate every instruction in the file ----------------------------------------------------------
	var bad: Array = []
	var instructions: int = 0
	for key in effects.keys():
		if not (str(key).is_valid_int() and int(key) >= 1 and int(key) <= db.size()):
			bad.append("%s: key is not a card id" % str(key))
			continue
		for instr in _instructions_in(effects[key]):
			instructions += 1
			var who: String = str(instr.get("author", ""))
			var what: String = str(instr.get("name", ""))
			if not _executors.has(who):
				bad.append("%s: unknown author '%s' for '%s'" % [key, who, what])
				continue
			var target = _executors[who]
			if target == null or not target.has_method(what):
				bad.append("%s: '%s' has no method '%s'" % [key, who, what])
	_expect(instructions > 0, "the file contains instructions to validate (%d)" % instructions)
	_expect(bad.is_empty(), "every instruction name resolves to a real method %s" % ("" if bad.is_empty() else str(bad)))

	print("[Effects] %d checks | failures: %d" % [_checks, _fails])
	print("[Effects] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()


## Every dict in `node` that looks like an instruction ({name, author, argument}).
func _instructions_in(node) -> Array:
	var found: Array = []
	if node is Dictionary:
		if node.has("name") and node.has("author"):
			found.append(node)
		for v in node.values():
			found.append_array(_instructions_in(v))
	elif node is Array:
		for v in node:
			found.append_array(_instructions_in(v))
	return found
