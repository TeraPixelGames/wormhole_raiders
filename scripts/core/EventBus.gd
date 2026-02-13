extends Node
class_name EventBus

signal run_started(seed: int)
signal run_ended(reason: String)
signal run_resumed()

signal speed_changed(speed: float)
signal difficulty_changed(difficulty: float)

signal orb_collected(value: int)
signal orb_missed()
signal powerup_collected(powerup_type: int)
signal shield_changed(active: bool)
signal bomb_hit(with_shield: bool)
signal combo_changed(combo: int, multiplier: int)
signal score_changed(score: int)
signal high_score_changed(high_score: int)
signal combo_milestone(combo: int)
signal near_miss(bonus_score: int)
signal wave_changed(wave_index: int, phase: int, boss_wave: bool)
signal slipstream_changed(active: bool, strength: float)
signal feedback_pulse(kind: String, angle: float, z: float, intensity: float)
signal laser_fired(by_player: bool)
signal explosion_requested(world_pos: Vector3, is_player: bool, intensity: float)
