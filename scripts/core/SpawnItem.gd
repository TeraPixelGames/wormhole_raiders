extends RefCounted
class_name SpawnItem

var kind: int
var id: int = 0
var angle: float
var z: float
var value: int = 1
var powerup_type: int = -1
var active: bool = true
var missed_checked: bool = false
var near_miss_checked: bool = false

# Motion params (deterministic, no physics).
var spawn_run_time: float = 0.0
var spawn_player_z: float = 0.0
var angle_amp: float = 0.0
var angle_freq: float = 0.0
var angle_phase: float = 0.0
var z_follow_ratio: float = 0.0
var z_drift: float = 0.0
var z_amp: float = 0.0
var z_freq: float = 0.0
var z_phase: float = 0.0

func _init(_kind: int, _angle: float, _z: float) -> void:
    kind = _kind
    angle = _angle
    z = _z

func is_dynamic_motion() -> bool:
    return absf(angle_amp) > 0.0001 or absf(z_follow_ratio) > 0.0001 or absf(z_drift) > 0.0001 or absf(z_amp) > 0.0001

func runtime_angle(run_time: float, _player_z: float) -> float:
    if absf(angle_amp) <= 0.0001:
        return _normalize_angle(angle)
    var t: float = max(run_time - spawn_run_time, 0.0)
    return _normalize_angle(angle + sin(t * angle_freq + angle_phase) * angle_amp)

func runtime_z(run_time: float, player_z: float) -> float:
    var t: float = max(run_time - spawn_run_time, 0.0)
    var z_now: float = z
    z_now += (player_z - spawn_player_z) * z_follow_ratio
    z_now += t * z_drift
    if absf(z_amp) > 0.0001:
        z_now += sin(t * z_freq + z_phase) * z_amp
    return z_now

func _normalize_angle(a: float) -> float:
    return wrapf(a + PI, 0.0, TAU) - PI
