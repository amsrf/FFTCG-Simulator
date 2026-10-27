extends Node
## Aura migration: every aura card exposes code definitions, and a source entering/leaving applies and removes the
## exact continuous ledger entries.

const GAME_SCENE := preload("res://game.tscn")
const EXPECTED := {30: 1, 57: 1, 83: 1, 95: 1, 150: 1, 155: 2, 156: 1, 180: 1, 188: 1}

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[AuraMigrate] ok   %s" % what)
	else:
		_fails += 1
		print("[AuraMigrate] FAIL %s" % what)


func _place(id: int, side: String = "player") -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_game.get("field").play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	return card


func _ready() -> void:
	for id in EXPECTED:
		var script = load("res://assets/effects/card_%d.gd" % id)
		_expect(script != null, "%d has a code aura script" % id)
		if script == null:
			continue
		var effect = script.new()
		var auras: Array = effect.auras()
		_expect(auras.size() == int(EXPECTED[id]), "%d exposes %d aura(s)" % [id, EXPECTED[id]])
		for i in range(auras.size()):
			var spec = auras[i]
			var rule: Dictionary = spec.as_rule()
			_expect(not rule.get("targets", {}).is_empty(), "%d aura %d has target criteria" % [id, i])
			_expect(rule.get("method") == "power_change" or rule.get("method") == "grant_status",
				"%d aura %d has a known method" % [id, i])

	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = _game.get("field")

	# Zangan 188 is a Backup; it grants Haste to a Tifa of cost 4 or less.
	var zangan: Card = _place(188)
	var tifa: Card = _place(189)
	_expect(tifa.has_granted("haste"), "Zangan's code aura grants Tifa Haste")
	field.remove_card(zangan)
	await get_tree().process_frame
	_expect(not tifa.has_granted("haste"), "and removes it when Zangan leaves")

	# Warrior of Light 155 has TWO auras; a Standard Unit Forward gets both.
	var standard_forward: int = 0
	var index: int = 0
	for entry in CardDatabase.card_database:
		index += 1
		if str(entry.get("type_en", "")) == "Forward" and str(entry.get("job_en", "")) == "Standard Unit":
			standard_forward = index
			break
	_expect(standard_forward > 0, "the database has a Standard Unit Forward")
	if standard_forward > 0:
		var unit: Card = _place(standard_forward)
		var before: int = unit.power
		var wol: Card = _place(155)
		_expect(unit.power == before + 2000, "Warrior of Light's +2000 aura applies")
		_expect(unit.is_first_strike(), "and its First Strike aura applies from the same source")
		field.remove_card(wol)
		await get_tree().process_frame
		_expect(unit.power == before and not unit.is_first_strike(),
			"both aura effects are revoked together")

	print("[AuraMigrate] %d checks | failures: %d" % [_checks, _fails])
	print("[AuraMigrate] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
