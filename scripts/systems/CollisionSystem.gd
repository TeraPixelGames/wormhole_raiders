extends Node
class_name CollisionSystem

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")
@onready var gen: PatternGenerator = get_parent().get_node("PatternGenerator")

@export var enable_missed_orb_combo_reset: bool = true
@export var orb_miss_window: float = 0.6
@export var orb_miss_angle_window: float = 0.24
@export var hit_window_angle: float = GameConstants.HIT_WINDOW_ANGLE
@export var near_miss_z_window: float = 0.8
@export var near_miss_angle_window: float = 0.24
@export var near_miss_bonus_score: int = 8

func _process(delta: float) -> void:
    if not state.running:
        return

    var bomb_candidate: SpawnItem = null
    var powerup_candidate: SpawnItem = null
    var orb_candidate: SpawnItem = null
    var bomb_hit_angle: float = 0.0
    var bomb_hit_z: float = 0.0
    var powerup_hit_angle: float = 0.0
    var powerup_hit_z: float = 0.0
    var orb_hit_angle: float = 0.0
    var orb_hit_z: float = 0.0
    var best_bomb_dz := INF
    var best_powerup_dz := INF
    var best_orb_dz := INF
    var speed_hit_bonus: float = clampf((state.speed - 24.0) * 0.005, 0.0, 0.04)
    var angle_hit_limit: float = hit_window_angle + speed_hit_bonus

    for item in gen.commands:
        if not item.active:
            continue

        var item_angle: float = item.runtime_angle(state.run_time, state.player_z)
        var item_z: float = item.runtime_z(state.run_time, state.player_z)
        var ang_diff: float = GameConstants.angle_diff(item_angle, state.player_angle)

        if enable_missed_orb_combo_reset and item.kind == GameConstants.ItemKind.ORB:
            if not item.missed_checked and item_z < state.player_z - orb_miss_window and absf(ang_diff) <= orb_miss_angle_window:
                item.missed_checked = true
                bus.emit_signal("orb_missed")
        if item.kind == GameConstants.ItemKind.BOMB:
            if not item.near_miss_checked and item_z < state.player_z and item_z >= state.player_z - near_miss_z_window:
                var ad: float = absf(ang_diff)
                if ad > angle_hit_limit and ad <= near_miss_angle_window:
                    item.near_miss_checked = true
                    bus.emit_signal("near_miss", near_miss_bonus_score * max(state.multiplier, 1))
                    bus.emit_signal("feedback_pulse", "near_miss", item_angle, item_z, 0.55)

        var dz := item_z - state.player_z
        if dz < -0.2 or dz > GameConstants.HIT_WINDOW_Z:
            continue
        if absf(ang_diff) > angle_hit_limit:
            continue

        var dz_abs := absf(dz)
        match item.kind:
            GameConstants.ItemKind.BOMB:
                if dz_abs < best_bomb_dz:
                    best_bomb_dz = dz_abs
                    bomb_candidate = item
                    bomb_hit_angle = item_angle
                    bomb_hit_z = item_z
            GameConstants.ItemKind.POWERUP:
                if dz_abs < best_powerup_dz:
                    best_powerup_dz = dz_abs
                    powerup_candidate = item
                    powerup_hit_angle = item_angle
                    powerup_hit_z = item_z
            GameConstants.ItemKind.ORB:
                if dz_abs < best_orb_dz:
                    best_orb_dz = dz_abs
                    orb_candidate = item
                    orb_hit_angle = item_angle
                    orb_hit_z = item_z

    if bomb_candidate != null:
        _consume_item(bomb_candidate)
        bus.emit_signal("bomb_hit", state.shield)
        if state.shield:
            bus.emit_signal("feedback_pulse", "shield_break", bomb_hit_angle, bomb_hit_z, 1.0)
        else:
            bus.emit_signal("feedback_pulse", "player_death", bomb_hit_angle, bomb_hit_z, 1.25)
        return
    if powerup_candidate != null:
        _consume_item(powerup_candidate)
        bus.emit_signal("powerup_collected", powerup_candidate.powerup_type)
        bus.emit_signal("feedback_pulse", "powerup", powerup_hit_angle, powerup_hit_z, 0.65)
        return
    if orb_candidate != null:
        _consume_item(orb_candidate)
        bus.emit_signal("orb_collected", orb_candidate.value)
        bus.emit_signal("feedback_pulse", "orb_hit", orb_hit_angle, orb_hit_z, 0.55)

func _consume_item(item: SpawnItem) -> void:
    if not item.active:
        return
    item.active = false
