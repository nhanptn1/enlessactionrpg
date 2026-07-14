extends Node
## Procedural placeholder audio — swap stream paths for real assets later.

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const UI_BUS := &"UI"
const SFX_POOL_SIZE := 8

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _ui_player: AudioStreamPlayer
var _sfx_index := 0
var _current_music := ""
var _streams: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_streams()
	_music_player = _make_player(MUSIC_BUS)
	add_child(_music_player)
	for _i in SFX_POOL_SIZE:
		var player := _make_player(SFX_BUS)
		add_child(player)
		_sfx_players.append(player)
	_ui_player = _make_player(UI_BUS)
	add_child(_ui_player)
	_connect_signals()


func _connect_signals() -> void:
	SignalBus.player_shot.connect(func(): play_sfx("arrow_shot"))
	SignalBus.enemy_hit.connect(func(): play_sfx("enemy_hit", 0.85))
	SignalBus.enemy_died.connect(func(): play_sfx("enemy_die", 0.9))
	SignalBus.player_damaged.connect(func(_amount): play_sfx("damage_taken"))
	SignalBus.level_up.connect(func(_level): play_sfx("level_up"))
	SignalBus.skill_unlocked.connect(func(_skill): play_sfx("skill_cast", 1.05))
	SignalBus.item_collected.connect(func(_id): play_sfx("item_pickup", 0.95))
	SignalBus.player_died.connect(_on_player_died)
	SignalBus.wave_started.connect(_on_wave_started)
	SignalBus.wave_cleared.connect(_on_wave_cleared)
	SignalBus.boss_phase_changed.connect(func(_phase): play_sfx("boss_phase", 1.1))
	SignalBus.boss_attack_telegraph.connect(func(): play_sfx("boss_warning", 1.15))
	SignalBus.game_paused.connect(_on_game_paused)
	SignalBus.game_unpaused.connect(_on_game_unpaused)


func play_music(track_id: String, fade_in: float = 0.4) -> void:
	if track_id == _current_music and _music_player.playing:
		return
	if not _streams.has(track_id):
		return
	_current_music = track_id
	var stream: AudioStream = _streams[track_id]
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music_player.stream = stream
	_music_player.volume_db = -24.0
	_music_player.play()
	if fade_in > 0.0:
		var tween := create_tween()
		tween.tween_property(_music_player, "volume_db", -4.0, fade_in)


func stop_music(fade_out: float = 0.3) -> void:
	if not _music_player.playing:
		return
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", -40.0, fade_out)
	tween.tween_callback(_music_player.stop)
	_current_music = ""


func play_sfx(sfx_id: String, pitch_scale: float = 1.0) -> void:
	if not _streams.has(sfx_id):
		return
	var player := _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_players.size()
	player.pitch_scale = pitch_scale * randf_range(0.95, 1.05)
	player.stream = _streams[sfx_id]
	player.play()


func play_ui(sfx_id: String) -> void:
	if not _streams.has(sfx_id):
		return
	_ui_player.pitch_scale = randf_range(0.98, 1.02)
	_ui_player.stream = _streams[sfx_id]
	_ui_player.play()


func _on_wave_started(wave_number: int, is_boss: bool) -> void:
	if is_boss:
		play_sfx("boss_roar", 1.0)
		play_music("boss")
	else:
		if _current_music != "gameplay":
			play_music("gameplay")


func _on_wave_cleared(_wave_number: int, was_boss: bool) -> void:
	if was_boss:
		play_sfx("victory")
		await get_tree().create_timer(1.8).timeout
		if GameManager.state != GameManager.State.GAME_OVER:
			play_music("gameplay")


func _on_player_died() -> void:
	stop_music(0.2)
	play_sfx("game_over")


func _on_game_paused(source: String) -> void:
	if source == "pause_menu":
		play_ui("ui_open")
	_music_player.stream_paused = true


func _on_game_unpaused(source: String) -> void:
	if source == "pause_menu":
		play_ui("ui_close")
	_music_player.stream_paused = false


func _make_player(bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	return player


func _build_streams() -> void:
	_streams["arrow_shot"] = _make_tone(880.0, 0.06, 0.22)
	_streams["enemy_hit"] = _make_tone(220.0, 0.05, 0.28, "square")
	_streams["enemy_die"] = _make_tone(140.0, 0.14, 0.32, "sine", true)
	_streams["damage_taken"] = _make_tone(110.0, 0.18, 0.35, "saw")
	_streams["level_up"] = _make_arpeggio([523.0, 659.0, 784.0, 1047.0], 0.08, 0.25)
	_streams["skill_cast"] = _make_arpeggio([440.0, 554.0, 659.0], 0.1, 0.28)
	_streams["item_pickup"] = _make_tone(988.0, 0.09, 0.24)
	_streams["boss_roar"] = _make_tone(70.0, 0.45, 0.4, "saw")
	_streams["boss_warning"] = _make_tone(180.0, 0.2, 0.3, "square")
	_streams["boss_phase"] = _make_arpeggio([220.0, 277.0, 330.0, 415.0], 0.12, 0.32)
	_streams["victory"] = _make_arpeggio([523.0, 659.0, 784.0, 988.0, 1175.0], 0.1, 0.22)
	_streams["game_over"] = _make_tone(98.0, 0.55, 0.35, "sine", true)
	_streams["ui_click"] = _make_tone(660.0, 0.04, 0.18)
	_streams["ui_open"] = _make_tone(440.0, 0.07, 0.16)
	_streams["ui_close"] = _make_tone(330.0, 0.06, 0.14)
	_streams["gameplay"] = _make_loop_arpeggio([196.0, 247.0, 294.0, 370.0], 2.4, 0.12)
	_streams["boss"] = _make_loop_arpeggio([98.0, 123.0, 147.0, 185.0, 220.0], 1.6, 0.16, "saw")


func _make_tone(
	frequency: float,
	duration: float,
	volume: float,
	waveform: String = "sine",
	falloff: bool = false,
) -> AudioStreamWAV:
	var sample_rate := 22050
	var sample_count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / sample_rate
		var envelope := 1.0
		if falloff:
			envelope = clampf(1.0 - t / duration, 0.0, 1.0)
		elif t < duration * 0.08:
			envelope = t / (duration * 0.08)
		elif t > duration * 0.65:
			envelope = clampf((duration - t) / (duration * 0.35), 0.0, 1.0)
		var sample := _wave_sample(waveform, t, frequency) * envelope * volume
		_write_sample(data, i, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


func _make_arpeggio(frequencies: Array, note_duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var note_samples := int(sample_rate * note_duration)
	var total_samples := note_samples * frequencies.size()
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	for note_index in frequencies.size():
		var freq: float = frequencies[note_index]
		for i in note_samples:
			var t := float(i) / sample_rate
			var envelope := clampf(1.0 - t / note_duration, 0.0, 1.0)
			var sample := sin(t * freq * TAU) * envelope * volume
			_write_sample(data, note_index * note_samples + i, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


func _make_loop_arpeggio(
	frequencies: Array,
	loop_duration: float,
	volume: float,
	waveform: String = "sine",
) -> AudioStreamWAV:
	var sample_rate := 22050
	var sample_count := int(sample_rate * loop_duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var note_duration := loop_duration / float(frequencies.size())
	for i in sample_count:
		var t := float(i) / sample_rate
		var note_index := int(t / note_duration) % frequencies.size()
		var local_t := fmod(t, note_duration)
		var freq: float = frequencies[note_index]
		var envelope := clampf(1.0 - local_t / note_duration, 0.2, 1.0)
		var sample := _wave_sample(waveform, t, freq) * envelope * volume
		_write_sample(data, i, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.data = data
	return stream


func _wave_sample(waveform: String, t: float, frequency: float) -> float:
	match waveform:
		"square":
			return 1.0 if fmod(t * frequency, 1.0) < 0.5 else -1.0
		"saw":
			return fmod(t * frequency, 1.0) * 2.0 - 1.0
		_:
			return sin(t * frequency * TAU)


func _write_sample(data: PackedByteArray, index: int, sample: float) -> void:
	var s16 := int(clampf(sample * 32767.0, -32768.0, 32767.0))
	data[index * 2] = s16 & 0xFF
	data[index * 2 + 1] = (s16 >> 8) & 0xFF
