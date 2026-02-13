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

var _hidden_transform: Transform3D = Transform3D(Basis(), Vector3(0.0, 0.0, -10000.0))
var _clock: float = 0.0
var _next_slot: int = 0
var _slots: Array[Dictionary] = []
var _quad_mesh: QuadMesh = QuadMesh.new()

func _ready() -> void:
	_configure_multimesh()
	_reset_pool()
	bus.explosion_requested.connect(_on_explosion_requested)
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

		var origin: Vector3 = slot["origin"] as Vector3
		var kind: float = float(slot["kind"])
		var intensity: float = float(slot["intensity"])
		var base_scale: float = float(slot["scale"])
		var scale_now: float = base_scale * lerpf(0.35, 1.65, clampf(progress, 0.0, 1.0))

		var basis: Basis = Basis().scaled(Vector3.ONE * scale_now)
		mm.set_instance_transform(i, Transform3D(basis, origin))
		mm.set_instance_custom_data(i, Color(progress, kind, intensity, 0.0))

func _on_explosion_requested(world_pos: Vector3, is_player: bool, intensity: float) -> void:
	var safe_intensity: float = max(intensity, 0.6)
	if is_player:
		_spawn(world_pos, 1.0, player_lifetime, player_scale, max(safe_intensity, 1.0))
		_spawn(world_pos + Vector3(0.08, 0.02, 0.18), 1.0, player_lifetime * 0.9, player_scale * 0.72, max(safe_intensity * 0.9, 0.9))
		_spawn(world_pos + Vector3(-0.08, -0.02, 0.12), 1.0, player_lifetime * 0.85, player_scale * 0.65, max(safe_intensity * 0.85, 0.85))
	else:
		_spawn(world_pos, 0.0, enemy_lifetime, enemy_scale, max(safe_intensity, 0.7))

func _spawn(world_pos: Vector3, kind: float, lifetime: float, scale_val: float, intensity: float) -> void:
	if max_explosions <= 0:
		return
	var idx: int = _next_slot
	_next_slot = (_next_slot + 1) % max_explosions
	_slots[idx] = {
		"active": true,
		"origin": world_pos,
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
			"origin": Vector3.ZERO,
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
