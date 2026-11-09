extends Node
## CARD DAMAGE REACTION probe.
##
## The reference is clip4: effect damage makes a card pop off the table, scale
## up and tilt, then shake/settle. The reaction must live on HandMesh (not the
## Card layout) and must not survive a zone change.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[DamageReaction] ok   %s" % what)
	else:
		_fails += 1
		print("[DamageReaction] FAIL %s" % what)


func _play_card(game: Node, field: Node, id: int) -> Card:
	var card: Card = game.create_card(id, "player")
	game.add_child(card)
	field.play_card(card, false, false)
	return card


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.get("field")

	var card: Card = _play_card(game, field, 41)
	await get_tree().process_frame
	await get_tree().create_timer(0.05).timeout
	_expect(card.hand_mesh.position.is_equal_approx(Vector3.ZERO),
		"the card starts at its resting mesh pose")

	card.suffer_damage(5000, "Ability", "player")
	await get_tree().create_timer(0.04).timeout
	_expect(card.damage_fx.is_reacting(), "effect damage starts a hit reaction")
	_expect(card.hand_mesh.position.y > 0.005, "the card pops upward off the table")
	_expect(card.hand_mesh.scale.x > 1.005, "the card scales up during the hit")
	_expect(absf(card.hand_mesh.rotation.y) > 0.005, "the card tilts during the hit")

	await get_tree().create_timer(0.72).timeout
	_expect(not card.damage_fx.is_reacting(), "the hit reaction finishes")
	_expect(card.hand_mesh.position.is_equal_approx(Vector3.ZERO)
		and card.hand_mesh.scale.is_equal_approx(Vector3.ONE)
		and card.hand_mesh.rotation.is_equal_approx(Vector3.ZERO),
		"the card returns exactly to its resting pose")

	# Combat damage keeps the clash presentation and must not trigger this.
	card.clear_damage()
	card.suffer_damage(1000, "", "player")
	await get_tree().create_timer(0.04).timeout
	_expect(not card.damage_fx.is_reacting()
		and card.hand_mesh.position.is_equal_approx(Vector3.ZERO),
		"combat damage does not play the effect-damage reaction")
	card.clear_damage()

	# Multi-target effect damage is staggered: the second card must still be at
	# rest when the first one has already popped.
	var second: Card = _play_card(game, field, 12)
	await get_tree().process_frame
	await get_tree().create_timer(0.05).timeout
	var ctx = EFFECT_CONTEXT.new(game, card, "test", {}, card, [card, second])
	ctx.damage([card, second], 1000, "multi")
	await get_tree().create_timer(0.05).timeout
	_expect(card.hand_mesh.position.y > 0.005,
		"the first target reacts immediately")
	_expect(second.hand_mesh.position.is_equal_approx(Vector3.ZERO),
		"the second target waits for the stagger")
	await get_tree().create_timer(0.24).timeout
	_expect(second.damage_fx.is_reacting() and second.hand_mesh.position.y > 0.005,
		"the second target reacts after the stagger")

	await get_tree().create_timer(0.80).timeout
	# A zone change must normalize any still-running reaction.
	card.suffer_damage(1000, "Ability", "player")
	await get_tree().create_timer(0.04).timeout
	card.enter_zone(Card.Zone.GRAVEYARD)
	await get_tree().process_frame
	_expect(not card.damage_fx.is_reacting()
		and card.hand_mesh.position.is_equal_approx(Vector3.ZERO)
		and card.hand_mesh.rotation.is_equal_approx(Vector3.ZERO),
		"leaving the field normalizes the reaction pose")

	print("[DamageReaction] %d checks | failures: %d" % [_checks, _fails])
	print("[DamageReaction] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
