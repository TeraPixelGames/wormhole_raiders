extends Node
class_name SpeedSystem

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")
@onready var run: RunController = get_parent().get_node("RunController")

@export var base_speed: float = 24.0
@export var ramp_per_second: float = 0.0
@export var multiplier_speed_bonus_per_step: float = 0.0
@export var slipstream_speed_bonus: float = 0.0

func _process(delta: float) -> void:
    if not state.running:
        return
    var combo_speed_bonus: float = float(max(state.multiplier - 1, 0)) * multiplier_speed_bonus_per_step
    var flow_bonus: float = state.slipstream_strength * slipstream_speed_bonus
    state.speed = max(base_speed + ramp_per_second * run.get_run_time() + combo_speed_bonus + flow_bonus, 0.1)
    bus.emit_signal("speed_changed", state.speed)
