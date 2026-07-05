# SoundManager.gd
# Autoload that owns all game audio.
#
# The placeholder sounds are synthesized as real PCM16 wav streams at
# startup, so everything is audible today; to use recorded audio later,
# swap the stream in _register() for a loaded .wav/.ogg.
#
# Usage:  SoundManager.play("card_play")

extends Node

const MIX_RATE = 22050

var enabled: bool = true
var volume: float = 1.0
var _players: Dictionary = {}

func _ready() -> void:
	enabled = Settings.sound_enabled
	volume = Settings.volume
	_register("card_select", _tone([880.0], 0.05, 0.35))
	_register("card_play", _tone([220.0, 330.0], 0.09, 0.5))
	_register("card_deal", _noise_whoosh(0.09, 0.3))
	_register("pass", _tone([150.0], 0.12, 0.4))
	_register("table_clear", _sweep(620.0, 180.0, 0.22, 0.45))
	_register("win", _arpeggio([523.25, 659.25, 783.99, 1046.5], 0.13, 0.45))
	_register("button_click", _tone([1250.0], 0.03, 0.3))


func play(sound_name: String) -> void:
	if not enabled:
		return
	var player = _players.get(sound_name)
	if player:
		player.play()


func set_enabled(value: bool) -> void:
	enabled = value


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	for player in _players.values():
		player.volume_db = linear_to_db(maxf(volume, 0.001))


func _register(sound_name: String, stream: AudioStreamWAV) -> void:
	var player = AudioStreamPlayer.new()
	player.stream = stream
	player.max_polyphony = 4  # rapid replays (dealing) overlap instead of cutting off
	player.volume_db = linear_to_db(maxf(volume, 0.001))
	add_child(player)
	_players[sound_name] = player


# =============================================================
# SOUND SYNTHESIS
# =============================================================

func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


# Mixed sine tones with a linear decay — clicks, thocks, blips
func _tone(freqs: Array, dur: float, amp: float) -> AudioStreamWAV:
	var n = int(dur * MIX_RATE)
	var samples = PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t = float(i) / MIX_RATE
		var envelope = 1.0 - float(i) / n
		var s = 0.0
		for freq in freqs:
			s += sin(TAU * freq * t)
		samples[i] = s / freqs.size() * amp * envelope
	return _make_wav(samples)


# Soft filtered-noise whoosh for dealt cards
func _noise_whoosh(dur: float, amp: float) -> AudioStreamWAV:
	var n = int(dur * MIX_RATE)
	var samples = PackedFloat32Array()
	samples.resize(n)
	var prev = 0.0
	for i in n:
		var envelope = sin(PI * float(i) / n)  # fade in and out
		prev = lerpf(prev, randf_range(-1.0, 1.0), 0.25)  # crude low-pass
		samples[i] = prev * amp * envelope
	return _make_wav(samples)


# Frequency sweep — table clear
func _sweep(f0: float, f1: float, dur: float, amp: float) -> AudioStreamWAV:
	var n = int(dur * MIX_RATE)
	var samples = PackedFloat32Array()
	samples.resize(n)
	var phase = 0.0
	for i in n:
		var x = float(i) / n
		phase += TAU * lerpf(f0, f1, x) / MIX_RATE
		samples[i] = sin(phase) * amp * (1.0 - x)
	return _make_wav(samples)


# Rising notes — win jingle
func _arpeggio(notes: Array, note_dur: float, amp: float) -> AudioStreamWAV:
	var per_note = int(note_dur * MIX_RATE)
	var samples = PackedFloat32Array()
	samples.resize(per_note * notes.size())
	for k in notes.size():
		for i in per_note:
			var t = float(i) / MIX_RATE
			var envelope = 1.0 - float(i) / per_note
			samples[k * per_note + i] = sin(TAU * notes[k] * t) * amp * envelope
	return _make_wav(samples)
