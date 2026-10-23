extends Node
## PARTY CARDS probe — bucket C: the party triggers that needed no new instruction, plus the two small predicates they
## leaned on (`is_character`, `is_type_any`) and the `party_has_named:` trigger condition.
##
## Every case is driven through the real attack path: form a party, `execute_card_attack()`, complete the target if the
## trigger asks for one, then drain the stack. The target step is done by hand because a LocalAgent would wait for a
## mouse click.

const GAME_SCENE := preload("res://game.tscn")

const MIME := 173           # water Forward: party attacks -> draw 1
const KNIGHT := 165         # water Forward, no party trigger: a neutral partner
const GUNBREAKER := 523     # ice Forward: party attacks -> opponent discards 1
const SQUALL := 41          # ice Forward, no effects
const KING_OF_EBLAN := 3260 # fire Forward
const QUEEN_OF_EBLAN := 3261# fire Forward: party WITH King of Eblan -> 5000 to an opponent Forward
const RED_XIII := 29        # fire Forward, no party trigger
const CHELINKA := 3023      # wind Forward: party WITH Yuri -> break a Forward or Monster
const YURI := 1788          # wind Forward
const TONOGIRI := 719       # water Forward: party attacks -> return a Forward to hand
const RED_MAGE := 1879      # ice Forward: party attacks -> dull and freeze a Character
const SNOW := 43            # ice Forward, used as a victim

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[PartyCards] ok   %s" % what)
	else:
		_fails += 1
		print("[PartyCards] FAIL %s" % what)


func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.accumulated_damage = 0
	card.untap()
	return card


## Form a party: primary first, then the second member (same element is required by set/add_party_member).
func _party(a: Card, b: Card) -> void:
	_field.reset_attacker()
	_field.set_attacker(a)
	_field.add_party_member(b)


func _drain() -> void:
	var stack = _game.get("stack")
	var guard: int = 0
	while stack.stack_length() > 0 and guard < 24:
		await stack.resolve_top_effect()
		guard += 1
	await get_tree().process_frame


## Finish a pending targeting request the way a click plus Confirm would.
func _complete_target(card: Card) -> void:
	_field.set_target_card(card)
	_game.get("assistant").call("on_target_complete")


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"opponent_type": "ai",          # so the opponent's discard has an agent that can answer
		"opponent_hand": [1, 2, 3],
		"player_hand": [10, 11, 12],
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	var hand = _game.get("hand")
	var opp_hand = _game.get("opponent_hand")

	# --- 173 Mime: "forms a party and attacks, draw 1" ------------------------------------------------------
	var mime: Card = _make(MIME, "player")
	var knight: Card = _make(KNIGHT, "player")
	await _drain()
	var hand_before: int = hand.cards.size()
	_party(mime, knight)
	_field.execute_card_attack()
	await _drain()
	print("[PartyCards] Mime draw: hand %d -> %d" % [hand_before, hand.cards.size()])
	_expect(hand.cards.size() == hand_before + 1, "Mime: the party attack draws 1 card")

	# --- 523 Gunbreaker: "party attacks, opponent discards 1" ------------------------------------------------
	var gunbreaker: Card = _make(GUNBREAKER, "player")
	var squall: Card = _make(SQUALL, "player")
	await _drain()
	var opp_before: int = opp_hand.cards.size()
	_party(gunbreaker, squall)
	_field.execute_card_attack()
	await _drain()
	print("[PartyCards] Gunbreaker discard: opponent hand %d -> %d" % [opp_before, opp_hand.cards.size()])
	_expect(opp_hand.cards.size() == opp_before - 1, "Gunbreaker: the opponent discards 1")

	# --- 3261 Queen of Eblan: party WITH King of Eblan -> 5000 damage -----------------------------------------
	var king: Card = _make(KING_OF_EBLAN, "player")
	var queen: Card = _make(QUEEN_OF_EBLAN, "player")
	var victim_a: Card = _make(SQUALL, "opponent")
	await _drain()
	_party(queen, king)
	_field.execute_card_attack()
	_expect(not _field.targeting_picked.is_empty() or _game.get("stack").stack_length() > 0,
		"Queen of Eblan: the trigger asks for a target")
	_complete_target(victim_a)
	await _drain()
	print("[PartyCards] Queen of Eblan dealt %d to %s" % [victim_a.accumulated_damage, victim_a.card_name])
	_expect(victim_a.accumulated_damage == 5000, "Queen of Eblan: 5000 damage to the chosen opponent Forward")

	# --- the same card WITHOUT King of Eblan must not trigger ------------------------------------------------
	var queen_b: Card = _make(QUEEN_OF_EBLAN, "player")
	var red_xiii: Card = _make(RED_XIII, "player")
	await _drain()
	_party(queen_b, red_xiii)
	# `targeting_picked` is only cleared when a NEW session starts (request_target), not when one completes, so a
	# leftover pick from the previous test is not evidence of a trigger. Compare before/after instead.
	var picks_before: int = _field.targeting_picked.size()
	_field.execute_card_attack()
	await get_tree().process_frame
	print("[PartyCards] Queen without King: stack=%d picks %d -> %d mode=%s" % [
		_game.get("stack").stack_length(), picks_before, _field.targeting_picked.size(),
		GlobalVariables.get_player_mode()])
	_expect(_game.get("stack").stack_length() == 0
			and _field.targeting_picked.size() == picks_before
			and GlobalVariables.get_player_mode() != GlobalVariables.Player_Mode.TARGET,
		"Queen of Eblan: no trigger without King of Eblan in the party")

	# --- 3023 Chelinka: party WITH Yuri -> break a Forward ---------------------------------------------------
	var chelinka: Card = _make(CHELINKA, "player")
	var yuri: Card = _make(YURI, "player")
	var victim_b: Card = _make(SNOW, "opponent")
	await _drain()
	_party(chelinka, yuri)
	_field.execute_card_attack()
	_complete_target(victim_b)
	await _drain()
	print("[PartyCards] Chelinka: %s on field after the break = %s" % [victim_b.card_name, victim_b.is_on_field()])
	_expect(not victim_b.is_on_field(), "Chelinka: the chosen Forward is broken")

	# --- 719 Tonogiri: party attacks -> return a Forward to its owner's hand --------------------------------
	var tonogiri: Card = _make(TONOGIRI, "player")
	var knight_b: Card = _make(KNIGHT, "player")
	var victim_c: Card = _make(SQUALL, "opponent")
	await _drain()
	var opp_hand_before: int = opp_hand.cards.size()
	_party(tonogiri, knight_b)
	_field.execute_card_attack()
	_complete_target(victim_c)
	await _drain()
	print("[PartyCards] Tonogiri: %s on field=%s parent=%s in_hand=%s, opponent hand %d -> %d" % [
		victim_c.card_name, victim_c.is_on_field(),
		victim_c.get_parent().name if victim_c.get_parent() != null else "<none>",
		opp_hand.cards.has(victim_c), opp_hand_before, opp_hand.cards.size()])
	# The return animation is a TWEEN the instruction awaits; give any tail one more frame before judging the hand.
	if opp_hand.cards.size() == opp_hand_before:
		await get_tree().create_timer(1.0).timeout
		print("[PartyCards] Tonogiri after a 1s wait: hand %d, parent=%s" % [
			opp_hand.cards.size(),
			victim_c.get_parent().name if victim_c.get_parent() != null else "<none>"])
	_expect(not victim_c.is_on_field(), "Tonogiri: the chosen Forward leaves the field")
	_expect(opp_hand.cards.size() == opp_hand_before + 1,
		"Tonogiri: and it goes to its OWNER's hand")

	# --- 1879 Red Mage: party attacks -> dull and freeze a Character ----------------------------------------
	var red_mage: Card = _make(RED_MAGE, "player")
	var squall_b: Card = _make(SQUALL, "player")
	var victim_d: Card = _make(SNOW, "opponent")
	await _drain()
	_party(red_mage, squall_b)
	_field.execute_card_attack()
	_complete_target(victim_d)
	await _drain()
	print("[PartyCards] Red Mage: %s tapped=%s frozen=%s" % [
		victim_d.card_name, victim_d.tapped, victim_d.status_effects.has("frozen")])
	_expect(victim_d.tapped, "Red Mage: the chosen Character is dulled")
	_expect(victim_d.status_effects.has("frozen"), "Red Mage: and frozen")

	print("[PartyCards] %d checks | failures: %d" % [_checks, _fails])
	print("[PartyCards] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
