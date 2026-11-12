extends Node

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const SHARDS_SCENE := preload("res://scenes/cards/card_shards.tscn")
const CARD_SCENE := preload("res://scenes/cards/card.tscn")
const SHARDS_SCRIPT := preload("res://scripts/cards/card_shards.gd")

var _checks: int = 0
var _fails: int = 0
var _game: Node


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Shatter] ok   %s" % what)
	else:
		_fails += 1
		print("[Shatter] FAIL %s" % what)


func _meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_meshes(child, out)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var card = _game.field.get_front_cards_for("player")[0]
	var elements: Array[String] = card.current_elements()
	var expected_tint: Color = Card.ELEMENT_COLOURS.get(elements[0] if not elements.is_empty() else "", Color(0.70, 0.90, 1.0))
	_game.call("break_card", card)
	await get_tree().process_frame

	var fx: Node = null
	for child in _game.get_children():
		if child.has_method("burst_from_card"):
			fx = child
			break
	_expect(fx != null, "breaking a card creates a break presentation node")
	if fx != null:
		_expect(int(fx.get("style")) == SHARDS_SCRIPT.Style.DESTROY_BURST, "a match break uses the destroy burst")
		await _check_destroy_burst(fx, expected_tint)

	# GLASS_SHATTER: the Blender fracture, still selectable on the node.
	var glass: Node = SHARDS_SCENE.instantiate()
	glass.set("style", SHARDS_SCRIPT.Style.GLASS_SHATTER)
	glass.set("free_when_done", false)
	add_child(glass)
	var victim: Card = CARD_SCENE.instantiate()
	add_child(victim)
	victim.initialize(1, "player")
	victim.enter_zone(Card.Zone.FIELD)
	glass.call("burst_from_card", victim)
	await get_tree().process_frame
	_check_glass(glass)
	glass.call("_clear")

	# Direct controller: verify it can be reused by the preview.
	var direct: Node = SHARDS_SCENE.instantiate()
	add_child(direct)
	direct.set("free_when_done", false)
	var c: Card = CARD_SCENE.instantiate()
	add_child(c)
	c.initialize(1, "player")
	c.enter_zone(Card.Zone.FIELD)
	direct.call("burst_from_card", c)
	await get_tree().process_frame
	_expect(direct.get("_running") == true, "the preview can trigger a second burst")
	direct.call("_clear")

	print("[Shatter] %d checks | failures: %d" % [_checks, _fails])
	print("[Shatter] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()


## The reference beats, in order (Clips/destroy 145-205, ONE card's burst): the card pops, crystal shards of its
## element fly out, a single swirl opens into a bubble, sparkles twinkle late, and the whole thing cleans itself up.
func _check_destroy_burst(fx: Node, expected_tint: Color) -> void:
	var burst: Node = fx.get_node_or_null("DestroyBurst")
	_expect(burst != null, "the destroy burst is spawned under the break node")
	if burst == null:
		return
	_expect(burst.get("top_level") == true, "the burst lives in world space (it must not inherit the card's scale)")
	# sample() is deterministic and the next _process re-samples at the burst's own age, so this does not disturb it.
	# (Reading after "one frame" depends on that frame's delta, which headless can make long.)
	burst.call("sample", 0.01)
	_expect(burst.call("pop_opacity") > 0.9, "the card's picture is still there on the break frame (no gap)")
	_expect(burst.call("shard_count") >= 16, "crystal shards are built")
	_expect((burst.call("shard_tint") as Color).is_equal_approx(expected_tint),
		"the shards are the broken card's element colour")
	_expect(burst.find_children("Swirl*", "", false, false).size() == 1, "ONE swirl: a single burst per card")
	var centre: Vector3 = (fx as Node3D).global_position
	await _wait(0.10)
	var early: PackedVector3Array = (burst.call("visible_shard_positions") as PackedVector3Array).duplicate()
	await _wait(0.12)
	_expect(burst.call("pop_opacity") == 0.0, "the card's picture has popped by 0.22 s")
	var late: PackedVector3Array = (burst.call("visible_shard_positions") as PackedVector3Array).duplicate()
	_expect(not early.is_empty() and not late.is_empty() and _mean_distance(late, centre) > _mean_distance(early, centre) * 1.3,
		"the shards fly outward (%.3f -> %.3f m)" % [_mean_distance(early, centre), _mean_distance(late, centre)])
	await _wait(0.30)
	_expect(float(burst.call("swirl_bubble")) > 0.9 and float(burst.call("swirl_size")) > 1.5,
		"by 0.5 s the swirl has opened into a bubble wider than the card (%.2f card heights)" % float(burst.call("swirl_size")))
	var sparkled: bool = int(burst.call("visible_sparkle_count")) > 0
	if not sparkled:
		sparkled = await _sparkles_later(burst)
	_expect(sparkled, "sparkles twinkle as it settles")
	# LIFETIME is 1.5 s and about 0.6 s has passed.
	await _wait(1.3)
	_expect(not is_instance_valid(burst) and not is_instance_valid(fx), "the burst and its break node free themselves")


func _sparkles_later(burst: Node) -> bool:
	for i in 30:
		await _wait(0.02)
		if not is_instance_valid(burst):
			return false
		if int(burst.call("visible_sparkle_count")) > 0:
			return true
	return false


func _check_glass(fx: Node) -> void:
	var model: Node = fx.get("_model")
	_expect(model != null, "glass: the chosen fracture variant is instantiated")
	var meshes: Array[MeshInstance3D] = []
	if model != null:
		_meshes(model, meshes)
	_expect(meshes.size() == 10, "glass: the shatter has ten pieces")
	_expect(fx.get("_running") == true, "glass: the explosion is running")
	var flash: Node = fx.get("_flash")
	_expect(flash != null and flash is MeshInstance3D, "glass: a burst flash is spawned on top of the pieces")
	if not meshes.is_empty():
		var art = meshes[0].get_surface_override_material(0)
		var glass = meshes[0].get_surface_override_material(1)
		_expect(art != null and art is ShaderMaterial and art.get_shader_parameter("texture_albedo") != null,
			"glass: front faces keep the card artwork material")
		_expect(glass != null and glass is ShaderMaterial, "glass: cut faces use the glass material")


func _mean_distance(points: PackedVector3Array, centre: Vector3) -> float:
	if points.is_empty():
		return 0.0
	var total := 0.0
	for p in points:
		total += p.distance_to(centre)
	return total / points.size()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
