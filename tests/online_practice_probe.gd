extends Node
## Hosting on the practice board: both seats get Ifrit in the opening hand and a Fire Backup (Red Mage) to pay for it,
## with no more than five Backups each. Builds the setup exactly as the host does, without a network.

const NET_SESSION := preload("res://scripts/net/net_session.gd")

var _checks := 0
var _fails := 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	print("[Practice] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _backups(field: Array) -> int:
	var n := 0
	for entry in field:
		for card in CardDatabase.card_database:
			if int(card.get("id", -1)) == int(entry["id"]) and str(card.get("type_en", "")) == "Backup":
				n += 1
	return n

func _has(field: Array, id: int) -> bool:
	return field.any(func(e): return int(e["id"]) == id)

func _ready() -> void:
	var session: Node = NET_SESSION.new()
	add_child(session)
	session.is_host = true
	session.local_seat = 1
	session.practice_board = true
	var got := [null]
	session.match_ready.connect(func(cfg): got[0] = cfg)
	session._on_hello({"protocol": session.PROTOCOL, "deck": []})
	var cfg: Dictionary = got[0] if got[0] != null else {}
	_expect(not cfg.is_empty(), "the host built a practice match")
	if not cfg.is_empty():
		_expect(cfg["player_hand"].has(4), "seat 1 has Ifrit in hand %s" % str(cfg["player_hand"]))
		_expect(cfg["opponent_hand"].has(4), "seat 2 has Ifrit in hand %s" % str(cfg["opponent_hand"]))
		_expect(_has(cfg["player_field"], 3) and _has(cfg["opponent_field"], 3), "both fields have a Red Mage for Fire mana")
		_expect(_backups(cfg["player_field"]) <= 5 and _backups(cfg["opponent_field"]) <= 5,
			"still at most five Backups each (%d / %d)" % [_backups(cfg["player_field"]), _backups(cfg["opponent_field"])])
	print("[Practice] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
