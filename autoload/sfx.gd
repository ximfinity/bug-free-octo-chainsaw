extends Node
## Sound effects and ambience. Sfx.play("sound", world_position) plays a
## one-shot; without a position it plays at full volume (UI sounds).
## Missing files are skipped silently, so the game runs fine without audio.

const DIR := "res://assets/audio/"
const POOL := 14
const AMBIENT := ["amb_water", "amb_birds", "amb_crickets", "amb_falls"]

var _streams: Dictionary = {}
var _players: Array = []
var _flat: Array = []
var _next: int = 0
var _next_flat: int = 0
var _ambient: Dictionary = {}
var _targets: Dictionary = {}
var _last_played: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL:
		var p := AudioStreamPlayer2D.new()
		p.max_distance = 900.0
		p.attenuation = 1.4
		add_child(p)
		_players.append(p)
	for i in 4:
		var f := AudioStreamPlayer.new()
		add_child(f)
		_flat.append(f)
	for sound in AMBIENT:
		var a := AudioStreamPlayer.new()
		a.volume_db = -60.0
		a.stream = _stream(sound)
		add_child(a)
		a.finished.connect(a.play)
		_ambient[sound] = a
		_targets[sound] = 0.0


func _stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var path: String = DIR + sound + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_streams[sound] = s
	return s


## pos: Vector2 world position, or null for a non-positional sound.
func play(sound: String, pos = null, volume_db: float = 0.0, pitch_var: float = 0.08) -> void:
	var s: AudioStream = _stream(sound)
	if s == null:
		return
	# Don't stack the same sound many times in one instant.
	var now: int = Time.get_ticks_msec()
	if now - int(_last_played.get(sound, -1000)) < 40:
		return
	_last_played[sound] = now
	var pitch: float = 1.0 + randf_range(-pitch_var, pitch_var)
	if pos == null:
		var f: AudioStreamPlayer = _flat[_next_flat]
		_next_flat = (_next_flat + 1) % _flat.size()
		f.stream = s
		f.volume_db = volume_db
		f.pitch_scale = pitch
		f.play()
	else:
		var p: AudioStreamPlayer2D = _players[_next]
		_next = (_next + 1) % _players.size()
		p.stream = s
		p.global_position = pos
		p.volume_db = volume_db
		p.pitch_scale = pitch
		p.play()


## Target loudness (0..1) for each ambience loop; fades smoothly.
func set_ambience(water: float, birds: float, crickets: float, falls: float) -> void:
	_targets["amb_water"] = water
	_targets["amb_birds"] = birds
	_targets["amb_crickets"] = crickets
	_targets["amb_falls"] = falls


func stop_ambience() -> void:
	set_ambience(0.0, 0.0, 0.0, 0.0)


func _process(delta: float) -> void:
	for sound in _ambient:
		var a: AudioStreamPlayer = _ambient[sound]
		if a.stream == null:
			continue
		var target: float = float(_targets[sound])
		var cur: float = db_to_linear(a.volume_db)
		cur = move_toward(cur, target * 0.5, delta * 0.4)
		a.volume_db = linear_to_db(maxf(cur, 0.0001))
		if cur > 0.002 and not a.playing:
			a.play()
		elif cur <= 0.002 and a.playing:
			a.stop()
