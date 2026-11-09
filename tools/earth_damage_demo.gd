extends Node
## Replays the production Earth cue without applying rules damage.
const GAME := preload("res://scenes/game/game.tscn")
const CUE := preload("res://assets/effects/earth/earth_totem_cue.tscn")
const EVENT := preload("res://scripts/vfx/vfx_event.gd")
var game: Node
var target: Card
var damage := 6000
var _cue: Node3D
var _slow := false
var _lethal := false
var _area := false
var _preview_targets: Array[Card] = []
var _preview_shards: Array[Node] = []

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	MatchSetup.config["opponent_type"] = "mock"
	game = GAME.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var cards: Array = game.get_node("Field").get_front_cards_for("player")
	if not cards.is_empty():
		target = cards.front()
	_update_help()

func _hit() -> void:
	_reset()
	if not is_instance_valid(target):
		return
	var cue: Node3D = CUE.instantiate()
	_cue = cue
	add_child(cue)
	if _area:
		_preview_targets.assign(game.get_node("Field").get_front_cards_for("player"))
	else:
		_preview_targets.assign([target])
	var event := EVENT.new(EVENT.Kind.BOARD_DAMAGE if _area else EVENT.Kind.DAMAGE,
		_preview_targets, "土", damage, null, "board" if _area else "single")
	if _lethal:
		for victim in _preview_targets:
			event.target_visuals[victim.get_instance_id()] = {"lethal": true,
				"transform": victim.global_transform, "floor_y": victim.get_parent().global_position.y}
			var existing := game.get_children()
			game._play_break_shatter(victim)
			for child in game.get_children():
				if not existing.has(child) and child.get_script() == preload("res://scripts/cards/card_shards.gd"):
					_preview_shards.append(child)
			victim.set_hidden(true)
	await cue.play(event)
	if is_instance_valid(cue):
		cue.queue_free()
	if _cue == cue:
		_cue = null

func _reset() -> void:
	for effect in _preview_shards:
		if is_instance_valid(effect):
			effect.queue_free()
	_preview_shards.clear()
	if is_instance_valid(_cue):
		_cue.cancel()
	_cue = null
	for victim in _preview_targets:
		if is_instance_valid(victim):
			victim.damage_fx.normalize()
			victim.set_hidden(false)
	_preview_targets.clear()
	if is_instance_valid(target):
		target.damage_fx.normalize()
		target.set_hidden(false)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE: _hit()
		KEY_R: _reset()
		KEY_1: damage = 3000
		KEY_2: damage = 6000
		KEY_3: damage = 8000
		KEY_4: damage = 10000
		KEY_K: _lethal = not _lethal
		KEY_M: _area = not _area
		KEY_S:
			_slow = not _slow
			Engine.time_scale = 0.25 if _slow else 1.0
	_update_help()

func _update_help() -> void:
	$CanvasLayer/Panel/Help.text = "EARTH DAMAGE — VISUAL PREVIEW\nSpace: hit   R: reset   S: slow motion\n1: 3000   2: 6000   3: 8000   4: 10000\nK: lethal preview %s   M: multi-target %s\nSelected damage: %d   Target: %s" % ["ON" if _lethal else "OFF", "ON" if _area else "OFF", damage, target.card_name if target != null else "none"]

func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if is_instance_valid(target):
		target.damage_fx.normalize()
