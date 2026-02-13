extends Node
class_name SpawnSystem

@onready var state: RunState = get_parent().get_node("RunState")
@onready var gen: PatternGenerator = get_parent().get_node("PatternGenerator")
@onready var bus: EventBus = get_parent().get_node("EventBus")

# Visual targets
@onready var game_root: Node = get_tree().current_scene

var _orbs_mm: MultiMeshInstance3D
var _bombs_mm: MultiMeshInstance3D
var _pups_mm: MultiMeshInstance3D

# Simple visual meshes (can be replaced with nicer assets)
var _orb_mesh: SphereMesh = SphereMesh.new()
var _bomb_mesh: SphereMesh = SphereMesh.new()
var _pup_mesh: SphereMesh = SphereMesh.new()
var _orb_mat: StandardMaterial3D = StandardMaterial3D.new()
var _bomb_mat: StandardMaterial3D = StandardMaterial3D.new()
var _pup_mat: StandardMaterial3D = StandardMaterial3D.new()

@export var max_orb_instances: int = 320
@export var max_bomb_instances: int = 130
@export var max_powerup_instances: int = 50
@export var hidden_cull_z: float = -10000.0
@export var render_behind_distance: float = 4.5
@export var models_dir: String = "res://imported_models"
@export var auto_assign_imported_models: bool = true
@export var orb_model_path: String = ""
@export var bomb_model_path: String = ""
@export var powerup_model_path: String = ""
@export var enemy_model_path: String = ""
@export var elite_enemy_model_path: String = ""
@export var pickup_model_path: String = ""
@export var orb_auto_index: int = 1
@export var bomb_auto_index: int = 2
@export var powerup_auto_index: int = 3
@export var orb_target_size: float = 0.52
@export var bomb_target_size: float = 0.58
@export var powerup_target_size: float = 0.62
@export var entity_radius_inset: float = 0.95

var _orb_item_to_idx: Dictionary = {}
var _bomb_item_to_idx: Dictionary = {}
var _pup_item_to_idx: Dictionary = {}

var _orb_free: Array[int] = []
var _bomb_free: Array[int] = []
var _pup_free: Array[int] = []

var _orb_active_count: int = 0
var _bomb_active_count: int = 0
var _pup_active_count: int = 0
var _orb_instance_scale: float = 1.0
var _bomb_instance_scale: float = 1.0
var _pup_instance_scale: float = 1.0

func _ready() -> void:
	_orb_mesh.radius = 0.25
	_bomb_mesh.radius = 0.28
	_pup_mesh.radius = 0.30

	_orbs_mm = game_root.get_node("World/OrbsMM")
	_bombs_mm = game_root.get_node("World/BombsMM")
	_pups_mm = game_root.get_node("World/PowerupsMM")

	_configure_item_materials()
	_configure_meshes_and_materials()

	_init_multimesh(_orbs_mm.multimesh, max_orb_instances)
	_init_multimesh(_bombs_mm.multimesh, max_bomb_instances)
	_init_multimesh(_pups_mm.multimesh, max_powerup_instances)

	_orb_free = _make_free_stack(max_orb_instances)
	_bomb_free = _make_free_stack(max_bomb_instances)
	_pup_free = _make_free_stack(max_powerup_instances)

	bus.run_started.connect(_on_run_started)

func _process(delta: float) -> void:
	if not state.running:
		return

	gen.prune_before(state.player_z - GameConstants.CULL_BEHIND - 3.0)
	# Generate ahead
	gen.ensure_generated(state.player_z + GameConstants.GENERATE_AHEAD)

	var min_z := state.player_z - render_behind_distance
	var max_z := state.player_z + GameConstants.GENERATE_AHEAD

	for item in gen.commands:
		_sync_visual_for_item(item, min_z, max_z)

func _pos_for_angle_z(angle: float, z: float) -> Vector3:
	var radius: float = max(GameConstants.R - entity_radius_inset, 0.2)
	return GameConstants.angle_world_pos(angle, z, radius, state.difficulty)

func _init_multimesh(mm: MultiMesh, capacity: int) -> void:
	if mm.instance_count != 0:
		mm.instance_count = 0
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = capacity
	mm.visible_instance_count = -1
	var hidden := Transform3D(Basis(), Vector3(0.0, 0.0, hidden_cull_z))
	for i in range(capacity):
		mm.set_instance_transform(i, hidden)

func _configure_item_materials() -> void:
	_orb_mat.albedo_color = Color(0.35, 0.9, 1.0, 1.0)
	_orb_mat.emission_enabled = true
	_orb_mat.emission = Color(0.10, 0.28, 0.35, 1.0)
	_orb_mat.roughness = 0.25

	_bomb_mat.albedo_color = Color(0.95, 0.30, 0.24, 1.0)
	_bomb_mat.emission_enabled = true
	_bomb_mat.emission = Color(0.22, 0.03, 0.03, 1.0)
	_bomb_mat.roughness = 0.45

	_pup_mat.albedo_color = Color(1.0, 0.88, 0.30, 1.0)
	_pup_mat.emission_enabled = true
	_pup_mat.emission = Color(0.22, 0.18, 0.03, 1.0)
	_pup_mat.roughness = 0.35

func _make_free_stack(capacity: int) -> Array[int]:
	var stack: Array[int] = []
	for i in range(capacity):
		stack.append(capacity - 1 - i)
	return stack

func _sync_visual_for_item(item: SpawnItem, min_z: float, max_z: float) -> void:
	var runtime_z: float = item.runtime_z(state.run_time, state.player_z)
	var runtime_angle: float = item.runtime_angle(state.run_time, state.player_z)
	var in_window := item.active and runtime_z >= min_z and runtime_z <= max_z
	match item.kind:
		GameConstants.ItemKind.ORB:
			_sync_kind(item, in_window, _orbs_mm.multimesh, _orb_item_to_idx, _orb_free, true, _orb_instance_scale, runtime_angle, runtime_z)
		GameConstants.ItemKind.BOMB:
			_sync_kind(item, in_window, _bombs_mm.multimesh, _bomb_item_to_idx, _bomb_free, false, _bomb_instance_scale, runtime_angle, runtime_z)
		GameConstants.ItemKind.POWERUP:
			_sync_kind(item, in_window, _pups_mm.multimesh, _pup_item_to_idx, _pup_free, null, _pup_instance_scale, runtime_angle, runtime_z)

func _sync_kind(item: SpawnItem, in_window: bool, mm: MultiMesh, map: Dictionary, free: Array[int], is_orb: Variant, visual_scale: float, runtime_angle: float, runtime_z: float) -> void:
	if in_window:
		var basis: Basis = Basis().scaled(Vector3.ONE * visual_scale)
		var xform := Transform3D(basis, _pos_for_angle_z(runtime_angle, runtime_z))
		if not map.has(item.id):
			if free.is_empty():
				return
			var idx : int = free.pop_back()
			map[item.id] = idx
			mm.set_instance_transform(idx, xform)
			if is_orb == true:
				_orb_active_count += 1
			elif is_orb == false:
				_bomb_active_count += 1
			else:
				_pup_active_count += 1
		elif item.is_dynamic_motion():
			var update_idx: int = map[item.id]
			mm.set_instance_transform(update_idx, xform)
		return

	if map.has(item.id):
		var remove_idx: int = map[item.id]
		map.erase(item.id)
		mm.set_instance_transform(remove_idx, Transform3D(Basis(), Vector3(0.0, 0.0, hidden_cull_z)))
		free.append(remove_idx)
		if is_orb == true:
			_orb_active_count = max(_orb_active_count - 1, 0)
		elif is_orb == false:
			_bomb_active_count = max(_bomb_active_count - 1, 0)
		else:
			_pup_active_count = max(_pup_active_count - 1, 0)

func _on_run_started(seed: int) -> void:
	_orb_item_to_idx.clear()
	_bomb_item_to_idx.clear()
	_pup_item_to_idx.clear()
	_orb_free = _make_free_stack(max_orb_instances)
	_bomb_free = _make_free_stack(max_bomb_instances)
	_pup_free = _make_free_stack(max_powerup_instances)
	_orb_active_count = 0
	_bomb_active_count = 0
	_pup_active_count = 0
	_init_multimesh(_orbs_mm.multimesh, max_orb_instances)
	_init_multimesh(_bombs_mm.multimesh, max_bomb_instances)
	_init_multimesh(_pups_mm.multimesh, max_powerup_instances)

func _configure_meshes_and_materials() -> void:
	var resolved_orb_path: String = enemy_model_path if not enemy_model_path.is_empty() else orb_model_path
	var resolved_bomb_path: String = elite_enemy_model_path if not elite_enemy_model_path.is_empty() else bomb_model_path
	var resolved_powerup_path: String = pickup_model_path if not pickup_model_path.is_empty() else powerup_model_path
	if auto_assign_imported_models:
		resolved_orb_path = ModelAssetUtils.resolve_model_path(models_dir, resolved_orb_path, orb_auto_index)
		resolved_bomb_path = ModelAssetUtils.resolve_model_path(models_dir, resolved_bomb_path, bomb_auto_index)
		resolved_powerup_path = ModelAssetUtils.resolve_model_path(models_dir, resolved_powerup_path, powerup_auto_index)

	var imported_orb_mesh: Mesh = ModelAssetUtils.load_first_mesh(resolved_orb_path)
	var imported_bomb_mesh: Mesh = ModelAssetUtils.load_first_mesh(resolved_bomb_path)
	var imported_powerup_mesh: Mesh = ModelAssetUtils.load_first_mesh(resolved_powerup_path)

	_orbs_mm.multimesh.mesh = _orb_mesh
	_bombs_mm.multimesh.mesh = _bomb_mesh
	_pups_mm.multimesh.mesh = _pup_mesh
	_orbs_mm.material_override = _orb_mat
	_bombs_mm.material_override = _bomb_mat
	_pups_mm.material_override = _pup_mat
	_orb_instance_scale = 1.0
	_bomb_instance_scale = 1.0
	_pup_instance_scale = 1.0

	if imported_orb_mesh != null:
		_orbs_mm.multimesh.mesh = imported_orb_mesh
		_orbs_mm.material_override = null
		_orb_instance_scale = _calc_uniform_scale_for_mesh(imported_orb_mesh, orb_target_size)
	if imported_bomb_mesh != null:
		_bombs_mm.multimesh.mesh = imported_bomb_mesh
		_bombs_mm.material_override = null
		_bomb_instance_scale = _calc_uniform_scale_for_mesh(imported_bomb_mesh, bomb_target_size)
	if imported_powerup_mesh != null:
		_pups_mm.multimesh.mesh = imported_powerup_mesh
		_pups_mm.material_override = null
		_pup_instance_scale = _calc_uniform_scale_for_mesh(imported_powerup_mesh, powerup_target_size)

func _calc_uniform_scale_for_mesh(mesh: Mesh, target_size: float) -> float:
	var aabb: AABB = mesh.get_aabb()
	var max_dim: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if max_dim <= 0.0001:
		return 1.0
	return target_size / max_dim
