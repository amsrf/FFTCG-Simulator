extends Node
## Loads every scene, resource, script and shader in the project and reports what fails to load or compile.
##   godot --headless --path . res://tools/load_everything.tscn
## Used to check the project after files are moved: a broken path shows up here as a failed load.

const SKIP := ["res://.godot", "res://.git", "res://Blender", "res://tools/probe_logs"]
var _failed: Array[String] = []
var _loaded := 0

func _ready() -> void:
	_walk("res://")
	for path in _failed:
		print("LOAD-FAIL ", path)
	print("LOAD-SUMMARY loaded %d, failed %d" % [_loaded, _failed.size()])
	get_tree().quit(1 if not _failed.is_empty() else 0)

func _walk(dir_path: String) -> void:
	for skip in SKIP:
		if dir_path.begins_with(skip):
			return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub) if dir_path != "res://" else "res://" + sub)
	for file in dir.get_files():
		if file.get_extension() in ["tscn", "tres", "gd", "gdshader"]:
			var path := (dir_path.path_join(file)) if dir_path != "res://" else "res://" + file
			print("LOADING ", path)
			var res = load(path)
			if res == null or (res is GDScript and not (res as GDScript).can_instantiate()):
				_failed.append(path)
			else:
				_loaded += 1
