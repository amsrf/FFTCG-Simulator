extends Control
## Opens the deck search window and screenshots it, so the layout can be looked at rather than only measured.
##
## Windowed on purpose: the probes run headless, and headless has no pixels. This is the same loop used for the
## arrow and crystal shots.
##
##   godot --resolution 1600x900 res://tools/search_shot.tscn

const SEARCH := preload("res://deck_search.tscn")

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# A plain backdrop, standing in for the board, so the window's dim has something to sit over.
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.20, 0.17)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var window = SEARCH.instantiate()
	add_child(window)

	# The real Agrias deck's shape: six Ovelia across two ids, three Agrias, one Auron.
	window.open([714, 156, 156, 156, 714, 714, 151, 151, 151, 1], {"name": "Ovelia"})

	# HOVER a card, so the shot shows the thing being judged: the hovered card growing toward the viewer while the
	# rest of the row stays where it is. Without this the screenshot is indistinguishable from the version with the
	# neighbours sliding away.
	await get_tree().process_frame
	var middle: Control = window._fan.get_child(2)
	if middle != null:
		window._hover(window._id_of(middle), middle)

	# Give the layout a frame, then let the renderer finish before reading the framebuffer. The hover is TWEENED, so
	# this waits past SPREAD_SECONDS rather than a single frame, which would catch it mid-way.
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw

	var img: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	var out: String = "res://tools/shots/search_window.png"
	var err: int = img.save_png(out)
	if err != OK:
		print("[SearchShot] save failed (%d)" % err)
	else:
		var kb: float = float(FileAccess.get_file_as_bytes(out).size()) / 1024.0
		print("[SearchShot] wrote %s  %dx%d  %.1f KB" % [out, img.get_width(), img.get_height(), kb])
	get_tree().quit()
