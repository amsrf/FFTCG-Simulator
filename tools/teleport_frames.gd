extends Node3D
## Renders the teleport presentation frame-by-frame for inspection.
## Run windowed (not --headless):
##   godot --path . res://tools/teleport_frames.tscn
## Writes tools/shots/teleport_frames/source_*.png and destination_*.png

const CARD_SCENE := preload("res://card.tscn")
const OUT_DIR := "res://tools/shots/teleport_frames"
const CAPTURE_INTERVAL_MS := 33

var _card: Card = null
var _frame: int = 0
var _done: bool = false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.95
	cam.position = Vector3(0.0, 2.0, 0.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(cam)
	cam.current = true

	await _run_source()
	await _run_destination()
	print("[TeleportFrames] done")
	get_tree().quit()


func _new_card() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = CARD_SCENE.instantiate()
	add_child(_card)
	_card.initialize(25, "player")
	_card.enter_zone(Card.Zone.FIELD)
	_card.position = Vector3.ZERO
	_card.scale = Vector3.ONE * 1.4
	_card.visible = true


func _run_source() -> void:
	_new_card()
	var tween: Tween = _card.teleport.play_out(0.90, 0.45)
	await _capture_until(tween, "source")


func _run_destination() -> void:
	_new_card()
	var tween: Tween = _card.teleport.play_in(1.30, 0.40, 0.55)
	await _capture_until(tween, "destination")


func _capture_until(tween: Tween, prefix: String) -> void:
	_frame = 0
	var next_ms: int = 0
	_done = false
	tween.finished.connect(func() -> void: _done = true)
	while not _done:
		await get_tree().process_frame
		var now: int = Time.get_ticks_msec()
		if now >= next_ms:
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			img.save_png("%s/%s_%03d.png" % [OUT_DIR, prefix, _frame])
			_frame += 1
			next_ms = now + CAPTURE_INTERVAL_MS
	await RenderingServer.frame_post_draw
	var final_img: Image = get_viewport().get_texture().get_image()
	final_img.save_png("%s/%s_%03d.png" % [OUT_DIR, prefix, _frame])
	print("[TeleportFrames] %s: %d frames" % [prefix, _frame + 1])
