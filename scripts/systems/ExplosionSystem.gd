extends Node
class_name ExplosionSystem

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")
@onready var game_root: Node = get_tree().current_scene
@onready var explosions_mm: MultiMeshInstance3D = game_root.get_node("World/ExplosionsMM") as MultiMeshInstance3D

@export var max_explosions: int = 96
@export var enemy_lifetime: float = 0.68
@export var player_lifetime: float = 0.95
@export var enemy_scale: float = 2.6
@export var player_scale: float = 3.4
@export var explosion_radius_inset: float = 0.95

var _hidden_transform: Transform3D = Transform3D(Basis(), Vector3(0.0, 0.0, -10000.0))
var _clock: float = 0.0
var _next_slot: int = 0
var _slots: Array[Dictionary] = []
var _quad_mesh: QuadMesh = QuadMesh.new()

func _ready() -> void:
	_configure_multimesh()
	_reset_pool()
	bus.feedback_pulse.connect(_on_feedback_pulse)
	bus.run_started.connect(_on_run_started)

func _on_run_started(_seed: int) -> void:
	_reset_pool()

func _process(delta: float) -> void:
	_clock += delta
	var mm: MultiMesh = explosions_mm.multimesh
	for i in range(_slots.size()):
		var slot: Dictionary = _slots[i]
		if not bool(slot["active"]):
			continue

		var start_t: float = float(slot["start_t"])
		var life: float = max(float(slot["lifetime"]), 0.001)
		var progress: float = (_clock - start_t) / life
		if progress >= 1.0:
			_deactivate(i)
			continue

		var angle: float = float(slot["angle"])
		var z: float = float(slot["z"]) + progress * 0.35
		var kind: float = float(slot["kind"])
		var intensity: float = float(slot["intensity"])
		var base_scale: float = float(slot["scale"])
		var scale_now: float = base_scale * lerpf(0.35, 1.65, clampf(progress, 0.0, 1.0))

		var pos: Vector3 = GameConstants.angle_world_pos(
			angle,
			z,
			max(GameConstants.R - explosion_radius_inset, 0.2),
			state.difficulty
		)
		var basis: Basis = Basis().scaled(Vector3.ONE * scale_now)
		mm.set_instance_transform(i, Transform3D(basis, pos))
		mm.set_instance_custom_data(i, Color(progress, kind, intensity, 0.0))

func _on_feedback_pulse(kind: String, angle: float, z: float, intensity: float) -> void:
	match kind:
		"orb_hit":
			_spawn(angle, z, 0.0, enemy_lifetime, enemy_scale, max(intensity, 0.7))
		"player_death":
			_spawn(angle, z, 1.0, player_lifetime, player_scale, max(intensity, 1.0))
			_spawn(angle + 0.08, z + 0.3, 1.0, player_lifetime * 0.9, player_scale * 0.72, max(intensity * 0.9, 0.9))
			_spawn(angle - 0.08, z + 0.2, 1.0, player_lifetime * 0.85, player_scale * 0.65, max(intensity * 0.85, 0.85))

func _spawn(angle: float, z: float, kind: float, lifetime: float, scale_val: float, intensity: float) -> void:
	if max_explosions <= 0:
		return
	var idx: int = _next_slot
	_next_slot = (_next_slot + 1) % max_explosions
	_slots[idx] = {
		"active": true,
		"angle": GameConstants.normalize_angle(angle),
		"z": z,
		"kind": kind,
		"start_t": _clock,
		"lifetime": max(lifetime, 0.05),
		"scale": scale_val,
		"intensity": intensity
	}

func _deactivate(idx: int) -> void:
	var mm: MultiMesh = explosions_mm.multimesh
	_slots[idx]["active"] = false
	mm.set_instance_transform(idx, _hidden_transform)
	mm.set_instance_custom_data(idx, Color(0.0, 0.0, 0.0, 0.0))

func _reset_pool() -> void:
	_clock = 0.0
	_next_slot = 0
	_slots.clear()
	var mm: MultiMesh = explosions_mm.multimesh
	for i in range(max_explosions):
		_slots.append({
			"active": false,
			"angle": 0.0,
			"z": 0.0,
			"kind": 0.0,
			"start_t": 0.0,
			"lifetime": enemy_lifetime,
			"scale": enemy_scale,
			"intensity": 1.0
		})
		mm.set_instance_transform(i, _hidden_transform)
		mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))

func _configure_multimesh() -> void:
	_quad_mesh.size = Vector2(1.0, 1.0)
	var mm: MultiMesh = explosions_mm.multimesh
	if mm.instance_count != 0:
		mm.instance_count = 0
	mm.transform_format = MultiMesh.TRANSFORM_3D
	_enable_multimesh_custom_data(mm)
	mm.instance_count = max(max_explosions, 0)
	mm.visible_instance_count = -1
	mm.mesh = _quad_mesh
	for i in range(max_explosions):
		mm.set_instance_transform(i, _hidden_transform)
		mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))

	var mat: Material = load("res://materials/explosion_vfx.tres") as Material
	if mat != null:
		explosions_mm.material_override = mat

func _enable_multimesh_custom_data(mm: MultiMesh) -> void:
	if _has_property(mm, "custom_data_format"):
		mm.set("custom_data_format", 2)
		return
	if _has_property(mm, "use_custom_data"):
		mm.set("use_custom_data", true)

func _has_property(obj: Object, prop_name: String) -> bool:
	for prop: Dictionary in obj.get_property_list():
		if prop.has("name") and String(prop["name"]) == prop_name:
			return true
	return false
