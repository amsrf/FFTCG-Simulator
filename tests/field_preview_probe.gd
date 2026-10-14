extends Node
## FIELD HOVER PREVIEW probe — the hover a human does, driven without a mouse.
##
## The point of writing this rather than trusting a boot: the field preview is a SCREEN-SPACE aid, and
## nothing in the game-logic probes touches it. A boot would prove the script parses; it would not prove
## the preview appears, shows the right card, is readable, stays inside the viewport, or keeps its hands
## off the mouse. Those are exactly the things that go wrong with an overlay, so they are asserted.
##
## The last two checks drive Card._on_card_area_3d_mouse_entered/exited directly — the same functions the
## card's Area3D calls — so the wiring from a hovering pointer to the preview is covered too.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[FieldPreview] ok   %s" % what)
	else:
		_fails += 1
		print("[FieldPreview] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = game.get("field")
	_expect(field != null, "the field exists")
	if field == null:
		_finish()
		return

	var fronts: Array = field.get("front_cards")
	_expect(fronts.size() > 0, "and the debug board has cards on it")
	if fronts.is_empty():
		_finish()
		return
	var card = fronts[0]

	_expect(not field.preview_visible(), "no preview before anything is hovered")

	# The hover, driven directly — the call the card's hover handler makes.
	field.show_card_preview(card)
	await get_tree().process_frame
	_expect(field.preview_visible(), "hovering a field card SHOWS the preview")
	_expect(field.preview_card() == card, "and it is showing the card that was hovered")

	var p = field.get("_preview")
	_expect(p != null, "the preview node exists")
	if p != null:
		_expect(p.texture != null, "and it has a texture — the full scan, not a blank panel")
		var view: Vector2 = get_viewport().get_visible_rect().size
		var frac: float = p.size.y / maxf(view.y, 1.0)
		print("[FieldPreview] preview %.0f x %.0f px (%.0f%% of %.0f tall) at %s" % [
			p.size.x, p.size.y, frac * 100.0, view.y, str(p.position)])
		# A BAND, NOT A FLOOR. The first version only asked "is it big enough", so turning the size down to
		# something reasonable FAILED the test — an assertion holding a number fights every tuning change.
		# This encodes the actual intent: readable, but not covering the board.
		_expect(frac > 0.25 and frac < 0.55,
			"and it is readable without taking over the screen (0.25-0.55 of the viewport)")
		_expect(p.size.y <= view.y and p.size.x <= view.x, "and it fits in the viewport")
		_expect(p.position.x >= 0.0 and p.position.y >= 0.0, "and it is not off the left or top")
		_expect(p.position.x + p.size.x <= view.x + 1.0, "nor off the right")
		_expect(p.position.y + p.size.y <= view.y + 1.0, "nor off the bottom")
		_expect(p.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"and it IGNORES the mouse, or it would steal the hover that opened it")

		# AND IT MUST NOT SIT ON TOP OF THE CARD. This check exists because of the reported bug: the preview was
		# offset from the card's CENTRE, so it covered the card's right half — the aid hiding the thing it was
		# meant to help read. Measured against the card's rightmost projected corner so a rotated card is handled.
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			var s3: Vector3 = card.global_transform.basis.get_scale()
			var across: Vector3 = card.global_transform.basis.x.normalized() * (0.429 * 0.5 * s3.x)
			var right_x: float = maxf(cam.unproject_position(card.global_position + across).x,
				cam.unproject_position(card.global_position - across).x)
			_expect(p.position.x >= right_x - 2.0,
				"and it does NOT overlap the card it previews (its left edge %.0f vs the card's right edge %.0f)"
					% [p.position.x, right_x])

	# Now the real path: the card's own handler, which is what a hovering pointer triggers.
	card._on_card_area_3d_mouse_entered()
	await get_tree().process_frame
	_expect(field.preview_visible(), "the card's own hover handler reaches the preview")
	card._on_card_area_3d_mouse_exited()
	await get_tree().process_frame
	_expect(not field.preview_visible(), "and leaving the card takes it away")

	_finish()


func _finish() -> void:
	print("[FieldPreview] %d checks | failures: %d" % [_checks, _fails])
	print("[FieldPreview] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
