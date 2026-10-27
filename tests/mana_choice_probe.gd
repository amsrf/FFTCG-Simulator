extends Node
## Radial mana choice: one static crystal per available element, arranged evenly around the card.

const GAME_SCENE := preload("res://game.tscn")
const COSMOS := 183

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _assistant = null
var _card: Card = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[ManaChoice] ok   %s" % what)
	else:
		_fails += 1
		print("[ManaChoice] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"opponent_type": "mock",
		"player_field": [{"id": COSMOS}],
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_assistant = _game.get("assistant")
	for c in _field.get_all_cards():
		if c.id == COSMOS:
			_card = c
	_expect(_card != null, "Cosmos is on the field")
	_expect(_card.mana_elements().size() == 8, "a source that produces any Element offers eight colours")

	_assistant.mana_cost = {"火": 1}
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.PAYING_COST)
	_field.begin_mana_choice(_card)
	await get_tree().process_frame
	var choice = _field.get("mana_choice")
	_expect(choice != null and is_instance_valid(choice), "clicking a multi-colour source opens the radial picker")
	var crystals: Array = choice.get("crystals") if choice != null else []
	_expect(crystals.size() == 8, "one crystal per available colour")

	var center: Vector3 = _card.get_global_face_centre()
	var cam: Camera3D = get_viewport().get_camera_3d()
	var right: Vector3 = cam.global_transform.basis.x.normalized()
	var up: Vector3 = -cam.global_transform.basis.y.normalized()
	var distances: Array[float] = []
	var angles: Array[float] = []
	for crystal in crystals:
		var pos: Vector3 = (crystal as Node3D).global_position
		var rel: Vector3 = pos - center
		distances.append(rel.length())
		angles.append(atan2(rel.dot(up), rel.dot(right)))
	_expect(_all_close(distances, distances[0], 0.03), "the crystals sit on one circle around the card")
	angles.sort()
	var gaps: Array[float] = []
	for i in range(angles.size()):
		var next: float = angles[(i + 1) % angles.size()] + (TAU if i == angles.size() - 1 else 0.0)
		gaps.append(next - angles[i])
	_expect(_all_close(gaps, TAU / 8.0, 0.02), "and are equally spaced in angle")
	var still: bool = true
	for crystal in crystals:
		if absf(float(crystal.get("spin_deg_per_sec"))) > 0.001 \
				or absf(float(crystal.get("idle_spin_deg_per_sec"))) > 0.001 \
				or absf(float(crystal.get("glow_pulse"))) > 0.001:
			still = false
	_expect(still, "the picker crystals are stop-motion, unlike the payment row")

	var first = crystals[0]
	var tween: Tween = choice.get("_tweens").get(first)
	choice.call("_set_hover", first, true)
	tween = choice.get("_tweens").get(first)
	if tween != null and tween.is_valid():
		tween.pause()
		tween.custom_step(0.2)
	_expect(first.scale.x > 1.01, "hover grows a crystal")

	choice.call("choose", "火")
	await get_tree().process_frame
	_expect(_field.selected_cards_for_mana_conversion.has(_card), "choosing a crystal selects the source")
	_expect(str(_field.selected_mana_elements.get(_card, "")) == "火", "and remembers the colour it generated")
	_expect(int(_assistant.mana_acc.get("火", 0)) == 1, "the chosen colour reaches the payment accumulator")
	_expect(_field.get("mana_choice") == null, "the picker closes after choosing")

	_field.remove_card_from_mana_conversion(_card)
	_expect(int(_assistant.mana_acc.get("火", 0)) == 0, "deselecting refunds the same colour")

	print("[ManaChoice] %d checks | failures: %d" % [_checks, _fails])
	print("[ManaChoice] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()


func _all_close(values: Array[float], target: float, tolerance: float) -> bool:
	for value in values:
		if absf(value - target) > tolerance:
			return false
	return true
