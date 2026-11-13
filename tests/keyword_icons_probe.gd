extends Node
## Keyword badges: a field card shows one badge per keyword it HAS, in a row along the bottom of its face starting
## from the left; the row closes up when a keyword goes away, and nothing is shown off the field.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const TEST_GROUNDS := preload("res://scripts/core/test_grounds.gd")

var _checks: int = 0
var _fails: int = 0


func _ready() -> void:
	await get_tree().process_frame
	MatchSetup.config = TEST_GROUNDS.config("clean")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	game.player_agent = MockAgent.new()
	game.player_agent.bind(game)
	game.opponent_agent = MockAgent.new()
	game.opponent_agent.bind(game)
	await get_tree().process_frame

	var field = game.field
	var card: Card = game.create_card(1, "player")
	game.add_child(card)
	field.play_card(card, false, false)
	await get_tree().process_frame

	var icons = card.keyword_icons
	_expect(not card.is_brave() and not card.is_first_strike(), "setup: card 1 (Auron) prints neither keyword")
	_expect(icons.shown().is_empty(), "an ordinary card shows no badges")

	card.add_status_effect("first_strike", 1)
	await get_tree().process_frame
	_expect(icons.shown() == ["first_strike"], "First Strike alone shows one badge (got %s)" % [icons.shown()])
	var face: Vector2 = card._card_face_size()
	var fs: MeshInstance3D = icons.badge("first_strike")
	_expect(fs != null and fs.position.x < -face.x * 0.25, "a lone badge sits at the LEFT of the face (x %.3f)" % fs.position.x)
	_expect(fs.position.z > face.y * 0.30, "along the BOTTOM of the face (z %.3f of half-height %.3f)" % [fs.position.z, face.y * 0.5])
	var half: float = (fs.mesh as PlaneMesh).size.x * 0.5
	_expect(fs.position.x - half > -face.x * 0.5 and fs.position.z + half < face.y * 0.5, "and wholly inside the card")
	_expect(fs.get_parent().get_parent() == card.hand_mesh, "the row rides on HandMesh (follows the damage recoil)")
	var mat := fs.material_override as StandardMaterial3D
	_expect(mat != null and mat.albedo_texture != null and mat.albedo_texture.get_width() >= 64, "the badge has its texture")

	card.add_status_effect("brave", 1)
	await get_tree().process_frame
	_expect(icons.shown() == ["brave", "first_strike"], "both keywords: Brave then First Strike (got %s)" % [icons.shown()])
	var br: MeshInstance3D = icons.badge("brave")
	_expect(br.position.x < fs.position.x and is_equal_approx(br.position.z, fs.position.z), "the row runs left to right on one line")
	_expect(fs.position.x - br.position.x > (fs.mesh as PlaneMesh).size.x, "the badges do not overlap")

	card.add_status_effect("unbreakable", 1)
	await get_tree().process_frame
	_expect(icons.shown() == ["brave", "first_strike", "indestructible"],
		"\"cannot be broken\" adds the indestructible badge third (got %s)" % [icons.shown()])
	var ind: MeshInstance3D = icons.badge("indestructible")
	var ind_half: float = (ind.mesh as PlaneMesh).size.x * 0.5
	_expect(ind.position.x > fs.position.x and ind.position.x + ind_half < face.x * 0.5, "three badges still fit on the card")
	_expect(mat.albedo_texture.get_width() >= 256, "badges are rasterized at 256 px (got %d)" % mat.albedo_texture.get_width())
	card.add_status_effect("block_disabled", 1)
	await get_tree().process_frame
	_expect(icons.shown() == ["brave", "first_strike", "indestructible", "cannot_block"],
		"\"cannot block\" adds the cracked-shield badge fourth (got %s)" % [icons.shown()])
	var cb: MeshInstance3D = icons.badge("cannot_block")
	var cb_half: float = (cb.mesh as PlaneMesh).size.x * 0.5
	_expect(cb.position.x + cb_half < face.x * 0.5 and br.position.x - (br.mesh as PlaneMesh).size.x * 0.5 > -face.x * 0.5,
		"four badges shrink to stay on the card")
	card.status_effects.erase("block_disabled")
	card.refresh_status_visuals()
	await get_tree().process_frame
	_expect(is_equal_approx((fs.mesh as PlaneMesh).size.x, face.x * 0.23), "and grow back to full size when one goes")
	card.status_effects.erase("unbreakable")
	card.refresh_status_visuals()
	await get_tree().process_frame

	card.status_effects.erase("brave")
	card.refresh_status_visuals()
	await get_tree().process_frame
	_expect(icons.shown() == ["first_strike"], "losing Brave closes the row up")
	_expect(is_equal_approx(fs.position.x, br.position.x), "First Strike moves into the leftmost slot")

	card.enter_zone(Card.Zone.HAND)
	await get_tree().process_frame
	_expect(icons.shown().is_empty(), "leaving the field hides the badges")

	print("[KeywordIcons] %d checks | failures: %d" % [_checks, _fails])
	print("[KeywordIcons] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if what.is_empty():
		return
	_checks += 1
	if ok:
		print("[KeywordIcons] ok   ", what)
	else:
		_fails += 1
		print("[KeywordIcons] FAIL ", what)
