extends Node
## EFFECTS DATA probe — coverage report + a validator for the silent-failure class.
##
## Card abilities are code (assets/effects/card_<id>.gd): the per-card JSON file and the instruction executor are gone.
## What a typo could still hide is a status payload's "on_enter_break_zone" METHOD NAME (Cid 72/73, Cid Raines 192,
## Rygdea 211): the card loads and the name only fails when the marked card reaches the Break Zone. This checks every
## such name exists on the card's own effect, and that no instruction-style entry ({"name": ..., "author": ...}) is
## left in any code effect (nothing would run it).
##
## It also prints coverage for 1-100 so progress is measurable rather than remembered.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


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

	# --- no instruction entries left (nothing runs them), and every payload method exists ------------------
	var entry_pattern := RegEx.create_from_string('\\{\\s*"name"\\s*:\\s*"\\w+"\\s*,\\s*"author"')
	var payload_pattern := RegEx.create_from_string('"on_enter_break_zone"\\s*:\\s*"(\\w+)"')
	var leftovers: Array = []
	var bad_methods: Array = []
	var payloads: int = 0
	for file_name in DirAccess.get_files_at("res://assets/effects"):
		if not file_name.ends_with(".gd"):
			continue
		var path: String = "res://assets/effects/" + file_name
		var source: String = FileAccess.get_file_as_string(path)
		if entry_pattern.search(source) != null:
			leftovers.append(file_name)
		for m in payload_pattern.search_all(source):
			payloads += 1
			var effect_obj = load(path).new()
			if not effect_obj.has_method(m.get_string(1)):
				bad_methods.append("%s: no method '%s'" % [file_name, m.get_string(1)])
	print("[Effects] %d on_enter_break_zone payload(s) in code effects" % payloads)
	_expect(leftovers.is_empty(), "no instruction-style entries are left in code effects %s" % ("" if leftovers.is_empty() else str(leftovers)))
	_expect(payloads >= 4, "the status payloads were found (Cid 72/73, Cid Raines 192, Rygdea 211)")
	_expect(bad_methods.is_empty(), "every payload names a method its card's effect has %s" % ("" if bad_methods.is_empty() else str(bad_methods)))
	_expect(not FileAccess.file_exists("res://assets/card_effects.json"), "the per-card JSON effects file is gone")
	_expect(not _game.has_method("_execute_instructions"), "the instruction executor is gone")

	print("[Effects] %d checks | failures: %d" % [_checks, _fails])
	print("[Effects] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()

