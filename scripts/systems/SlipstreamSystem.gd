extends Node
class_name SlipstreamSystem

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")

@export var flow_line_count: int = 3
@export var flow_width: float = 0.22
@export var flow_curve_freq: float = 0.010
@export var flow_drift_speed: float = 0.7
@export var speed_boost_strength: float = 1.0

var _offsets: Array[float] = []
var _last_active: bool = false

func _ready() -> void:
	bus.run_started.connect(_on_run_started)
	_seed_offsets(1337)

func _on_run_started(seed: int) -> void:
	_seed_offsets(seed)
	state.slipstream_strength = 0.0
	_last_active = false

func _process(_delta: float) -> void:
	if not state.running:
		state.slipstream_strength = 0.0
		return
	var best: float = 0.0
	for i in range(flow_line_count):
		var base: float = _offsets[i]
		var flow_angle: float = GameConstants.normalize_angle(base + state.player_z * flow_curve_freq + state.run_time * flow_drift_speed * (1.0 + 0.2 * float(i)))
		var diff: float = absf(GameConstants.angle_diff(state.player_angle, flow_angle))
		var contrib: float = 1.0 - clampf(diff / max(flow_width, 0.001), 0.0, 1.0)
		best = max(best, contrib)
	state.slipstream_strength = best * speed_boost_strength
	var active: bool = state.slipstream_strength > 0.05
	if active != _last_active:
		_last_active = active
		bus.emit_signal("slipstream_changed", active, state.slipstream_strength)

func _seed_offsets(seed: int) -> void:
	_offsets.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in range(max(flow_line_count, 1)):
		_offsets.append(rng.randf_range(-PI, PI))
