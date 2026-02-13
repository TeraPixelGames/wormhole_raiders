extends Node
class_name VFXSystem

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")

@onready var game_root: Node = get_tree().current_scene
@onready var camera: Camera3D = game_root.get_node("World/PlayerRig/Camera3D")
@onready var track: GeometryInstance3D = game_root.get_node("World/Track") as GeometryInstance3D

@export var enable_camera_roll: bool = false
@export var camera_roll_response: float = 8.0
@export var camera_roll_scale: float = 0.08
@export var camera_roll_max: float = 0.15
@export var track_scroll_speed_scale: float = 0.22
@export var track_scroll_speed_min: float = 1.5
@export var base_fov: float = 70.0
@export var combo_fov_bonus_max: float = 6.0
@export var slipstream_fov_bonus: float = 4.0
@export var fov_response: float = 6.0
@export var shake_decay: float = 3.5
@export var shake_gain: float = 1.0
@export var max_shake: float = 0.08
@export var pulse_decay: float = 4.0
@export var flash_decay: float = 3.0
@export var desat_decay: float = 1.6
@export var near_miss_time_scale: float = 0.94
@export var near_miss_slow_duration: float = 0.07
@export var run_hue_ramp_seconds: float = 120.0

var _roll_angle: float = 0.0
var _shake: float = 0.0
var _pulse_strength: float = 0.0
var _pulse_angle01: float = 0.0
var _pulse_z: float = 0.0
var _flash_strength: float = 0.0
var _flash_tint: Color = Color(1.0, 0.95, 0.5, 1.0)
var _desat_amount: float = 0.0
var _milestone_boost: float = 0.0
var _slowmo_timer: float = 0.0
var _base_grid_color: Color = Color(1.0, 0.52, 0.98, 1.0)

func _ready() -> void:
    bus.feedback_pulse.connect(_on_feedback_pulse)
    bus.combo_milestone.connect(_on_combo_milestone)
    bus.run_started.connect(_on_run_started)
    bus.run_ended.connect(_on_run_ended)
    if track != null and track.material_override is ShaderMaterial:
        var sm: ShaderMaterial = track.material_override as ShaderMaterial
        if sm != null:
            var v: Variant = sm.get_shader_parameter("grid_color")
            if v is Color:
                _base_grid_color = v

func _process(delta: float) -> void:
    if enable_camera_roll:
        var target_roll: float = clampf(state.player_ang_vel * camera_roll_scale, -camera_roll_max, camera_roll_max)
        _roll_angle = lerpf(_roll_angle, target_roll, clampf(delta * camera_roll_response, 0.0, 1.0))
        camera.rotation.z = _roll_angle
    else:
        _roll_angle = 0.0
    _shake = move_toward(_shake, 0.0, shake_decay * delta)
    if _shake > 0.0:
        camera.h_offset = randf_range(-_shake, _shake)
        camera.v_offset = randf_range(-_shake, _shake)
    else:
        camera.h_offset = 0.0
        camera.v_offset = 0.0
    if _slowmo_timer > 0.0:
        _slowmo_timer = max(_slowmo_timer - delta, 0.0)
        Engine.time_scale = near_miss_time_scale
    else:
        Engine.time_scale = move_toward(Engine.time_scale, 1.0, 4.5 * delta)

    _pulse_strength = move_toward(_pulse_strength, 0.0, pulse_decay * delta)
    _flash_strength = move_toward(_flash_strength, 0.0, flash_decay * delta)
    _desat_amount = move_toward(_desat_amount, 0.0, desat_decay * delta)
    _milestone_boost = move_toward(_milestone_boost, 0.0, 1.8 * delta)

    var combo_t01: float = clampf(float(state.combo) / 30.0, 0.0, 1.0)
    var target_fov: float = base_fov + combo_t01 * combo_fov_bonus_max + state.slipstream_strength * slipstream_fov_bonus + _milestone_boost * 2.0
    camera.fov = lerpf(camera.fov, target_fov, clampf(delta * fov_response, 0.0, 1.0))

    if track == null:
        return
    var material: Material = track.material_override
    if material is ShaderMaterial:
        var shader_mat := material as ShaderMaterial
        if shader_mat.shader != null:
            var scroll_speed: float = max(track_scroll_speed_min, state.speed * track_scroll_speed_scale)
            var phase_boost: float = 0.0
            if state.wave_phase == GameConstants.WavePhase.SURGE:
                phase_boost = 0.12
            elif state.wave_phase == GameConstants.WavePhase.RELEASE:
                phase_boost = -0.06
            elif state.wave_phase == GameConstants.WavePhase.POWERUP:
                phase_boost = 0.05
            var combo_intensity: float = clampf(float(state.combo) * 0.015, 0.0, 0.42)
            var hue_t: float = clampf(state.run_time / max(run_hue_ramp_seconds, 1.0), 0.0, 1.0)
            var hue_color: Color = _base_grid_color.lerp(Color(1.0, 0.62, 0.86, 1.0), hue_t)
            shader_mat.set_shader_parameter("scroll_speed", scroll_speed)
            shader_mat.set_shader_parameter("intensity", clampf(0.7 + state.difficulty * 0.2 + combo_intensity + phase_boost + _milestone_boost * 0.35, 0.65, 1.6))
            shader_mat.set_shader_parameter("difficulty", state.difficulty)
            shader_mat.set_shader_parameter("grid_color", hue_color)
            shader_mat.set_shader_parameter("flow_visual_strength", clampf(0.2 + state.slipstream_strength * 0.9, 0.0, 1.1))
            shader_mat.set_shader_parameter("pulse_angle", _pulse_angle01)
            shader_mat.set_shader_parameter("pulse_z", _pulse_z)
            shader_mat.set_shader_parameter("pulse_strength", _pulse_strength)
            shader_mat.set_shader_parameter("flash_tint", _flash_tint)
            shader_mat.set_shader_parameter("flash_strength", _flash_strength)
            shader_mat.set_shader_parameter("desat_amount", _desat_amount)

func _on_feedback_pulse(kind: String, angle: float, z: float, intensity: float) -> void:
    _pulse_angle01 = fposmod(GameConstants.normalize_angle(angle) / TAU + 1.0, 1.0)
    _pulse_z = z
    _pulse_strength = max(_pulse_strength, intensity)
    match kind:
        "orb_hit":
            _shake = min(max_shake, _shake + 0.03 * shake_gain)
            _flash_tint = Color(0.95, 0.50, 1.0, 1.0)
            _flash_strength = max(_flash_strength, 0.10)
        "powerup":
            _shake = min(max_shake, _shake + 0.02 * shake_gain)
            _flash_tint = Color(1.0, 0.95, 0.45, 1.0)
            _flash_strength = max(_flash_strength, 0.14)
        "near_miss":
            _shake = min(max_shake, _shake + 0.04 * shake_gain)
            _flash_tint = Color(0.75, 0.88, 1.0, 1.0)
            _flash_strength = max(_flash_strength, 0.09)
            _slowmo_timer = max(_slowmo_timer, near_miss_slow_duration)
        "shield_break":
            _shake = min(max_shake, _shake + 0.06 * shake_gain)
            _flash_tint = Color(1.0, 0.9, 0.45, 1.0)
            _flash_strength = max(_flash_strength, 0.26)
        "player_death":
            _shake = min(max_shake, _shake + 0.08 * shake_gain)
            _flash_tint = Color(0.9, 0.25, 0.25, 1.0)
            _flash_strength = max(_flash_strength, 0.22)
            _desat_amount = max(_desat_amount, 0.45)

func _on_combo_milestone(_combo: int) -> void:
    _milestone_boost = 1.0
    _shake = min(max_shake, _shake + 0.05 * shake_gain)
    _flash_tint = Color(1.0, 0.5, 0.95, 1.0)
    _flash_strength = max(_flash_strength, 0.18)

func _on_run_started(_seed: int) -> void:
    _shake = 0.0
    _pulse_strength = 0.0
    _flash_strength = 0.0
    _desat_amount = 0.0
    _milestone_boost = 0.0
    _slowmo_timer = 0.0
    Engine.time_scale = 1.0

func _on_run_ended(_reason: String) -> void:
    _desat_amount = max(_desat_amount, 0.35)

func _exit_tree() -> void:
    Engine.time_scale = 1.0
