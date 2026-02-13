extends Node
class_name UISystem

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")
@onready var run: RunController = get_parent().get_node("RunController")
@onready var progression: ProgressionSystem = get_parent().get_node_or_null("ProgressionSystem") as ProgressionSystem

@onready var game_root := get_tree().current_scene
@onready var ad_manager := get_node_or_null("/root/AdManager")
@onready var hud_label: Label = game_root.get_node("UI/Hud/Label")
@onready var end_panel: Control = game_root.get_node("UI/EndPanel")
@onready var end_reason: Label = game_root.get_node("UI/EndPanel/Reason")
@onready var restart_btn: Button = game_root.get_node("UI/EndPanel/RestartButton")
@onready var continue_btn: Button = game_root.get_node("UI/EndPanel/ContinueButton")
@onready var camera: Camera3D = game_root.get_node("World/PlayerRig/Camera3D") as Camera3D

@export var popup_lifetime: float = 0.55
@export var popup_rise_speed: float = 72.0
@export var popup_x_jitter: float = 8.0

@export var show_angle_debug: bool = false

var _high_score: int = 0
var _wave_index: int = 1
var _wave_phase: int = GameConstants.WavePhase.BUILD
var _boss_wave: bool = false
var _pop_layer: Control
var _popups: Array[Dictionary] = []

func _ready() -> void:
    bus.run_started.connect(_on_run_started)
    bus.run_resumed.connect(_on_run_resumed)
    bus.run_ended.connect(_on_run_ended)
    bus.shield_changed.connect(_on_shield_changed)
    bus.combo_changed.connect(_on_combo_changed)
    bus.score_changed.connect(_on_score_changed)
    bus.wave_changed.connect(_on_wave_changed)
    bus.feedback_pulse.connect(_on_feedback_pulse)
    bus.high_score_changed.connect(_on_high_score_changed)

    restart_btn.pressed.connect(_on_restart_pressed)
    continue_btn.pressed.connect(_on_continue_pressed)

    if ad_manager != null:
        ad_manager.rewarded_granted.connect(_on_rewarded_granted)
        ad_manager.rewarded_failed.connect(_on_rewarded_failed)
        ad_manager.rewarded_loaded.connect(_on_rewarded_loaded)

    if progression != null:
        _high_score = progression.get_high_score()

    _pop_layer = Control.new()
    _pop_layer.name = "Popups"
    _pop_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _pop_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
    _pop_layer.offset_left = 0.0
    _pop_layer.offset_top = 0.0
    _pop_layer.offset_right = 0.0
    _pop_layer.offset_bottom = 0.0
    game_root.get_node("UI").add_child(_pop_layer)

    end_panel.visible = false
    _refresh_hud()

func _on_run_started(seed: int) -> void:
    end_panel.visible = false
    _refresh_hud()

func _on_run_resumed() -> void:
    end_panel.visible = false
    _refresh_hud()

func _on_run_ended(reason: String) -> void:
    end_panel.visible = true
    end_reason.text = "Run Ended: %s" % reason
    continue_btn.disabled = ad_manager == null or not ad_manager.is_rewarded_ready()
    _refresh_hud()

func _on_restart_pressed() -> void:
    if ad_manager != null:
        ad_manager.maybe_show_interstitial_after_run()
    run.start_run(run.get_next_seed())

func _on_continue_pressed() -> void:
    continue_btn.disabled = true
    if ad_manager != null:
        ad_manager.show_rewarded_for_continue()
    else:
        _on_rewarded_failed()

func _on_rewarded_granted() -> void:
    if ad_manager != null:
        ad_manager.mark_rewarded_continue_used()
    run.continue_with_shield()

func _on_rewarded_failed() -> void:
    continue_btn.disabled = false

func _on_rewarded_loaded(ready: bool) -> void:
    if end_panel.visible:
        continue_btn.disabled = not ready

func _on_shield_changed(active: bool) -> void:
    _refresh_hud()

func _on_combo_changed(combo: int, multiplier: int) -> void:
    _refresh_hud()

func _on_score_changed(score: int) -> void:
    _refresh_hud()

func _on_high_score_changed(high_score: int) -> void:
    _high_score = high_score
    _refresh_hud()

func _on_wave_changed(wave_index: int, phase: int, boss_wave: bool) -> void:
    var stage_changed: bool = wave_index != _wave_index
    _wave_index = wave_index
    _wave_phase = phase
    _boss_wave = boss_wave
    if stage_changed:
        _spawn_popup(_wave_banner_text(), _phase_color(phase), Vector2(get_viewport().get_visible_rect().size.x * 0.5, 110.0), 0.8)
    _refresh_hud()

func _on_feedback_pulse(kind: String, angle: float, z: float, _intensity: float) -> void:
    var world_pos: Vector3 = GameConstants.angle_world_pos(angle, z, max(GameConstants.R - 0.3, 0.1), state.difficulty)
    var screen_pos: Vector2 = _to_screen(world_pos)
    match kind:
        "orb_hit":
            _spawn_popup("ENEMY DOWN", Color(0.35, 0.95, 1.0, 1.0), screen_pos, popup_lifetime)
        "powerup":
            _spawn_popup("PICKUP SHIELD", Color(1.0, 0.92, 0.35, 1.0), screen_pos, popup_lifetime + 0.1)
        "near_miss":
            _spawn_popup("NEAR MISS", Color(0.7, 0.88, 1.0, 1.0), screen_pos, popup_lifetime + 0.08)
        "shield_break":
            _spawn_popup("SHIELD BREAK", Color(1.0, 0.85, 0.45, 1.0), screen_pos, popup_lifetime + 0.1)
        "player_death":
            _spawn_popup("HIT", Color(1.0, 0.4, 0.4, 1.0), screen_pos, popup_lifetime + 0.12)

func _process(delta: float) -> void:
    if state.running:
        _refresh_hud()
    _update_popups(delta)

func _refresh_hud() -> void:
    var shield_text := "ON" if state.shield else "OFF"
    var wave_text: String = _phase_name(_wave_phase)
    if _boss_wave:
        wave_text += " BOSS"
    var base_text: String = "Score %d | HS %d | x%d | Combo %d | Shield %s | Speed %.1f | W%d %s" % [state.score, _high_score, state.multiplier, state.combo, shield_text, state.speed, _wave_index, wave_text]
    if show_angle_debug:
        base_text += " | A %.2f | AV %.2f" % [state.player_angle, state.player_ang_vel]
    hud_label.text = base_text

func _to_screen(world_pos: Vector3) -> Vector2:
    if camera == null:
        return get_viewport().get_visible_rect().size * 0.5
    var p: Vector2 = camera.unproject_position(world_pos)
    return Vector2(p.x + randf_range(-popup_x_jitter, popup_x_jitter), p.y)

func _spawn_popup(text: String, color: Color, screen_pos: Vector2, lifetime: float) -> void:
    if _pop_layer == null:
        return
    var label: Label = Label.new()
    label.text = text
    label.self_modulate = color
    label.position = screen_pos
    _pop_layer.add_child(label)
    _popups.append({
        "label": label,
        "ttl": max(lifetime, 0.1),
        "max_ttl": max(lifetime, 0.1)
    })

func _update_popups(delta: float) -> void:
    if _popups.is_empty():
        return
    for i in range(_popups.size() - 1, -1, -1):
        var p: Dictionary = _popups[i]
        var label: Label = p["label"] as Label
        var ttl: float = float(p["ttl"]) - delta
        p["ttl"] = ttl
        if label != null:
            label.position.y -= popup_rise_speed * delta
            var alpha: float = clampf(ttl / max(float(p["max_ttl"]), 0.001), 0.0, 1.0)
            var c: Color = label.self_modulate
            c.a = alpha
            label.self_modulate = c
        if ttl <= 0.0:
            if label != null and is_instance_valid(label):
                label.queue_free()
            _popups.remove_at(i)
        else:
            _popups[i] = p

func _phase_name(phase: int) -> String:
    match phase:
        GameConstants.WavePhase.BUILD:
            return "BUILD"
        GameConstants.WavePhase.SURGE:
            return "SURGE"
        GameConstants.WavePhase.RELEASE:
            return "RELEASE"
        GameConstants.WavePhase.POWERUP:
            return "POWER"
    return "BUILD"

func _wave_banner_text() -> String:
    var text: String = "STAGE %d" % _wave_index
    if _boss_wave:
        text += " BOSS"
    return text

func _phase_color(phase: int) -> Color:
    match phase:
        GameConstants.WavePhase.BUILD:
            return Color(0.78, 0.82, 1.0, 1.0)
        GameConstants.WavePhase.SURGE:
            return Color(1.0, 0.55, 0.9, 1.0)
        GameConstants.WavePhase.RELEASE:
            return Color(0.62, 0.98, 0.92, 1.0)
        GameConstants.WavePhase.POWERUP:
            return Color(1.0, 0.9, 0.45, 1.0)
    return Color.WHITE
