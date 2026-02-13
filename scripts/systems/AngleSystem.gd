extends Node
class_name AngleSystem

@onready var state: RunState = get_parent().get_node("RunState")

@export var tube_radius: float = GameConstants.R
@export var player_surface_inset: float = 0.85
@export var orientation_lerp_speed: float = 12.0
@export var camera_distance: float = 7.0
@export var camera_height: float = 2.8
@export var camera_look_ahead: float = 11.0
@export var camera_position_lerp: float = 10.0
@export var camera_normal_bias: float = 0.9
@export var models_dir: String = "res://imported_models"
@export var auto_assign_imported_player_model: bool = true
@export var player_model_path: String = ""
@export var player_model_auto_index: int = 0
@export var player_target_height: float = 1.2
@export var player_model_y_offset: float = 0.0
@export var player_model_rotation_degrees: Vector3 = Vector3.ZERO

func _ready() -> void:
	_apply_player_model_visual()

func _process(delta: float) -> void:
	if not state.running:
		return
	state.player_angle = GameConstants.normalize_angle(state.player_angle + state.player_ang_vel * delta)

	var game: Node = get_tree().current_scene
	if game == null:
		return
	var rig: Node3D = game.get_node("World/PlayerRig") as Node3D
	if rig == null:
		return

	var player_radius: float = max(tube_radius - player_surface_inset, 0.1)
	var pos: Vector3 = pos_for_angle_z(state.player_angle, state.player_z, player_radius)
	rig.position = pos

	var outward: Vector3 = GameConstants.radial_from_angle(state.player_angle, state.player_z, state.difficulty)
	var inward: Vector3 = -outward
	var tangent: Vector3 = GameConstants.tube_tangent(state.player_z, state.difficulty)
	var around: Vector3 = (cos(state.player_angle) * GameConstants.tube_side_axis(state.player_z, state.difficulty) + sin(state.player_angle) * GameConstants.tube_up_axis(state.player_z, state.difficulty)).normalized()
	var motion: Vector3 = tangent * state.speed + around * state.player_ang_vel * player_radius
	var forward: Vector3 = (motion - inward * motion.dot(inward)).normalized()
	if forward.length_squared() < 0.0001:
		forward = tangent
	var right: Vector3 = forward.cross(inward).normalized()
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	var target_basis: Basis = Basis(right, inward, -forward).orthonormalized()
	var t: float = clampf(delta * orientation_lerp_speed, 0.0, 1.0)
	var from_q: Quaternion = rig.global_basis.get_rotation_quaternion()
	var to_q: Quaternion = target_basis.get_rotation_quaternion()
	rig.global_basis = Basis(from_q.slerp(to_q, t)).orthonormalized()

	_update_camera(delta, pos, forward, inward)

func pos_for_angle_z(angle: float, z: float, radius: float = GameConstants.R) -> Vector3:
	return GameConstants.angle_world_pos(angle, z, radius, state.difficulty)

func _apply_player_model_visual() -> void:
	var game: Node = get_tree().current_scene
	if game == null:
		return
	var player_body: MeshInstance3D = game.get_node_or_null("World/PlayerRig/PlayerBody") as MeshInstance3D
	if player_body == null:
		return

	var resolved_path: String = player_model_path
	if auto_assign_imported_player_model:
		resolved_path = ModelAssetUtils.resolve_model_path(models_dir, resolved_path, player_model_auto_index)
	var imported_mesh: Mesh = ModelAssetUtils.load_first_mesh(resolved_path)
	if imported_mesh == null:
		return

	player_body.mesh = imported_mesh
	player_body.material_override = null
	var aabb: AABB = imported_mesh.get_aabb()
	var height: float = max(aabb.size.y, 0.001)
	var uniform_scale: float = player_target_height / height
	player_body.scale = Vector3.ONE * uniform_scale
	player_body.position = Vector3(0.0, -aabb.position.y * uniform_scale + player_model_y_offset, 0.0)
	player_body.rotation_degrees = player_model_rotation_degrees

func _update_camera(delta: float, player_pos: Vector3, forward: Vector3, inward: Vector3) -> void:
	var game: Node = get_tree().current_scene
	if game == null:
		return
	var camera: Camera3D = game.get_node("World/PlayerRig/Camera3D") as Camera3D
	if camera == null:
		return
	var cam_target: Vector3 = player_pos + inward * camera_height - forward * camera_distance
	camera.global_position = camera.global_position.lerp(cam_target, clampf(delta * camera_position_lerp, 0.0, 1.0))
	var look_target: Vector3 = player_pos + forward * camera_look_ahead + inward * camera_normal_bias
	camera.look_at(look_target, inward)
