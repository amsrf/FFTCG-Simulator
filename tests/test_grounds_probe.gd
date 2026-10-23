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

	# The MAIN MENU keeps its everyday presets; the grounds live on their own screen behind "Test Mode".
	var presets: Array = MatchSetup.get_presets()
	_expect(presets == ["custom", "ai", "standard", "debug"],
		"the main menu presets are unchanged (%s)" % str(presets))
	var grounds_listed: Array = MatchSetup.get_test_grounds()
	for name in names:
		_expect(grounds_listed.has(name), "'%s' is listed on the Test Mode screen" % name)
		_expect(not presets.has(name), "and '%s' does NOT clutter the main menu" % name)
		_expect(not MatchSetup.describe_preset(name).is_empty(), "and it describes itself")

	# The Test Mode screen itself: one button per ground, built from the registry.
	var menu_scene: PackedScene = load("res://test_grounds_menu.tscn")
	_expect(menu_scene != null, "the Test Mode scene loads")
	if menu_scene != null:
		var menu: Control = menu_scene.instantiate()
		add_child(menu)
		await get_tree().process_frame
		_expect(menu.call("ground_button_count") == names.size(),
			"it shows one button per ground (%d of %d)" % [menu.call("ground_button_count"), names.size()])
		_expect(str(menu.call("ground_button_text", 0)).begins_with("Ground:"),
			"and the first button is labelled as a ground ('%s')" % menu.call("ground_button_text", 0))
		menu.queue_free()
		await get_tree().process_frame

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
	_expect(ai_ids.has(GROUNDS.BARD) and ai_ids.has(GROUNDS.ICE_A),
		"the blocking ground gives the AI an ice pair")
	_expect(not ai_ids.has(GROUNDS.ICE_B),
		"and NOT Snow — its when-attack dull would disable the very blocker this ground exists to test")
	_expect(blocking["opponent_hand"].is_empty(), "and an empty hand, so it only attacks")

	# THE ACTUAL REGRESSION GUARD: no card the AI attacks with may have a when-attack trigger, and the player must
	# still have a Forward able to block once the party is declared.
	var attackers_are_passive: bool = true
	for id in ai_ids:
		var effects: Dictionary = CardDatabase.card_effects.get(str(int(id)), {})
		if effects.has("when_attack"):
			attackers_are_passive = false
			push_error("[Grounds] the blocking ground's attacker %d has a when_attack effect" % int(id))
	_expect(attackers_are_passive, "no AI attacker has a when-attack trigger that could dull the blocker")

	var blocking_player_ids: Array = []
	for e in blocking["player_field"]:
		blocking_player_ids.append(int(e["id"]))
	_expect(blocking_player_ids.has(GROUNDS.DARK_KNIGHT),
		"and the player has Dark Knight (8000) as a real blocker")

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
	# Three ice/fire Forwards plus the Chocobo + Hope wind pair, so BOTH kinds of party can be built here.
	var player_fronts: Array = field.get_front_cards_for("player")
	_expect(player_fronts.size() == 5,
		"the party ground starts with five player Forwards (%d)" % player_fronts.size())
	var player_front_ids: Array = []
	for c in player_fronts:
		player_front_ids.append(c.id)
	_expect(player_front_ids.has(GROUNDS.CHOCOBO) and player_front_ids.has(GROUNDS.HOPE),
		"including the Chocobo + Hope wind pair, whose party trigger this ground is also for")
	_expect(field.get_front_cards_for("opponent").size() == 3,
		"and three opponent Forwards (%d)" % field.get_front_cards_for("opponent").size())
	_expect(game.get("opponent_agent") != null, "the opponent agent was created")
	_expect(not (game.get("opponent_agent") is AIAgent),
		"the party ground's opponent is MOCK, so it will not act while you test")

	# --- the blocking ground, end to end -------------------------------------------------------------------
	# Boot it, let the real AI declare, execute the attack, and assert the player still has a Forward that can
	# block. This is the regression the ground was fixed for: Snow's when-attack dull used to leave none.
	game.queue_free()
	await get_tree().process_frame
	MatchSetup.config = MatchSetup.build_config("party_ai")
	var blocking_game = GAME_SCENE.instantiate()
	add_child(blocking_game)
	await get_tree().process_frame
	await get_tree().process_frame
	var bfield = blocking_game.get("field")
	var ai = blocking_game.get("opponent_agent")
	_expect(ai is AIAgent, "the blocking ground's opponent is the AI")
	var declared: Array = await ai.decide_attackers(2)
	_expect(declared.size() >= 2, "the AI declares a party there (%d members)" % declared.size())
	bfield.reset_attacker()
	if not declared.is_empty():
		bfield.set_attacker(declared[0])
		for i in range(1, declared.size()):
			bfield.add_party_member(declared[i])
		bfield.execute_card_attack()
	var blockable: int = 0
	for c in bfield.get_front_cards_for("player"):
		if bfield.can_block(c):
			blockable += 1
	print("[Grounds] after the AI's party attack, %d player Forward(s) can still block: %s" % [
		blockable, str(bfield.get_front_cards_for("player").map(func(c): return "%s(tapped=%s)" % [c.card_name, c.tapped]))])
	_expect(blockable > 0, "and you can still block it — the ground's whole purpose")

	print("[Grounds] %d checks | failures: %d" % [_checks, _fails])
	print("[Grounds] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
