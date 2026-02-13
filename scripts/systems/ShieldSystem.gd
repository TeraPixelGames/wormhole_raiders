extends Node
class_name ShieldSystem

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")
@onready var run: RunController = get_parent().get_node("RunController")

func _ready() -> void:
    bus.powerup_collected.connect(_on_powerup_collected)
    bus.bomb_hit.connect(_on_bomb_hit)

func _on_powerup_collected(powerup_type: int) -> void:
    if powerup_type == GameConstants.PowerupType.SHIELD:
        state.shield = true
        bus.emit_signal("shield_changed", true)

func _on_bomb_hit(with_shield: bool) -> void:
    if with_shield:
        state.shield = false
        bus.emit_signal("shield_changed", false)
        # run continues
    else:
        run.end_run("bomb")
