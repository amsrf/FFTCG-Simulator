extends RefCounted
## Ordered target stages, e.g. Hades' "choose 1 Forward, then 1 Backup".

const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")

var stages: Array = []


func _init(requests: Array = []) -> void:
	stages = requests


func add(request):
	if request != null:
		stages.append(request)
	return self


func to_legacy() -> Array:
	var out: Array = []
	for request in stages:
		if request != null and request.has_method("to_legacy"):
			out.append(request.to_legacy())
	return out
