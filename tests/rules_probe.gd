extends Node
## RULES probe — the query layer extracted from Field.
##
## Field still exposes the same four methods (forwarders), so callers and older probes do not care. This probe asserts
## the layer is real: Game owns a bound Rules instance, and the rules answer the same questions when asked DIRECTLY.

const GAME_SCENE := preload("res://game.tscn")

const WOL := 5
const TERRA_47 := 47        # cost 4
const TERRA_46 := 46        # ice Forward: cost aura (+1) and cannot be chosen by opponent's Summons
const AURON := 2
const CHEMIST := 31         # Backup protected by Auron
const DAJH := 17
const SAZH := 13
const IFRIT := 4

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Rules] ok   %s" % what)
	else:
		_fails += 1
		print("[Rules] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": WOL}, {"id": AURON}, {"id": CHEMIST}, {"id": DAJH}, {"id": SAZH}],
		"opponent_field": [{"id": TERRA_47}, {"id": TERRA_46}],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = game.get("field")
	var rules = game.get("rules")
	_expect(rules != null, "Game owns a Rules instance")
	_expect(rules.field == field, "bound to the board")
	_expect(rules.game == game, "and to the match")

	var cards: Dictionary = {}
	for c in field.get_all_cards():
		cards[c.id] = c
	var ifrit: Card = game.call("create_card", IFRIT, "player")
	game.add_child(ifrit)

	# --- damage -------------------------------------------------------------------------------------------
	_expect(rules.modify_damage(cards[WOL], cards[TERRA_47], 5000) == 10000,
		"the rules double Warrior of Light's damage to a cost-4 Forward")
	_expect(field.modify_damage(cards[WOL], cards[TERRA_47], 5000)
			== rules.modify_damage(cards[WOL], cards[TERRA_47], 5000),
		"and Field forwards to the same answer")

	# --- cost ----------------------------------------------------------------------------------------------
	var direct: Dictionary = rules.effective_cost(ifrit)
	_expect(int(direct.get("neutral", 0)) == int(ifrit.get_cost().get("neutral", 0)) + 1,
		"the rules apply the opponent's Terra cost aura (%s)" % str(direct))
	_expect(field.effective_cost(ifrit) == direct, "and Field forwards to the same dictionary")

	# --- break protection ----------------------------------------------------------------------------------
	_expect(rules.is_protected_from_break(cards[CHEMIST], "opponent", "Ability"),
		"the rules protect Auron's Backup from the opponent's abilities")
	_expect(field.is_protected_from_break(cards[CHEMIST], "opponent", "Ability"),
		"and Field forwards to the same answer")

	# --- choice protection ---------------------------------------------------------------------------------
	_expect(rules.is_protected_from_being_chosen(cards[SAZH], cards[TERRA_46], "Ability"),
		"the rules shield Sazh from the opponent's abilities (Dajh)")
	_expect(field.is_protected_from_being_chosen(cards[SAZH], cards[TERRA_46], "Ability"),
		"and Field forwards to the same answer")
	_expect(not rules.is_protected_from_being_chosen(cards[SAZH], cards[WOL], "Ability"),
		"but not from your own")

	print("[Rules] %d checks | failures: %d" % [_checks, _fails])
	print("[Rules] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
