extends Node
## Downscales a reference PNG so the image tool can read it.
##
## The image tool hangs on the full-size references (2.5 MB, 1694x841) and has done so repeatedly — it is not a
## size limit either, since it also failed on a 17 KB file. Rather than give up on seeing the reference at all,
## this writes a small JPEG copy that the tool can usually digest.
##
##   godot --headless res://tools/ref_shrink.tscn -- res://references/search.png 900

const DEFAULT_PATH := "res://references/search.png"
const DEFAULT_WIDTH := 900
const OUT_DIR := "res://tools/shots"

func _ready() -> void:
	var path: String = DEFAULT_PATH
	var target_width: int = DEFAULT_WIDTH
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]
	if args.size() > 1:
		target_width = int(args[1])

	var img := Image.new()
	if img.load(path) != OK:
		print("[RefShrink] cannot load %s" % path)
		get_tree().quit(1)
		return

	var w: int = img.get_width()
	var h: int = img.get_height()
	print("[RefShrink] source %dx%d" % [w, h])

	# Downscale in one step: resize() resamples properly, and doing it once keeps it simple.
	var scale: float = float(target_width) / float(w)
	img.resize(target_width, maxi(1, int(round(float(h) * scale))), Image.INTERPOLATE_LANCZOS)
	print("[RefShrink] -> %dx%d" % [img.get_width(), img.get_height()])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var base: String = path.get_file().get_basename()
	var out_path: String = "%s/%s_small.jpg" % [OUT_DIR, base]
	var err: int = img.save_jpg(out_path, 0.82)
	if err != OK:
		# JPEG can refuse an image with an odd pixel format; PNG always works.
		out_path = out_path.get_basename() + ".png"
		err = img.save_png(out_path)
	if err != OK:
		print("[RefShrink] could not write %s (error %d)" % [out_path, err])
		get_tree().quit(1)
		return

	var size_kb: float = float(FileAccess.get_file_as_bytes(out_path).size()) / 1024.0
	print("[RefShrink] wrote %s  (%.1f KB)" % [out_path, size_kb])
	get_tree().quit()
