extends Node

const GAME_SCENE := preload("res://game.tscn")
const SHARDS_SCENE := preload("res://card_shards.tscn")
const CARD_SCENE := preload("res://card.tscn")

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
	var before: int = _game.get_child_count()
	_game.call("break_card", card)
	await get_tree().process_frame

	var fx: Node = null
	for child in _game.get_children():
		if child.has_method("burst_from_card"):
			fx = child
			break
	_expect(fx != null, "breaking a card creates a shatter node")
	if fx != null:
		_expect(fx.get_child_count() == 1, "the chosen fracture variant is instantiated")
		var meshes: Array[MeshInstance3D] = []
		_meshes(fx, meshes)
		_expect(meshes.size() == 10, "the shatter has ten pieces")
		_expect(fx.get("_running") == true, "the explosion is running")
		if not meshes.is_empty():
			var art = meshes[0].get_surface_override_material(0)
			var glass = meshes[0].get_surface_override_material(1)
			_expect(art != null and art is ShaderMaterial and art.get_shader_parameter("texture_albedo") != null,
				"front faces keep the card artwork material")
			_expect(glass != null and glass is ShaderMaterial, "cut faces use the glass material")

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
