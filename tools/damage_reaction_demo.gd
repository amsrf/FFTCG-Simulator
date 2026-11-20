extends Node
## Interactive demo for the card damage reaction.
##
## Run it directly (F6, or `Godot --path . res://tools/damage_reaction_demo.tscn`).
## It uses the same HandMesh-local recoil as `card.damage_fx.play_reaction()` and
## exercises the real `Card.suffer_damage()` path. Damage is cleared afterwards
## so repeated high-tier hits do not break the demo cards.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

const TARGET_IDS: Array[int] = [41, 12, 43]
const DEMO_DAMAGE: Array[int] = [3000, 5000, 8000, 12000]
const DEMO_TIER_NAMES: Array[String] = ["weak", "medium", "high", "maximum"]
const STAGGER_SECONDS := 0.20

var _game: Node = null
var _field: Node = null
var _targets: Array[Card] = []
var _labels: Array[Label3D] = []
var _selected: int = 1
var _damage_index: int = 1
var _hud: Label = null
var _last_action: String = "ready"
var _last_hit_ms: int = 0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var tier_arg: int = args.find("--tier")
	if tier_arg >= 0 and tier_arg + 1 < args.size():
		_damage_index = clampi(int(args[tier_arg + 1]), 0, DEMO_DAMAGE.size() - 1)
	MatchSetup.config = MatchSetup.build_config("clean")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	_field = _game.get("field")
	for id in TARGET_IDS:
		var card: Card = _game.create_card(id, "player")
		_game.add_child(card)
		_field.play_card(card, false, false)
		_targets.append(card)

	_build_hud()
	var phase_text: Node = _game.get_node_or_null("PhaseText")
	if phase_text != null:
		phase_text.visible = false
	await get_tree().create_timer(0.20).timeout
	_sort_targets_by_screen_x()
	_create_target_labels()
	_select(1)
	await get_tree().create_timer(0.55).timeout
	var capture_arg: int = args.find("--capture")
	if capture_arg >= 0 and capture_arg + 1 < args.size():
		await _capture_hit(args[capture_arg + 1])
		return
	_hit_selected()


## `-- --capture <dir> [--style tip|lean|corner|hop|twist]`: hit the selected card once and save a frame every 1/60 s of the reaction (1.5 s), then quit. Needs a
## real window (not --headless). Saving a PNG is slower than the reaction, so the tween is paused and STEPPED.
func _capture_hit(out_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	_hud.visible = false
	for label in _labels:
		label.visible = false
	for card in _targets:
		card.set_selected_highlight(false)
	await RenderingServer.frame_post_draw
	var card: Card = _targets[_selected]
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var style_arg: int = args.find("--style")
	if style_arg >= 0 and style_arg + 1 < args.size():
		card.damage_fx.next_style = args[style_arg + 1]
	card.suffer_damage(_damage_amount(), "Ability", "player")
	var motion: Tween = card.damage_fx.tween
	motion.pause()
	var stepped := 0.0
	for frame in range(0, 90):
		var moment := float(frame) / 60.0
		motion.custom_step(moment - stepped)
		stepped = moment
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("f%02d.png" % frame))
	print("[DamageDemo] wrote 90 frames to %s" % out_dir)
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1, KEY_KP_1:
			_select(0)
		KEY_2, KEY_KP_2:
			_select(1)
		KEY_3, KEY_KP_3:
			_select(2)
		KEY_SPACE, KEY_ENTER, KEY_R:
			_hit_selected()
		KEY_M:
			_hit_all()
		KEY_T:
			_cycle_damage_tier()
		_:
			return
	get_viewport().set_input_as_handled()


func _sort_targets_by_screen_x() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	_targets.sort_custom(func(a: Card, b: Card) -> bool:
		return cam.unproject_position(a.global_position).x < cam.unproject_position(b.global_position).x
	)


func _create_target_labels() -> void:
	for i in _targets.size():
		var card: Card = _targets[i]
		if card == null or not is_instance_valid(card):
			continue
		var label := Label3D.new()
		label.text = str(i + 1)
		label.font_size = 96
		label.pixel_size = 0.0018
		label.outline_size = 18
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.render_priority = 120
		label.modulate = Color(0.84, 0.92, 1.0, 1.0)
		label.outline_modulate = Color(0.02, 0.03, 0.10, 0.95)
		_game.add_child(label)
		label.global_position = card.global_position + Vector3.UP * 0.48
		_labels.append(label)


func _select(index: int) -> void:
	if index < 0 or index >= _targets.size():
		return
	_selected = index
	for i in _targets.size():
		var card: Card = _targets[i]
		if card != null and is_instance_valid(card):
			card.set_selected_highlight(i == _selected)
		if i < _labels.size() and is_instance_valid(_labels[i]):
			if i == _selected:
				_labels[i].modulate = Color(1.0, 0.68, 0.18, 1.0)
			else:
				_labels[i].modulate = Color(0.84, 0.92, 1.0, 1.0)
	_update_hud()


func _damage_amount() -> int:
	return DEMO_DAMAGE[clampi(_damage_index, 0, DEMO_DAMAGE.size() - 1)]


func _damage_tier_name() -> String:
	return DEMO_TIER_NAMES[clampi(_damage_index, 0, DEMO_TIER_NAMES.size() - 1)]


func _hit_selected() -> void:
	if _is_cooling_down():
		return
	var card: Card = _targets[_selected]
	if card == null or not is_instance_valid(card):
		return
	_last_hit_ms = Time.get_ticks_msec()
	_last_action = "hit Card %d — %d (%s)" % [
		_selected + 1, _damage_amount(), _damage_tier_name()]
	_update_hud()
	card.suffer_damage(_damage_amount(), "Ability", "player")
	_clear_damage_later([card], 0.95)


func _hit_all() -> void:
	if _is_cooling_down():
		return
	_last_hit_ms = Time.get_ticks_msec()
	_last_action = "all three — %d (%s), %.2f s apart" % [
		_damage_amount(), _damage_tier_name(), STAGGER_SECONDS]
	_update_hud()
	for i in _targets.size():
		var card: Card = _targets[i]
		if card != null and is_instance_valid(card):
			card.suffer_damage(_damage_amount(), "Ability", "player", null,
				float(i) * STAGGER_SECONDS)
	_clear_damage_later(_targets, 1.20)


func _clear_damage_later(cards: Array, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	for card in cards:
		if card != null and is_instance_valid(card):
			card.clear_damage()


func _cycle_damage_tier() -> void:
	_damage_index = (_damage_index + 1) % DEMO_DAMAGE.size()
	_last_action = "damage set to %d (%s)" % [_damage_amount(), _damage_tier_name()]
	_update_hud()
	_hit_selected()


func _is_cooling_down() -> bool:
	return Time.get_ticks_msec() - _last_hit_ms < 260


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	var panel := ColorRect.new()
	panel.position = Vector2(16, 14)
	panel.size = Vector2(900, 440)
	panel.color = Color(0.015, 0.020, 0.070, 0.58)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)

	_hud = Label.new()
	_hud.position = Vector2(38, 28)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_theme_font_size_override("font_size", 26)
	_hud.add_theme_color_override("font_color", Color(0.84, 0.94, 1.0))
	_hud.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.10, 0.92))
	_hud.add_theme_constant_override("outline_size", 7)
	_hud.add_theme_constant_override("line_spacing", 8)
	layer.add_child(_hud)


func _update_hud() -> void:
	if _hud == null:
		return
	_hud.text = "\n".join(PackedStringArray([
		"CARD DAMAGE REACTION",
		"Real HandMesh recoil; damage is cleared after each demo hit",
		"",
		"SPACE / R — Hit selected card",
		"1 / 2 / 3 — Select target",
		"M — Hit all three (staggered)",
		"T — Damage: %d (%s)" % [_damage_amount(), _damage_tier_name()],
		"",
		"Selected: Card %d" % (_selected + 1),
		"Last: %s" % _last_action,
	]))
