extends Node
class_name GameConstants

# Tube
const R: float = 6.0

# Bend profile used by both gameplay placement and shader deformation.
const BEND_FREQ_A: float = 0.012
const BEND_FREQ_B: float = 0.027
const BEND_PHASE_B: float = 1.7
const BEND_AMP_A: float = 3.2
const BEND_AMP_B: float = 1.6

# World window
const GENERATE_AHEAD: float = 120.0
const CULL_BEHIND: float = 12.0

# Collision
const HIT_WINDOW_Z: float = 1.2
const HIT_WINDOW_ANGLE: float = 0.16

# Segment generation
const SEGMENT_LEN: float = 12.0

# Items
enum ItemKind { ORB, BOMB, POWERUP }
enum PowerupType { SHIELD }
enum WavePhase { BUILD, SURGE, RELEASE, POWERUP }

static func bend_offset_x(z: float, difficulty: float) -> float:
	return sin(z * BEND_FREQ_A) * BEND_AMP_A + sin(z * BEND_FREQ_B + BEND_PHASE_B) * BEND_AMP_B

static func bend_slope_x(z: float, difficulty: float) -> float:
	return cos(z * BEND_FREQ_A) * BEND_AMP_A * BEND_FREQ_A + cos(z * BEND_FREQ_B + BEND_PHASE_B) * BEND_AMP_B * BEND_FREQ_B

static func normalize_angle(angle: float) -> float:
	return wrapf(angle + PI, 0.0, TAU) - PI

static func angle_diff(a: float, b: float) -> float:
	return normalize_angle(a - b)

static func tube_center(z: float, difficulty: float) -> Vector3:
	return Vector3(bend_offset_x(z, difficulty), 0.0, z)

static func tube_tangent(z: float, difficulty: float) -> Vector3:
	return Vector3(bend_slope_x(z, difficulty), 0.0, 1.0).normalized()

static func tube_side_axis(z: float, difficulty: float) -> Vector3:
	var tangent: Vector3 = tube_tangent(z, difficulty)
	var side: Vector3 = Vector3.UP.cross(tangent)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	return side.normalized()

static func tube_up_axis(z: float, difficulty: float) -> Vector3:
	var tangent: Vector3 = tube_tangent(z, difficulty)
	var side: Vector3 = tube_side_axis(z, difficulty)
	return tangent.cross(side).normalized()

static func radial_from_angle(angle: float, z: float, difficulty: float) -> Vector3:
	var a: float = normalize_angle(angle)
	var side: Vector3 = tube_side_axis(z, difficulty)
	var up_axis: Vector3 = tube_up_axis(z, difficulty)
	return (sin(a) * side - cos(a) * up_axis).normalized()

static func angle_world_pos(angle: float, z: float, tube_radius: float, difficulty: float) -> Vector3:
	return tube_center(z, difficulty) + radial_from_angle(angle, z, difficulty) * tube_radius
