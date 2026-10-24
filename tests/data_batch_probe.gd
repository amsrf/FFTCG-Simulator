extends Node
## DATA BATCH probe — the cards that needed only small vocabulary additions:
##   9  Cloud      +2000 while you control another Category VII Forward; ETB 2000 to an opponent's Forward
##   20 Fang       Bahamut costs 2 less; when Fang attacks she gains First Strike
##   61 Alexander  choose a Forward of cost 5 or more and break it
##   80 Bartz      ETB: activate all your Wind Characters
##   58 Laguna     "deals damage to your opponent" trigger must not open an EMPTY targeting session

const GAME_SCENE := preload("res://game.tscn")

const CLOUD := 9
const TIFA := 16
const FANG := 20
const BAHAMUT := 18
const BARTZ := 80
const ALEXANDER := 61
const LAGUNA := 58
const TERRA_47 := 47        # cost 4 — NOT a legal Alexander target
const EVOKER := 68         # wind Backup
const CHEMIST := 31        # ice Backup

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[DataBatch] ok   %s" % what)
	else:
		_fails += 1
		print("[DataBatch] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [
			{"id": CLOUD}, {"id": TIFA}, {"id": FANG}, {"id": BARTZ},
			{"id": EVOKER, "tapped": true}, {"id": CHEMIST, "tapped": true},
		],
		"opponent_field": [{"id": TERRA_47}, {"id": LAGUNA}],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	var stack = _game.get("stack")

	# --- 9 Cloud: the Category VII conditional -----------------------------------------------------------
	var cloud: Card = null
	var tifa: Card = null
	for c in _field.get_front_cards_for("player"):
		if c.id == CLOUD:
			cloud = c
		elif c.id == TIFA:
			tifa = c
	_expect(cloud != null and tifa != null, "Cloud and Tifa are on the board")
	_expect(cloud.power == 5000 + 2000, "Cloud is +2000 while another Category VII Forward is out (%d)" % cloud.power)
	_field.remove_card(tifa)
	_expect(cloud.power == 5000, "and loses it when that Forward leaves (%d)" % cloud.power)

	# --- 20 Fang: cost reduction + First Strike on attack -------------------------------------------------
	var fang: Card = null
	for c in _field.get_front_cards_for("player"):
		if c.id == FANG:
			fang = c
	var bahamut: Card = _game.call("create_card", BAHAMUT, "player")
	_game.add_child(bahamut)
	var reduced: Dictionary = _field.effective_cost(bahamut)
	var total: int = 0
	for v in reduced.values():
		total += int(v)
	print("[DataBatch] Bahamut printed %s -> with Fang %s" % [str(bahamut.get_cost()), str(reduced)])
	_expect(bahamut.get_cost() != reduced, "Fang reduces Bahamut's cost")
	_expect(total == 9 - 2, "by exactly 2 (9 -> %d)" % total)
	_field.execute_card_effect(fang, "when_attack")
	await get_tree().process_frame
	await stack.resolve_top_effect()
	_expect(fang.is_first_strike(), "and attacking gives Fang First Strike")

	# --- 61 Alexander: cost 5 or more only ----------------------------------------------------------------
	var alexander: Card = _game.call("create_card", ALEXANDER, "player")
	_game.add_child(alexander)
	_expect(_field.has_viable_target({"is_type": "Forward", "is_cost_at_least": 5}, alexander, "Summon"),
		"Alexander finds a legal target among cost 4 and cost 5")
	_field.set_viable_targets({"is_type": "Forward", "is_cost_at_least": 5}, alexander, "Summon")
	var terra: Card = null
	var laguna: Card = null
	for c in _field.get_front_cards_for("opponent"):
		if c.id == TERRA_47:
			terra = c
		elif c.id == LAGUNA:
			laguna = c
	_expect(laguna != null and laguna.is_valid_target, "the cost-5 Forward IS legal")
	_expect(terra != null and not terra.is_valid_target, "the cost-4 Forward is NOT")
	_field.reset_targets()

	# --- 80 Bartz: activate all Wind Characters ------------------------------------------------------------
	var bartz: Card = null
	var evoker: Card = null
	var chemist: Card = null
	for c in _field.get_all_cards():
		if c.id == BARTZ:
			bartz = c
		elif c.id == EVOKER:
			evoker = c
		elif c.id == CHEMIST:
			chemist = c
	bartz.tap()
	_expect(evoker.tapped and chemist.tapped, "the wind Backup and the wind Forward both start dull")
	_field.execute_card_effect(bartz, "when_enter_field")
	await get_tree().process_frame
	await stack.resolve_top_effect()
	print("[DataBatch] after Bartz: bartz tapped=%s, evoker tapped=%s, chemist tapped=%s" % [
		str(bartz.tapped), str(evoker.tapped), str(chemist.tapped)])
	_expect(not evoker.tapped, "the Wind Backup is activated")
	_expect(chemist.tapped, "the non-Wind Backup stays dull")

	# --- 58 Laguna: no dull Forward means NO targeting session --------------------------------------------
	_expect(not terra.tapped and not laguna.tapped, "no opponent Forward is dull")
	_field.execute_card_effect(laguna, "when_cause_damage_to_player")
	await get_tree().process_frame
	_expect(GlobalVariables.get_player_mode() != GlobalVariables.Player_Mode.TARGET,
		"the 'deals damage' trigger does not open an empty targeting session")
	_expect(stack.stack_length() == 1, "it still queues its effect (%d)" % stack.stack_length())
	await stack.resolve_top_effect()
	await get_tree().process_frame
	_expect(stack.stack_length() == 0, "which resolves harmlessly")
	_expect(terra.accumulated_damage == 0 and laguna.accumulated_damage == 0,
		"dealing no damage to anything")

	print("[DataBatch] %d checks | failures: %d" % [_checks, _fails])
	print("[DataBatch] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
