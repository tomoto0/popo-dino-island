extends Node

const BrowserBgmPlayer = preload("res://scripts/manus/browser_bgm_player.gd")
## One persistent music player and a fixed pool of one-shot SFX voices.

const CATALOG = preload("res://scripts/audio_catalog.gd")
const MAX_SFX_VOICES := 8
const MUSIC_BUS := &"GameMusic"
const SFX_BUS := &"GameSFX"
const UI_BUS := &"GameUI"
const MASTER_BUS := &"Master"
const SETTINGS_PATH := "user://audio.cfg"
const MUSIC_GAIN_DB := -8.0
const MUSIC_FADE_SECONDS := 0.25
const BUS_NAMES := {&"Master": MASTER_BUS, &"Music": MUSIC_BUS, &"SFX": SFX_BUS, &"UI": UI_BUS}

var music: BrowserBgmPlayer
var voices: Array[AudioStreamPlayer] = []
var enabled := false
var muted := false
var volume := 0.8
var pause_state_changes := 0
var music_starts := 0
var play_counts: Dictionary[StringName, int] = {}
var _cues: Dictionary[StringName, AudioStream] = {}
var _source_bgm: AudioStream
var _next_voice := 0
var _catalog_configured := false
var _warmup_generation := 0
var _unlocked := false
var _title_music := false
var _bus_volumes := {&"Music": 1.0, &"SFX": 1.0, &"UI": 1.0}
var _bus_mutes := {&"Music": false, &"SFX": false, &"UI": false}
var _last_cue_ms: Dictionary[StringName, int] = {}
var _duck_until_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus_name in [MUSIC_BUS, SFX_BUS, UI_BUS]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	for bus_name in [SFX_BUS, UI_BUS]:
		var index := AudioServer.get_bus_index(bus_name)
		# Independent Web music does not traverse Godot effects. Reserve headroom
		# in the one-shot categories so even a full eight-voice burst stays clean.
		if AudioServer.get_bus_effect_count(index) == 0:
			var limiter := AudioEffectHardLimiter.new()
			limiter.ceiling_db = -6.0 if bus_name == SFX_BUS else -12.0
			AudioServer.add_bus_effect(index, limiter)
	music = BrowserBgmPlayer.new()
	music.name = "MusicPlayer"
	music.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	music.bus = MUSIC_BUS
	music.volume_db = MUSIC_GAIN_DB
	add_child(music)
	for index in MAX_SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "SFXVoice%d" % index
		voice.bus = SFX_BUS
		voice.max_polyphony = 1
		voice.volume_db = -3.0
		add_child(voice)
		voices.append(voice)
	_load_settings()
	_apply_mix()
	get_tree().node_added.connect(_bind_control)
	_bind_tree(get_tree().root)
	_warm_catalog.call_deferred()
	_bind_tuning.call_deferred()


func configure(bgm: AudioStream, cues: Dictionary[StringName, AudioStream]) -> void:
	# Configure at boot or while stopped, never from a gameplay frame loop.
	if enabled:
		push_error("Stop GameAudio before replacing its catalog")
		return
	_warmup_generation += 1
	_catalog_configured = true
	_cues = cues.duplicate()
	play_counts.clear()
	_last_cue_ms.clear()
	for cue in _cues:
		play_counts[cue] = 0
	_configure_music(bgm)


func _configure_music(bgm: AudioStream) -> void:
	if _source_bgm != bgm:
		_source_bgm = bgm
		music.stream = bgm.duplicate() as AudioStream if bgm != null else null
		music.buffer_key = bgm.resource_path if bgm != null else ""
		if music.stream is AudioStreamOggVorbis:
			(music.stream as AudioStreamOggVorbis).loop = true
		elif music.stream is AudioStreamWAV:
			(music.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD


var current_track: StringName = &"map"

## Swap the looping music to a named world track (map, overworld, cave, ...).
## Safe between scenes and from button/key gestures; restarts only on change.
func select_track(track: StringName) -> void:
	if not CATALOG.BGM_TRACKS.has(track):
		return
	if track == current_track and _source_bgm != null:
		return
	var stream := load(CATALOG.BGM_TRACKS[track]) as AudioStream
	if stream == null:
		push_error("GameAudio could not load track: " + String(track))
		return
	current_track = track
	var was_playing := music.playing or music.stream_paused
	if was_playing:
		music.stop()
	_configure_music(stream)
	_catalog_configured = true
	if was_playing or enabled or (_title_music and _unlocked):
		_start_music_if_ready()


func _warm_catalog() -> void:
	if _catalog_configured:
		return
	var generation := _warmup_generation
	# Give title art and controls two presentation frames before optional audio.
	await get_tree().process_frame
	await get_tree().process_frame
	for cue in CATALOG.CUE_PATHS:
		if generation != _warmup_generation or not is_inside_tree():
			return
		_load_cue(cue)
		await get_tree().process_frame
	if generation != _warmup_generation or not is_inside_tree():
		return
	# Music is the largest audio file; gameplay/UI cues take priority.
	if _source_bgm != null:
		_catalog_configured = true
		return
	var bgm: AudioStream = null
	if not CATALOG.BGM_PATH.is_empty():
		bgm = load(CATALOG.BGM_PATH) as AudioStream
	if bgm == null and not CATALOG.BGM_PATH.is_empty():
		push_error("GameAudio could not load the gameplay music")
	_configure_music(bgm)
	_catalog_configured = true
	if enabled or (_title_music and _unlocked):
		_start_music_if_ready()


func _load_cue(cue: StringName) -> AudioStream:
	if _cues.has(cue):
		return _cues[cue]
	var path: String = CATALOG.CUE_PATHS.get(cue, "")
	if path.is_empty():
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		push_error("GameAudio could not load cue: " + String(cue))
		return null
	_cues[cue] = stream
	play_counts[cue] = 0
	return stream


func _start_music_if_ready() -> void:
	if get_tree().paused or _music_hold:
		return
	if music.stream != null and not music.playing:
		music.volume_db = MUSIC_GAIN_DB - 24.0
		music.play()
		music_starts += 1


var _music_hold := false

## Silence the looping music (e.g. while a clear/game-over jingle plays).
func hold_music(value: bool) -> void:
	_music_hold = value
	if value and (music.playing or music.stream_paused):
		music.stop()
	elif not value:
		_start_music_if_ready()


func begin_title() -> void:
	# Title/settings can reuse the same selected track after any real gesture.
	# Cold boot remains silent, and the gameplay cue gate stays closed.
	stop_game()
	_title_music = true
	if _unlocked:
		_start_music_if_ready()


func begin_game() -> void:
	# Call synchronously from the Start button/key gesture, not scene _ready().
	if enabled or get_tree().paused:
		return
	_unlocked = true
	_title_music = false
	enabled = true
	_set_music_paused(get_tree().paused)
	_start_music_if_ready()
	play(&"confirm")


func stop_game() -> void:
	enabled = false
	_title_music = false
	_music_hold = false
	if music.playing or music.stream_paused:
		music.stop()
	for voice in voices:
		if voice.playing or voice.stream_paused:
			voice.stop()
	_set_music_paused(false)
	_next_voice = 0
	_duck_until_ms = 0
	_last_cue_ms.clear()


func _process(delta: float) -> void:
	if enabled or (_title_music and _unlocked):
		_set_music_paused(get_tree().paused)
		_start_music_if_ready()
		if music.playing and not music.stream_paused:
			var target := MUSIC_GAIN_DB - (4.0 if Time.get_ticks_msec() < _duck_until_ms else 0.0)
			var gain := move_toward(music.volume_db, target, 24.0 * delta / MUSIC_FADE_SECONDS)
			if not is_equal_approx(gain, music.volume_db):
				music.volume_db = gain


func _set_music_paused(value: bool) -> void:
	# Repeated false assignments can reallocate buffers on the Web backend.
	if music.stream != null and (music.playing or music.stream_paused) and music.stream_paused != value:
		music.stream_paused = value
		pause_state_changes += 1
	# Apply the same transition to active one-shots; no per-frame setter calls.
	for voice in voices:
		if voice.bus == UI_BUS:
			continue
		if (voice.playing or voice.stream_paused) and voice.stream_paused != value:
			voice.stream_paused = value


func play(cue: StringName) -> void:
	if not enabled or get_tree().paused:
		return
	_play_cue(cue, false)


func play_ui(cue: StringName = &"confirm") -> void:
	if not _unlocked:
		return
	var semantic := cue if String(cue).begins_with("ui_") else StringName("ui_" + String(cue))
	_play_cue(semantic, true)


func _play_cue(cue: StringName, ui: bool) -> void:
	# Only load the requested small cue; the deferred bank warm-up reuses it.
	if not _catalog_configured:
		_load_cue(cue)
	if _cues.get(cue) == null:
		return
	var settings: Dictionary = CATALOG.CUE_SETTINGS.get(cue, {})
	var now := Time.get_ticks_msec()
	var cooldown := int(settings.get("cooldown_ms", 35))
	if now - _last_cue_ms.get(cue, -1000000) < cooldown:
		return
	_last_cue_ms[cue] = now
	var voice := voices[_next_voice]
	for candidate in voices:
		if not candidate.playing:
			voice = candidate
			break
	if voice.playing or voice.stream_paused:
		voice.stop()
	if voice.stream_paused:
		voice.stream_paused = false
	voice.bus = UI_BUS if ui else SFX_BUS
	voice.volume_db = float(settings.get("gain_db", -3.0))
	voice.pitch_scale = float(settings.get("pitch", 1.0))
	var stream: AudioStream = _cues[cue]
	if voice.stream != stream:
		voice.stream = stream
	voice.play()
	_next_voice = (voices.find(voice) + 1) % MAX_SFX_VOICES
	play_counts[cue] = get_play_count(cue) + 1
	if ui and cue in [&"ui_notification", &"ui_invalid"]:
		_duck_until_ms = now + 400


func _input(event: InputEvent) -> void:
	# Focus/hover alone is not a browser activation gesture.
	if (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		_unlocked = true
		if _title_music:
			_start_music_if_ready()


func _bind_tree(node: Node) -> void:
	_bind_control(node)
	for child in node.get_children():
		_bind_tree(child)


func _bind_control(node: Node) -> void:
	if not node is Control or node.has_meta("game_audio_bound"):
		return
	node.set_meta("game_audio_bound", true)
	if node is BaseButton:
		node.mouse_entered.connect(_button_cue.bind(node, &"hover"))
		node.focus_entered.connect(_button_cue.bind(node, &"focus"))
		node.pressed.connect(_button_cue.bind(node, &"toggle" if node.toggle_mode else &"confirm"))
	if node is OptionButton:
		node.item_selected.connect(func(_index: int): _button_cue(node, &"selection"))
	if node is Range:
		node.value_changed.connect(func(_value: float):
			if node.is_visible_in_tree() and (node.has_focus() or node.get_global_rect().has_point(node.get_global_mouse_position())):
				play_ui(&"slider"))
	if node is LineEdit:
		node.text_submitted.connect(func(_text: String): play_ui(&"confirm"))
	if node is TabContainer:
		node.tab_changed.connect(func(_tab: int): play_ui(&"selection"))


func _button_cue(button: BaseButton, cue: StringName) -> void:
	if not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree():
		return
	# Optional semantic metadata lets Back/Cancel buttons select a cue, not media.
	var selected: StringName = button.get_meta("audio_cue", cue) if cue in [&"confirm", &"toggle"] else cue
	play_ui(selected)


func get_play_count(cue: StringName) -> int:
	return play_counts.get(cue, 0)


func get_bus_volume(bus: StringName) -> float:
	return volume if bus == &"Master" else float(_bus_volumes.get(bus, 1.0))


func set_bus_volume(bus: StringName, value: float) -> void:
	if not BUS_NAMES.has(bus) or not is_finite(value):
		return
	if bus == &"Master":
		volume = clampf(value, 0.0, 1.0)
	else:
		_bus_volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_mix()
	_save_settings()


func is_bus_muted(bus: StringName) -> bool:
	return muted if bus == &"Master" else bool(_bus_mutes.get(bus, false))


func set_bus_muted(bus: StringName, value: bool) -> void:
	if not BUS_NAMES.has(bus):
		return
	if bus == &"Master":
		muted = value
	else:
		_bus_mutes[bus] = value
	_apply_mix()
	_save_settings()


func set_volume(value: float) -> void:
	set_bus_volume(&"Master", value)


func set_muted(value: bool) -> void:
	set_bus_muted(&"Master", value)


func _bind_tuning() -> void:
	var tuning := get_node_or_null("/root/TuningStore")
	if tuning != null and tuning.has_signal("value_changed"):
		tuning.value_changed.connect(func(key: String, _value: Variant):
			if key.begins_with("audio_"): _apply_mix())
	_apply_mix()


func _tuning_multiplier(bus: StringName) -> float:
	var tuning := get_node_or_null("/root/TuningStore")
	if tuning == null or not tuning.has_method("get_value"):
		return 1.0
	var value: Variant = tuning.get_value("audio_" + String(bus).to_lower())
	return clampf(float(value), 0.0, 1.0) if value is float or value is int else 1.0


func _apply_mix() -> void:
	# Preserve the reference mix: the legacy 0.8 volume now lives at Master.
	# Each category crosses that stage once; controls never compound gains.
	for key in BUS_NAMES:
		var index := AudioServer.get_bus_index(BUS_NAMES[key])
		if index < 0:
			continue
		var value := get_bus_volume(key) * _tuning_multiplier(key)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))
		AudioServer.set_bus_mute(index, is_bus_muted(key) or (key != &"Master" and muted) or is_zero_approx(value))


func _save_settings() -> void:
	var config := ConfigFile.new()
	for bus in BUS_NAMES:
		config.set_value(String(bus), "volume", get_bus_volume(bus))
		config.set_value(String(bus), "muted", is_bus_muted(bus))
	config.save(SETTINGS_PATH)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for bus in BUS_NAMES:
		var saved: Variant = config.get_value(String(bus), "volume", get_bus_volume(bus))
		if (saved is float or saved is int) and is_finite(float(saved)):
			if bus == &"Master": volume = clampf(float(saved), 0.0, 1.0)
			else: _bus_volumes[bus] = clampf(float(saved), 0.0, 1.0)
		var saved_mute: Variant = config.get_value(String(bus), "muted", false)
		if saved_mute is bool:
			if bus == &"Master": muted = saved_mute
			else: _bus_mutes[bus] = saved_mute


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_M:
		set_muted(not muted)
	elif event.keycode == KEY_MINUS:
		set_volume(volume - 0.1)
	elif event.keycode == KEY_EQUAL or event.keycode == KEY_PLUS:
		set_volume(volume + 0.1)
	else:
		return
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	# Cancel deferred loads and release playback before the persistent owner exits.
	# No sleep or await is needed on normal scene transitions; this node survives.
	_warmup_generation += 1
	enabled = false
	_title_music = false
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	if is_instance_valid(music):
		music.stop()
		music.stream = null
	_source_bgm = null
	_cues.clear()
