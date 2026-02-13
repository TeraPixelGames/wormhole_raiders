extends Node
class_name LaserSystem

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")
@onready var gen: PatternGenerator = get_parent().get_node("PatternGenerator")
@onready var input_system: InputSystem = get_parent().get_node("InputSystem") as InputSystem
@onready var spawn_system: SpawnSystem = get_parent().get_node("SpawnSystem") as SpawnSystem
@onready var game_root: Node = get_tree().current_scene
@onready var player_lasers_mm: MultiMeshInstance3D = game_root.get_node("World/PlayerLasersMM") as MultiMeshInstance3D
@onready var enemy_lasers_mm: MultiMeshInstance3D = game_root.get_node("World/EnemyLasersMM") as MultiMeshInstance3D

@export var max_player_lasers: int = 160
@export var max_enemy_lasers: int = 96
@export var desktop_fire_key: Key = KEY_SPACE
@export var player_fire_rate: float = 10.0
@export var player_laser_speed: float = 78.0
@export var player_laser_length: float = 1.45
@export var player_laser_radius: float = 0.05
@export var player_muzzle_forward_offset: float = 2.1
@export var player_laser_inherit_speed: float = 0.25
@export var player_laser_lifetime: float = 1.7
@export var player_laser_fade_duration: float = 0.28
@export var laser_radius_inset: float = 0.9
@export var player_hit_window_z: float = 0.95
@export var player_hit_window_angle: float = 0.17
@export var elite_hit_value_bonus: int = 1

@export var enemy_fire_enabled: bool = true
@export var enemy_fire_rate_per_second: float = 1.25
@export var enemy_laser_relative_speed: float = 36.0
@export var enemy_laser_length: float = 1.9
@export var enemy_laser_radius: float = 0.09
@export var enemy_laser_lifetime: float = 2.4
@export var enemy_laser_fade_duration: float = 0.34
@export var enemy_hit_window_z: float = 0.9
@export var enemy_hit_window_angle: float = 0.16
@export var enemy_track_strength: float = 1.6
@export var enemy_fire_min_ahead_z: float = 8.0
@export var enemy_fire_max_ahead_z: float = 46.0

var _hidden_transform: Transform3D = Transform3D(Basis(), Vector3(0.0, 0.0, -10000.0))
var _player_lasers: Array[Dictionary] = []
var _enemy_lasers: Array[Dictionary] = []
var _next_player_slot: int = 0
var _next_enemy_slot: int = 0
var _player_fire_timer: float = 0.0
var _enemy_fire_timer: float = 0.0
var _player_mesh: CylinderMesh = CylinderMesh.new()
var _enemy_mesh: CylinderMesh = CylinderMesh.new()

func _ready() -> void:
	_configure_meshes_and_materials()
	_init_multimesh(player_lasers_mm.multimesh, max_player_lasers)
	_init_multimesh(enemy_lasers_mm.multimesh, max_enemy_lasers)
	_reset_lasers()
	bus.run_started.connect(_on_run_started)
	bus.run_ended.connect(_on_run_ended)

func _on_run_started(_seed: int) -> void:
	_reset_lasers()

func _on_run_ended(_reason: String) -> void:
	_reset_lasers()

func _process(delta: float) -> void:
	if not state.running:
		return

	_player_fire_timer = max(_player_fire_timer - delta, 0.0)
	_enemy_fire_timer = max(_enemy_fire_timer - delta, 0.0)

	_update_player_fire()
	_update_enemy_fire()
	_update_player_lasers(delta)
	_update_enemy_lasers(delta)
	_resolve_player_hits()
	_resolve_enemy_hits()

func _update_player_fire() -> void:
	var wants_fire: bool = Input.is_key_pressed(desktop_fire_key)
	if input_system != null and input_system.is_fire_pressed():
		wants_fire = true
	if not wants_fire:
		return
	if _player_fire_timer > 0.0:
		return
	var fire_rate: float = player_fire_rate * (1.0 + state.fire_rate_boost)
	_player_fire_timer = 1.0 / max(fire_rate, 0.1)
	var muzzle_lead_time: float = player_muzzle_forward_offset / max(state.speed, 0.1)
	var spawn_angle: float = GameConstants.normalize_angle(state.player_angle + state.player_ang_vel * muzzle_lead_time)
	_spawn_player_laser(spawn_angle, state.player_z + player_muzzle_forward_offset)

func _update_enemy_fire() -> void:
	if not enemy_fire_enabled:
		return
	if _enemy_fire_timer > 0.0:
		return

	var cadence: float = enemy_fire_rate_per_second
	if state.wave_phase == GameConstants.WavePhase.SURGE:
		cadence *= 1.5
	elif state.wave_phase == GameConstants.WavePhase.RELEASE:
		cadence *= 0.65
	elif state.wave_phase == GameConstants.WavePhase.POWERUP:
		cadence *= 0.8
	_enemy_fire_timer = 1.0 / max(cadence, 0.1)

	var source: SpawnItem = _find_enemy_laser_source()
	if source == null:
		return
	var shot_angle: float = source.runtime_angle(state.run_time, state.player_z)
	var shot_z: float = source.runtime_z(state.run_time, state.player_z)
	_spawn_enemy_laser(shot_angle, shot_z)

func _find_enemy_laser_source() -> SpawnItem:
	var best: SpawnItem = null
	var best_dz: float = INF
	for item in gen.commands:
		if not item.active:
			continue
		if item.kind != GameConstants.ItemKind.BOMB:
			continue
		var iz: float = item.runtime_z(state.run_time, state.player_z)
		var dz: float = iz - state.player_z
		if dz < enemy_fire_min_ahead_z or dz > enemy_fire_max_ahead_z:
			continue
		if dz < best_dz:
			best_dz = dz
			best = item
	return best

func _spawn_player_laser(angle: float, z: float) -> void:
	if max_player_lasers <= 0:
		return
	var i: int = _next_player_slot
	_next_player_slot = (_next_player_slot + 1) % max_player_lasers
	var z_speed: float = player_laser_speed + state.speed * player_laser_inherit_speed
	_player_lasers[i]["active"] = true
	_player_lasers[i]["angle"] = GameConstants.normalize_angle(angle)
	_player_lasers[i]["angle_vel"] = state.player_ang_vel
	_player_lasers[i]["z"] = z
	_player_lasers[i]["z_speed"] = z_speed
	_player_lasers[i]["age"] = 0.0
	_player_lasers[i]["lifetime"] = max(player_laser_lifetime, 0.05)
	_player_lasers[i]["fade_duration"] = max(player_laser_fade_duration, 0.01)
	bus.emit_signal("laser_fired", true)

func _spawn_enemy_laser(angle: float, z: float) -> void:
	if max_enemy_lasers <= 0:
		return
	var i: int = _next_enemy_slot
	_next_enemy_slot = (_next_enemy_slot + 1) % max_enemy_lasers
	_enemy_lasers[i]["active"] = true
	_enemy_lasers[i]["angle"] = GameConstants.normalize_angle(angle)
	_enemy_lasers[i]["z"] = z
	_enemy_lasers[i]["rel_speed"] = enemy_laser_relative_speed
	_enemy_lasers[i]["age"] = 0.0
	_enemy_lasers[i]["lifetime"] = max(enemy_laser_lifetime, 0.05)
	_enemy_lasers[i]["fade_duration"] = max(enemy_laser_fade_duration, 0.01)
	bus.emit_signal("laser_fired", false)

func _update_player_lasers(delta: float) -> void:
	var mm: MultiMesh = player_lasers_mm.multimesh
	for i in range(_player_lasers.size()):
		var shot: Dictionary = _player_lasers[i]
		if not bool(shot["active"]):
			continue
		var angle_vel: float = float(shot["angle_vel"])
		var angle: float = GameConstants.normalize_angle(float(shot["angle"]) + angle_vel * delta)
		var z: float = float(shot["z"]) + float(shot["z_speed"]) * delta
		var age: float = float(shot["age"]) + delta
		var lifetime: float = max(float(shot["lifetime"]), 0.05)
		var fade_duration: float = min(max(float(shot["fade_duration"]), 0.01), lifetime)
		shot["angle"] = angle
		shot["z"] = z
		shot["age"] = age
		if age >= lifetime or z > state.player_z + GameConstants.GENERATE_AHEAD + 24.0:
			_deactivate_player_laser(i)
			continue
		var fade: float = _compute_fade(age, lifetime, fade_duration)
		mm.set_instance_transform(i, _laser_transform(angle, z, player_laser_radius, player_laser_length, angle_vel, float(shot["z_speed"])))
		mm.set_instance_custom_data(i, Color(fade, 0.0, 0.0, 0.0))
		_player_lasers[i] = shot

func _update_enemy_lasers(delta: float) -> void:
	var mm: MultiMesh = enemy_lasers_mm.multimesh
	for i in range(_enemy_lasers.size()):
		var shot: Dictionary = _enemy_lasers[i]
		if not bool(shot["active"]):
			continue
		var angle: float = float(shot["angle"])
		var z_speed: float = state.speed - float(shot["rel_speed"])
		var z: float = float(shot["z"]) + z_speed * delta
		var age: float = float(shot["age"]) + delta
		var lifetime: float = max(float(shot["lifetime"]), 0.05)
		var fade_duration: float = min(max(float(shot["fade_duration"]), 0.01), lifetime)
		shot["angle"] = angle
		shot["z"] = z
		shot["age"] = age
		if age >= lifetime or z < state.player_z - 9.0:
			_deactivate_enemy_laser(i)
			continue
		mm.set_instance_transform(i, _laser_transform(angle, z, enemy_laser_radius, enemy_laser_length, 0.0, z_speed))
		mm.set_instance_custom_data(i, Color(_compute_fade(age, lifetime, fade_duration), 0.0, 0.0, 0.0))
		_enemy_lasers[i] = shot

func _resolve_player_hits() -> void:
	for i in range(_player_lasers.size()):
		var shot: Dictionary = _player_lasers[i]
		if not bool(shot["active"]):
			continue
		var shot_angle: float = float(shot["angle"])
		var shot_z: float = float(shot["z"])
		var hit: bool = false
		for item in gen.commands:
			if not item.active:
				continue
			if item.kind != GameConstants.ItemKind.ORB and item.kind != GameConstants.ItemKind.BOMB:
				continue
			var item_angle: float = item.runtime_angle(state.run_time, state.player_z)
			var item_z: float = item.runtime_z(state.run_time, state.player_z)
			if absf(item_z - shot_z) > player_hit_window_z:
				continue
			if absf(GameConstants.angle_diff(item_angle, shot_angle)) > player_hit_window_angle:
				continue
			var hit_origin: Vector3 = _item_world_origin(item)
			item.active = false
			var reward: int = item.value
			if item.kind == GameConstants.ItemKind.BOMB:
				reward += elite_hit_value_bonus
			bus.emit_signal("orb_collected", reward)
			bus.emit_signal("feedback_pulse", "orb_hit", item_angle, item_z, 0.62)
			bus.emit_signal("explosion_requested", hit_origin, false, 0.85)
			hit = true
			break
		if hit:
			_deactivate_player_laser(i)

func _resolve_enemy_hits() -> void:
	for i in range(_enemy_lasers.size()):
		var shot: Dictionary = _enemy_lasers[i]
		if not bool(shot["active"]):
			continue
		var shot_angle: float = float(shot["angle"])
		var shot_z: float = float(shot["z"])
		if absf(shot_z - state.player_z) > enemy_hit_window_z:
			continue
		if absf(GameConstants.angle_diff(shot_angle, state.player_angle)) > enemy_hit_window_angle:
			continue
		_deactivate_enemy_laser(i)
		bus.emit_signal("bomb_hit", state.shield)
		if state.shield:
			bus.emit_signal("feedback_pulse", "shield_break", shot_angle, shot_z, 1.0)
		else:
			bus.emit_signal("feedback_pulse", "player_death", shot_angle, shot_z, 1.2)
			var player_origin: Vector3 = GameConstants.angle_world_pos(state.player_angle, state.player_z, max(GameConstants.R - 0.9, 0.1), state.difficulty)
			bus.emit_signal("explosion_requested", player_origin, true, 1.15)
		break

func _laser_transform(angle: float, z: float, radius: float, length: float, angle_vel: float = 0.0, z_speed_hint: float = 1.0) -> Transform3D:
	var tangent: Vector3 = GameConstants.tube_tangent(z, state.difficulty)
	var radial: Vector3 = GameConstants.radial_from_angle(angle, z, state.difficulty)
	var side_axis: Vector3 = GameConstants.tube_side_axis(z, state.difficulty)
	var up_axis: Vector3 = GameConstants.tube_up_axis(z, state.difficulty)
	var around: Vector3 = (cos(angle) * side_axis + sin(angle) * up_axis).normalized()
	var around_speed: float = angle_vel * max(GameConstants.R - laser_radius_inset, 0.2)
	var motion: Vector3 = tangent * z_speed_hint + around * around_speed
	var travel_axis: Vector3 = motion.normalized() if motion.length_squared() > 0.000001 else tangent
	var right: Vector3 = travel_axis.cross(radial).normalized()
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	var pos: Vector3 = GameConstants.angle_world_pos(angle, z, max(GameConstants.R - laser_radius_inset, 0.2), state.difficulty)
	var basis: Basis = Basis(right, travel_axis, radial).orthonormalized()
	basis = basis.scaled(Vector3(radius, length, radius))
	return Transform3D(basis, pos)

func _deactivate_player_laser(i: int) -> void:
	_player_lasers[i]["active"] = false
	var mm: MultiMesh = player_lasers_mm.multimesh
	mm.set_instance_transform(i, _hidden_transform)
	mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))

func _deactivate_enemy_laser(i: int) -> void:
	_enemy_lasers[i]["active"] = false
	var mm: MultiMesh = enemy_lasers_mm.multimesh
	mm.set_instance_transform(i, _hidden_transform)
	mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))

func _reset_lasers() -> void:
	_next_player_slot = 0
	_next_enemy_slot = 0
	_player_fire_timer = 0.0
	_enemy_fire_timer = 0.0
	_player_lasers.clear()
	_enemy_lasers.clear()

	var mm_player: MultiMesh = player_lasers_mm.multimesh
	for i in range(max_player_lasers):
		_player_lasers.append({
			"active": false,
			"angle": 0.0,
			"angle_vel": 0.0,
			"z": 0.0,
			"z_speed": player_laser_speed,
			"age": 0.0,
			"lifetime": player_laser_lifetime,
			"fade_duration": player_laser_fade_duration
		})
		mm_player.set_instance_transform(i, _hidden_transform)
		mm_player.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))

	var mm_enemy: MultiMesh = enemy_lasers_mm.multimesh
	for i in range(max_enemy_lasers):
		_enemy_lasers.append({
			"active": false,
			"angle": 0.0,
			"z": 0.0,
			"rel_speed": enemy_laser_relative_speed,
			"age": 0.0,
			"lifetime": enemy_laser_lifetime,
			"fade_duration": enemy_laser_fade_duration
		})
		mm_enemy.set_instance_transform(i, _hidden_transform)
		mm_enemy.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))

func _init_multimesh(mm: MultiMesh, capacity: int) -> void:
	if mm.instance_count != 0:
		mm.instance_count = 0
	mm.transform_format = MultiMesh.TRANSFORM_3D
	_enable_multimesh_custom_data(mm)
	mm.instance_count = max(capacity, 0)
	mm.visible_instance_count = -1
	for i in range(capacity):
		mm.set_instance_transform(i, _hidden_transform)
		mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))

func _configure_meshes_and_materials() -> void:
	_player_mesh.top_radius = 1.0
	_player_mesh.bottom_radius = 1.0
	_player_mesh.height = 1.0
	_player_mesh.radial_segments = 6
	_player_mesh.rings = 1
	_player_mesh.cap_top = true
	_player_mesh.cap_bottom = true
	_enemy_mesh.top_radius = 1.0
	_enemy_mesh.bottom_radius = 1.0
	_enemy_mesh.height = 1.0
	_enemy_mesh.radial_segments = 6
	_enemy_mesh.rings = 1
	_enemy_mesh.cap_top = true
	_enemy_mesh.cap_bottom = true

	player_lasers_mm.multimesh.mesh = _player_mesh
	enemy_lasers_mm.multimesh.mesh = _enemy_mesh

	var player_mat: Material = load("res://materials/player_laser_green.tres") as Material
	if player_mat != null:
		player_lasers_mm.material_override = player_mat
	var enemy_mat: Material = load("res://materials/enemy_laser_red.tres") as Material
	if enemy_mat != null:
		enemy_lasers_mm.material_override = enemy_mat

func _compute_fade(age: float, lifetime: float, fade_duration: float) -> float:
	var fade_start: float = max(lifetime - fade_duration, 0.0)
	if age <= fade_start:
		return 1.0
	return clampf((lifetime - age) / max(fade_duration, 0.001), 0.0, 1.0)

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

func _item_world_origin(item: SpawnItem) -> Vector3:
	if spawn_system != null:
		return spawn_system.get_item_world_origin(item)
	var angle: float = item.runtime_angle(state.run_time, state.player_z)
	var z: float = item.runtime_z(state.run_time, state.player_z)
	return GameConstants.angle_world_pos(angle, z, max(GameConstants.R - 0.9, 0.1), state.difficulty)
