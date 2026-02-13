extends Node
class_name PatternGenerator

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var generated_to_z: float = 0.0
var _next_id: int = 1
var _shield_pity_seconds: float = 0.0
var _last_run_time: float = 0.0
var _templates: Array[Dictionary] = []
var _shield_stage_index: int = 1
var _shields_spawned_in_stage: int = 0

# Stores SpawnItem command objects (logic)
var commands: Array[SpawnItem] = []

@export var target_density_per_segment: float = 0.75
@export var max_total_active_items: int = 500
@export var shield_pity_start_seconds: float = 25.0
@export var shield_pity_full_seconds: float = 45.0
@export var min_shields_per_stage: int = 1
@export var max_shields_per_stage: int = 2
@export var formation_follow_ratio: float = 1.0
@export var formation_forward_drift: float = 0.0
@export var elite_extra_z_drift: float = 0.0
@export var base_formation_ahead_z: float = 26.0
@export var max_formation_ahead_z: float = 44.0
@export var enemy_value: int = 1
@export var opening_single_enemy_seconds: float = 10.0
@export var intro_max_active_hostiles: int = 1
@export var swarm_ramp_waves: int = 5
@export var stage_hostiles_base: int = 1
@export var stage_hostiles_growth: int = 4
@export var stage_hostiles_cap: int = 56
@export var boss_stage_hostile_bonus: int = 10
@export var stage_intro_duration: float = 1.1
@export var stage_intro_follow_ratio: float = 0.88
@export var stage_spawn_rewind_ahead_z: float = 34.0

var _stage_hostile_budget: int = 1
var _stage_hostiles_spawned: int = 0
var _stage_intro_until_run_time: float = 0.0

func _ready() -> void:
	_build_templates()
	bus.powerup_collected.connect(_on_powerup_collected)
	bus.run_started.connect(reset)

func reset(seed: int) -> void:
	rng.seed = seed
	generated_to_z = 0.0
	_next_id = 1
	_shield_pity_seconds = 0.0
	_last_run_time = 0.0
	_shield_stage_index = max(state.wave_index, 1)
	_shields_spawned_in_stage = 0
	commands.clear()
	start_stage(max(state.wave_index, 1), state.boss_wave_active)

func start_stage(stage_index: int, boss_stage: bool) -> void:
	_stage_hostile_budget = _compute_stage_hostile_budget(stage_index, boss_stage)
	_stage_hostiles_spawned = 0
	_stage_intro_until_run_time = state.run_time + max(stage_intro_duration, 0.0)
	_shield_stage_index = max(stage_index, 1)
	_shields_spawned_in_stage = 0
	var rewind_target_z: float = state.player_z + max(stage_spawn_rewind_ahead_z, GameConstants.SEGMENT_LEN)
	generated_to_z = min(generated_to_z, rewind_target_z)

func active_hostile_count() -> int:
	return _active_hostile_count()

func stage_hostiles_spawned_count() -> int:
	return _stage_hostiles_spawned

func stage_hostile_budget_count() -> int:
	return _stage_hostile_budget

func stage_hostile_budget_exhausted() -> bool:
	return _stage_hostiles_spawned >= _stage_hostile_budget

func ensure_generated(ahead_z: float) -> void:
	if not state.running:
		return
	var dt: float = max(state.run_time - _last_run_time, 0.0)
	_last_run_time = state.run_time
	_shield_pity_seconds += dt
	_sync_shield_stage_index()
	while generated_to_z < ahead_z:
		if active_count() >= max_total_active_items:
			break
		_generate_segment(generated_to_z, generated_to_z + GameConstants.SEGMENT_LEN)
		generated_to_z += GameConstants.SEGMENT_LEN

func prune_before(min_z: float) -> void:
	var kept: Array[SpawnItem] = []
	for item in commands:
		var item_z: float = item.runtime_z(state.run_time, state.player_z)
		if item.active and item_z < min_z and (item.kind == GameConstants.ItemKind.ORB or item.kind == GameConstants.ItemKind.BOMB):
			item.active = false
		if item.active or item_z >= min_z:
			kept.append(item)
	commands = kept

func active_count() -> int:
	var count: int = 0
	for item in commands:
		if item.active:
			count += 1
	return count

func _generate_segment(z0: float, z1: float) -> void:
	if stage_hostile_budget_exhausted():
		return
	var difficulty01: float = clampf(state.difficulty / 2.0, 0.0, 1.0)
	var swarm_scale: float = _wave_swarm_scale()
	var phase_density: float = _phase_density_multiplier(state.wave_phase)
	if state.boss_wave_active:
		phase_density *= 1.28
	var density: float = clampf((target_density_per_segment + difficulty01 * 0.5) * phase_density * swarm_scale, 0.2, 2.0)
	var templates_to_pick: int = 1
	var max_templates: int = clampi(1 + int(floor(swarm_scale * 2.0 + difficulty01 * 0.8)), 1, 3)
	if max_templates >= 2 and rng.randf() < density:
		templates_to_pick += 1
	if max_templates >= 3 and rng.randf() < max(density - 0.7, 0.0):
		templates_to_pick += 1

	var anchor_angle: float = GameConstants.normalize_angle(state.player_angle + rng.randf_range(-0.5, 0.5))
	if _is_opening_single_enemy_window():
		_generate_intro_segment(z0, z1, anchor_angle, difficulty01)
		_ensure_min_stage_shields(z0, z1, anchor_angle)
		maybe_spawn_pity_shield(z0, z1, anchor_angle)
		return

	for _i in range(templates_to_pick):
		if active_count() >= max_total_active_items:
			return
		var t: Dictionary = _pick_template(difficulty01)
		if t.is_empty():
			return
		var call: Callable = t["emit"]
		call.call(z0, z1, difficulty01, anchor_angle)
		anchor_angle = GameConstants.normalize_angle(anchor_angle + rng.randf_range(-0.35, 0.35))
	if state.boss_wave_active:
		_tpl_boss_ring(z0, z1, difficulty01, anchor_angle)
	_ensure_min_stage_shields(z0, z1, anchor_angle)
	maybe_spawn_pity_shield(z0, z1, anchor_angle)

func _pick_template(difficulty01: float) -> Dictionary:
	var filtered: Array[Dictionary] = []
	var total_weight: float = 0.0
	for t in _templates:
		if difficulty01 < float(t["min_d"]):
			continue
		if difficulty01 > float(t["max_d"]):
			continue
		var weight: float = _phase_weight_adjusted(t)
		if weight <= 0.0:
			continue
		var copy: Dictionary = t.duplicate()
		copy["weight"] = weight
		filtered.append(copy)
		total_weight += weight
	if filtered.is_empty() or total_weight <= 0.0:
		return {}
	var pick: float = rng.randf() * total_weight
	var cursor: float = 0.0
	for t in filtered:
		cursor += float(t["weight"])
		if pick <= cursor:
			return t
	return filtered[filtered.size() - 1]

func _phase_density_multiplier(phase: int) -> float:
	match phase:
		GameConstants.WavePhase.BUILD:
			return 1.0
		GameConstants.WavePhase.SURGE:
			return 1.35
		GameConstants.WavePhase.RELEASE:
			return 0.75
		GameConstants.WavePhase.POWERUP:
			return 0.82
	return 1.0

func _phase_weight_adjusted(t: Dictionary) -> float:
	var base: float = float(t["weight"])
	var name: String = String(t["name"])
	var wave_scale: float = _wave_swarm_scale()
	if name == "formation_block":
		base *= lerpf(0.4, 1.0, wave_scale)
	elif name == "formation_snake":
		base *= lerpf(0.5, 1.0, wave_scale)
	elif name == "formation_wing":
		base *= lerpf(0.75, 1.0, wave_scale)
	match state.wave_phase:
		GameConstants.WavePhase.SURGE:
			if name == "formation_block" or name == "formation_wing" or name == "formation_snake":
				base *= 1.4
			if name == "pickup_lane":
				base *= 0.5
		GameConstants.WavePhase.RELEASE:
			if name == "formation_arc" or name == "formation_line":
				base *= 1.3
			if name == "formation_block":
				base *= 0.7
		GameConstants.WavePhase.POWERUP:
			if name == "pickup_lane":
				base *= 2.5
			if name == "formation_block":
				base *= 0.75
	return base

func _build_templates() -> void:
	_templates = [
		{"name":"formation_line", "weight":1.1, "min_d":0.0, "max_d":1.0, "emit":Callable(self, "_tpl_formation_line")},
		{"name":"formation_arc", "weight":1.0, "min_d":0.0, "max_d":1.0, "emit":Callable(self, "_tpl_formation_arc")},
		{"name":"formation_wing", "weight":0.9, "min_d":0.15, "max_d":1.0, "emit":Callable(self, "_tpl_formation_wing")},
		{"name":"formation_block", "weight":0.8, "min_d":0.2, "max_d":1.0, "emit":Callable(self, "_tpl_formation_block")},
		{"name":"formation_snake", "weight":0.85, "min_d":0.25, "max_d":1.0, "emit":Callable(self, "_tpl_formation_snake")},
		{"name":"pickup_lane", "weight":0.55, "min_d":0.0, "max_d":1.0, "emit":Callable(self, "_tpl_pickup_lane")}
	]

func _add_item(kind: int, angle: float, z: float) -> SpawnItem:
	if active_count() >= max_total_active_items:
		return null
	var item: SpawnItem = SpawnItem.new(kind, GameConstants.normalize_angle(angle), z)
	item.id = _next_id
	item.value = enemy_value
	item.spawn_run_time = state.run_time
	item.spawn_player_z = state.player_z
	_next_id += 1
	commands.append(item)
	return item

func _add_enemy(angle: float, z: float) -> SpawnItem:
	if stage_hostile_budget_exhausted():
		return null
	var item: SpawnItem = _add_item(GameConstants.ItemKind.ORB, angle, z)
	if item != null:
		_stage_hostiles_spawned += 1
	return item

func _add_elite(angle: float, z: float) -> SpawnItem:
	if stage_hostile_budget_exhausted():
		return null
	var item: SpawnItem = _add_item(GameConstants.ItemKind.BOMB, angle, z)
	if item != null:
		_stage_hostiles_spawned += 1
	return item

func _add_shield(angle: float, z: float) -> SpawnItem:
	_sync_shield_stage_index()
	if not _can_spawn_stage_shield():
		return null
	var item: SpawnItem = _add_item(GameConstants.ItemKind.POWERUP, angle, z)
	if item != null:
		item.powerup_type = GameConstants.PowerupType.SHIELD
		_shields_spawned_in_stage += 1
	return item

func _random_angle_near(base_angle: float, spread: float) -> float:
	return GameConstants.normalize_angle(base_angle + rng.randf_range(-spread, spread))

func _formation_anchor_z(z0: float, z1: float, difficulty01: float) -> float:
	var depth_t: float = clampf(0.5 + difficulty01 * 0.35, 0.35, 0.95)
	var ahead: float = lerpf(base_formation_ahead_z, max_formation_ahead_z, depth_t)
	var seg_mid: float = lerpf(z0, z1, 0.5)
	return max(seg_mid, state.player_z + ahead)

func _apply_formation_motion(item: SpawnItem, slot_t: float, difficulty01: float, aggressive: bool) -> void:
	if item == null:
		return
	var amp_base: float = lerpf(0.16, 0.46, difficulty01)
	var freq_base: float = lerpf(1.1, 2.0, difficulty01)
	item.angle_amp = amp_base * lerpf(0.7, 1.2, absf(slot_t))
	item.angle_freq = freq_base + absf(slot_t) * 0.4
	item.angle_phase = slot_t * PI + rng.randf_range(-0.2, 0.2)
	item.z_follow_ratio = formation_follow_ratio
	item.z_drift = formation_forward_drift + (elite_extra_z_drift if aggressive else 0.0)
	if _is_stage_intro_active():
		item.z_follow_ratio = min(item.z_follow_ratio, clampf(stage_intro_follow_ratio, 0.5, 1.0))
	item.z_amp = lerpf(0.0, 0.55, difficulty01) if aggressive else lerpf(0.0, 0.25, difficulty01)
	item.z_freq = lerpf(1.2, 2.1, difficulty01)
	item.z_phase = rng.randf() * TAU

func _compute_stage_hostile_budget(stage_index: int, boss_stage: bool) -> int:
	var stage_n: int = max(stage_index, 1)
	var budget: int = stage_hostiles_base + (stage_n - 1) * stage_hostiles_growth
	if boss_stage:
		budget += boss_stage_hostile_bonus
	return clampi(budget, max(stage_hostiles_base, 1), max(stage_hostiles_cap, stage_hostiles_base))

func _is_stage_intro_active() -> bool:
	return state.run_time <= _stage_intro_until_run_time

func _wave_swarm_scale() -> float:
	var wave_index: int = max(state.wave_index, 1)
	if wave_index <= 1:
		if state.run_time < opening_single_enemy_seconds:
			return 0.2
		return 0.36
	var ramp_denominator: float = max(float(swarm_ramp_waves - 1), 1.0)
	var ramp_t: float = clampf(float(wave_index - 1) / ramp_denominator, 0.0, 1.0)
	return lerpf(0.36, 1.0, ramp_t)

func _scaled_formation_count(base_count: int, min_count: int = 1) -> int:
	var phase_scalar: float = 1.0
	match state.wave_phase:
		GameConstants.WavePhase.SURGE:
			phase_scalar = 1.15
		GameConstants.WavePhase.RELEASE:
			phase_scalar = 0.9
		GameConstants.WavePhase.POWERUP:
			phase_scalar = 0.82
	var scaled: int = int(round(float(base_count) * _wave_swarm_scale() * phase_scalar))
	return clampi(scaled, min_count, base_count)

func _active_hostile_count() -> int:
	var count: int = 0
	for item in commands:
		if not item.active:
			continue
		if item.kind == GameConstants.ItemKind.ORB or item.kind == GameConstants.ItemKind.BOMB:
			count += 1
	return count

func _is_opening_single_enemy_window() -> bool:
	return state.wave_index == 1 and state.run_time < opening_single_enemy_seconds

func _generate_intro_segment(z0: float, z1: float, anchor_angle: float, difficulty01: float) -> void:
	if _active_hostile_count() >= max(intro_max_active_hostiles, 1):
		return
	var anchor_z: float = _formation_anchor_z(z0, z1, difficulty01)
	var spawn_angle: float = GameConstants.normalize_angle(anchor_angle + rng.randf_range(-0.12, 0.12))
	var scout: SpawnItem = _add_enemy(spawn_angle, anchor_z)
	if scout == null:
		return
	scout.z_follow_ratio = formation_follow_ratio
	scout.z_drift = formation_forward_drift
	scout.angle_amp = 0.05
	scout.angle_freq = 1.0
	scout.angle_phase = rng.randf() * TAU
	scout.z_amp = 0.0
	scout.z_freq = 1.0
	scout.z_phase = 0.0

func _tpl_formation_line(z0: float, z1: float, difficulty01: float, anchor_angle: float) -> void:
	var base_count: int = 6 + int(round(difficulty01 * 2.0))
	var count: int = _scaled_formation_count(base_count, 1)
	var anchor_z: float = _formation_anchor_z(z0, z1, difficulty01)
	for i in range(count):
		var t: float = (float(i) / max(float(count - 1), 1.0)) * 2.0 - 1.0
		var enemy: SpawnItem = _add_enemy(anchor_angle + t * 0.34, anchor_z)
		_apply_formation_motion(enemy, t, difficulty01, false)

func _tpl_formation_arc(z0: float, z1: float, difficulty01: float, anchor_angle: float) -> void:
	var count: int = _scaled_formation_count(7, 2)
	var anchor_z: float = _formation_anchor_z(z0, z1, difficulty01)
	for i in range(count):
		var t: float = (float(i) / max(float(count - 1), 1.0)) * 2.0 - 1.0
		var angle: float = anchor_angle + t * 0.42
		var enemy: SpawnItem = _add_enemy(angle, anchor_z + absf(t) * 1.6)
		_apply_formation_motion(enemy, t, difficulty01, false)
	if count >= 4 and difficulty01 > 0.45 and rng.randf() < 0.4:
		var elite: SpawnItem = _add_elite(anchor_angle, anchor_z - 0.8)
		_apply_formation_motion(elite, 0.0, difficulty01, true)

func _tpl_formation_wing(z0: float, z1: float, difficulty01: float, anchor_angle: float) -> void:
	var pair_count: int = _scaled_formation_count(4, 1)
	var anchor_z: float = _formation_anchor_z(z0, z1, difficulty01)
	for i in range(pair_count):
		var t: float = float(i) / max(float(pair_count - 1), 1.0)
		var d: float = lerpf(0.1, 0.62, t)
		var left: SpawnItem = _add_enemy(anchor_angle - d, anchor_z + t * 1.2)
		var right: SpawnItem = _add_enemy(anchor_angle + d, anchor_z + t * 1.2)
		_apply_formation_motion(left, -d, difficulty01, false)
		_apply_formation_motion(right, d, difficulty01, false)
	if pair_count >= 2 and rng.randf() < lerpf(0.2, 0.65, difficulty01):
		var center_elite: SpawnItem = _add_elite(anchor_angle, anchor_z + 0.6)
		_apply_formation_motion(center_elite, 0.0, difficulty01, true)

func _tpl_formation_block(z0: float, z1: float, difficulty01: float, anchor_angle: float) -> void:
	var rows_base: int = 2 + int(round(difficulty01 * 1.5))
	var rows: int = _scaled_formation_count(rows_base, 1)
	var cols: int = _scaled_formation_count(4, 1)
	var anchor_z: float = _formation_anchor_z(z0, z1, difficulty01)
	for r in range(rows):
		for c in range(cols):
			var t: float = (float(c) / max(float(cols - 1), 1.0)) * 2.0 - 1.0
			var z_off: float = float(r) * 1.5
			var use_elite: bool = difficulty01 > 0.5 and r == 0 and (c == 0 or c == cols - 1) and rng.randf() < 0.45
			var item: SpawnItem = _add_elite(anchor_angle + t * 0.42, anchor_z + z_off) if use_elite else _add_enemy(anchor_angle + t * 0.42, anchor_z + z_off)
			_apply_formation_motion(item, t, difficulty01, use_elite)

func _tpl_formation_snake(z0: float, z1: float, difficulty01: float, anchor_angle: float) -> void:
	var base_count: int = 9 + int(round(difficulty01 * 3.0))
	var count: int = _scaled_formation_count(base_count, 2)
	var anchor_z: float = _formation_anchor_z(z0, z1, difficulty01)
	for i in range(count):
		var t: float = float(i) / max(float(count - 1), 1.0)
		var wave: float = sin(t * TAU * 1.4) * lerpf(0.22, 0.7, difficulty01)
		var item: SpawnItem = _add_enemy(anchor_angle + wave, anchor_z + t * 2.1)
		_apply_formation_motion(item, wave, difficulty01, false)
	if count >= 5 and difficulty01 > 0.6:
		var elite_i: int = int(floor(float(count) * 0.45))
		var elite_t: float = float(elite_i) / max(float(count - 1), 1.0)
		var elite_wave: float = sin(elite_t * TAU * 1.4) * lerpf(0.22, 0.7, difficulty01)
		var elite: SpawnItem = _add_elite(anchor_angle + elite_wave, anchor_z + elite_t * 2.1 + 0.4)
		_apply_formation_motion(elite, elite_wave, difficulty01, true)

func _tpl_pickup_lane(z0: float, z1: float, difficulty01: float, anchor_angle: float) -> void:
	var anchor_z: float = _formation_anchor_z(z0, z1, difficulty01)
	var shield: SpawnItem = _add_shield(anchor_angle, anchor_z + 1.1)
	if shield != null:
		shield.z_follow_ratio = formation_follow_ratio * 0.92
		shield.z_drift = formation_forward_drift * 0.75
		shield.angle_amp = 0.08
		shield.angle_freq = 1.2
		shield.angle_phase = rng.randf() * TAU
	var flank_gap: float = 0.26
	var flank_count: int = _scaled_formation_count(2, 0)
	if flank_count >= 1:
		var left_elite: SpawnItem = _add_elite(anchor_angle - flank_gap, anchor_z + 0.8)
		_apply_formation_motion(left_elite, -flank_gap, difficulty01, true)
	if flank_count >= 2:
		var right_elite: SpawnItem = _add_elite(anchor_angle + flank_gap, anchor_z + 0.8)
		_apply_formation_motion(right_elite, flank_gap, difficulty01, true)

func _tpl_boss_ring(z0: float, z1: float, difficulty01: float, anchor_angle: float) -> void:
	var count: int = 10
	var anchor_z: float = _formation_anchor_z(z0, z1, difficulty01) + 2.0
	var safe_angle: float = anchor_angle + rng.randf_range(-0.2, 0.2)
	for i in range(count):
		var t: float = float(i) / float(count)
		var a: float = t * TAU
		if absf(GameConstants.angle_diff(a, safe_angle)) <= 0.34:
			var enemy: SpawnItem = _add_enemy(a, anchor_z + 0.8)
			_apply_formation_motion(enemy, 0.0, difficulty01, false)
		else:
			var elite: SpawnItem = _add_elite(a, anchor_z)
			_apply_formation_motion(elite, 0.0, difficulty01, true)

func _on_powerup_collected(powerup_type: int) -> void:
	if powerup_type != GameConstants.PowerupType.SHIELD:
		return
	_shield_pity_seconds = 0.0

func maybe_spawn_pity_shield(z0: float, z1: float, anchor_angle: float) -> void:
	_sync_shield_stage_index()
	if not _can_spawn_stage_shield():
		return
	var pity_progress: float = clampf((_shield_pity_seconds - shield_pity_start_seconds) / max(shield_pity_full_seconds - shield_pity_start_seconds, 0.001), 0.0, 1.0)
	var shield_chance: float = lerpf(0.03, 0.6, pity_progress)
	if rng.randf() < shield_chance:
		var shield_z: float = max(rng.randf_range(z0 + 2.0, z1 - 2.0), state.player_z + base_formation_ahead_z * 0.92)
		var shield: SpawnItem = _add_shield(_random_angle_near(anchor_angle, 0.22), shield_z)
		if shield != null:
			shield.z_follow_ratio = formation_follow_ratio * 0.88
			shield.z_drift = formation_forward_drift * 0.7
			shield.angle_amp = 0.12
			shield.angle_freq = 1.1
			shield.angle_phase = rng.randf() * TAU
		_shield_pity_seconds = 0.0

func _sync_shield_stage_index() -> void:
	var stage_index: int = max(state.wave_index, 1)
	if stage_index == _shield_stage_index:
		return
	_shield_stage_index = stage_index
	_shields_spawned_in_stage = 0

func _stage_shield_cap() -> int:
	return max(max_shields_per_stage, 1)

func _stage_shield_min() -> int:
	return min(max(min_shields_per_stage, 1), _stage_shield_cap())

func _can_spawn_stage_shield() -> bool:
	return _shields_spawned_in_stage < _stage_shield_cap()

func _ensure_min_stage_shields(z0: float, z1: float, anchor_angle: float) -> void:
	_sync_shield_stage_index()
	var need: int = _stage_shield_min() - _shields_spawned_in_stage
	if need <= 0:
		return
	for i in range(need):
		if active_count() >= max_total_active_items:
			return
		if not _can_spawn_stage_shield():
			return
		var base_spread: float = 0.20 + 0.10 * float(i)
		var shield_angle: float = _random_angle_near(anchor_angle, base_spread)
		var shield_z: float = max(rng.randf_range(z0 + 2.0, z1 - 2.0), state.player_z + base_formation_ahead_z * (0.9 + 0.08 * float(i)))
		var shield: SpawnItem = _add_shield(shield_angle, shield_z)
		if shield == null:
			continue
		shield.z_follow_ratio = formation_follow_ratio * 0.9
		shield.z_drift = formation_forward_drift * 0.7
		shield.angle_amp = 0.1
		shield.angle_freq = 1.05 + 0.08 * float(i)
		shield.angle_phase = rng.randf() * TAU
		_shield_pity_seconds = 0.0
