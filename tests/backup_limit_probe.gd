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

	# --- an EFFECT plays a sixth: choose first, then the new one takes the chosen one's SLOT ------------------------
	await Vfx.idle()
	var spare2: Card = null
	for c in hand.cards:
		if c.type == Card.BACKUP and not game.would_be_unique_name_conflict(c):
			spare2 = c
			break
	if spare2 == null:
		for c in game.deck.deck_cards:
			if c.type == Card.BACKUP and not game.would_be_unique_name_conflict(c):
				spare2 = c
				break
		if spare2 != null:
			game.deck.deck_cards.erase(spare2)
			hand.add_card(spare2)
			await get_tree().create_timer(0.3).timeout
	_expect(spare2 != null, "a second Backup is available to play by effect")
	if spare2 != null:
		var row: Array = field.back_cards
		var five: Array = field.get_back_cards_for(Card.PLAYER).duplicate()
		var ordered: Array = five.filter(func(b): return b.tapped) + five.filter(func(b): return not b.tapped)
		var victim: Card = ordered[0]   # the agent answers with the first offer
		var victim_index: int = row.find(victim)
		var victim_pos: Vector3 = victim.position
		var ctx = load("res://scripts/effects/effect_context.gd").new(game, spare2, "test")
		await ctx.play_from_hand_card(spare2)
		await Vfx.idle()
		await get_tree().create_timer(0.3).timeout
		var now: Array = field.get_back_cards_for(Card.PLAYER)
		_expect(now.size() == 5, "still five Backups after the swap (%d)" % now.size())
		_expect(not now.has(victim) and game.player_graveyard.graveyard_cards.has(victim),
			"the chosen Backup (%s) went to the Break Zone" % victim.card_name)
		_expect(row.find(spare2) == victim_index,
			"the new Backup took the chosen one's place in the row (index %d, want %d)" % [row.find(spare2), victim_index])
		_expect(spare2.position.distance_to(victim_pos) < 0.01,
			"and lands on its slot (%.3f m away)" % spare2.position.distance_to(victim_pos))

	# --- a gap is filled NEAREST THE CENTRE first ------------------------------------------------------------------
	var centre_x: float = field.get_node("BackrowCard").position.x
	var middle: Card = null
	for b in field.get_back_cards_for(Card.PLAYER):
		if absf(b.position.x - centre_x) < 0.05:
			middle = b
	# (The rule-process check above already took the centre Backup away, so it is usually free already.)
	var spare3: Card = null
	for c in hand.cards + game.deck.deck_cards:
		if c.type == Card.BACKUP and (middle == null or c.card_name != middle.card_name) \
				and not game.would_be_unique_name_conflict(c):
			spare3 = c
			break
	_expect(spare3 != null, "a third Backup is available to play by effect")
	if spare3 != null:
		# Free a slot: the centre Backup if there is one, else the OUTERMOST, so the centre is the nearest gap.
		var leaving: Card = middle
		if leaving == null:
			for b in field.get_back_cards_for(Card.PLAYER):
				if leaving == null or absf(b.position.x - centre_x) > absf(leaving.position.x - centre_x):
					leaving = b
		game.put_card_into_graveyard(leaving)
		await Vfx.idle()
		_expect(field.get_back_cards_for(Card.PLAYER).size() < 5, "a slot is free before the next play")
		if game.deck.deck_cards.has(spare3):
			game.deck.deck_cards.erase(spare3)
			hand.add_card(spare3)
			await get_tree().create_timer(0.3).timeout
		var ctx3 = load("res://scripts/effects/effect_context.gd").new(game, spare3, "test")
		await ctx3.play_from_hand_card(spare3)
		await Vfx.idle()
		await get_tree().create_timer(0.3).timeout
		_expect(absf(spare3.position.x - centre_x) < 0.01,
			"the next Backup fills the vacated CENTRE slot (x %.2f, centre %.2f)" % [spare3.position.x, centre_x])
		var xs: Array = []
		for b in field.get_back_cards_for(Card.PLAYER):
			xs.append(snappedf(b.position.x, 0.01))
		var unique_xs: Dictionary = {}
		for x in xs:
			unique_xs[x] = true
		_expect(unique_xs.size() == xs.size(), "no two Backups share a slot (%s)" % str(xs))

	print("[Backups] %d checks | failures: %d" % [_checks, _fails])
	print("[Backups] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
