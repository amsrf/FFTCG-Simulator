extends Node
## Card 1-030R reads "your Fire Forwards gain +1000 power", which is an `aura` — a continuous effect a card grants to
## OTHER cards, as opposed to `conditional_power` which a card applies to itself.
##
## NOTHING READ THE `aura` KEY AT ALL until now: the effect was loaded from JSON, stored on the card, and never applied,
## so the power simply never moved. This probe exists so that stays fixed, and it checks the other half too — that the
## bonus is taken back when the source leaves, which is the way this kind of effect usually breaks.
##
##   godot --headless res://tests/aura_probe.tscn --quit-after 900

const GAME_SCENE := preload("res://game.tscn")
const AURA_CARD := 30          ## 1-030R, the Fire Backup that grants the aura.

var _checks: int = 0
var _fails: int = 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Aura] ok   ", what)
	else:
		_fails += 1
		print("[Aura] FAIL ", what)

## Fire, whether the row stores its element as an Array (the usual shape) or a bare String.
func _is_fire(entry: Dictionary) -> bool:
	var el: Variant = entry.get("element", [])
	if el is Array:
		return "火" in el
	return str(el) == "火"

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = game.field
	_expect(field != null, "the match built a Field")

	# A Fire Forward, found by scanning rather than hard-coded: the point is the element and the type, not the card.
	var fire_forward: int = 0
	var index: int = 1
	# `element` is an Array of element keys in the database — and `x or []` is NOT a null-safe default in GDScript, it
	# yields a BOOL, which is how "火" in (element or []) came to be a runtime error the first time.
	for entry in CardDatabase.card_database:
		if str(entry.get("type_en", "")) == "Forward" and _is_fire(entry):
			fire_forward = index
			break
		index += 1
	_expect(fire_forward > 0, "there is a Fire Forward in the database to test against")

	# A Fire BACKUP too: the aura says "Fire Forwards", so a Backup of the same element must be left alone.
	var fire_backup: int = 0
	index = 1
	for entry in CardDatabase.card_database:
		if str(entry.get("type_en", "")) == "Backup" and _is_fire(entry):
			fire_backup = index
			break
		index += 1

	var target: Card = game.create_card(fire_forward, "player")
	field.add_child(target)
	var base_power: int = target.power
	field.play_card(target, false, false)
	print("[Aura] the Fire Forward starts at %d power" % base_power)

	# 1-030 onto the field.
	var source: Card = game.create_card(AURA_CARD, "player")
	field.add_child(source)
	field.play_card(source, false, false)
	print("[Aura] with 1-030R on the field its power is %d" % target.power)
	_expect(target.power == base_power + 1000, "1-030R gives a Fire Forward +1000 power")

	# A second Fire Forward: the aura is not a one-shot on the first card it saw.
	var second: Card = game.create_card(fire_forward, "player")
	field.add_child(second)
	field.play_card(second, false, false)
	print("[Aura] a second Fire Forward enters at %d" % second.power)
	_expect(second.power == base_power + 1000, "and it applies to every Fire Forward, not just the first")

	# Something the aura does NOT name must be untouched.
	if fire_backup > 0:
		var backup: Card = game.create_card(fire_backup, "player")
		field.add_child(backup)
		var backup_base: int = backup.power
		field.play_card(backup, false, false)
		print("[Aura] a Fire Backup reads %d (started %d)" % [backup.power, backup_base])
		_expect(backup.power == backup_base, "a Fire BACKUP is not affected — the aura says Forwards")

		# ...and 1-030 leaving must not leave anything behind.
		field.remove_card(source)
		print("[Aura] after 1-030R leaves: forward %d, second %d, backup %d" % [
			target.power, second.power, backup.power])
		_expect(target.power == base_power, "the +1000 goes away when the source leaves the field")
		_expect(second.power == base_power, "for every card it was given to")
		_expect(backup.power == backup_base, "and nothing drifts on a card it never touched")

	print("[Aura] %d checks | failures: %d" % [_checks, _fails])
	print("[Aura] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0)
