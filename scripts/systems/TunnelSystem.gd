extends Node
class_name TunnelSystem

@onready var state: RunState = get_parent().get_node("RunState")
@onready var game_root: Node = get_tree().current_scene
@onready var track_mm: MultiMeshInstance3D = game_root.get_node("World/Track")

@export var section_count: int = 260
@export var section_spacing: float = 10.0
@export var section_overlap: float = 0.0
@export var behind_distance: float = 240.0
@export var radial_segments: int = 40
@export var rings_per_section: int = 4

var _last_first_start_z: float = -INF

func _ready() -> void:
	_setup_track_multimesh()
	_refresh_sections(true)

func _process(delta: float) -> void:
	_refresh_sections(false)

func _setup_track_multimesh() -> void:
	var mm: MultiMesh = track_mm.multimesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	_enable_multimesh_custom_data(mm)
	mm.instance_count = section_count
	mm.visible_instance_count = -1

	var section_length: float = section_spacing + section_overlap
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = GameConstants.R
	cyl.bottom_radius = GameConstants.R
	cyl.height = section_length
	cyl.radial_segments = radial_segments
	cyl.rings = rings_per_section
	cyl.cap_top = false
	cyl.cap_bottom = false
	mm.mesh = cyl

	var mat := track_mm.material_override
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("section_world_span", section_length)

func _refresh_sections(force: bool) -> void:
	var first_start_z: float = floor((state.player_z - behind_distance) / section_spacing) * section_spacing
	if not force and is_equal_approx(first_start_z, _last_first_start_z):
		return
	_last_first_start_z = first_start_z

	var mm: MultiMesh = track_mm.multimesh
	var z_span: float = section_spacing + section_overlap
	for i in range(section_count):
		var z0: float = first_start_z + float(i) * section_spacing
		var z1: float = z0 + z_span
		var x0: float = GameConstants.bend_offset_x(z0, state.difficulty)
		var x1: float = GameConstants.bend_offset_x(z1, state.difficulty)
		var start_p: Vector3 = Vector3(x0, 0.0, z0)
		var end_p: Vector3 = Vector3(x1, 0.0, z1)
		var delta: Vector3 = end_p - start_p
		var dir: Vector3 = delta.normalized()
		var center_p: Vector3 = (start_p + end_p) * 0.5
		var basis: Basis = _basis_from_axis(dir)
		mm.set_instance_transform(i, Transform3D(basis, center_p))
		if mm.has_method("set_instance_custom_data"):
			mm.set_instance_custom_data(i, Color(z0, 0.0, 0.0, 0.0))

func _basis_from_axis(axis_y: Vector3) -> Basis:
	var y: Vector3 = axis_y.normalized()
	var ref: Vector3 = Vector3.UP
	if absf(y.dot(ref)) > 0.98:
		ref = Vector3.RIGHT
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = y.cross(x).normalized()
	return Basis(x, y, z)

func _enable_multimesh_custom_data(mm: MultiMesh) -> void:
	# Compatible across Godot 4 variants: 2 maps to float custom data format.
	if _has_property(mm, "custom_data_format"):
		mm.set("custom_data_format", 2)
		return
	if _has_property(mm, "use_custom_data"):
		mm.set("use_custom_data", true)

func _has_property(obj: Object, prop_name: String) -> bool:
	for prop in obj.get_property_list():
		if prop.has("name") and String(prop["name"]) == prop_name:
			return true
	return false
