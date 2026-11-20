extends Node
## POWER-UP presentation probe (card_power_fx.gd + power_up_burst.gd + power_display.gd animate_power_up).
##
## Asserts what the eye is promised:
##   a buff on a settled field Forward spawns ONE burst with three swords, and the readout HOLDS the old number
##   while the swords play; the swords pop in, then fade; the readout then counts up while swelling (>1.3x) and
##   settles back to its exact resting scale, tint and draw order, showing the new value; the burst frees itself;
##   a power LOSS, a same-frame grant+revoke (net zero) and a buff on a card that only just arrived play no burst;
##   leaving the field mid-burst removes it and leaves the readout at rest.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const DRAIN := preload("res://scripts/vfx/power_down_drain.gd")
const BURST := preload("res://scripts/vfx/power_up_burst.gd")
const DISPLAY := preload("res://scripts/cards/power_display.gd")

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[PowerUp] ok   %s" % what)
	else:
		_fails += 1
		print("[PowerUp] FAIL %s" % what)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.get("field")

	var card: Card = game.create_card(41, "player")
	game.add_child(card)
	field.play_card(card, false, false)
	card.set_base_power(5000)
	await _wait(1.0)
	var label = card.power_label
	var num: Label3D = label.power_part()
	var dmg: Label3D = label.damage_part()
	_expect(label != null and label.visible and label.text.begins_with("5000/"), "the Forward shows 5000")
	var rest_scale: Vector3 = num.scale
	var rest_priority: int = num.render_priority
	var rest_modulate: Color = num.modulate
	var dmg_rest_modulate: Color = dmg.modulate   # the /damage part has its own amber tint

	# --- A BUFF: swords first, then the number. ---
	card.add_power_modifier("probe:a", 3000)
	_expect(card.power == 8000, "the rules value is immediate (8000)")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(card.power_fx.is_playing(), "a buff on a settled field Forward plays the power-up")
	var burst: Node3D = card.power_fx.burst()
	_expect(burst != null and int(burst.call("sword_count")) == 3, "with three swords")
	_expect(burst != null and int(burst.call("puff_count")) >= 10, "and red gas (%d puffs)" % (burst.call("puff_count") if burst else 0))
	await _wait(0.30)
	var alphas: Array = burst.call("sword_alphas") if is_instance_valid(burst) else []
	_expect(alphas.size() == 3 and alphas.all(func(a): return float(a) > 0.9), "all three swords are up at 0.3 s %s" % [alphas])
	_expect(label.text.begins_with("5000/") and num.scale.is_equal_approx(rest_scale),
		"the readout waits, unchanged, while the swords play (%s)" % label.text)

	await _wait(BURST.NUMBER_START - 0.30 + 0.45)
	alphas = burst.call("sword_alphas") if is_instance_valid(burst) else [0.0, 0.0, 0.0]
	_expect(alphas.all(func(a): return float(a) < 0.05), "the swords are gone once the count runs %s" % [alphas])
	var grown: float = num.scale.x / rest_scale.x
	print("[PowerUp] mid-count: '%s' at %.2fx" % [label.text, grown])
	_expect(grown > 1.3, "the readout swells while it counts (%.2fx)" % grown)
	_expect(num.render_priority > rest_priority, "the swollen readout draws above the gas")
	_expect(dmg.scale.is_equal_approx(Vector3.ONE) and dmg.modulate.is_equal_approx(dmg_rest_modulate),
		"only the POWER number swells: the /damage part is untouched (%s %s)" % [dmg.scale, dmg.modulate])
	# The damage part shows just the number (no slash); the parent keeps "power/damage" for readers, drawn invisible.
	_expect(label.modulate.a == 0.0 and not num.text.contains("/") and not dmg.text.contains("/")
		and label.text == "%s/%s" % [num.text, dmg.text],
		"the readout is drawn as two parts ('%s' + '%s'); the parent draws nothing" % [num.text, dmg.text])
	var mid: int = int(label.text.split("/")[0])
	_expect(mid > 5000 and mid <= 8000, "the count is under way (%d)" % mid)

	await _wait(DISPLAY.boost_seconds(BURST.NUMBER_START) - BURST.NUMBER_START - 0.45 + 0.15)
	_expect(label.text.begins_with("8000/"), "the readout lands on 8000 (%s)" % label.text)
	_expect(num.scale.is_equal_approx(rest_scale) and num.modulate.is_equal_approx(rest_modulate)
		and num.render_priority == rest_priority, "and is back at rest: scale, tint and draw order (%s %s %d)"
		% [num.scale, num.modulate, num.render_priority])
	await _wait(maxf(0.0, BURST.LIFETIME - DISPLAY.boost_seconds(BURST.NUMBER_START)) + 0.1)
	_expect(not card.power_fx.is_playing() and not is_instance_valid(burst), "the burst has freed itself")

	# --- A LOSS: plain count, no swords. ---
	card.remove_power_modifier("probe:a")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not card.power_fx.is_playing(), "a power loss plays no power-up")
	# A loss from an effect plays the drain, whose count runs longer than a plain one.
	await _wait(DISPLAY.drain_seconds(DRAIN.NUMBER_START) + 0.15)
	_expect(label.text.begins_with("5000/"), "and counts down to 5000 (%s)" % label.text)

	# --- Net zero in one frame. ---
	card.add_power_modifier("probe:b", 2000)
	card.remove_power_modifier("probe:b")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not card.power_fx.is_playing(), "a same-frame grant + revoke plays nothing")

	# --- Two buffs in a row: one burst, the count re-aimed at the total. ---
	card.add_power_modifier("probe:c", 1000)
	await get_tree().process_frame
	await get_tree().process_frame
	var first: Node3D = card.power_fx.burst()
	await _wait(0.2)
	card.add_power_modifier("probe:d", 1000)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(first != null and card.power_fx.burst() == first, "a second buff during the swords keeps the one burst")
	await _wait(DISPLAY.boost_seconds(BURST.NUMBER_START) + 0.1)
	_expect(label.text.begins_with("7000/") and num.scale.is_equal_approx(rest_scale),
		"and the readout lands on the total, at rest (%s, %s vs %s)" % [label.text, num.scale, rest_scale])
	await _wait(0.3)

	# --- End-of-turn EXPIRY is not an effect: no swords and no drain, either way. ---
	card.power_change(1000, 1)                       # an effect: +1000 until end of turn
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(card.power_fx.is_playing(), "an effect's +1000 until end of turn plays the power-up")
	await _wait(BURST.LIFETIME + 0.2)
	card.turn_end()                                  # the +1000 expires
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(card.power == 7000 and not card.power_fx.is_playing() and not card.power_fx.is_draining(),
		"its expiry at end of turn plays no drain (power %d)" % card.power)
	await _wait(0.9)
	_expect(label.text.begins_with("7000/"), "and just counts back to 7000 (%s)" % label.text)
	card.power_change(-1000, 1)                      # an effect: -1000 until end of turn
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(card.power_fx.is_draining(), "an effect's -1000 still plays the drain")
	await _wait(3.0)
	card.turn_end()                                  # the -1000 expires: power goes back UP
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(card.power == 7000 and not card.power_fx.is_playing(),
		"and its expiry plays no power-up (power %d)" % card.power)
	await _wait(0.9)
	_expect(label.text.begins_with("7000/"), "the readout is back on 7000 (%s)" % label.text)

	# --- Just arrived: no fanfare. ---
	var fresh: Card = game.create_card(41, "player")
	game.add_child(fresh)
	field.play_card(fresh, false, false)
	await get_tree().process_frame
	fresh.add_power_modifier("probe:e", 2000)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not fresh.power_fx.is_playing(), "a buff on a card that only just arrived plays no burst")

	# --- Leaving the field mid-burst. ---
	card.add_power_modifier("probe:f", 1000)
	await get_tree().process_frame
	await get_tree().process_frame
	var doomed: Node3D = card.power_fx.burst()
	await _wait(BURST.NUMBER_START + 0.2)
	_expect(label.is_boosting(), "(the readout is mid-swell)")
	card.enter_zone(Card.Zone.GRAVEYARD)
	await get_tree().process_frame
	_expect(not card.power_fx.is_playing() and not is_instance_valid(doomed), "leaving the field removes the burst")
	_expect(num.scale.is_equal_approx(rest_scale) and not label.is_boosting() and label.text.begins_with("8000/"),
		"and leaves the readout at rest on the final value (%s)" % label.text)

	print("[PowerUp] %d checks | failures: %d" % [_checks, _fails])
	print("[PowerUp] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
