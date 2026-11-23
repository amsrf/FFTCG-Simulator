extends Node
## Viewing harness for the blocked clash (scripts/vfx/clash_cinematic.gd). Boots a board with one Forward a side,
## declares the attack and the block through the real Field path, runs Game.resolve_blocked_clash() and saves every
## Nth frame to --out-dir. Run windowed with --fixed-fps 60, so every frame is exactly 1/60 s of game time however
## long the PNG save takes:
##   godot --resolution 1920x1080 --fixed-fps 60 res://tools/clash_demo.tscn -- --out-dir <dir> \
##       [--every N] [--frames N] [--swap] [--loser attacker|blocker|both|none] [--frame-width m] [--elevation deg]
## --swap        the opponent attacks and the player blocks (default: the player attacks)
## --loser       who is defeated (default blocker). Survivors get a one-shot "damage set to 0"; a loser's power is
##               dropped to 1000 so the other card's hit is lethal.
## --frame-width / --elevation  the board camera (BoardCameraRig), as in tools/shot.gd.
## --defeat toss|tumble  force the defeated card's style (ClashCinematic.next_defeat_style); default: rolled.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var i: int = args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := _arg(args, "--out-dir", "user://clash_demo")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var every: int = maxi(int(_arg(args, "--every", "1")), 1)
	var frames: int = maxi(int(_arg(args, "--frames", "150")), 1)
	var swap: bool = args.has("--swap")
	var loser: String = _arg(args, "--loser", "blocker")

	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": 37, "tapped": false}],
		"opponent_field": [{"id": 15, "tapped": false}],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	var game = GAME_SCENE.instantiate()
	var rig: Node = game.get_node_or_null("Camera3D")
	if rig != null:
		if args.has("--frame-width"):
			rig.set("frame_width", float(_arg(args, "--frame-width", "8.0")))
		if args.has("--elevation"):
			rig.set("elevation_deg", float(_arg(args, "--elevation", "67.0")))
	add_child(game)
	await get_tree().create_timer(1.5).timeout

	var field = game.get("field")
	var mine: Card = field.get("front_cards")[0] if not field.get("front_cards").is_empty() else null
	var theirs: Card = null
	for card in field.get_all_cards():
		if card.controller == Card.OPPONENT and card.is_type("Forward"):
			theirs = card
	if mine == null or theirs == null:
		push_error("[ClashDemo] need one Forward a side (mine=%s theirs=%s)" % [mine, theirs])
		get_tree().quit(1)
		return
	var attacker: Card = theirs if swap else mine
	var blocker: Card = mine if swap else theirs

	var zero := {"operation": "set", "value": 0}
	if loser == "attacker" or loser == "both":
		attacker.set_base_power(1000)
	else:
		attacker.add_status_effect("next_receiving_damage", 1, zero)
	if loser == "blocker" or loser == "both":
		blocker.set_base_power(1000)
	else:
		blocker.add_status_effect("next_receiving_damage", 1, zero)

	field.set_attacker(attacker)
	field.execute_card_attack()
	await get_tree().create_timer(0.6).timeout
	field.blocker_card = blocker
	print("[ClashDemo] %s (%d) attacks, %s (%d) blocks, loser=%s" % [
		attacker.card_name, attacker.power, blocker.card_name, blocker.power, loser])

	if args.has("--defeat"):
		preload("res://scripts/vfx/clash_cinematic.gd").next_defeat_style = _arg(args, "--defeat", "")
	game.resolve_blocked_clash()
	for frame in frames:
		await RenderingServer.frame_post_draw
		if frame % every == 0:
			get_viewport().get_texture().get_image().save_png("%s/f_%03d.png" % [out_dir, frame])
	print("[ClashDemo] wrote %d frames to %s" % [ceili(float(frames) / every), out_dir])
	get_tree().quit()
