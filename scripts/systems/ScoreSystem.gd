extends Node
class_name ScoreSystem

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")

@export var speed_reference: float = 24.0
@export var speed_factor_cap: float = 2.5
@export var near_miss_base_bonus: int = 6

func _ready() -> void:
    bus.run_started.connect(_on_run_started)
    bus.orb_collected.connect(_on_orb_collected)
    bus.near_miss.connect(_on_near_miss)

func _on_run_started(seed: int) -> void:
    state.score = 0
    bus.emit_signal("score_changed", state.score)

func _on_orb_collected(value: int) -> void:
    var speed_factor := clampf(state.speed / max(speed_reference, 0.001), 1.0, speed_factor_cap)
    var delta_score := int(round(float(value) * float(state.multiplier) * speed_factor))
    state.score += delta_score
    bus.emit_signal("score_changed", state.score)

func _on_near_miss(bonus_score: int) -> void:
    var add: int = bonus_score
    if add <= 0:
        add = near_miss_base_bonus * max(state.multiplier, 1)
    state.score += add
    bus.emit_signal("score_changed", state.score)
