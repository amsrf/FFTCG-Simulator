extends Node
## POWER-DOWN presentation probe (card_power_fx.gd + power_down_drain.gd + power_display.animate_power_down, and the
## lethal form: Vfx.drained -> drain_death_cue.gd).
##
## Asserts what the eye is promised:
##   a loss on a settled field Forward spawns ONE power-down (no power-up swords) sized by the drop; a sword pops in
##   ABOVE the card, draws back, and stabs DOWN until its point is at the card's centre; at the impact a light flash
##   blooms, colour leaves the art in blobs, six orbs travel AWAY from the card and the readout's POWER NUMBER (only
##   it) deflates and turns red while it counts down; it all settles: readout at rest on the new value, art's colour
##   back, freed. A loss on a card that just arrived plays nothing; leaving the field mid-way clears it.
##   LETHAL: power drained to 0 (a removal) and power drained to its damage (a break) both move the card at once and
##   present a DRAINED event: a stand-in holds the slot, the drain plays on it, then the counter's cyan pieces appear
##   and everything is gone once the queue is idle.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const DRAIN := preload("res://scripts/vfx/power_down_drain.gd")
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")
const DISPLAY := preload("res://scripts/cards/power_display.gd")

var _checks: int = 0
var _fails: int = 0
var _game: Node
var _field


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[PowerDown] ok   %s" % what)
	else:
		_fails += 1
		print("[PowerDown] FAIL %s" % what)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _frames(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame


func _forward(power: int) -> Card:
	var card: Card = _game.create_card(41, "player")
	_game.add_child(card)
	_field.play_card(card, false, false)
	card.set_base_power(power)
	return card


func _param(card: Card, name: String) -> float:
	var v = (card.get("mat") as ShaderMaterial).get_shader_parameter(name)
	return float(v) if v is float else 0.0


func _mean(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += float(v)
	return total / maxf(1.0, values.size())


func _count_named(root: Node, prefix: String) -> int:
	var n := 0
	for child in root.get_children():
		if str(child.name).begins_with(prefix):
			n += 1
		n += _count_named(child, prefix)
	return n


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await _frames()
	_field = _game.get("field")

	var card := _forward(5000)
	await _wait(1.0)
	var label = card.power_label
	var num: Label3D = label.power_part()
	var dmg: Label3D = label.damage_part()
	_expect(label != null and label.text.begins_with("5000/"), "the Forward shows 5000")
	var rest_scale: Vector3 = num.scale
	var rest_modulate: Color = num.modulate
	# The /damage part has a colour of its own (amber), so it is compared with ITSELF at rest, not with the number.
	var dmg_rest_modulate: Color = dmg.modulate

	# --- A LOSS: the drain, not the swords. ---
	card.add_power_modifier("probe:a", -2000)
	_expect(card.power == 3000, "the rules value is immediate (3000)")
	await _frames()
	_expect(card.power_fx.is_draining() and not card.power_fx.is_playing(), "a loss plays the drain, not the power-up")
	var drain: Node3D = card.power_fx.drain()
	_expect(drain != null and int(drain.call("spark_count")) == DRAIN.TIER_SPARKS[0],
		"a -2000 power-down has the smallest tier's sparks (%d)" % (drain.call("spark_count") if drain else -1))
	_expect(drain != null and float(drain.call("sword_tip")) > 0.5, "the sword starts above the card (point at %.2f)"
		% (drain.call("sword_tip") if drain else 0.0))
	await _wait(0.13)
	_expect(drain != null and int(drain.call("visible_puffs")) >= DRAIN.HAZE_PUFFS - 1, "the sword appears in a violet mist (%d puffs)"
		% (drain.call("visible_puffs") if drain else 0))

	await _wait(DRAIN.IMPACT_AT + 0.06)
	_expect(is_instance_valid(drain) and absf(float(drain.call("sword_tip"))) < 0.1,
		"the sword has stabbed the card's centre (point at %.2f)" % (drain.call("sword_tip") if drain else 9.0))
	_expect(is_instance_valid(drain) and float(drain.call("flash_size")) > 0.25, "the impact flashes (%.2f)"
		% (drain.call("flash_size") if drain else 0.0))
	_expect(is_instance_valid(drain) and (drain.call("visible_splash_distances") as Array).size() == DRAIN.SPLASH_COUNT,
		"and %d orbs burst out" % DRAIN.SPLASH_COUNT)
	_expect(is_instance_valid(drain) and int(drain.call("visible_puffs")) >= DRAIN.IMPACT_PUFFS,
		"with a burst of mist (%d puffs)" % (drain.call("visible_puffs") if drain else 0))

	await _wait(0.12)
	_expect(_param(card, "drain_blobs") > 0.3, "colour is leaving the art in blobs (%.2f)" % _param(card, "drain_blobs"))
	_expect(_param(card, "drain_amount") < 0.001, "but a non-lethal one never turns the whole card cold")
	_expect(num.scale.y < rest_scale.y * 0.85, "the power number deflates (%.2fx)" % (num.scale.y / rest_scale.y))
	_expect(num.modulate.r > num.modulate.b + 0.4, "and turns red (%s)" % num.modulate)
	_expect(dmg.scale.is_equal_approx(Vector3.ONE) and dmg.modulate.is_equal_approx(dmg_rest_modulate),
		"only the POWER number deflates: the /damage part is untouched (scale %s, modulate %s, rest %s)" % [
			dmg.scale, dmg.modulate, dmg_rest_modulate])
	var mid: int = int(label.text.split("/")[0])
	_expect(mid < 5000 and mid >= 3000, "the count is under way (%d)" % mid)

	# The shape, sampled deterministically on a second one: the stab only goes DOWN, the orbs only go OUT.
	var probe_drain: Node3D = DRAIN.new()
	add_child(probe_drain)
	probe_drain.set_process(false)
	probe_drain.call("setup", card, 1234, 0)
	var tips: Array = []
	for t in [DRAIN.STAB_AT, DRAIN.STAB_AT + 0.04, DRAIN.STAB_AT + 0.08, DRAIN.IMPACT_AT]:
		probe_drain.call("sample", t)
		tips.append(float(probe_drain.call("sword_tip")))
	_expect(tips[0] > tips[1] and tips[1] > tips[2] and tips[2] > tips[3], "the stab drives the point down %s" % [tips])
	probe_drain.call("sample", DRAIN.IMPACT_AT - 0.01)
	_expect((probe_drain.call("visible_splash_distances") as Array).is_empty() and float(probe_drain.call("flash_size")) == 0.0,
		"nothing ruptures before the point goes in")
	probe_drain.call("sample", DRAIN.IMPACT_AT + 0.15)
	var out1: Array = probe_drain.call("visible_splash_distances")
	probe_drain.call("sample", DRAIN.IMPACT_AT + 0.45)
	var out2: Array = probe_drain.call("visible_splash_distances")
	_expect(_mean(out2) > _mean(out1) and _mean(out2) > 0.5, "the orbs travel away from the card (%.2f -> %.2f)"
		% [_mean(out1), _mean(out2)])
	probe_drain.call("sample", DRAIN.IMPACT_AT + DRAIN.SPLASH_SECONDS + 0.01)
	_expect((probe_drain.call("visible_splash_distances") as Array).is_empty(), "and are gone once they land")
	_expect(float(probe_drain.call("sword_alpha")) < 0.01, "and so is the sword")
	probe_drain.queue_free()
	await _frames()

	await _wait(maxf(DRAIN.LIFETIME, DISPLAY.drain_seconds(DRAIN.NUMBER_START)) + 0.2)
	_expect(label.text.begins_with("3000/"), "the readout lands on 3000 (%s)" % label.text)
	_expect(num.scale.is_equal_approx(rest_scale) and num.modulate.is_equal_approx(rest_modulate),
		"and is back at rest (%s %s)" % [num.scale, num.modulate])
	_expect(not card.power_fx.is_draining() and not is_instance_valid(drain), "the drain has freed itself")
	_expect(_param(card, "drain_blobs") < 0.001, "and the art's colour is back (%.3f)" % _param(card, "drain_blobs"))

	# --- A big drop is a bigger drain. ---
	card.remove_power_modifier("probe:a")
	await _wait(2.2)
	card.add_power_modifier("probe:big", -4000)
	await _frames()
	drain = card.power_fx.drain()
	_expect(drain != null and int(drain.call("spark_count")) == DRAIN.TIER_SPARKS[1],
		"a -4000 power-down is the next tier (%d sparks)" % (drain.call("spark_count") if drain else -1))

	# --- Leaving the field mid-drain. ---
	await _wait(0.3)
	card.enter_zone(Card.Zone.GRAVEYARD)
	await _frames()
	_expect(not card.power_fx.is_draining() and not is_instance_valid(drain), "leaving the field removes the drain")
	_expect(_param(card, "drain_blobs") < 0.001, "and leaves the art's colour alone")
	_expect(not label.is_boosting(), "and the readout at rest")

	# --- Just arrived: no drain. ---
	var fresh := _forward(5000)
	await _frames(1)
	fresh.add_power_modifier("probe:e", -1000)
	await _frames()
	_expect(not fresh.power_fx.is_draining(), "a loss on a card that only just arrived plays no drain")
	await _wait(1.0)

	# --- LETHAL: drained to 0 (a removal, not a break). ---
	var zero := _forward(3000)
	await _wait(1.0)
	Vfx.clear_events()
	zero.add_power_modifier("probe:z", -3000)
	_game.enforce_game_state_rules()
	_expect(zero.current_zone == Card.Zone.GRAVEYARD and not zero.broken, "drained to 0: in the Break Zone at once, not broken")
	var kinds: Array = Vfx.get_events().map(func(e): return e.kind)
	_expect(kinds.has(VfxEvent.Kind.DRAINED) and not kinds.has(VfxEvent.Kind.TRIBUTE),
		"presented as DRAINED, not a tribute (%s)" % [kinds])
	await _frames()
	_expect(_count_named(_game, "HeldCard") == 1, "a stand-in holds the slot")
	await _wait(DRAIN.LETHAL_LEAD + 0.55)
	_expect(_count_named(Vfx, "CounterShard") > 10, "then it shatters into the counter's cyan pieces (%d)"
		% _count_named(Vfx, "CounterShard"))
	await Vfx.idle()
	await _frames()
	_expect(_count_named(_game, "HeldCard") == 0 and _count_named(Vfx, "CounterShard") == 0
		and _count_named(Vfx, "PowerDownDrain") == 0, "and everything is gone once the queue is idle")

	# --- LETHAL BY AN ABILITY (Kain 1-127: "It loses 5000 power"): EffectContext.power_change() must apply rule 12.4.4
	# itself. It once lowered the power and stopped, leaving the Forward on the field at 0 for the rest of the turn.
	var victim := _forward(5000)
	await _wait(1.0)
	Vfx.clear_events()
	var ctx = EFFECT_CONTEXT.new(_game, victim, "test")
	ctx.power_change([victim], -5000)
	_expect(victim.current_zone == Card.Zone.GRAVEYARD and not victim.broken,
		"an ABILITY's -5000 on a 5000 Forward puts it in the Break Zone at once (rule 12.4.4)")
	_expect(Vfx.get_events().map(func(e): return e.kind).has(VfxEvent.Kind.DRAINED), "presented as the drain death")
	await Vfx.idle()
	await _frames()

	# --- LETHAL: drained to its damage (a break). ---
	var hurt := _forward(5000)
	await _wait(1.0)
	hurt.accumulated_damage = 3000
	Vfx.clear_events()
	hurt.add_power_modifier("probe:h", -2000)
	_game.enforce_game_state_rules()
	_expect(hurt.current_zone == Card.Zone.GRAVEYARD, "drained to its damage: broken at once")
	kinds = Vfx.get_events().map(func(e): return e.kind)
	_expect(kinds.has(VfxEvent.Kind.DRAINED), "presented as DRAINED (%s)" % [kinds])
	await Vfx.idle()

	# --- Damage alone still breaks the ordinary way. ---
	var plain := _forward(3000)
	await _wait(1.0)
	plain.accumulated_damage = 3000
	Vfx.clear_events()
	_game.enforce_game_state_rules()
	kinds = Vfx.get_events().map(func(e): return e.kind)
	_expect(plain.current_zone == Card.Zone.GRAVEYARD and not kinds.has(VfxEvent.Kind.DRAINED),
		"a break by damage alone is not a drain (%s)" % [kinds])

	print("[PowerDown] %d checks | failures: %d" % [_checks, _fails])
	print("[PowerDown] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
