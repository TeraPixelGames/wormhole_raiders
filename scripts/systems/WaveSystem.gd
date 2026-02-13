extends Node
class_name WaveSystem

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")
@onready var gen: PatternGenerator = get_parent().get_node("PatternGenerator")

@export var build_duration: float = 10.0
@export var surge_duration: float = 8.0
@export var release_duration: float = 4.0
@export var powerup_duration: float = 3.0
@export var boss_every_n_waves: int = 5
@export var clear_to_next_stage_delay: float = 1.0

var _last_phase: int = -1
var _last_wave: int = -1
var _last_boss: bool = false
var _stage_elapsed: float = 0.0
var _clear_timer: float = -1.0

func _ready() -> void:
	bus.run_started.connect(_on_run_started)

func _on_run_started(_seed: int) -> void:
	_last_phase = -1
	_last_wave = -1
	_last_boss = false
	_stage_elapsed = 0.0
	_clear_timer = -1.0
	state.wave_index = 1
	state.wave_phase = GameConstants.WavePhase.BUILD
	state.boss_wave_active = false
	gen.start_stage(state.wave_index, false)
	_emit_wave_if_changed()

func _process(delta: float) -> void:
	if not state.running:
		return
	_stage_elapsed += delta
	state.wave_phase = _phase_for_elapsed(_stage_elapsed)
	_emit_wave_if_changed()
	_update_stage_clear(delta)

func _phase_for_elapsed(elapsed: float) -> int:
	if elapsed < build_duration:
		return GameConstants.WavePhase.BUILD
	if elapsed < build_duration + surge_duration:
		return GameConstants.WavePhase.SURGE
	if elapsed < build_duration + surge_duration + release_duration:
		return GameConstants.WavePhase.RELEASE
	return GameConstants.WavePhase.POWERUP

func _update_stage_clear(delta: float) -> void:
	var hostiles_remaining: int = gen.active_hostile_count()
	var stage_exhausted: bool = gen.stage_hostile_budget_exhausted()
	var stage_spawned: int = gen.stage_hostiles_spawned_count()
	if stage_exhausted and stage_spawned > 0 and hostiles_remaining <= 0:
		if _clear_timer < 0.0:
			_clear_timer = clear_to_next_stage_delay
			return
		_clear_timer -= delta
		if _clear_timer <= 0.0:
			_advance_stage()
		return
	_clear_timer = -1.0

func _advance_stage() -> void:
	state.wave_index += 1
	state.boss_wave_active = (state.wave_index % max(boss_every_n_waves, 1)) == 0
	state.wave_phase = GameConstants.WavePhase.BUILD
	_stage_elapsed = 0.0
	_clear_timer = -1.0
	gen.start_stage(state.wave_index, state.boss_wave_active)
	_emit_wave_if_changed()

func _emit_wave_if_changed() -> void:
	if state.wave_index == _last_wave and state.wave_phase == _last_phase and state.boss_wave_active == _last_boss:
		return
	_last_wave = state.wave_index
	_last_phase = state.wave_phase
	_last_boss = state.boss_wave_active
	bus.emit_signal("wave_changed", state.wave_index, state.wave_phase, state.boss_wave_active)
