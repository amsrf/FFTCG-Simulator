extends Node
## B2: damage replacement / prevention (160, 165, 166, 171) and Yuna's break-zone exile (176).

const GAME_SCENE := preload("res://game.tscn")

const GORDON := 160
const KNIGHT := 165
const MINWU := 171
const YUNA := 176
const ULTIMECIA := 152
const SQUALL := 41
const ZACK := 12
const TERRA := 47

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[B2] ok   %s" % what)
	else:
		_fails += 1
		print("[B2] FAIL %s" % what)


func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.accumulated_damage = 0
	card.untap()
	return card


func _ready() -> void:
	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/card_effects.json"))
	var gordon_effect = load("res://assets/effects/card_160.gd").new()
	var gordon_specs: Array = gordon_effect.activated_abilities()
	_expect(gordon_specs.size() == 1 and gordon_specs[0].run.is_valid(),
		"Gordon 160's next-receiving-damage ability is code-owned")
	_expect(not effects.get("160", {}).has("damage_modifiers"),
		"the shield is carried by the status payload, not a static modifier")
	_expect(effects.get("165", {}).get("damage_modifiers", [{}])[0].get("operation") == "set"
		and effects.get("166", {}).get("damage_modifiers", [{}])[0].get("operation") == "set",
		"both Knights carry a generic damage modifier")
	_expect(effects.get("171", {}).get("damage_modifiers", [{}])[0]
		.get("conditions", [{}])[0].has("compare_values"),
		"Minwu 171 uses the generic compare_values condition")
	var yuna: Dictionary = effects.get("176", {})
	_expect(yuna.get("ex_burst") == "when_enter_field"
		and load("res://assets/effects/card_176.gd").new().has_method("when_enter_field")
		and bool(yuna.get("break_zone_exile", false)),
		"Yuna 176 has her return ETB, EX Burst and exile rule")

	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	# --- 160 Gordon: the next damage is 0, then the shield is spent --------------------------------
	var gordon: Card = _make(GORDON, "player")
	gordon.add_status_effect("next_receiving_damage", 1, {"operation": "set", "value": 0})
	var first: int = _field.cause_damage(gordon, 3000)
	var second: int = _field.cause_damage(gordon, 3000)
	print("[B2] Gordon: first %d, second %d, accumulated %d" % [first, second, gordon.accumulated_damage])
	_expect(first == 0 and gordon.accumulated_damage == 3000, "Gordon 160's shield eats the first damage only")
	_expect(not gordon.status_effects.has("next_receiving_damage"), "and the shield is consumed")
	_game.call("put_card_into_graveyard", gordon)

	# --- 171 Minwu: damage below the Forward's power is 0 ----------------------------------------
	var minwu: Card = _make(MINWU, "player")
	var squall: Card = _make(SQUALL, "player")
	var small: int = _field.cause_damage(squall, 1000)
	var equal: int = _field.cause_damage(squall, 6000)
	print("[B2] Minwu: 1000 -> %d, 6000 -> %d" % [small, equal])
	_expect(small == 0, "Minwu 171 prevents damage below the Forward's power")
	_expect(equal == 6000 and squall.accumulated_damage == 6000,
		"damage equal to its power still happens")
	var their_squall: Card = _make(SQUALL, "opponent")
	var theirs: int = _field.cause_damage(their_squall, 1000)
	_expect(theirs == 1000, "and Minwu does not protect the opponent's Forwards")
	_game.call("put_card_into_graveyard", minwu)

	# --- 165/166 Knight: the OTHER party members take 0 ------------------------------------------
	var knight: Card = _make(KNIGHT, "player")
	var partner: Card = _make(ULTIMECIA, "player")       # water Forward, same element as Knight
	_field.set_attacker(knight)
	var joined: bool = _field.add_party_member(partner)
	var partner_hit: int = _field.cause_damage(partner, 1000)
	var knight_hit: int = _field.cause_damage(knight, 1000)
	print("[B2] Knight party: joined=%s partner=%d knight=%d" % [joined, partner_hit, knight_hit])
	_expect(joined and _field.party_members().size() == 2, "the Knight and its partner form a party")
	_expect(partner_hit == 0, "the other party member takes 0")
	_expect(knight_hit == 1000, "Knight itself is not protected by its own rule")
	_field.reset_attacker()
	var alone: int = _field.cause_damage(partner, 1000)
	print("[B2] after the party disbands: %d" % alone)
	_expect(alone == 1000, "and the protection disappears when the party does")

	# --- 176 Yuna: a Character that leaves the field is exiled instead -----------------------------
	var yuna_card: Card = _make(YUNA, "player")
	var victim: Card = _make(ZACK, "player")
	_game.call("break_card", victim)
	var removed = _game.get("player_removed")
	var graveyard = _game.get("player_graveyard")
	print("[B2] Yuna: victim removed=%s graveyard=%s" % [
		removed.graveyard_cards.has(victim), graveyard.graveyard_cards.has(victim)])
	_expect(removed.graveyard_cards.has(victim) and not graveyard.graveyard_cards.has(victim),
		"Yuna 176 exiles a Character put from the field into the Break Zone")
	_game.call("put_card_into_graveyard", yuna_card)
	var second_victim: Card = _make(TERRA, "player")
	_game.call("break_card", second_victim)
	_expect(graveyard.graveyard_cards.has(second_victim),
		"with Yuna gone, the next Character goes to the Break Zone normally")

	print("[B2] %d checks | failures: %d" % [_checks, _fails])
	print("[B2] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
