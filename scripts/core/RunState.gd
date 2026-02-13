extends Node
class_name RunState

# Authoritative run state (logic only).
var seed: int = 0
var running: bool = false

var player_z: float = 0.0
var player_angle: float = 0.0     # radians around tube
var player_ang_vel: float = 0.0   # radians per second

var shield: bool = false

var combo: int = 0
var multiplier: int = 1
var score: int = 0

var speed: float = 24.0
var difficulty: float = 0.0
var run_time: float = 0.0
var wave_phase: int = GameConstants.WavePhase.BUILD
var wave_index: int = 1
var boss_wave_active: bool = false
var slipstream_strength: float = 0.0
var fire_rate_boost: float = 0.0
var combo_timer: float = 0.0

func reset(new_seed: int) -> void:
    seed = new_seed
    running = true
    player_z = 0.0
    player_angle = 0.0
    player_ang_vel = 0.0
    shield = false
    combo = 0
    multiplier = 1
    score = 0
    speed = 24.0
    difficulty = 0.0
    run_time = 0.0
    wave_phase = GameConstants.WavePhase.BUILD
    wave_index = 1
    boss_wave_active = false
    slipstream_strength = 0.0
    fire_rate_boost = 0.0
    combo_timer = 0.0
