extends Node
class_name AudioSystem

const SOUND_ROOT: String = "res://assets/sound/explosion/"
const THEME_PATH: String = "res://assets/sound/theme.ogg"
const LASER_FILES: Array[String] = [
	"laserShoot.wav",
	"laserShoot1.wav",
	"laserShoot2.wav"
]
const EXPLOSION_FILES: Array[String] = [
	"explosion.wav",
	"explosion1.wav",
	"explosion2.wav"
]
const POWERUP_FILE: String = "powerUp.wav"

@onready var bus: EventBus = get_parent().get_node("EventBus")

@export var audio_bus: StringName = &"Master"
@export var laser_player_pool_size: int = 8
@export var explosion_player_pool_size: int = 6
@export var laser_player_volume_db: float = -7.0
@export var laser_enemy_volume_db: float = -11.0
@export var explosion_volume_db: float = -5.5
@export var explosion_player_death_volume_db: float = -2.5
@export var powerup_volume_db: float = -4.5
@export var music_volume_db: float = -12.0
@export var music_pitch_scale: float = 1.0
@export var player_laser_cooldown: float = 0.04
@export var enemy_laser_cooldown: float = 0.09
@export var explosion_cooldown: float = 0.03

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _laser_streams: Array[AudioStream] = []
var _explosion_streams: Array[AudioStream] = []
var _powerup_stream: AudioStream
var _music_stream: AudioStream
var _laser_players: Array[AudioStreamPlayer] = []
var _explosion_players: Array[AudioStreamPlayer] = []
var _powerup_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _next_laser_player: int = 0
var _next_explosion_player: int = 0
var _player_laser_timer: float = 0.0
var _enemy_laser_timer: float = 0.0
var _explosion_timer: float = 0.0

func _ready() -> void:
	_rng.randomize()
	_load_streams()
	_build_players()
	bus.laser_fired.connect(_on_laser_fired)
	bus.feedback_pulse.connect(_on_feedback_pulse)
	bus.powerup_collected.connect(_on_powerup_collected)
	bus.run_started.connect(_on_run_started)
	bus.run_resumed.connect(_on_run_resumed)
	_ensure_theme_playing()

func _process(delta: float) -> void:
	_player_laser_timer = max(_player_laser_timer - delta, 0.0)
	_enemy_laser_timer = max(_enemy_laser_timer - delta, 0.0)
	_explosion_timer = max(_explosion_timer - delta, 0.0)

func _on_run_started(_seed: int) -> void:
	_player_laser_timer = 0.0
	_enemy_laser_timer = 0.0
	_explosion_timer = 0.0
	_ensure_theme_playing()

func _on_run_resumed() -> void:
	_ensure_theme_playing()

func _on_laser_fired(by_player: bool) -> void:
	if _laser_streams.is_empty():
		return
	if by_player:
		if _player_laser_timer > 0.0:
			return
		_player_laser_timer = player_laser_cooldown
	else:
		if _enemy_laser_timer > 0.0:
			return
		_enemy_laser_timer = enemy_laser_cooldown

	var player: AudioStreamPlayer = _next_pool_player(_laser_players, "_next_laser_player")
	if player == null:
		return
	player.stream = _laser_streams[_rng.randi_range(0, _laser_streams.size() - 1)]
	player.volume_db = laser_player_volume_db if by_player else laser_enemy_volume_db
	player.pitch_scale = _rng.randf_range(0.98, 1.08) if by_player else _rng.randf_range(0.86, 0.96)
	player.play()

func _on_feedback_pulse(kind: String, _angle: float, _z: float, _intensity: float) -> void:
	if _explosion_streams.is_empty():
		return
	if kind != "orb_hit" and kind != "player_death":
		return
	if kind == "orb_hit" and _explosion_timer > 0.0:
		return
	_explosion_timer = explosion_cooldown

	var player: AudioStreamPlayer = _next_pool_player(_explosion_players, "_next_explosion_player")
	if player == null:
		return
	player.stream = _explosion_streams[_rng.randi_range(0, _explosion_streams.size() - 1)]
	player.volume_db = explosion_player_death_volume_db if kind == "player_death" else explosion_volume_db
	player.pitch_scale = _rng.randf_range(0.85, 0.96) if kind == "player_death" else _rng.randf_range(0.94, 1.08)
	player.play()

func _on_powerup_collected(_powerup_type: int) -> void:
	if _powerup_player == null or _powerup_stream == null:
		return
	_powerup_player.stream = _powerup_stream
	_powerup_player.volume_db = powerup_volume_db
	_powerup_player.pitch_scale = _rng.randf_range(0.98, 1.05)
	_powerup_player.play()

func _load_streams() -> void:
	_laser_streams.clear()
	_explosion_streams.clear()
	for f: String in LASER_FILES:
		var s: AudioStream = load(SOUND_ROOT + f) as AudioStream
		if s != null:
			_laser_streams.append(s)
	for f: String in EXPLOSION_FILES:
		var s: AudioStream = load(SOUND_ROOT + f) as AudioStream
		if s != null:
			_explosion_streams.append(s)
	_powerup_stream = load(SOUND_ROOT + POWERUP_FILE) as AudioStream
	_music_stream = load(THEME_PATH) as AudioStream
	_enable_stream_loop(_music_stream)

func _build_players() -> void:
	for p: AudioStreamPlayer in _laser_players:
		if is_instance_valid(p):
			p.queue_free()
	for p: AudioStreamPlayer in _explosion_players:
		if is_instance_valid(p):
			p.queue_free()
	if _powerup_player != null and is_instance_valid(_powerup_player):
		_powerup_player.queue_free()
	if _music_player != null and is_instance_valid(_music_player):
		_music_player.queue_free()

	_laser_players.clear()
	_explosion_players.clear()

	for _i in range(max(laser_player_pool_size, 1)):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = audio_bus
		add_child(player)
		_laser_players.append(player)

	for _i in range(max(explosion_player_pool_size, 1)):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = audio_bus
		add_child(player)
		_explosion_players.append(player)

	_powerup_player = AudioStreamPlayer.new()
	_powerup_player.bus = audio_bus
	add_child(_powerup_player)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = audio_bus
	_music_player.volume_db = music_volume_db
	_music_player.pitch_scale = music_pitch_scale
	if _music_stream != null:
		_music_player.stream = _music_stream
	add_child(_music_player)

	_next_laser_player = 0
	_next_explosion_player = 0

func _next_pool_player(pool: Array[AudioStreamPlayer], counter_name: String) -> AudioStreamPlayer:
	if pool.is_empty():
		return null
	var idx: int = int(get(counter_name))
	if idx < 0 or idx >= pool.size():
		idx = 0
	set(counter_name, (idx + 1) % pool.size())
	return pool[idx]

func _ensure_theme_playing() -> void:
	if _music_player == null or _music_stream == null:
		return
	_music_player.volume_db = music_volume_db
	_music_player.pitch_scale = music_pitch_scale
	if _music_player.stream != _music_stream:
		_music_player.stream = _music_stream
	if not _music_player.playing:
		_music_player.play()

func _enable_stream_loop(stream: AudioStream) -> void:
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
		return
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
