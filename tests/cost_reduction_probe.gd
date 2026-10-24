extends Node
## B4a: cost reductions from Category counts and a filtered cost aura.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[B4a] ok   %s" % what)
	else:
		_fails += 1
		print("[B4a] FAIL %s" % what)


func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.accumulated_damage = 0
	card.untap()
	return card


func _off_field(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	return card


func _total(cost: Dictionary) -> int:
	var total: int = 0
	for value in cost.values():
		total += int(value)
	return total


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	# 177 Yuna: Water Summons cost 1 less, never below 1.
	_make(177, "player")
	var fairy: Card = _off_field(170, "player")     # Water Summon, cost 2
	var moogle: Card = _off_field(172, "player")    # Water Summon, cost 1
	var ifrit: Card = _off_field(4, "player")       # Fire Summon, cost 1
	_expect(_total(_field.effective_cost(fairy)) == 1, "Yuna reduces a 2-cost Water Summon to 1")
	_expect(_total(_field.effective_cost(moogle)) == 1, "a 1-cost Water Summon cannot become 0")
	_expect(_total(_field.effective_cost(ifrit)) == 1, "the Water-only aura does not touch a Fire Summon")

	# 187 Cloud: Category VII Forwards reduce its cost.
	_make(9, "player")       # Cloud, Category VII
	_make(12, "player")      # Zack, Category VII
	var cloud: Card = _off_field(187, "player")
	var cloud_cost: Dictionary = _field.effective_cost(cloud)
	_expect(_total(cloud_cost) == 4 and int(cloud_cost.get("neutral", 0)) == 3,
		"Cloud costs 4 with two Category VII Forwards (6 - 2)")
	# An opponent's Category VII Forward must not count.
	_make(16, "opponent")    # Tifa, Category VII
	_expect(_total(_field.effective_cost(cloud)) == 4, "the opponent's Category VII Forward does not count")

	# 210 Lightning: Category XIII Forwards reduce its cost.
	_make(43, "player")      # Snow, Category XIII
	_make(7, "player")       # Gadot, Category XIII
	var lightning: Card = _off_field(210, "player")
	_expect(_total(_field.effective_cost(lightning)) == 4,
		"Lightning costs 4 with two Category XIII Forwards")

	# 213 Tidus: Category X Forwards reduce its cost.
	_make(51, "player")      # Nooj, Category X
	_make(90, "player")      # Rikku, Category X
	var tidus: Card = _off_field(213, "player")
	_expect(_total(_field.effective_cost(tidus)) == 4,
		"Tidus costs 4 with two Category X Forwards")

	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/card_effects.json"))
	_expect(bool(effects.get("177", {}).get("cost_aura", {}).get("element") == "水"),
		"Yuna's aura is filtered to Water")
	_expect(int(effects.get("187", {}).get("self_cost", {}).get("delta", 0)) == -1,
		"Cloud's cost reduction is data")
	_expect(bool(effects.get("210", {}).get("haste", false))
		and effects.get("210", {}).has("when_cause_damage_to_player"),
		"Lightning has Haste and the damage trigger")
	_expect(bool(effects.get("187", {}).get("skill", [{}])[0].get("s_cost", false)),
		"Cloud's Climhazzard is an S ability")

	print("[B4a] %d checks | failures: %d" % [_checks, _fails])
	print("[B4a] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
