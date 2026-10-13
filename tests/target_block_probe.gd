extends Node
## TARGET BLOCKS — the shared evaluator behind choose_target and aura targets (scripts/card_target.gd).
##
## It exists because there used to be two matchers with two schemas, and the practical fallout was that "named Aerith"
## could only be said in one of them AND a session key like `count` made every candidate illegal in the other, silently.
## So these checks are mostly about the three KINDS of key and about not regressing the old spellings.
##
##   godot --headless res://tests/target_block_probe.tscn --quit-after 900

const GAME_SCENE := preload("res://game.tscn")
const CARD_TARGET := preload("res://scripts/card_target.gd")

var _checks: int = 0
var _fails: int = 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Target] ok   ", what)
	else:
		_fails += 1
		print("[Target] FAIL ", what)

## A Backup from the database, optionally one whose name is (or is not) `named`.
func _a_backup(named: String, want_that_name: bool) -> int:
	var db: Array = CardDatabase.card_database
	for i in range(db.size()):
		var entry: Dictionary = db[i]
		if str(entry.get("type_en", "")) != "Backup":
			continue
		var matches: bool = str(entry.get("name_en", "")) == named
		if matches == want_that_name:
			return i + 1
	return 0

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.field

	var aerith_backup: int = _a_backup("Aerith", true)
	var other_backup: int = _a_backup("Aerith", false)
	print("[Target] Aerith-named Backup id=%d | other Backup id=%d" % [aerith_backup, other_backup])
	_expect(aerith_backup > 0, "the database has a Backup named Aerith")
	_expect(other_backup > 0, "and a Backup that is not")
	if aerith_backup == 0 or other_backup == 0:
		_finish()
		return

	var aerith_card: Card = game.create_card(aerith_backup, "player")
	var other_card: Card = game.create_card(other_backup, "player")
	field.add_child(aerith_card)
	field.add_child(other_card)

	# --- session keys say nothing about a card -----------------------------------------------------------------------
	# This is the one that used to break: `count` was read as a method name, failed, and took every candidate with it.
	_expect(CARD_TARGET.matches(other_card, {"is_type": "Backup", "count": 3}),
		"a session key like count is skipped, not tested against the card")

	# --- the exclude rule -------------------------------------------------------------------------------------------
	var block: Dictionary = {"is_type": "Backup", "exclude": {"is_named": "Aerith"}}
	_expect(CARD_TARGET.matches(other_card, block), "a plain Backup passes an 'other than Aerith' block")
	_expect(not CARD_TARGET.matches(aerith_card, block), "a card named Aerith does not")
	# ...and it is the NAME, not this instance: any other Aerith is excluded too.
	var aerith_copy: Card = game.create_card(aerith_backup, "player")
	field.add_child(aerith_copy)
	_expect(not CARD_TARGET.matches(aerith_copy, block),
		"neither does another copy — the exclusion is by NAME, which is what 'other than Aerith' means")

	# A list of exclusions means "none of these".
	var listed: Dictionary = {"is_type": "Backup", "exclude": [{"is_named": "Aerith"}, {"is_named": "Chemist"}]}
	_expect(CARD_TARGET.matches(other_card, {"is_type": "Backup", "exclude": [{"is_named": "Nobody"}]}),
		"an exclusion list that matches nothing lets everything through")
	_expect(not CARD_TARGET.matches(aerith_card, listed), "and one that matches excludes it")
	_expect(CARD_TARGET.matches(other_card, listed), "while cards in neither list still pass")

	# --- rules about the SOURCE ------------------------------------------------------------------------------------
	_expect(CARD_TARGET.matches(other_card, {"is_type": "Backup", "exclude": {"is_source": true}}, other_card) == false,
		"is_source excludes the card the effect came from")
	_expect(CARD_TARGET.matches(other_card, {"is_type": "Backup", "exclude": {"is_source": true}}, aerith_card),
		"and leaves every other card alone")

	# --- the old spellings still work (the aura data uses them) ------------------------------------------------------
	_expect(CARD_TARGET.matches(other_card, {"type": "Backup"}), "type is accepted as a spelling of is_type")
	_expect(CARD_TARGET.matches(other_card, {"controller": "player"}, other_card),
		"controller compares directly, as it always did")
	_expect(not CARD_TARGET.matches(other_card, {"controller": "opponent"}, other_card),
		"and a mismatched controller still fails")

	# --- an unreadable key is a LOUD failure, never a silent pass ----------------------------------------------------
	_expect(not CARD_TARGET.matches(other_card, {"is_not_a_method": 1}),
		"a key that is not a method fails the match rather than being ignored")

	_finish()

func _finish() -> void:
	print("[Target] %d checks | failures: %d" % [_checks, _fails])
	print("[Target] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0)
