extends Node
## Ultimecia 152: the first static entry rule, plus the unique-name rule it exposed.

const GAME_SCENE := preload("res://game.tscn")

const SQUALL := 41
const CHEMIST := 31
const ZACK := 12
const CHOCOBO := 75
const RED_XIII := 29
const TERRA := 47
const ULTIMECIA := 152

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Ultimecia] ok   %s" % what)
	else:
		_fails += 1
		print("[Ultimecia] FAIL %s" % what)


func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.accumulated_damage = 0
	card.untap()
	return card


## A REAL play: entry rules and unique-name checks run, and summoning sickness applies.
func _play_live(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", true, true)
	return card


func _count_on_field(side: String, card_name: String) -> int:
	var n: int = 0
	for card in _field.get_front_cards_for(side) + _field.get_back_cards_for(side):
		if card != null and card.card_name == card_name:
			n += 1
	return n


func _ready() -> void:
	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/card_effects.json"))
	var rule: Dictionary = effects.get("152", {}).get("on_character_enter", [{}])[0]
	_expect(rule.get("action") == "dull", "Ultimecia 152 has an on_character_enter dull rule")
	_expect(rule.get("targets", {}).get("exclude", {}).get("is_named") == "Ultimecia",
		"and excludes every card named Ultimecia")
	var skill: Dictionary = effects.get("152", {}).get("skill", [{}])[0]
	_expect(skill.get("apply_effect", {}).get("exclude", {}).get("is_named") == "Ultimecia",
		"Time Compression also excludes every Ultimecia")
	_expect(skill.get("instructions", [{}])[0].get("argument", [""])[0] == "frozen",
		"and freezes the chosen Forwards")

	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	# A Forward that was ALREADY on the field when Ultimecia arrives is not touched.
	var older: Card = _make(SQUALL, "player")
	var ult: Card = _play_live(ULTIMECIA, "player")
	_expect(ult.is_on_field() and not ult.tapped, "Ultimecia enters the field active")
	_expect(not older.tapped, "a Forward already on the field stays active")

	# Forwards that enter afterwards arrive dull.
	var late: Card = _play_live(ZACK, "player")
	_expect(late.is_on_field() and late.tapped, "a Forward entering after Ultimecia enters dull")
	var backup: Card = _play_live(CHEMIST, "player")
	_expect(backup.is_on_field() and not backup.tapped, "a Backup entering afterwards is unaffected")

	# The exclusion is by NAME and is global: an opponent's Ultimecia is not dulled by ours.
	var theirs: Card = _play_live(ULTIMECIA, "opponent")
	_expect(theirs.is_on_field() and not theirs.tapped,
		"an opponent's Ultimecia enters active too")

	# Entry-dull beats Haste: Haste ignores summoning sickness, not this.
	var haste: Card = _play_live(CHOCOBO, "player")
	_expect(haste.is_on_field() and haste.tapped, "a Haste Forward still enters dull")

	# The rule disappears with its source — no registry, no teardown.
	_game.call("break_card", ult)
	var after_ours: Card = _play_live(RED_XIII, "player")
	_expect(after_ours.tapped, "the opponent's Ultimecia still dulls entries after ours leaves")
	_game.call("break_card", theirs)
	var after_both: Card = _play_live(TERRA, "player")
	_expect(not after_both.tapped, "with every Ultimecia gone, the next Forward enters active")

	# UNIQUE NAMES, same controller: the new copy never reaches the field.
	var duplicate: Card = _play_live(SQUALL, "player")
	_expect(not duplicate.is_on_field(), "a second copy of a Character you already control never enters")
	_expect(_count_on_field("player", "Squall") == 1, "and exactly one Squall remains on your field")
	_expect(_game.get("player_graveyard").graveyard_cards.has(duplicate) and not duplicate.broken,
		"the new copy goes to the Break Zone without counting as a break")

	# UNIQUE NAMES, different controllers: both are legal.
	var opposite: Card = _play_live(SQUALL, "opponent")
	_expect(opposite.is_on_field() and _count_on_field("opponent", "Squall") == 1,
		"the same name on the opponent's field is legal")

	print("[Ultimecia] %d checks | failures: %d" % [_checks, _fails])
	print("[Ultimecia] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
