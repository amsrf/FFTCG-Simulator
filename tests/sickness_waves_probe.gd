extends Node
## SUMMONING-SICKNESS WAVES probe (Card.shows_summoning_sickness + card_status_overlays + sickness_overlay.gd).
##
## Asserts what the player is promised:
##   a Forward played this turn shows the waves, but only once it has LANDED (not while arriving),
##   they lie ON the card (card-aligned, parented to the visible mesh, exactly the card's size — nothing outside it),
##   they animate (the shader's clock advances) at a calm pace (a wave takes >= 2 s to cross),
##   the sickness ending (end of turn) fades them out and the card can act,
##   gaining Haste clears them, dulling fades them and standing up brings them back,
##   leaving the field hides them at once, and a Backup or a pre-placed card never shows them.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const WAVES := preload("res://scripts/cards/sickness_overlay.gd")
const SQUIRE := 25
const KNIGHT := 50
const BLACK_BELT := 99
const MONK := 119
const EVOKER := 11   # Backup, no abilities

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Sickness] ok   %s" % what)
	else:
		_fails += 1
		print("[Sickness] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.get("field")
	await Vfx.idle()

	# PLAYED THIS TURN: the waves appear once the card has landed.
	var squire: Card = _play(game, field, SQUIRE)
	_expect(not squire.can_tap(), "a Forward played this turn cannot tap (the rule the waves report)")
	_expect(squire.overlays.sickness_state() in ["NONE", "HIDDEN"], "no waves while the card is still arriving")
	await Vfx.idle()
	_expect(squire.overlays.sickness_state() in ["APPEARING", "IDLE"],
		"the waves appear once it has landed (%s)" % squire.overlays.sickness_state())
	await get_tree().create_timer(WAVES.APPEAR_SECONDS + 0.05).timeout
	var waves: MeshInstance3D = squire.overlays.sickness_waves
	_expect(squire.overlays.sickness_state() == "IDLE" and is_equal_approx(float(waves.call("level")), 1.0),
		"they fade in fully and settle")

	# ON THE CARD: the visible mesh's child, card-aligned, exactly the face — so nothing can spill onto a neighbour.
	_expect(waves.get_parent() == squire.hand_mesh, "they ride the card's visible mesh (hover, hit and tilt follow)")
	var plane: PlaneMesh = waves.mesh
	_expect(plane != null and plane.size.is_equal_approx(squire._card_face_size()),
		"they cover exactly the card face (%s vs %s)" % [plane.size if plane else null, squire._card_face_size()])
	_expect(waves.position.y > 0.0 and waves.position.y < 0.01 and waves.rotation == Vector3.ZERO,
		"they lie flat a hair above the face")

	# ANIMATED, CALMLY.
	var t0: float = float(waves.call("shader_time"))
	await get_tree().create_timer(0.5).timeout
	_expect(float(waves.call("shader_time")) > t0 + 0.3, "the waves keep moving")
	var travel: float = float((waves.material_override as ShaderMaterial).get_shader_parameter("travel_seconds"))
	_expect(travel >= 2.0, "and calmly: a ring takes %.1f s to ripple out" % travel)

	# DULLING fades them; standing up while still sick brings them back.
	squire.tap()
	_expect(squire.overlays.sickness_state() == "LEAVING", "dulling fades the waves out")
	await get_tree().create_timer(WAVES.DISMISS_SECONDS + 0.1).timeout
	_expect(squire.overlays.sickness_state() == "HIDDEN", "and they are gone")
	squire.untap()
	_expect(squire.overlays.sickness_state() == "APPEARING", "standing up while still sick brings them back")

	# THE SICKNESS ENDS (end of the turn it was played): they fade out, and the card can act.
	squire.turn_end()
	_expect(squire.can_tap(), "after its first End Phase the card can tap")
	_expect(squire.overlays.sickness_state() == "LEAVING", "the waves fade out")
	await get_tree().create_timer(WAVES.WAKE_SECONDS + 0.1).timeout
	_expect(squire.overlays.sickness_state() == "HIDDEN", "and are gone once awake")

	# GAINING HASTE clears them.
	var knight: Card = _play(game, field, KNIGHT)
	await Vfx.idle()
	_expect(knight.overlays.sickness_state() in ["APPEARING", "IDLE"], "a second new Forward shows its waves")
	knight.add_status_effect("haste", 1)
	_expect(knight.can_tap(), "Haste lets it act")
	_expect(knight.overlays.sickness_state() == "LEAVING", "gaining Haste clears the waves")

	# LEAVING THE FIELD hides them at once.
	var belt: Card = _play(game, field, BLACK_BELT)
	await Vfx.idle()
	_expect(belt.overlays.sickness_state() in ["APPEARING", "IDLE"], "a third new Forward shows its waves")
	game.call("break_card", belt)
	await get_tree().process_frame
	_expect(belt.overlays.sickness_state() == "HIDDEN", "leaving the field hides them at once")

	# A BACKUP never shows them.
	var evoker: Card = _play(game, field, EVOKER)
	await Vfx.idle()
	await get_tree().create_timer(0.1).timeout
	_expect(evoker.overlays.sickness_state() in ["NONE", "HIDDEN"], "a Backup never shows the waves")

	# A SETUP board card (not played) shows none.
	var monk: Card = game.call("create_card", MONK, "player")
	game.add_child(monk)
	field.play_card(monk, false, false, false)
	await get_tree().process_frame
	_expect(monk.overlays.sickness_state() in ["NONE", "HIDDEN"], "a pre-placed card shows none")
	_finish(game)


func _play(game: Node, field, id: int) -> Card:
	var card: Card = game.call("create_card", id, "player")
	game.add_child(card)
	field.play_card(card, false, true, true)
	return card


func _finish(game: Node) -> void:
	print("[Sickness] RESULT: %s (%d checks, %d failed)" % ["all checks passed" if _fails == 0 else "FAILED", _checks, _fails])
	game.queue_free()
	get_tree().quit()
