extends Node
class_name RunController

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")
@onready var progression: ProgressionSystem = get_parent().get_node_or_null("ProgressionSystem") as ProgressionSystem

@export var auto_start: bool = true
@export var seed: int = 1337
var _run_time: float = 0.0

func _ready() -> void:
    if auto_start:
        call_deferred("start_run", _resolve_initial_seed())

func _resolve_initial_seed() -> int:
    if progression != null:
        return progression.choose_seed(seed)
    return seed

func start_run(new_seed: int) -> void:
    state.reset(new_seed)
    _run_time = 0.0
    bus.emit_signal("run_started", new_seed)

func end_run(reason: String) -> void:
    if not state.running:
        return
    state.running = false
    bus.emit_signal("run_ended", reason)

func continue_with_shield() -> void:
    if state.running:
        return
    state.shield = true
    bus.emit_signal("shield_changed", true)
    state.running = true
    bus.emit_signal("run_resumed")

func get_run_time() -> float:
    return _run_time

func get_next_seed() -> int:
    if progression != null and progression.enable_daily_seed:
        return progression.get_daily_seed()
    return state.seed + 1

func _process(delta: float) -> void:
    if not state.running:
        return
    _run_time += delta
    state.run_time = _run_time
    # Authoritative forward progress: only depends on speed.
    state.player_z += state.speed * delta
