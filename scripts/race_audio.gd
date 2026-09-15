class_name RaceAudio extends Node

var _player: AudioStreamPlayer
var _sfx_countdown: AudioStreamWAV
var _sfx_go: AudioStreamWAV
var _sfx_lap: AudioStreamWAV
var _sfx_final_lap: AudioStreamWAV
var _sfx_finish: AudioStreamWAV
var _sfx_click: AudioStreamWAV
var _sfx_hover: AudioStreamWAV
var _sfx_select: AudioStreamWAV
var _sfx_connect: AudioStreamWAV

const SAMPLE_RATE: int = 22050

# Synthesizing ~3.8 s of audio sample-by-sample in GDScript costs well over
# 100 ms on web/mobile. Both the title screen and the race HUD create a
# RaceAudio, so keep one generated set for the whole session.
static var _sfx_cache: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = &"Master"
	add_child(_player)
	_generate_all_sfx()

func play_countdown() -> void:
	_play_stream(_sfx_countdown)

func play_go() -> void:
	_play_stream(_sfx_go)

func play_lap() -> void:
	_play_stream(_sfx_lap)

func play_final_lap() -> void:
	_play_stream(_sfx_final_lap)

func play_finish() -> void:
	_play_stream(_sfx_finish)

func play_click() -> void:
	_play_stream(_sfx_click)

func play_hover() -> void:
	_play_stream(_sfx_hover, -6.0)

func play_car_select() -> void:
	_play_stream(_sfx_select, -3.0)

func play_connect_success() -> void:
	_play_stream(_sfx_connect, -1.0)

func _play_stream(stream: AudioStreamWAV, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = &"Master"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _generate_all_sfx() -> void:
	if _sfx_cache.is_empty():
		_sfx_cache = {
			"countdown": _synth_tone([440.0], 0.18, 0.01, 0.12, 0.4, 0.6),
			"go": _synth_chord([587.33, 880.0, 1174.66, 1760.0], 0.65, 0.01, 0.5, 0.7),
			"lap": _synth_melody([587.33, 880.0], [0.12, 0.25], 0.01, 0.6),
			"final_lap": _synth_melody([440.0, 659.25, 880.0, 1318.5], [0.1, 0.1, 0.1, 0.4], 0.01, 0.7),
			"finish": _synth_fanfare(),
			"click": _synth_tone([880.0], 0.05, 0.005, 0.03, 0.3, 0.5),
			"hover": _synth_tone([1320.0], 0.03, 0.005, 0.02, 0.15, 0.3),
			"select": _synth_melody([659.25, 880.0], [0.06, 0.10], 0.005, 0.4),
			"connect": _synth_melody([587.33, 880.0, 1174.66], [0.08, 0.08, 0.22], 0.008, 0.6),
		}
	_sfx_countdown = _sfx_cache.countdown
	_sfx_go = _sfx_cache.go
	_sfx_lap = _sfx_cache.lap
	_sfx_final_lap = _sfx_cache.final_lap
	_sfx_finish = _sfx_cache.finish
	_sfx_click = _sfx_cache.click
	_sfx_hover = _sfx_cache.hover
	_sfx_select = _sfx_cache.select
	_sfx_connect = _sfx_cache["connect"]

func _synth_tone(freqs: Array, duration: float, attack: float, decay: float, square_mix: float, volume: float) -> AudioStreamWAV:
	var total_samples: int = int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = 1.0
		if t < attack:
			env = t / attack
		else:
			var decay_t: float = t - attack
			env = clampf(exp(-decay_t / decay), 0.0, 1.0)
		
		var sample: float = 0.0
		for freq in freqs:
			var s: float = sin(t * freq * TAU)
			var sq: float = sign(s)
			sample += lerp(s, sq, square_mix)
		sample = (sample / float(freqs.size())) * env * volume
		var s16: int = clampi(int(sample * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, s16)
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav

func _synth_chord(freqs: Array, duration: float, attack: float, decay: float, volume: float) -> AudioStreamWAV:
	var total_samples: int = int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = 1.0
		if t < attack:
			env = t / attack
		else:
			env = clampf(exp(-(t - attack) / decay), 0.0, 1.0)
		
		var sample: float = 0.0
		for f in freqs:
			sample += sin(t * f * TAU) * 0.7 + sin(t * f * 2.0 * TAU) * 0.3
		sample = (sample / float(freqs.size())) * env * volume
		var s16: int = clampi(int(sample * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, s16)
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav

func _synth_melody(freqs: Array, durations: Array, attack: float, volume: float) -> AudioStreamWAV:
	var total_duration: float = 0.0
	for d in durations:
		total_duration += d
	
	var total_samples: int = int(total_duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	var note_start_sample: int = 0
	var note_idx: int = 0
	
	for i in range(total_samples):
		var note_duration: float = durations[note_idx]
		var note_samples: int = int(note_duration * SAMPLE_RATE)
		var note_sample_pos: int = i - note_start_sample
		var t_note: float = float(note_sample_pos) / float(SAMPLE_RATE)
		var t_abs: float = float(i) / float(SAMPLE_RATE)
		
		var env: float = 1.0
		if t_note < attack:
			env = t_note / attack
		else:
			env = clampf(exp(-(t_note - attack) / (note_duration * 0.7)), 0.0, 1.0)
		
		var freq: float = freqs[note_idx]
		var sample: float = (sin(t_abs * freq * TAU) * 0.7 + sin(t_abs * freq * 2.0 * TAU) * 0.3) * env * volume
		var s16: int = clampi(int(sample * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, s16)
		
		if note_sample_pos >= note_samples - 1 and note_idx < freqs.size() - 1:
			note_idx += 1
			note_start_sample = i + 1
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav

func _synth_fanfare() -> AudioStreamWAV:
	# C5 (523.25), E5 (659.25), G5 (783.99), C6 (1046.50) triumphant finish
	var notes = [523.25, 659.25, 783.99, 1046.50]
	var durs = [0.15, 0.15, 0.20, 0.8]
	return _synth_melody(notes, durs, 0.015, 0.75)
