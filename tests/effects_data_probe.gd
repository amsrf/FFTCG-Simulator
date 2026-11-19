extends Node
## EFFECTS DATA probe — coverage report + a validator for the silent-failure class.
##
## Card abilities are code (assets/effects/card_<id>.gd); the per-card JSON file is gone. A few code effects still
## hand the instruction executor a list (a status's "on_enter_break_zone" payload, e.g. Cid 72/73, Rygdea 211), and
## a typo there is invisible: the card loads and the instruction only fails when it fires, as a push_error nobody
## reads. This finds every such entry in the code effects and checks its (author, name) resolves to a real method.
##
## It also prints coverage for 1-100 so progress is measurable rather than remembered.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

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

	var db = CardDatabase.card_database
	var code_ids: Dictionary = {}
	for file_name in DirAccess.get_files_at("res://assets/effects"):
		if not file_name.begins_with("card_") or not file_name.ends_with(".gd"):
			continue
		var stem: String = file_name.trim_prefix("card_").trim_suffix(".gd")
		if stem.is_valid_int():
			code_ids[int(stem)] = true

	# --- coverage ----------------------------------------------------------------------------------------
	# Two ranges, because they are tracked separately: 1-100 is finished; 100-216 is in progress and its
	# "still to write" list is the roadmap of cards that need new engine vocabulary.
	for span in [Vector2i(1, 100), Vector2i(101, 216)]:
		var covered: Array = []
		var vanilla: Array = []
		var missing: Array = []
		for i in range(span.x, span.y + 1):
			if code_ids.has(i):
				covered.append(i)
			elif str(db[i - 1].get("text_en", "")).strip_edges().is_empty():
				vanilla.append(i)
			else:
				missing.append(i)
		print("[Effects] %d-%d coverage: %d have an entry, %d are vanilla (no text), %d still to write" % [
			span.x, span.y, covered.size(), vanilla.size(), missing.size()])
		if span.x == 101:
			print("[Effects] 101-216 still to write: %s" % str(missing))

	# --- validate every instruction entry a code effect still hands the executor ---------------------------
	var entry_pattern := RegEx.create_from_string('\\{\\s*"name"\\s*:\\s*"(\\w+)"\\s*,\\s*"author"\\s*:\\s*"(\\w+)"')
	var bad: Array = []
	var instructions: int = 0
	for file_name in DirAccess.get_files_at("res://assets/effects"):
		if not file_name.ends_with(".gd"):
			continue
		var source: String = FileAccess.get_file_as_string("res://assets/effects/" + file_name)
		for m in entry_pattern.search_all(source):
			instructions += 1
			var what: String = m.get_string(1)
			var who: String = m.get_string(2)
			if not _executors.has(who):
				bad.append("%s: unknown author '%s' for '%s'" % [file_name, who, what])
				continue
			var target = _executors[who]
			if target == null or not target.has_method(what):
				bad.append("%s: '%s' has no method '%s'" % [file_name, who, what])
	print("[Effects] %d instruction entries in code effects" % instructions)
	_expect(instructions > 0, "the status-payload instruction entries were found (Cid 72/73, 192, Rygdea 211)")
	_expect(bad.is_empty(), "every instruction name resolves to a real method %s" % ("" if bad.is_empty() else str(bad)))
	_expect(not FileAccess.file_exists("res://assets/card_effects.json"), "the per-card JSON effects file is gone")

	print("[Effects] %d checks | failures: %d" % [_checks, _fails])
	print("[Effects] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()

