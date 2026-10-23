extends Node
## TEST GROUNDS probe — every registered ground must (a) describe itself, (b) build a config the game accepts, and
## (c) actually produce the board it claims. The last one boots a real game per ground, because a config that looks
## right and a board that starts are different things.

const GAME_SCENE := preload("res://game.tscn")
const GROUNDS := preload("res://scripts/test_grounds.gd")

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Grounds] ok   %s" % what)
	else:
		_fails += 1
		print("[Grounds] FAIL %s" % what)


func _valid_ids(ids: Array, what: String) -> bool:
	for id in ids:
		var n: int = int(id)
		if n < 1 or n > CardDatabase.card_database.size():
			push_error("[Grounds] %s has an out-of-range card id %d" % [what, n])
			return false
	return true


func _ready() -> void:
	var names: Array = GROUNDS.names()
	_expect(names.size() >= 4, "at least four grounds are registered (%d)" % names.size())

	# Every preset the menu will show: the grounds plus the general matches.
	var presets: Array = MatchSetup.get_presets()
	for name in names:
		_expect(presets.has(name), "'%s' is listed in the menu presets" % name)
		_expect(not MatchSetup.describe_preset(name).is_empty(), "and it describes itself")

	for name in names:
		var cfg: Dictionary = MatchSetup.build_config(name)
		var deck_ok: bool = _valid_ids(cfg.get("player_deck", []), "%s player_deck" % name) \
			and _valid_ids(cfg.get("opponent_deck", []), "%s opponent_deck" % name)
		var hand_ok: bool = _valid_ids(cfg.get("player_hand", []), "%s player_hand" % name) \
			and _valid_ids(cfg.get("opponent_hand", []), "%s opponent_hand" % name)
		var field_ok: bool = true
		for entry in cfg.get("player_field", []) + cfg.get("opponent_field", []):
			if not _valid_ids([entry.get("id", 0)], "%s field" % name):
				field_ok = false
		_expect(deck_ok, "'%s' decks are all real card ids" % name)
		_expect(hand_ok, "'%s' hands are all real card ids" % name)
		_expect(field_ok, "'%s' board cards are all real card ids" % name)
		_expect(not cfg.get("player_deck", []).is_empty(), "'%s' has a player deck to draw from" % name)

	# --- the claims each ground makes --------------------------------------------------------------------
	var party: Dictionary = GROUNDS.party_you_attack()
	var party_ids: Array = []
	for e in party["player_field"]:
		party_ids.append(int(e["id"]))
	_expect(party_ids.has(GROUNDS.ICE_A) and party_ids.has(GROUNDS.ICE_B),
		"the party ground gives the player the ice pair")
	_expect(party["opponent_hand"].is_empty(),
		"and the opponent has NO hand, so it cannot cast anything mid-test")

	var blocking: Dictionary = GROUNDS.party_ai_attacks()
	var ai_ids: Array = []
	for e in blocking["opponent_field"]:
		ai_ids.append(int(e["id"]))
	_expect(ai_ids.has(GROUNDS.ICE_A) and ai_ids.has(GROUNDS.ICE_B),
		"the blocking ground gives the AI the ice pair")
	_expect(blocking["opponent_hand"].is_empty(), "and an empty hand, so it only attacks")

	var summons: Dictionary = GROUNDS.summons_and_targeting()
	_expect(summons["opponent_hand"].has(GROUNDS.IFRIT), "the summons ground gives the AI Ifrit")
	var player_ids: Array = []
	for e in summons["player_field"]:
		player_ids.append(int(e["id"]))
	_expect(player_ids.has(GROUNDS.ZIDANE), "and puts Zidane on the player's board")

	var zone: Dictionary = GROUNDS.break_zone()
	_expect(zone["player_hand"].has(GROUNDS.BAHAMUT), "the break-zone ground puts Bahamut in hand")

	# --- boot one for real -------------------------------------------------------------------------------
	# The party ground is the one that must not move on its own, so it is the most useful smoke test.
	MatchSetup.config = MatchSetup.build_config("party")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.get("field")
	_expect(field.get_front_cards_for("player").size() == 3,
		"the party ground starts with three player Forwards (%d)" % field.get_front_cards_for("player").size())
	_expect(field.get_front_cards_for("opponent").size() == 3,
		"and three opponent Forwards (%d)" % field.get_front_cards_for("opponent").size())
	_expect(game.get("opponent_agent") != null, "the opponent agent was created")
	_expect(not (game.get("opponent_agent") is AIAgent),
		"the party ground's opponent is MOCK, so it will not act while you test")

	print("[Grounds] %d checks | failures: %d" % [_checks, _fails])
	print("[Grounds] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
