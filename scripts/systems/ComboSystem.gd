extends Node
class_name ComboSystem

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")

@export var combo_chain_window: float = 1.2
@export var combo_step_for_multiplier: int = 5
@export var max_multiplier: int = 8
@export var fire_rate_boost_per_multiplier_step: float = 0.035
@export var max_fire_rate_boost: float = 0.24

var _last_chain_time: float = -INF

func _ready() -> void:
    bus.run_started.connect(_on_run_started)
    bus.orb_collected.connect(_on_orb_collected)
    bus.orb_missed.connect(_reset_combo)
    bus.bomb_hit.connect(_on_bomb_hit)

func _process(_delta: float) -> void:
    if not state.running:
        return
    if state.combo > 0 and (state.run_time - _last_chain_time) > combo_chain_window:
        _reset_combo()
    if state.combo > 0:
        state.combo_timer = max(combo_chain_window - (state.run_time - _last_chain_time), 0.0)
    else:
        state.combo_timer = 0.0

func _on_run_started(seed: int) -> void:
    _last_chain_time = -INF
    _reset_combo()

func _on_orb_collected(value: int) -> void:
    if state.combo > 0 and (state.run_time - _last_chain_time) <= combo_chain_window:
        state.combo += 1
    else:
        state.combo = 1
    _last_chain_time = state.run_time
    var steps: int = int(floor(float(max(state.combo - 1, 0)) / float(max(combo_step_for_multiplier, 1))))
    state.multiplier = min(1 + steps, max_multiplier)
    state.fire_rate_boost = clampf(float(steps) * fire_rate_boost_per_multiplier_step, 0.0, max_fire_rate_boost)
    bus.emit_signal("combo_changed", state.combo, state.multiplier)
    if state.combo == 10 or state.combo == 20 or state.combo == 30:
        bus.emit_signal("combo_milestone", state.combo)

func _on_bomb_hit(with_shield: bool) -> void:
    if with_shield:
        _reset_combo()

func _reset_combo() -> void:
    state.combo = 0
    state.multiplier = 1
    state.fire_rate_boost = 0.0
    state.combo_timer = 0.0
    bus.emit_signal("combo_changed", state.combo, state.multiplier)
