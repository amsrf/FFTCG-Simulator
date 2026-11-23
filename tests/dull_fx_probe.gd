extends Node
## How a dull card LOOKS (scripts/cards/card_dull_fx.gd): it only TILTS - no card greys or dims any more, Backups
## included (the user's call, 2026-11-21); the Active Phase untap runs as a left-to-right wave with a light sweep, while the RULES untap every card
## at once.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _checks: int = 0
var _fails: int = 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[DullFx] %s %s" % ["ok  " if ok else "FAIL", what])

func _param(card: Card, key: String) -> float:
	var v = card.mat.get_shader_parameter(key)
	return float(v) if v is float else -1.0

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug", {"opponent_type": "mock"})
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.field
	var backups: Array = field.get_back_cards_for("player")
	_expect(backups.size() >= 3, "setup: the debug board gives the player at least three Backups (%d)" % backups.size())
	if backups.size() < 3:
		_finish()
		return

	# --- 1. DIM -------------------------------------------------------------------------------------------------
	var card: Card = backups[0]
	card.untap()
	await _wait(0.4)
	_expect(_param(card, "dull_amount") < 0.01, "an active card is drawn in full colour")
	card.tap()
	var brightest := INF
	for _i in range(10):
		await _wait(0.05)
		brightest = minf(brightest, 1.0 - _param(card, "dull_amount"))
	_expect(card.tapped and brightest > 0.99, "a dull Backup keeps its colour all the way through the tap (dim never above %.2f)" % (1.0 - brightest))
	card.untap()
	await _wait(0.45)
	card.tap()
	card.enter_zone(Card.Zone.GRAVEYARD)
	_expect(_param(card, "dull_amount") < 0.01, "a card leaving the field carries no dim")
	card.enter_zone(Card.Zone.FIELD)
	card.untap()
	await _wait(0.4)
	# A dull FORWARD keeps its colour: it only tilts.
	var forwards: Array = field.get_front_cards_for("player")
	if not forwards.is_empty():
		var fwd: Card = forwards[0]
		fwd.untap()
		await _wait(0.4)
		fwd.tap()
		await _wait(0.45)
		_expect(fwd.tapped and _param(fwd, "dull_amount") < 0.01, "a dull Forward keeps its colour too")
		fwd.untap()
		await _wait(0.4)

	# --- 2. REFRESH WAVE ----------------------------------------------------------------------------------------
	var row: Array = backups.slice(0, 3)
	for c in row:
		c.tap()
	await _wait(0.5)
	var cam: Camera3D = get_viewport().get_camera_3d()
	row.sort_custom(func(a, b): return cam.unproject_position(a.global_position).x < cam.unproject_position(b.global_position).x)
	var tilted: float = row[0].rotation_degrees.y
	field.untap_cards_for("player")
	var untapped := true
	for c in row:
		untapped = untapped and not c.tapped
	_expect(untapped, "the Active Phase untaps every card AT ONCE (rules)")
	# Shortly after: the leftmost card has started straightening and sweeping, the rightmost has not.
	await _wait(field.UNTAP_STAGGER * 1.5)
	var first: Card = row[0]
	var last: Card = row[row.size() - 1]
	_expect(absf(first.rotation_degrees.y - tilted) > 0.5, "the leftmost card straightens first")
	_expect(absf(last.rotation_degrees.y - last._upright_y) > absf(first.rotation_degrees.y - first._upright_y),
		"while the rightmost is still further from upright (a wave, left to right)")
	_expect(first.dull_fx.sweep > 0.0 and last.dull_fx.sweep == 0.0,
		"and the light sweep reaches the leftmost card before the rightmost")
	await _wait(1.2)
	var settled := true
	for c in row:
		settled = settled and _param(c, "dull_amount") < 0.01 and _param(c, "refresh_sweep") == 0.0 \
			and absf(c.rotation_degrees.y - c._upright_y) < 0.1
	_expect(settled, "and the wave ends with every card upright, in full colour, with no sweep left")
	_finish()

func _finish() -> void:
	print("[DullFx] %d checks | failures: %d" % [_checks, _fails])
	print("[DullFx] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
