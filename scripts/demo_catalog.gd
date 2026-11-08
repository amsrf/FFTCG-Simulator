extends RefCounted
## Discover interactive demos/previews by convention; never include automated probes.
static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for folder in ["res://", "res://tools/", "res://tests/"]:
		var directory := DirAccess.open(folder)
		if directory == null:
			continue
		for filename in directory.get_files():
			var scene_name := filename.trim_suffix(".remap")
			var lower := scene_name.to_lower()
			if not lower.ends_with(".tscn") or "probe" in lower:
				continue
			if not (lower.ends_with("_demo.tscn") or lower.ends_with("preview.tscn")):
				continue
			var path: String = folder + scene_name
			var title := scene_name.get_basename().to_snake_case().capitalize()
			result.append({"path": path, "title": title})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.title < b.title)
	return result
