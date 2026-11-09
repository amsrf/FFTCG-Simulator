extends RefCounted
class_name AnimationBatch
## Promise.all() for Godot.
##
## GDScript has no promise object — `await` takes a signal or a coroutine — so "start everything, join once" needs a
## small primitive. Every animating action STARTS its tween before anything is awaited, and the caller awaits one
## signal instead of N.
##
##     var batch := AnimationBatch.new()
##     for card in targets:
##         batch.add(_animate(card))       # starts it
##     batch.close()
##     await batch.wait()                  # joins
##
## Design rules, all of them load-bearing:
##   * It NEVER HANGS. null, invalid or already-finished entries count as done, and wait() returns immediately if the
##     batch already fired. A join that can deadlock is worse than the sequence it replaced.
##   * It NEVER ABORTS. Unlike Promise.all there is no rejection path: a killed tween must not leave the other
##     animations stranded or the caller never resuming.
##   * STAGGER LIVES HERE. Zero (the default) starts them all on the same frame, which is what "all at once" means.
##     A small offset often reads better, and it costs one number rather than a change at every call site.

signal all_done

var _pending: int = 0
var _closed: bool = false
var _fired: bool = false
var _stagger: float = 0.0
var _added: int = 0


func set_stagger(seconds: float) -> AnimationBatch:
	_stagger = maxf(0.0, seconds)
	return self


## Add an awaitable. A Tween is started here (or scheduled by the stagger) and joined; null counts as already done,
## so a caller that skipped an animation does not have to branch.
func add(awaitable) -> void:
	if awaitable == null:
		return
	if not (awaitable is Tween):
		# Not a tween: assume whatever it is has already been started by the caller (a coroutine or a timer).
		return
	var tween: Tween = awaitable
	if not tween.is_valid():
		return
	_pending += 1
	tween.finished.connect(_one_done, CONNECT_ONE_SHOT)
	if _stagger > 0.0:
		var delay: float = _stagger * float(_added)
		_added += 1
		if delay > 0.0:
			tween.pause()
			var tree := Engine.get_main_loop() as SceneTree
			if tree != null:
				tree.create_timer(delay).timeout.connect(tween.play)


func close() -> void:
	_closed = true
	if _pending <= 0:
		_fire()


## Await this. Safe even if the batch already finished, which a plain `await all_done` would not be.
func wait() -> void:
	if _fired or (_closed and _pending <= 0):
		_fire()
		return
	await all_done


func _one_done() -> void:
	_pending -= 1
	if _pending <= 0 and _closed:
		_fire()


func _fire() -> void:
	if _fired:
		return
	_fired = true
	all_done.emit()
