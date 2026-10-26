extends RefCounted
## One continuous aura. Unlike an AbilitySpec it has no costs, no stack object and no target choice: the criteria are
## evaluated against the live board, and Field owns the runtime grant/ledger.

var targets: Dictionary = {}
var method: String = ""
var value: int = 0
var status: String = ""
## Optional predicate; when present it is called as condition.call(source) and the aura is inactive when it returns
## false. The default empty Callable means "always active while the source can use abilities".
var condition: Callable


func _init(data: Dictionary = {}) -> void:
	targets = data.get("targets", {})
	method = str(data.get("method", ""))
	value = int(data.get("value", 0))
	status = str(data.get("status", ""))
	condition = data.get("condition", Callable())


func is_active(source: Card) -> bool:
	if condition.is_valid() and not bool(condition.call(source)):
		return false
	return true
