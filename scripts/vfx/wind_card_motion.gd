extends RefCounted
## The card's flight inside the wind tornado, shared by wind_tornado_cue.gd and the demo. It is timed against the
## tornado's own timeline (wind_tornado.gd), in seconds since the tornado started:
##   RISE_START..RISE_END  lifted with the buildup, as the funnel front climbs past it
##   ..hover_end           held aloft, bobbing and wobbling, while the funnel runs and fades away; this is the
##                         tornado's own length (wind_tornado.gd length_for(tier)), so a bigger hit holds longer
##   ..total_for(hover_end) drops back to its slot only once the tornado has faded (gravity ease-in, small settle)
## It SPINS the whole time with the funnel (a positive turn about +Y): a whole number of turns (SPIN_TURNS per
## BASE_TOTAL seconds, rounded), so it keeps the same pace at any length and lands in its original
## orientation: nothing snaps when the cue hands the card back to the field layout.

const TIMELINE := preload("res://scripts/vfx/wind_tornado.gd")

const RISE_START := TIMELINE.GROW_START + 0.12
const RISE_END := TIMELINE.BUILDUP + 0.15
const FALL := 0.5
const BASE_TOTAL := TIMELINE.LENGTH + FALL
const SPIN_TURNS := 6.0                   # per BASE_TOTAL seconds

static func total_for(hover_end: float) -> float:
	return hover_end + FALL

static func pose_at(seconds: float, height: float, phase: float = 0.0,
		hover_end: float = TIMELINE.LENGTH) -> Transform3D:
	var total := total_for(hover_end)
	var t := clampf(seconds, 0.0, total)
	var rise := smoothstep(RISE_START, RISE_END, t)
	var fall := clampf((t - hover_end) / FALL, 0.0, 1.0)
	var drop := fall * fall                                 # gravity: slow off the top, fast at the bottom
	var settle := sin(clampf((fall - 0.8) / 0.2, 0.0, 1.0) * PI) * 0.04 * height   # tiny bounce on landing
	var aloft := rise * (1.0 - drop)
	# Wobble only while it is carried; fades in with the rise and out with the drop.
	var envelope := rise * (1.0 - fall)
	var bob := sin(t * 3.1 + phase) * 0.05 * envelope
	var lift := height * aloft + bob * height + settle
	var drift := Vector3(sin(t * 2.3 + phase) * 0.09, 0.0, cos(t * 1.9 + phase) * 0.06) * envelope
	drift.y = lift
	var angles := Vector3(sin(t * 2.7 + phase) * 0.20, 0.0, cos(t * 2.2 + phase) * 0.16) * envelope
	# Spin: velocity 1 - cos(2*pi*u), i.e. picked up gently, fastest mid-flight, slowing to a stop on landing.
	var turns := maxf(1.0, roundf(SPIN_TURNS * total / BASE_TOTAL))
	var u := t / total
	var spin := TAU * turns * (u - sin(TAU * u) / TAU)
	var turn := Basis(Vector3.UP, spin)
	# The wobble orbits with the spin, so the card is carried round rather than spinning on one spot.
	return Transform3D(turn * Basis.from_euler(angles), turn * drift)
