extends Node
## Event vocabulary and handler-map integrity. Every card that declares a trigger must point at a real method, and
## every EX BURST pointer must name a known event.

const EVENTS := preload("res://scripts/effects/events.gd")
const EFFECT_DIR := "res://assets/effects"

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Events] ok   %s" % what)
	else:
		_fails += 1
		print("[Events] FAIL %s" % what)


func _ready() -> void:
	for event in EVENTS.NAMES:
		var event_name: String = EVENTS.name_of(event)
		_expect(event_name != "" and EVENTS.from_name(event_name) == event,
			"%s round-trips through the event vocabulary" % event_name)
	_expect(EVENTS.from_name("not_an_event") == EVENTS.Event.NONE, "an unknown name is NONE")

	var dir := DirAccess.open(EFFECT_DIR)
	var cards: int = 0
	var triggers: int = 0
	var bursts: int = 0
	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var script = load("%s/%s" % [EFFECT_DIR, file])
		if script == null:
			continue
		var effect = script.new()
		if effect == null:
			continue
		cards += 1
		var handlers: Dictionary = effect.handlers()
		for event in handlers:
			triggers += 1
			_expect(EVENTS.NAMES.has(event), "%s declares a known event" % file)
			var handler = handlers[event]
			_expect(handler is Callable and handler.is_valid(),
				"%s binds a valid Callable" % file)
			if handler is Callable and handler.is_valid():
				_expect(effect.has_method(handler.get_method()),
					"%s handler %s exists" % [file, handler.get_method()])
		var burst: int = int(effect.ex_burst_event())
		if burst != EVENTS.Event.NONE:
			bursts += 1
			_expect(EVENTS.NAMES.has(burst), "%s EX BURST points at a known event" % file)

	_expect(cards > 100, "%d card effect scripts were checked" % cards)
	_expect(triggers > 100, "%d trigger declarations were checked" % triggers)
	_expect(bursts >= 20, "%d EX BURST pointers were checked" % bursts)

	print("[Events] %d checks | failures: %d" % [_checks, _fails])
	print("[Events] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
