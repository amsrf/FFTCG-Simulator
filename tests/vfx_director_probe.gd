extends Node
## VFX EVENT CONTRACT probe.
##
## Checks that rules-facing code emits semantic events through the autoload
## director instead of spawning presentation directly:
##   status applied/removed, targeted damage, board damage, preset lookup.

const GAME_SCENE := preload("res://game.tscn")
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Vfx] ok   %s" % what)
	else:
		_fails += 1
		print("[Vfx] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	Vfx.clear_events()

	var card: Card = _game.create_card(41, "player")
	_game.add_child(card)
	_field.play_card(card, false, false)
	card.status_effects.clear()
	await get_tree().process_frame

	card.add_status_effect("frozen", 1)
	var applied: Array = Vfx.get_events()
	_expect(applied.size() == 1 and applied[0].kind == VfxEvent.Kind.STATUS_APPLIED,
		"adding a status emits one STATUS_APPLIED event")
	_expect(applied[0].status == "frozen" and applied[0].duration == 1,
		"the status event carries its name and duration")

	card.status_effects.erase("frozen")
	card.refresh_status_visuals()
	var removed: Array = Vfx.get_events()
	_expect(removed.size() == 2 and removed[1].kind == VfxEvent.Kind.STATUS_REMOVED,
		"directly erasing a status and refreshing emits STATUS_REMOVED")

	Vfx.clear_events()
	var other: Card = _game.create_card(25, "player")
	_game.add_child(other)
	_field.play_card(other, false, false)
	await get_tree().process_frame

	var ctx = EFFECT_CONTEXT.new(_game, card, "static", {}, card, [card, other])
	ctx.damage([card, other], 100, "radial")
	var damage_events: Array = Vfx.get_events()
	_expect(damage_events.size() == 1 and damage_events[0].kind == VfxEvent.Kind.DAMAGE,
		"effect damage emits one DAMAGE event")
	_expect(damage_events[0].target_count() == 2 and damage_events[0].mode == "radial",
		"the damage event preserves targets and spread mode")

	Vfx.clear_events()
	ctx.board_damage([card, other], 100)
	var board_events: Array = Vfx.get_events()
	_expect(board_events.size() == 1 and board_events[0].kind == VfxEvent.Kind.BOARD_DAMAGE,
		"board_damage emits a distinct BOARD_DAMAGE event")

	var fire: VfxPreset = Vfx.preset_for_element("火")
	_expect(fire != null and fire.tint.is_equal_approx(Color(0.86, 0.09, 0.17)),
		"element presets are loaded and expose their tint")

	print("[Vfx] %d checks | failures: %d" % [_checks, _fails])
	print("[Vfx] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
