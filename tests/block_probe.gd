extends Node3D
## Headless probe for the blocking visuals.
##
## Run it instead of the game:
##   "<godot>" --headless res://tests/block_probe.tscn --quit-after 5000
##
## Covers the two cases the human sees, and the rules the cues are supposed to obey:
##
##   * LOCAL defender — everything that could block is marked (blue ring), the pick turns
##     orange and draws the arc centre-to-centre, a reselect moves BOTH, clicking the same
##     card deselects, and clearing the prompt leaves every card dark again
##   * OPPONENT defender — the arc appears for their pick, but NO blue ring is used, since
##     that cue means "the game is asking YOU to choose"
#---
## It says nothing about how any of it LOOKS.

const GAME_SCENE := preload("res://game.tscn")

var _failures: Array[String] = []
var _field = null

func _ready() -> void:
	print("\n[BlockProbe] ================= blocking visuals =================")
	MatchSetup.config = MatchSetup.build_config("debug")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	$Camera3D.current = true
	_field = game.get("field")
	if _field == null:
		_expect(false, "the game scene exposed a Field")
		_report()
		get_tree().quit()
		return

	# The debug board gives the opponent one untapped Forward (Squall) and the player two
	# (Zack, Squall), which is exactly what the reselect case needs.
	var their_attacker: Card = _first_untapped_forward("opponent")
	var mine: Array = _untapped_forwards("player")
	_expect(their_attacker != null, "the opponent has an untapped Forward to attack with")
	_expect(mine.size() >= 2, "the player has at least two untapped Forwards (got %d)" % mine.size())
	if their_attacker == null or mine.size() < 2:
		_report()
		get_tree().quit()
		return
	_field.set_attacker(their_attacker)
	_expect(_field.attacker_card == their_attacker, "the attacker is declared")

	# ---- LOCAL DEFENDER: the game is asking the human ----------------------------
	_field.set_blockable("player", true)
	var marked: Array = _marked()
	print("[BlockProbe] marked blue: %s" % [_names(marked)])
	_expect(marked.size() == mine.size(),
		"exactly my %d untapped Forwards are marked (got %d)" % [mine.size(), marked.size()])
	var only_mine: bool = true
	for c in marked:
		if c.controller != "player" or not _field.can_block(c):
			only_mine = false
	_expect(only_mine, "every marked card is one of my own untapped Forwards")

	var first: Card = mine[0]
	_field.set_blocker_card(first)
	_expect(_field.blocker_card == first, "clicking a card selects it as the blocker")
	_expect(first._selected_highlight_on, "the selected blocker turns orange")
	var arrow = _field.block_arrow
	_expect(arrow != null and arrow.is_aiming, "selecting a blocker draws an arc")
	if arrow != null:
		var start: Vector3 = first.get_global_face_centre()
		var target: Vector3 = their_attacker.get_global_face_centre()
		print("[BlockProbe] arc %s -> %s (blocker centre %.3f m from attacker centre)"
			% [arrow.start_pos, target, start.distance_to(target)])
		_expect(arrow.start_pos.distance_to(start) < 0.01,
			"the arc starts at the blocker's CENTRE")
		var tip_gap: float = _nearest_vertex(arrow, target)
		var path: float = _farthest_vertex(arrow, start)
		var chord: float = start.distance_to(target)
		print("[BlockProbe] tip is %.4f m from the attacker's centre; the ribbon runs %.3f m for a %.3f m chord"
			% [tip_gap, path, chord])
		_expect(tip_gap < 0.05, "the arc lands on the attacker's centre")
		# A cross-row link must NOT bow along its own chord: that made a 1.54 m path for an
		# 0.85 m span, reading as a long loop rather than an arc. (The shaft is trimmed for
		# the head, so this measures slightly under the true path.)
		_expect(path < chord * 1.5,
			"the arc bows instead of running along its own chord (%.2fx)" % (path / chord))

	# Reselect: the orange and the arc both move, nothing is left behind.
	var second: Card = mine[1]
	_field.set_blocker_card(second)
	print("[BlockProbe] reselected: %s" % second.card_name)
	_expect(not first._selected_highlight_on, "the previous blocker is no longer orange")
	_expect(second._selected_highlight_on, "the new blocker is orange")
	_expect(_field.blocker_card == second, "the new blocker is the selected one")
	if arrow != null:
		_expect(arrow.start_pos.distance_to(second.get_global_face_centre()) < 0.01,
			"the arc moved to the new blocker's centre")

	# Clicking the same card again deselects.
	_field.set_blocker_card(second)
	_expect(_field.blocker_card == null, "clicking the same card again deselects it")
	_expect(not second._selected_highlight_on, "deselecting clears the orange")
	_expect(arrow == null or not arrow.is_aiming, "deselecting hides the arc")

	# The prompt glow is only for the duration of the question.
	_field.set_blockable("player", false)
	_expect(_marked().is_empty(), "clearing the prompt leaves every card dark again")

	# ---- OPPONENT DEFENDER: not the human's choice -------------------------------
	var their_blocker: Card = their_attacker  # any of their untapped Forwards will do
	_field.show_block_arc(their_blocker)
	print("[BlockProbe] opponent blocks with %s" % their_blocker.card_name)
	_expect(arrow != null and arrow.is_aiming, "the opponent's pick draws an arc for us to see")
	if arrow != null:
		_expect(arrow.start_pos.distance_to(their_blocker.get_global_face_centre()) < 0.01,
			"their arc starts at their blocker's centre")
	_expect(_marked().is_empty(),
		"no blue ring is used for the opponent's pick — that cue means \"your choice\"")

	# And the whole thing is cleared when the combat's blocker resets.
	_field.reset_blocker()
	_expect(arrow == null or not arrow.is_aiming, "reset_blocker() hides the arc")
	_expect(not their_blocker._selected_highlight_on, "reset_blocker() clears any orange")

	_report()
	get_tree().quit()

func _untapped_forwards(controller: String) -> Array:
	var out: Array = []
	for c in _field.get_all_cards():
		if c.controller == controller and _field.can_block(c):
			out.append(c)
	return out

func _first_untapped_forward(controller: String) -> Card:
	var found: Array = _untapped_forwards(controller)
	return found[0] if found.size() > 0 else null

func _marked() -> Array:
	var out: Array = []
	for c in _field.get_all_cards():
		if c.is_valid_target:
			out.append(c)
	return out

## Every vertex of every surface. The TIP lives in the head (surface 1), so scanning the
## shaft alone misses the very point the arrow lands on.
func _vertices(arrow) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mesh: ArrayMesh = arrow.line.mesh
	if mesh == null:
		return out
	for s in range(mesh.get_surface_count()):
		out.append_array(mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	return out

## Nearest vertex to a point. For the TARGET this is the head's tip, so "the arrow lands
## here" is this being ~0.
func _nearest_vertex(arrow, point: Vector3) -> float:
	var verts: PackedVector3Array = _vertices(arrow)
	if verts.is_empty():
		return -1.0
	var near: float = INF
	for v in verts:
		near = minf(near, point.distance_to(v))
	return near

func _farthest_vertex(arrow, point: Vector3) -> float:
	var mesh: ArrayMesh = arrow.line.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return -1.0
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var far: float = 0.0
	for v in verts:
		far = maxf(far, point.distance_to(v))
	return far

func _names(cards: Array) -> String:
	var out: Array[String] = []
	for c in cards:
		out.append("%s/%s" % [c.card_name, c.controller])
	return str(out)

func _expect(condition: bool, what: String) -> void:
	if condition:
		print("[BlockProbe]  ok  %s" % what)
	else:
		_failures.append(what)
		print("[BlockProbe] FAIL %s" % what)

func _report() -> void:
	if _failures.is_empty():
		print("[BlockProbe] RESULT: all checks passed\n")
		return
	print("[BlockProbe] RESULT: %d check(s) FAILED" % _failures.size())
	for f in _failures:
		print("[BlockProbe]   x %s" % f)
	print("")
