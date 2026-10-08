extends Node3D
## A live preview of the crystal shatter, on a loop.
##
## WHY IT EXISTS: the shatter is triggered by committing a mana payment, so the only place it could be seen was
## mid-match — boot the game, get to a payment, pay it, and try to catch a one-second effect. That is a slow and
## unreliable way to look at something this short. This scene fires the same burst, over and over, in isolation.
##
## OPEN IT AND PRESS F6 (or resize/reload, it keeps cycling). One burst per colour, left to right, so the tinting
## can be compared between elements. Nothing here touches the game: it calls CrystalShards exactly as the payment
## does — the same `burst(transform, colour)` — so what you see is what the game plays.
##
## It can also be shot without any window, which is how it was checked:
##
##   godot res://tools/shot.tscn --quit-after 300 -- --scene res://CrystalShardsPreview.tscn \
##       --seconds 0.6 --out tools/shots/shatter_preview.png
##
## The whole burst is `speed / drag` = 10 cm wide and lives for one second, so it is genuinely short: if you reload
## and see nothing, you caught the gap between cycles. `gap_seconds` is how long that gap is.

## The crystal's in-game fit scale. The model is 4.007 units tall and the game draws it at roughly 0.21 m, so this
## is the number ManaCrystal._fit() settles on. It looks oddly precise because it is what the game actually uses —
## the preview is meant to match the real size, not a convenient round number.
@export var crystal_scale: float = 0.0523

## Seconds between bursts, so the loop reads as an event rather than as a continuous cloud.
@export var gap_seconds: float = 1.6

## How far apart the bursts are, in metres. The crystals in the real row sit 0.16 m apart.
@export var spacing_m: float = 0.34

## One burst per entry, left to right. These are ManaCrystal.CRYSTAL_TINT values, so the fire one is the ruby the
## game uses rather than the badge's orange, and the wild one is the near-white "any colour" crystal.
@export var colours: Array[Color] = [
	Color(0.86, 0.09, 0.17),   # fire
	Color(0.94, 0.95, 1.0),    # wild / any colour
	Color(0.55, 0.87, 0.98),   # ice
	Color(0.36, 0.85, 0.44),   # wind
]

func _ready() -> void:
	# Replays until the scene is closed. The guard is checked after each wait, so closing the window mid-gap does
	# not leave a timer holding a freed node.
	while is_inside_tree():
		fire()
		await get_tree().create_timer(gap_seconds).timeout

## Fires one burst per colour. Public so the shot tool — or a probe — can trigger a single round instead of waiting.
func fire() -> void:
	var count: int = colours.size()
	for i in range(count):
		var x: float = (float(i) - (float(count) - 1) * 0.5) * spacing_m
		var shards: Node3D = preload("res://scripts/crystal_shards.gd").new()
		add_child(shards)
		# The same call the payment makes: a transform that places and sizes the pieces, and the crystal's colour.
		shards.call("burst", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * crystal_scale), Vector3(x, 0.0, 0.0)), colours[i])
