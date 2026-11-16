extends Node
## Shared presentation audio. Own RNG so cosmetic choices never alter game randomness.
signal sound_played(event: StringName, variant: int)

const MAX_VOICES := 24
const DRAW_PATH := "res://assets/audio/sfx/cards/draw/draw_%02d.wav"
const FLIP_PATH := "res://assets/audio/sfx/cards/flip_distant/flip_distant_%02d.wav"

var _rng := RandomNumberGenerator.new()
var _events: Dictionary = {}
var _last_variant: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0

func _ready() -> void:
	_rng.randomize()
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	register_event(&"card_draw", _load_bank(DRAW_PATH, 22), -8.0)
	register_event(&"card_flip", _load_bank(FLIP_PATH, 22), -8.0)

## Load a numbered bank `pattern % 1 .. pattern % count`, reporting every missing file.
func _load_bank(pattern: String, count: int) -> Array[AudioStream]:
	var bank: Array[AudioStream] = []
	for number in range(1, count + 1):
		var path: String = pattern % number
		var stream: AudioStream = _load_wav(path)
		if stream == null:
			push_error("Missing audio: " + path)
			continue
		bank.append(stream)
	return bank

func _load_wav(path: String) -> AudioStream:
	# Imported resources in exports; raw WAVs before the editor's first import.
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return AudioStreamWAV.load_from_file(path)

## Add future effects here or from an audio library; animation code only knows the event name.
func register_event(event: StringName, variants: Array[AudioStream], volume_db: float = 0.0) -> void:
	_events[event] = {"variants": variants, "volume_db": volume_db}
	_last_variant.erase(event)

func play(event: StringName, gain_db: float = 0.0) -> void:
	if not _events.has(event):
		push_error("Unknown sound event: " + String(event))
		return
	var variants: Array = _events[event]["variants"]
	if variants.is_empty() or AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")):
		return
	# Uniform random choice among every variant except the previous one.
	var previous: int = _last_variant.get(event, -1)
	var index: int = _rng.randi_range(0, variants.size() - 1)
	if variants.size() > 1 and previous >= 0:
		index = _rng.randi_range(0, variants.size() - 2)
		if index >= previous:
			index += 1
	_last_variant[event] = index
	var voice: AudioStreamPlayer = _available_voice()
	voice.stream = variants[index]
	voice.volume_db = float(_events[event]["volume_db"]) + gain_db
	voice.play()
	sound_played.emit(event, index)

func set_sfx_volume_db(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), value)

func set_sfx_muted(value: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), value)

func _available_voice() -> AudioStreamPlayer:
	for voice in _voices:
		if not voice.playing:
			return voice
	if _voices.size() < MAX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = "SFX"
		add_child(voice)
		_voices.append(voice)
		return voice
	# Bounded playback: reuse a voice when a very large batch exhausts the pool.
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % MAX_VOICES
	voice.stop()
	return voice
