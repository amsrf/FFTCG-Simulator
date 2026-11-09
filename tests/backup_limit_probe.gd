extends Node
## THE FIVE-BACKUP LIMIT (7.7.4 / 12.4.8) and a DULL free play landing the right way up.
##
## The practice board fields five Backups for the player and has Backups in hand:
##   * casting a sixth from hand is refused (7.7.4),
##   * an EFFECT may still put a sixth there ("play it onto the field dull", Auron); it lands tilted like any dull
##     card, NOT upside down — the tap used to be measured from the hand's upright before the field's half turn,
##   * the rule process before priority then has the controller put one into the Break Zone so five remain (12.4.8).

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const AGENT := preload("res://scripts/agents/agent.gd")

var _checks: int = 0
var _fails: int = 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[Backups] %s %s" % ["ok  " if ok else "FAIL", what])

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	for i in range(6):
		await get_tree().process_frame
	var field = game.field
	var hand = game.hand
	var backups: Array = field.get_back_cards_for(Card.PLAYER)
	_expect(backups.size() == 5, "the practice board fields five Backups (%d)" % backups.size())
	var spare: Card = null
	for c in hand.cards:
		if c.type == Card.BACKUP:
			spare = c
			break
	if spare == null:
		print("[Backups] no Backup in the practice hand")
		print("[Backups] RESULT: 1 FAILED")
		get_tree().quit(1)
		return
	_expect(not hand.can_play_character(spare), "casting a sixth Backup (%s) from hand is refused" % spare.card_name)

	# --- an effect puts it there anyway, dull --------------------------------------------------------------------
	hand.remove_for_play(spare)
	spare.reset_for_field_arrival()
	field.play_card(spare, false, true)
	spare.tap()   # what EffectContext.play_from_hand_card(card, true) does
	await Vfx.idle()
	await get_tree().create_timer(0.6).timeout
	var reference: Card = null
	for c in backups:
		reference = c
		break
	var want: float = reference._upright_y + reference.tap_angle
	var off: float = absf(wrapf(spare.rotation_degrees.y - want, -180.0, 180.0))
	_expect(off < 1.0, "the dull Backup lies the right way up, tilted like a dull card (y %.1f, want %.1f)"
		% [spare.rotation_degrees.y, want])
	_expect(field.get_back_cards_for(Card.PLAYER).size() == 6, "an effect can still put a sixth Backup on the field")

	# --- the rule process: the controller chooses one to put away --------------------------------------------------
	var chooser = AGENT.new()   # answers with the first candidate, like an AI that does not care
	chooser.bind(game)
	game.player_agent = chooser
	var first: Card = field.get_back_cards_for(Card.PLAYER)[0]
	var pile_before: int = game.player_graveyard.graveyard_cards.size()
	await game.apply_rule_processes()
	await get_tree().process_frame
	_expect(field.get_back_cards_for(Card.PLAYER).size() == 5, "the rule process leaves exactly five Backups")
	_expect(not field.get_back_cards_for(Card.PLAYER).has(first) and field.get_back_cards_for(Card.PLAYER).has(spare),
		"the one the controller chose (%s) went; the new one stayed — a swap" % first.card_name)
	_expect(game.player_graveyard.graveyard_cards.size() == pile_before + 1 and not first.broken,
		"it went to the Break Zone, placed rather than broken")

	print("[Backups] %d checks | failures: %d" % [_checks, _fails])
	print("[Backups] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
