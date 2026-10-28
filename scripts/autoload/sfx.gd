extends Node
## Every sound is synthesised at startup, so the project ships no audio files.

const RATE := 22050
const TAUNT_COUNT := 5

var streams := {}
var _players: Array[AudioStreamPlayer] = []
var _noise := RandomNumberGenerator.new()


func _ready() -> void:
	_noise.seed = 7
	_build_sounds()
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## Plays a non-positional sound (UI, your own actions).
func play(id: String, volume_db := 0.0) -> void:
	var stream: AudioStream = streams.get(id)
	if stream == null:
		return
	var player := _players[0]
	for p in _players:
		if not p.playing:
			player = p
			break
	player.stream = stream
	player.volume_db = volume_db
	player.play()


## Plays a sound in the 3D world so players can tell where it came from.
func play_at(id: String, pos: Vector3, volume_db := 0.0, unit_size := 6.0) -> void:
	var stream: AudioStream = streams.get(id)
	if stream == null or Game.world == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_distance = 90.0
	p.pitch_scale = randf_range(0.95, 1.05)
	Game.world.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _build_sounds() -> void:
	streams.swing = _wav(_noise_burst(0.18, 0.45, 0.12))
	streams.hit = _wav(_mix(_tone(0.2, 190.0, 60.0, 0, 0.9), _noise_burst(0.06, 0.6, 0.6)))
	streams.thud = _wav(_mix(_tone(0.12, 240.0, 140.0, 2, 0.6), _noise_burst(0.05, 0.4, 0.4)))
	streams.poof = _wav(_mix(_noise_burst(0.35, 0.45, 0.25), _tone(0.3, 500.0, 1100.0, 0, 0.25)))
	streams.caught = _wav(_concat([
		_tone(0.12, 880.0, 880.0, 2, 0.5), _tone(0.12, 660.0, 660.0, 2, 0.5),
		_tone(0.35, 440.0, 200.0, 2, 0.5),
	]))
	streams.ping = _wav(_mix(_tone(0.7, 1400.0, 1400.0, 0, 0.5), _tone(0.7, 2100.0, 2100.0, 0, 0.2)))
	streams.sonar = _wav(_tone(0.8, 260.0, 900.0, 0, 0.5))
	streams.tick = _wav(_tone(0.06, 1000.0, 1000.0, 1, 0.2))
	streams.hurt = _wav(_tone(0.25, 600.0, 280.0, 2, 0.5))
	streams.round_start = _wav(_mix(_mix(
		_tone(0.9, 392.0, 392.0, 2, 0.25), _tone(0.9, 494.0, 494.0, 2, 0.25)),
		_tone(0.9, 587.0, 587.0, 2, 0.25)))
	streams.release = _wav(_concat([
		_tone(0.15, 523.0, 523.0, 2, 0.5), _tone(0.15, 659.0, 659.0, 2, 0.5),
		_tone(0.45, 784.0, 784.0, 2, 0.5),
	]))
	streams.win = _wav(_concat([
		_tone(0.14, 523.0, 523.0, 2, 0.5), _tone(0.14, 659.0, 659.0, 2, 0.5),
		_tone(0.14, 784.0, 784.0, 2, 0.5), _tone(0.6, 1046.0, 1046.0, 2, 0.5),
	]))
	# Hider taunts: silly and easy to tell apart.
	streams.taunt0 = _wav(_tone(0.6, 700.0, 1600.0, 0, 0.5, 0.02))
	streams.taunt1 = _wav(_concat([
		_tone(0.18, 330.0, 320.0, 3, 0.35), _silence(0.06), _tone(0.3, 330.0, 300.0, 3, 0.35),
	]))
	streams.taunt2 = _wav(_tone(0.6, 180.0, 520.0, 0, 0.6, 0.15))
	streams.taunt3 = _wav(_concat([
		_tone(0.07, 1800.0, 2400.0, 0, 0.4), _silence(0.05),
		_tone(0.07, 1800.0, 2400.0, 0, 0.4), _silence(0.05),
		_tone(0.07, 1800.0, 2400.0, 0, 0.4),
	]))
	streams.taunt4 = _wav(_tone(0.7, 440.0, 330.0, 1, 0.25, 0.06))


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream


## A pitch sweep from f0 to f1. wave: 0 sine, 1 square, 2 triangle, 3 saw.
func _tone(duration: float, f0: float, f1: float, wave := 0, volume := 0.5, vibrato := 0.0) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var freq := lerpf(f0, f1, t) * (1.0 + vibrato * sin(i * TAU * 7.0 / RATE))
		phase = fmod(phase + freq / RATE, 1.0)
		var v := 0.0
		match wave:
			0: v = sin(phase * TAU)
			1: v = 1.0 if phase < 0.5 else -1.0
			2: v = 4.0 * absf(phase - 0.5) - 1.0
			3: v = 2.0 * phase - 1.0
		var envelope := minf(1.0, t * duration / 0.01) * pow(1.0 - t, 1.5)
		out[i] = v * envelope * volume
	return out


func _noise_burst(duration: float, volume: float, smoothing: float) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		y = lerpf(y, _noise.randf_range(-1.0, 1.0), smoothing)
		out[i] = y * volume * minf(1.0, t * 8.0) * pow(1.0 - t, 2.0)
	return out


func _silence(duration: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(duration * RATE))
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate() if a.size() >= b.size() else b.duplicate()
	var other := b if a.size() >= b.size() else a
	for i in other.size():
		out[i] += other[i]
	return out


func _concat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for part in parts:
		out.append_array(part)
	return out
