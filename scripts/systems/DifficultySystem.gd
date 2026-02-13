extends Node
class_name DifficultySystem

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")
@onready var run: RunController = get_parent().get_node("RunController")

@export var difficulty_per_second: float = 0.02
@export var performance_weight: float = 0.25
@export var combo_normalize: float = 20.0
@export var combo_ema_sharpness: float = 2.5
var _recent_combo_ema: float = 0.0

func _ready() -> void:
    bus.run_started.connect(_on_run_started)

func _process(delta: float) -> void:
    if not state.running:
        return
    var blend := clampf(delta * combo_ema_sharpness, 0.0, 1.0)
    _recent_combo_ema = lerpf(_recent_combo_ema, float(state.combo), blend)

    var time_term := run.get_run_time() * difficulty_per_second
    var perf_term := performance_weight * clampf(_recent_combo_ema / max(combo_normalize, 0.001), 0.0, 1.0)
    state.difficulty = time_term + perf_term
    bus.emit_signal("difficulty_changed", state.difficulty)

func _on_run_started(seed: int) -> void:
    _recent_combo_ema = 0.0
