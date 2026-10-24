extends Node
## CID 72/73 probe — a damage rider stored as a STATUS on the damaged Forward.
##
## "When the Forward that took damage from Cid Highwind is put from the field into the Break Zone on the same turn,
##  your opponent puts the top 2 cards of his/her deck into the Break Zone."
##
## The rider rides on the VICTIM: Field.cause_damage() applies `on_causing_damage_to_forward` from the dealer, which
## stores a one-turn status carrying the trigger. Card.turn_end() expires it; the Break Zone choke point runs it once.

const GAME_SCENE := preload("res://game.tscn")

const CID := 72
const SQUALL := 41
const SNOW := 43
const CHEMIST := 31
const TERRA := 47

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Cid] ok   %s" % what)
	else:
		_fails += 1
		print("[Cid] FAIL %s" % what)


func _card(id: int) -> Card:
	for c in _field.get_all_cards():
		if c.id == id:
			return c
	return null


func _deck_size() -> int:
	return _game.get("opponent_deck").deck_cards.size()


func _wait_for_deck(target: int) -> void:
	for _i in range(80):
		await get_tree().create_timer(0.1).timeout
		if _deck_size() <= target:
			return


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": CID}],
		"opponent_field": [{"id": SQUALL}, {"id": SNOW}, {"id": CHEMIST}, {"id": TERRA}],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	var cid: Card = _card(CID)
	var squall: Card = _card(SQUALL)
	var snow: Card = _card(SNOW)
	var chemist: Card = _card(CHEMIST)

	# --- a Backup is not a Forward: no mark ----------------------------------------------------------------
	_field.cause_damage(chemist, 1000, cid, "", "player")
	_expect(not chemist.status_effects.has("cid_verdict"), "damage to a Backup leaves no rider")

	# --- the rider lands on the damaged Forward ------------------------------------------------------------
	var deck_before: int = _deck_size()
	var dealt: int = _field.cause_damage(squall, 1000, cid, "", "player")
	print("[Cid] dealt %d, Squall statuses=%s, deck=%d" % [dealt, str(squall.status_effects.keys()), _deck_size()])
	_expect(dealt == 1000, "the damage lands")
	_expect(squall.status_effects.has("cid_verdict"), "and marks the Forward with the rider")
	var payload = squall.status_effects.get("cid_verdict", {})
	_expect(payload is Dictionary and str(payload.get("controller", "")) == "player",
		"the rider remembers WHO dealt it, for the mill later")
	_expect(_deck_size() == deck_before, "nothing happens while it is still on the field")

	# --- it dies this turn: the opponent mills 2 -------------------------------------------------------------
	_game.call("break_card", squall)
	await _wait_for_deck(deck_before - 2)
	print("[Cid] deck %d -> %d after the break" % [deck_before, _deck_size()])
	_expect(not squall.is_on_field(), "the Forward is broken")
	_expect(_deck_size() == deck_before - 2, "and its owner milled exactly 2")
	_expect(not squall.status_effects.has("cid_verdict"), "the rider is consumed")

	# --- it survives the turn: the rider expires, and no mill -----------------------------------------------
	var deck_now: int = _deck_size()
	_field.cause_damage(snow, 1000, cid, "", "player")
	_expect(snow.status_effects.has("cid_verdict"), "Snow is marked too")
	snow.turn_end()
	_expect(not snow.status_effects.has("cid_verdict"), "but the mark expires at end of turn")
	_game.call("break_card", snow)
	for _i in range(10):
		await get_tree().create_timer(0.1).timeout
	print("[Cid] deck after the expired-mark break: %d (was %d)" % [_deck_size(), deck_now])
	_expect(_deck_size() == deck_now, "so breaking it later mills nothing")

	# --- NOT a break: "put from the field into the Break Zone" -----------------------------------------------
	# The card does NOT say "breaks". A Forward removed by an effect, or one whose power reaches 0, still entered the
	# Break Zone, so the rider must still fire — and  must stay false, which is what keeps when_break silent.
	var terra: Card = _card(TERRA)
	var deck_before_put: int = _deck_size()
	_field.cause_damage(terra, 1000, cid, "", "player")
	_expect(terra.status_effects.has("cid_verdict"), "Terra is marked")
	_game.call("put_card_into_graveyard", terra)
	await _wait_for_deck(deck_before_put - 2)
	print("[Cid] put (not broken): on field=%s broken=%s deck %d -> %d" % [
		str(terra.is_on_field()), str(terra.broken), deck_before_put, _deck_size()])
	_expect(not terra.is_on_field(), "it left the field")
	_expect(terra.broken == false, "without being marked as BROKEN")
	_expect(_deck_size() == deck_before_put - 2, "and the rider still milled 2 on entering the Break Zone")

	print("[Cid] %d checks | failures: %d" % [_checks, _fails])
	print("[Cid] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
