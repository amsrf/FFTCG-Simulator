extends Node
## WARRIOR OF LIGHT probe — card 5: "If Warrior of Light deals damage to a Forward of cost 4 or more, double the
## damage instead."
##
## The doubling is applied BEFORE the damage lands (Field.modify_damage) and only when the DEALING card is the source,
## so it must not fire for other attackers, for effect damage from another card, or against a cheaper Forward.

const GAME_SCENE := preload("res://game.tscn")

const WOL := 5              # Forward, 5000, cost 2
const TERRA := 47           # Forward, 7000, cost 4 → doubled
const SQUALL := 41          # Forward, 6000, cost 3 → NOT doubled
const IFRIT := 4            # Summon (not a Forward dealer)

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[WoL] ok   %s" % what)
	else:
		_fails += 1
		print("[WoL] FAIL %s" % what)


func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	return card


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": WOL}],
		"opponent_field": [{"id": TERRA}, {"id": SQUALL}],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	var wol: Card = null
	for c in _field.get_front_cards_for("player"):
		if c.id == WOL:
			wol = c
	var terra: Card = null
	var squall: Card = null
	for c in _field.get_front_cards_for("opponent"):
		if c.id == TERRA:
			terra = c
		elif c.id == SQUALL:
			squall = c
	_expect(wol != null and terra != null and squall != null, "the board is set up")

	# --- the modifier itself ------------------------------------------------------------------------------
	var ifrit: Card = _game.call("create_card", IFRIT, "player")
	_game.add_child(ifrit)
	print("[WoL] modify: vs cost-4 %d, vs cost-3 %d, other dealer %d" % [
		_field.modify_damage(wol, terra, 5000),
		_field.modify_damage(wol, squall, 5000),
		_field.modify_damage(ifrit, terra, 5000)])
	_expect(_field.modify_damage(wol, terra, 5000) == 10000, "against a cost-4 Forward, 5000 becomes 10000")
	_expect(_field.modify_damage(wol, squall, 5000) == 5000, "against a cost-3 Forward it stays 5000")
	_expect(_field.modify_damage(ifrit, terra, 5000) == 5000, "another card's damage is not doubled")
	_expect(_field.modify_damage(wol, terra, 0) == 0, "zero damage stays zero")

	# --- the real combat path -----------------------------------------------------------------------------
	_game.call("clash_cards", wol, terra)
	await get_tree().process_frame
	print("[WoL] clash vs cost-4: Terra took %d (on field %s), WoL took %d" % [
		terra.accumulated_damage, str(terra.is_on_field()), wol.accumulated_damage])
	_expect(terra.accumulated_damage == 10000, "combat applies the doubling (Terra takes 10000, not 5000)")
	_expect(not terra.is_on_field(), "so Terra breaks from a single hit")

	# A second WoL against a cost-3 Forward: 5000 must NOT break a 6000.
	var wol2: Card = _make(WOL, "player")
	_game.call("clash_cards", wol2, squall)
	await get_tree().process_frame
	print("[WoL] clash vs cost-3: Squall took %d (on field %s)" % [
		squall.accumulated_damage, str(squall.is_on_field())])
	_expect(squall.accumulated_damage == 5000, "against the cost-3 Forward combat deals 5000")
	_expect(squall.is_on_field(), "which does not break a 6000 Forward")

	print("[WoL] %d checks | failures: %d" % [_checks, _fails])
	print("[WoL] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
