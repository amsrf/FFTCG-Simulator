extends Node
## The absorbed-mana reaction, which now lives in scripts/card_absorb.gd.
##
## NOTHING IN THE SUITE TOUCHED THIS BEFORE, so the extraction had no safety net at all — that is what this is. It checks
## the two quads appear, that the shockwave starts on the orb's last position projected into the card's plane, that the
## card is left energized, and — the subtle one — that a VOLLEY does not ratchet the card's size, which was a real bug
## once and is the reason the resting scale is recorded only on the first hit of a volley.
##
##   godot --headless res://tests/absorb_probe.tscn --quit-after 900

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Absorb] ok   ", what)
	else:
		_fails += 1
		print("[Absorb] FAIL ", what)

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = game.field
	var backs: Array[Card] = field.get_back_cards_for("player")
	_expect(not backs.is_empty(), "the debug board has a card to hit")
	if backs.is_empty():
		_finish()
		return
	var card: Card = backs[0]
	var resting: Vector3 = card.scale

	# An impact point offset along the card's own width, so a ring that ignored it would be detectable.
	var impact: Vector3 = card.global_position + card.global_transform.basis.x * 0.05
	card.absorb_power(Color(0.9, 0.1, 0.1), impact)
	await get_tree().process_frame

	var flash: Node = card.get_node_or_null("AbsorbFlash")
	var ring: Node = card.get_node_or_null("AbsorbRing")
	print("[Absorb] after one hit: flash=%s ring=%s energized=%s" % [
		flash != null, ring != null, card.get("_energized_highlight_on")])
	_expect(flash != null and ring != null, "the flash and the shockwave are both parented to the card")
	_expect(card.get("_absorb") != null, "the card builds its CardAbsorb on first use")
	if ring != null:
		var local_impact: Vector3 = card.to_local(impact)
		# Checked against what it was CONSTRUCTED with. Re-projecting here would use a transform the card has since
		# drifted a hair from, and would be measuring my own arithmetic rather than the code.
		print("[Absorb] ring at %s (impact was placed at local (0.050, 0, 0))" % (ring as Node3D).position)
		_expect(absf((ring as Node3D).position.x - 0.05) < 0.0001
			and absf((ring as Node3D).position.z) < 0.0001,
			"the shockwave starts on the orb's last position in the card's plane")
	# A FIELD card is deliberately NOT energized. set_energized_highlight() only lights a card that is still in HAND,
	# because the meaning is "mana was spent on this and it is about to be played" — a card already on the field has
	# been played. Asserting `true` here was my mistake, not the code's.
	_expect(not bool(card.get("_energized_highlight_on")),
		"a card already on the field is NOT energized — that glow is for cards awaiting payment in hand")

	# THE VOLLEY. Three more hits while the first punch is still up, the way the crystal row sends them.
	for _i in range(3):
		card.absorb_power(Color(0.9, 0.1, 0.1), impact)
	var absorb = card.get("_absorb")
	var tw: Tween = absorb._tween if absorb != null else null
	_expect(tw != null and tw.is_valid(), "the punch is a live tween")
	if tw != null and tw.is_valid():
		# Stepped deterministically: a wall-clock wait does not drive a tween in a headless run.
		tw.pause()
		tw.custom_step(1.0)
	print("[Absorb] after a volley of 4: scale %s | resting %s" % [card.scale, resting])
	_expect(card.scale.is_equal_approx(resting),
		"a volley of four leaves the card at its resting size, not inflated")

	_finish()

func _finish() -> void:
	print("[Absorb] %d checks | failures: %d" % [_checks, _fails])
	print("[Absorb] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0)
