extends Node
## POWER_PER probe — count-based continuous power:
##   15 Jecht       +1000 for each Forward the opponent controls
##   92 Dark Knight +1000 for each point of damage you have received
##   98 Gabranth    the same, plus Brave at 6+
##
## The point of the mechanism is the LEDGER: the rule's contribution is tracked and only the difference is applied,
## so recomputing never erases a temporary buff, and the count is read live from the board.

const GAME_SCENE := preload("res://game.tscn")

const JECHT := 15
const DARK_KNIGHT := 92
const GABRANTH := 98
const SQUALL := 41
const SNOW := 43
const KNIGHT_55 := 55
const ZACK := 12

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[PowerPer] ok   %s" % what)
	else:
		_fails += 1
		print("[PowerPer] FAIL %s" % what)


func _card(id: int) -> Card:
	for c in _field.get_all_cards():
		if c.id == id:
			return c
	return null


func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	return card


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": DARK_KNIGHT}, {"id": GABRANTH}, {"id": JECHT}],
		"opponent_field": [{"id": SQUALL}, {"id": SNOW}, {"id": KNIGHT_55}],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	var jecht: Card = _card(JECHT)
	var knight: Card = _card(DARK_KNIGHT)
	var gabranth: Card = _card(GABRANTH)
	print("[PowerPer] start: Jecht %d, Dark Knight %d, Gabranth %d (damage %d, opponent Forwards %d)" % [
		jecht.power, knight.power, gabranth.power,
		_game.get("player").damage_count(), _field.get_front_cards_for("opponent").size()])

	# --- Jecht counts the OPPONENT's Forwards ---------------------------------------------------------------
	_expect(jecht.power == 8000 + 3 * 1000, "Jecht starts at 8000 + 1000 per opponent Forward (3 → 11000)")
	_expect(knight.power == 3000, "Dark Knight starts at its base 3000 (no damage yet)")
	_expect(gabranth.power == 8000, "Gabranth starts at its base 8000")

	var fourth: Card = _make(ZACK, "opponent")
	_expect(jecht.power == 12000, "a fourth opponent Forward raises Jecht to 12000 (%d)" % jecht.power)
	_field.remove_card(fourth)
	_expect(jecht.power == 11000, "and removing it brings him back to 11000 (%d)" % jecht.power)

	# --- Dark Knight / Gabranth count YOUR damage -----------------------------------------------------------
	var player = _game.get("player")
	player.take_damage(5)
	await get_tree().process_frame
	print("[PowerPer] after 5 damage: Knight %d, Gabranth %d, brave %s" % [
		knight.power, gabranth.power, str(gabranth.is_brave())])
	_expect(player.damage_count() == 5, "five cards are in the damage zone (%d)" % player.damage_count())
	_expect(knight.power == 3000 + 5000, "Dark Knight is 3000 + 1000 per damage (8000)")
	_expect(gabranth.power == 8000 + 5000, "Gabranth is 8000 + 5000 (13000)")
	_expect(not gabranth.is_brave(), "and has no Brave below 6 damage")

	# A temporary buff must SURVIVE a recompute — this is what the ledger buys.
	knight.power_change(2000, 1)
	_expect(knight.power == 10000, "a +2000 buff takes Dark Knight to 10000 (%d)" % knight.power)
	player.take_damage(1)
	await get_tree().process_frame
	print("[PowerPer] after 6 damage: Knight %d, Gabranth %d, brave %s" % [
		knight.power, gabranth.power, str(gabranth.is_brave())])
	_expect(knight.power == 3000 + 6000 + 2000,
		"the 6th damage adds 1000 ON TOP of the buff, not instead of it (%d)" % knight.power)
	_expect(gabranth.power == 8000 + 6000, "Gabranth reaches 14000")
	_expect(gabranth.is_brave(), "and gains Brave at 6 damage")

	# --- leaving the field unregisters cleanly --------------------------------------------------------------
	var before: int = _field.get("_power_per_effects").size()
	_field.remove_card(gabranth)
	_expect(_field.get("_power_per_effects").size() == before - 1,
		"removing Gabranth drops its rule (%d → %d)" % [before, _field.get("_power_per_effects").size()])
	_expect(jecht.power == 11000 and knight.power == 11000,
		"and leaves the other cards' rules untouched (Jecht %d, Knight %d)" % [jecht.power, knight.power])

	print("[PowerPer] %d checks | failures: %d" % [_checks, _fails])
	print("[PowerPer] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
