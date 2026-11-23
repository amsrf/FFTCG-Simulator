extends Node
## WATER SPLASH probe: a Water card's effect that makes its controller draw splashes water up off THAT player's deck
## top (Game.draw_cards -> scripts/vfx/water_splash.gd). A non-Water source and the Draw Phase draw do not.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")
const SPLASH := preload("res://scripts/vfx/water_splash.gd")

const WATER_DRAWER := 175   # Water
const WIND_DRAWER := 199    # Wind

var _checks := 0
var _fails := 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[WaterSplash] ok   %s" % what)
	else:
		_fails += 1
		print("[WaterSplash] FAIL %s" % what)


func _splashes() -> Array:
	return get_tree().root.get_children().filter(
		func(n): return n.get_script() == SPLASH and not n.is_queued_for_deletion())


func _card(id: int) -> Card:
	for c in _game.get("field").get_all_cards():
		if c.id == id:
			return c
	return null


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": WATER_DRAWER}, {"id": WIND_DRAWER}],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	var water: Card = _card(WATER_DRAWER)
	var wind: Card = _card(WIND_DRAWER)
	_expect(water != null and water.current_elements().has("水"), "setup: the Water drawer is on the field")
	_expect(wind != null and not wind.current_elements().has("水"), "setup: the Wind drawer is not Water")

	var deck = _game.get("deck")
	var top: Card = deck.deck_cards[0]
	var top_at: Vector3 = top.global_position
	var hand_before: int = _game.get("hand").cards.size()

	# A Water card's "draw 1".
	EFFECT_CONTEXT.new(_game, water, "test").draw(1, 1)
	await get_tree().process_frame
	var found: Array = _splashes()
	_expect(found.size() == 1, "a Water source's draw makes ONE splash (%d)" % found.size())
	_expect(_game.get("hand").cards.size() == hand_before + 1, "and the card is drawn")
	if found.size() == 1:
		var splash = found[0]
		var off: float = splash.centre().distance_to(top_at)
		_expect(off < 0.01, "the splash sits on the deck top (%.3f m off)" % off)
		await _wait(0.12)
		var r0: Array = splash.ring_radii()
		var drops: int = splash.visible_droplet_positions().size()
		_expect(drops >= splash.droplet_count() * 0.6,
			"droplets are thrown (%d of %d in the air)" % [drops, splash.droplet_count()])
		var highest: float = -INF
		var widest: float = 0.0
		for p in splash.visible_droplet_positions():
			highest = maxf(highest, p.y - top_at.y)
			widest = maxf(widest, Vector2(p.x - top_at.x, p.z - top_at.z).length())
		_expect(highest > 0.1 and widest > 0.1,
			"up and out of the deck (%.2f m up, %.2f m out)" % [highest, widest])
		_expect(splash.crown_spread() > 0.6, "the crown has opened (%.2f)" % splash.crown_spread())
		await _wait(0.2)
		var r1: Array = splash.ring_radii()
		_expect(float(r1[0]) > float(r0[0]), "the first ripple spreads (%.2f -> %.2f)" % [r0[0], r1[0]])
		await _wait(SPLASH.LIFETIME)
		_expect(not is_instance_valid(splash) or splash.is_queued_for_deletion(), "the splash frees itself")

	# A Wind card's "draw 1" and the plain draw (no source) do not splash.
	EFFECT_CONTEXT.new(_game, wind, "test").draw(1, 1)
	_game.draw_cards(1, 1)
	await get_tree().process_frame
	_expect(_splashes().is_empty(), "a non-Water source and a sourceless draw make no splash")

	print("[WaterSplash] %d checks | failures: %d" % [_checks, _fails])
	print("[WaterSplash] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
