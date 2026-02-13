extends Node
class_name InputSystem

@onready var state: RunState = get_parent().get_node("RunState")

var _touch_start: Vector2
var _active_touch_index: int = -1
var _fire_touch_index: int = -1
var _touch_axis: float = 0.0
var _touch_fire_pressed: bool = false
var _left_pressed: bool = false
var _right_pressed: bool = false

@export var max_ang_speed: float = 3.2
@export var ang_accel: float = 12.0
@export var ang_damping: float = 10.0
@export var touch_axis_sensitivity: float = 2.2
@export var input_deadzone: float = 0.04
@export var invert_touch_axis: bool = true
@export var invert_keyboard_axis: bool = true

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.echo:
			return
		if key_event.keycode == KEY_LEFT or key_event.keycode == KEY_A:
			_left_pressed = key_event.pressed
		elif key_event.keycode == KEY_RIGHT or key_event.keycode == KEY_D:
			_right_pressed = key_event.pressed

	if event is InputEventScreenTouch:
		var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
		if touch_event.pressed and _active_touch_index == -1:
			_active_touch_index = touch_event.index
			_touch_start = touch_event.position
			_touch_axis = 0.0
			_touch_fire_pressed = true
		elif touch_event.pressed and _fire_touch_index == -1:
			_fire_touch_index = touch_event.index
			_touch_fire_pressed = true
		elif not touch_event.pressed and touch_event.index == _active_touch_index:
			_active_touch_index = -1
			_touch_axis = 0.0
			_touch_fire_pressed = _fire_touch_index != -1
		elif not touch_event.pressed and touch_event.index == _fire_touch_index:
			_fire_touch_index = -1
			_touch_fire_pressed = _active_touch_index != -1

	if event is InputEventScreenDrag:
		var drag_event: InputEventScreenDrag = event as InputEventScreenDrag
		if drag_event.index != _active_touch_index:
			return
		var viewport_width: float = float(get_viewport().get_visible_rect().size.x)
		var norm_dx: float = (drag_event.position.x - _touch_start.x) / max(viewport_width * 0.35, 1.0)
		_touch_axis = clampf(norm_dx * touch_axis_sensitivity, -1.0, 1.0)
		if invert_touch_axis:
			_touch_axis *= -1.0

func _process(delta: float) -> void:
	if not state.running:
		state.player_ang_vel = move_toward(state.player_ang_vel, 0.0, ang_damping * delta)
		_touch_fire_pressed = false
		_active_touch_index = -1
		_fire_touch_index = -1
		_touch_axis = 0.0
		return

	var keyboard_axis: float = float(int(_right_pressed) - int(_left_pressed))
	if invert_keyboard_axis:
		keyboard_axis *= -1.0
	var drive_axis: float = _touch_axis if _active_touch_index != -1 else keyboard_axis
	if absf(drive_axis) < input_deadzone:
		drive_axis = 0.0

	var target_vel: float = drive_axis * max_ang_speed
	var accel_rate: float = ang_accel if drive_axis != 0.0 else ang_damping
	state.player_ang_vel = move_toward(state.player_ang_vel, target_vel, accel_rate * delta)
	state.player_ang_vel = clampf(state.player_ang_vel, -max_ang_speed, max_ang_speed)

func is_fire_pressed() -> bool:
	return _touch_fire_pressed
