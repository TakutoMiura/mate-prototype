class_name TestField
extends Node3D

signal squad_selection_requested(squad_number: int)
signal view_changed
signal tactical_pause_changed(is_paused: bool)

const MATE_UNIT_STATE_SCRIPT := preload("res://Scripts/Data/mate_unit_state.gd")
const SQUAD_COLORS := [Color("#D39B4C"), Color("#6A9AA9"), Color("#879C68")]
const FLOOR_EXTENT := 30.0
const SQUAD_SPACING := 12.0
const MATE_SPACING := 2.7
const CAMERA_FOCUS_DURATION := 0.9
const CAMERA_INITIAL_TARGET := Vector3(0, 1.35, 0)
const CAMERA_INITIAL_OFFSET := Vector3(0, 14.65, 29.0)
const CAMERA_FOCUS_DISTANCE := 14.0
const WAYPOINT_ARRIVAL_RADIUS := 0.5
const WAYPOINT_MARKER_RADIUS := 0.32
const WAYPOINT_MARKER_SEGMENTS := 16
const WAYPOINT_VISUAL_HEIGHT := 0.06
const JUMP_MARKER_RADIUS := 0.55
const JUMP_ARC_SEGMENTS := 16
const JUMP_TAKEOFF_HEIGHT_TOLERANCE := 0.1
const JUMP_ROUTE_ALIGNMENT_TOLERANCE := MATE_SPACING * 0.5

@export_group("Camera Controls")
@export_range(1.0, 40.0, 0.5) var pan_speed := 12.0
@export_range(8.0, 80.0, 1.0) var minimum_distance := 8.0
@export_range(12.0, 120.0, 1.0) var maximum_distance := 60.0
@export_range(1.01, 1.5, 0.01) var zoom_multiplier := 1.12
@export_range(0.001, 0.02, 0.001) var rotation_radians_per_pixel := 0.005
@export_range(5.0, 45.0, 1.0) var minimum_elevation_degrees := 15.0
@export_range(45.0, 85.0, 1.0) var maximum_elevation_degrees := 75.0

@export_group("Squad Movement")
@export_range(0.5, 10.0, 0.1) var squad_move_speed := 2.5
@export_range(15.0, 180.0, 1.0) var squad_turn_speed_degrees_per_second := 90.0

@export_group("Jump Movement")
@export_range(0.5, 6.0, 0.1) var maximum_jump_height := 2.9
@export_range(0.2, 3.0, 0.05) var jump_duration_seconds := 0.8
@export_range(0.5, 6.0, 0.1) var jump_arc_height := 2.9

@export_group("Walking Motion")
@export_range(0.8, 3.0, 0.1) var walking_stride_length := 3.0
@export_range(10.0, 40.0, 1.0) var leg_swing_degrees := 32.0
@export_range(0.0, 10.0, 0.5) var walking_forward_lean_degrees := 10.0
@export_range(1.0, 1.8, 0.05) var torso_counter_ratio := 1.2
@export_range(0.0, 0.8, 0.05) var arm_counter_swing_ratio := 0.45
@export_range(0.0, 0.16, 0.01) var foot_contact_pause_seconds := 0.06

@export_group("Standing Turn")
@export_range(1.0, 180.0, 1.0) var turn_max_yaw_speed_degrees := 90.0
@export_range(0.0, 30.0, 0.5) var turn_start_angle_degrees := 3.0
@export_range(0.0, 15.0, 0.5) var turn_finish_angle_degrees := 1.0
@export_range(0.01, 1.0, 0.01) var foot_position_start_threshold := 0.28
@export_range(0.0, 0.5, 0.01) var foot_position_finish_threshold := 0.12
@export_range(1.0, 90.0, 1.0) var foot_yaw_start_threshold_degrees := 40.0
@export_range(0.0, 45.0, 1.0) var foot_yaw_finish_threshold_degrees := 12.0
@export_range(0.0, 0.25, 0.01) var foot_slide_max_distance := 0.05
@export_range(0.1, 1.0, 0.05) var step_duration := 0.32
@export_range(0.05, 0.5, 0.01) var step_lift_height := 0.20
@export_range(0.0, 45.0, 1.0) var step_lookahead_angle_degrees := 0.0
@export_range(0.1, 5.0, 0.1) var step_target_correction_speed := 1.0
@export_range(0.1, 1.0, 0.05) var turn_speed_during_step_factor := 0.70
@export_range(0.0, 0.5, 0.01) var step_cooldown := 0.08
@export_range(0.0, 0.2, 0.01) var body_weight_shift_amount := 0.06
@export var show_turn_debug := false

@export var equipment_catalog: EquipmentCatalog

var _camera: Camera3D
var _camera_tween: Tween
var _camera_target := CAMERA_INITIAL_TARGET
var _camera_yaw := 0.0
var _camera_elevation := 0.0
var _camera_distance := 0.0
var _follow_squad_number := 0
var _selected_squad_number := 0
var _is_rotating := false
var _continuous_rendering := false
var _squad_centers: Array[Vector3] = []
var _squad_states: Array[Array] = []
var _squad_mates: Array[Array] = []
var _simulation_root: Node3D
var _squad_waypoints: Array[Array] = []
var _squad_headings: Array[float] = []
var _squad_turning_active: Array[bool] = []
var _squad_jump_sequences: Array[Dictionary] = []
var _squad_blocked: Array[bool] = []
var _squad_traversed_jump_connections: Array[Dictionary] = []
var _reserved_jump_landings: Array[Vector3] = []
var _waypoint_visual: MeshInstance3D
var _waypoint_visual_mesh: ImmediateMesh
var _waypoint_origin_visual: MeshInstance3D
var _waypoint_origin_mesh: ImmediateMesh
var _waypoint_visual_material: StandardMaterial3D
var _jump_visual: MeshInstance3D
var _jump_visual_mesh: ImmediateMesh
var _jump_route_material: StandardMaterial3D
var _jump_takeoff_material: StandardMaterial3D
var _jump_landing_material: StandardMaterial3D
var _prepared := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_camera_actions()
	prepare()


func prepare() -> void:
	if _prepared:
		return
	if equipment_catalog == null:
		equipment_catalog = load("res://Data/Samples/sample_equipment_catalog.tres") as EquipmentCatalog
	_build_environment()
	_build_ground()
	_build_camera()
	_build_sample_mates()
	_request_viewport_render()
	_prepared = true


func get_squad_states(squad_number: int) -> Array[Resource]:
	var result: Array[Resource] = []
	var index := squad_number - 1
	if index < 0 or index >= _squad_states.size():
		return result
	for state in _squad_states[index]:
		result.append(state as Resource)
	return result


func get_squad_mates(squad_number: int) -> Array[MatePreview]:
	var result: Array[MatePreview] = []
	var index := squad_number - 1
	if index < 0 or index >= _squad_mates.size():
		return result
	for mate in _squad_mates[index]:
		result.append(mate as MatePreview)
	return result


func get_camera() -> Camera3D:
	return _camera


func get_squad_point(squad_number: int) -> Vector3:
	var index := squad_number - 1
	if index < 0 or index >= _squad_mates.size():
		return Vector3.ZERO
	var mates: Array = _squad_mates[index]
	var positions: Array[Vector2] = []
	for mate in mates:
		if mate != null and mate.is_alive():
			positions.append(Vector2(mate.global_position.x, mate.global_position.z))
	if positions.is_empty():
		return _squad_centers[index] if index < _squad_centers.size() else Vector3.ZERO
	var center := _minimum_enclosing_circle_center(positions)
	return Vector3(center.x, 0.0, center.y)


func _get_squad_movement_point(squad_number: int) -> Vector3:
	var point := get_squad_point(squad_number)
	var index := squad_number - 1
	if index < 0 or index >= _squad_mates.size():
		return point
	var height_total := 0.0
	var living_count := 0
	for mate in _squad_mates[index]:
		if mate != null and mate.is_alive():
			height_total += mate.global_position.y
			living_count += 1
	if living_count > 0:
		point.y = height_total / float(living_count)
	return point


func get_squad_waypoints(squad_number: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var index := squad_number - 1
	if index < 0 or index >= _squad_waypoints.size():
		return result
	result.assign(_squad_waypoints[index])
	return result


func focus_squad(squad_number: int) -> void:
	if _squad_centers.is_empty():
		return
	_selected_squad_number = clampi(squad_number, 1, _squad_centers.size())
	_follow_squad_number = 0
	var index := _selected_squad_number - 1
	_animate_camera_to(_squad_focus_point(index), _camera_yaw, _camera_elevation, CAMERA_FOCUS_DISTANCE)
	_refresh_waypoint_visual()


func follow_squad(squad_number: int) -> void:
	if _squad_centers.is_empty():
		return
	var index := clampi(squad_number - 1, 0, _squad_centers.size() - 1)
	_selected_squad_number = index + 1
	_follow_squad_number = index + 1
	_animate_camera_to(_squad_focus_point(index), _camera_yaw, _camera_elevation, CAMERA_FOCUS_DISTANCE)


func _finish_camera_transition() -> void:
	_set_continuous_rendering(false)


func _process(delta: float) -> void:
	var squads_active := false
	if not get_tree().paused:
		squads_active = _process_squad_movement(delta)
	var pan_input := Vector2(
		float(Input.is_action_pressed("camera_pan_right")) - float(Input.is_action_pressed("camera_pan_left")),
		float(Input.is_action_pressed("camera_pan_backward")) - float(Input.is_action_pressed("camera_pan_forward"))
	)
	if pan_input.length_squared() > 0.0:
		_follow_squad_number = 0
		var forward := -_camera.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := _camera.global_basis.x
		right.y = 0.0
		right = right.normalized()
		var movement := (right * pan_input.x + forward * -pan_input.y).normalized()
		_camera_target += movement * pan_speed * delta
		_cancel_camera_tween()
		_apply_camera_pose()
		_set_continuous_rendering(true)
		return

	if _follow_squad_number > 0 and _follow_squad_number <= _squad_centers.size():
		var follow_target := _squad_focus_point(_follow_squad_number - 1)
		if not _camera_target.is_equal_approx(follow_target):
			_camera_target = follow_target
			_apply_camera_pose()
			_set_continuous_rendering(true)
			return

	if squads_active:
		_set_continuous_rendering(true)
		return

	if not _is_rotating and (_camera_tween == null or not _camera_tween.is_running()):
		_set_continuous_rendering(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _set_waypoint_from_screen(event.position, event.shift_pressed):
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_rotating = event.pressed
			if _is_rotating:
				_follow_squad_number = 0
				_cancel_camera_tween()
			_set_continuous_rendering(_is_rotating)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_follow_squad_number = 0
			_camera_distance = maxf(minimum_distance, _camera_distance / zoom_multiplier)
			_cancel_camera_tween()
			_apply_camera_pose()
			_set_continuous_rendering(false)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_follow_squad_number = 0
			_camera_distance = minf(maximum_distance, _camera_distance * zoom_multiplier)
			_cancel_camera_tween()
			_apply_camera_pose()
			_set_continuous_rendering(false)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _is_rotating:
		_follow_squad_number = 0
		_camera_yaw = wrapf(_camera_yaw - event.relative.x * rotation_radians_per_pixel, -PI, PI)
		_camera_elevation = clampf(
			_camera_elevation + event.relative.y * rotation_radians_per_pixel,
			deg_to_rad(minimum_elevation_degrees),
			deg_to_rad(maximum_elevation_degrees)
		)
		_apply_camera_pose()
		get_viewport().set_input_as_handled()


func _set_waypoint_from_screen(screen_position: Vector2, append: bool) -> bool:
	if _selected_squad_number <= 0 or _selected_squad_number > _squad_waypoints.size():
		return false
	var ray_origin := _camera.project_ray_origin(screen_position)
	var ray_direction := _camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000.0)
	query.collision_mask = 6
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var route: Array = _squad_waypoints[_selected_squad_number - 1]
	if not append:
		route.clear()
		_squad_traversed_jump_connections[_selected_squad_number - 1].clear()
		_set_squad_blocked(_selected_squad_number - 1, false)
	route.append(hit.position)
	_refresh_waypoint_visual()
	_set_continuous_rendering(true)
	return true


func _process_squad_movement(delta: float) -> bool:
	var any_active := false
	var any_positions_moved := false
	var route_changed := false
	for index in range(_squad_waypoints.size()):
		for mate in _squad_mates[index]:
			if mate != null:
				mate.set_walking(false)
				mate.set_standing_turn(false)
		var route: Array = _squad_waypoints[index]
		var mates: Array[MatePreview] = _squad_mates[index]
		if bool(_squad_jump_sequences[index].get("active", false)):
			_process_squad_jump(index, delta)
			any_active = true
			any_positions_moved = true
			continue
		if route.is_empty():
			continue
		var living_mates: Array[MatePreview] = []
		for mate in mates:
			if mate != null and mate.is_alive():
				living_mates.append(mate)
		if living_mates.is_empty():
			route.clear()
			_squad_traversed_jump_connections[index].clear()
			route_changed = true
			continue
		var movement_budget := squad_move_speed * delta
		while not route.is_empty():
			var point := get_squad_point(index + 1)
			var waypoint: Vector3 = route[0]
			var movement_point := _get_squad_movement_point(index + 1)
			var jump_route := _get_squad_jump_route(index, waypoint, movement_point)
			if bool(jump_route.get("blocked", false)):
				_set_squad_blocked(index, true)
				break
			var travel_target: Vector3 = jump_route["takeoff"] if not jump_route.is_empty() else waypoint
			if not jump_route.is_empty() and Vector2(point.x - travel_target.x, point.z - travel_target.z).length() <= WAYPOINT_ARRIVAL_RADIUS:
				var jump_started := _begin_squad_jump(index, mates, point, jump_route, waypoint)
				_set_squad_blocked(index, not jump_started)
				any_active = any_active or jump_started
				any_positions_moved = any_positions_moved or jump_started
				break
			var direction := Vector3(travel_target.x - point.x, 0.0, travel_target.z - point.z)
			var distance := direction.length()
			if distance <= WAYPOINT_ARRIVAL_RADIUS:
				route.pop_front()
				_remove_completed_jump_waypoint(index, waypoint)
				route_changed = true
				continue
			var target_heading := atan2(direction.x, direction.z)
			var heading: float = _squad_headings[index]
			var heading_difference := wrapf(target_heading - heading, -PI, PI)
			var turn_start_threshold := PI
			var turn_finish_threshold := PI
			for mate in living_mates:
				turn_start_threshold = minf(turn_start_threshold, deg_to_rad(mate.turn_start_angle_degrees))
				turn_finish_threshold = minf(turn_finish_threshold, deg_to_rad(mate.turn_finish_angle_degrees))
			var animate_turn := _squad_turning_active[index] or absf(heading_difference) >= turn_start_threshold
			if absf(heading_difference) > turn_finish_threshold:
				_squad_turning_active[index] = animate_turn
				var turn_speed := deg_to_rad(squad_turn_speed_degrees_per_second)
				for mate in living_mates:
					turn_speed = minf(
						turn_speed,
						deg_to_rad(mate.turn_max_yaw_speed_degrees) * mate.get_standing_turn_speed_factor()
					)
				var maximum_turn := turn_speed * delta
				var turn_delta := clampf(heading_difference, -maximum_turn, maximum_turn)
				heading = wrapf(heading + turn_delta, -PI, PI)
				_squad_headings[index] = heading
				for mate in living_mates:
					mate.set_turn_debug_values(target_heading, rad_to_deg(turn_delta / maxf(delta, 0.001)))
					mate.set_standing_turn(animate_turn)
					mate.rotation.y = heading
				any_active = true
				heading_difference = wrapf(target_heading - heading, -PI, PI)
				if absf(heading_difference) > turn_finish_threshold:
					break
			else:
				_squad_turning_active[index] = false
				for mate in living_mates:
					mate.set_turn_debug_values(target_heading, 0.0)
					mate.set_standing_turn(false)
				if not is_equal_approx(heading, target_heading):
					heading = target_heading
					_squad_headings[index] = heading
					for mate in living_mates:
						mate.rotation.y = heading
					any_active = true
			var turn_animation_active := false
			for mate in living_mates:
				if mate.is_standing_turn_animating():
					turn_animation_active = true
					break
			if turn_animation_active:
				any_active = true
				break
			var travel_distance := minf(movement_budget, distance - WAYPOINT_ARRIVAL_RADIUS)
			if travel_distance <= 0.0:
				break
			var displacement := direction / distance * travel_distance
			if not _can_walk_displacement(living_mates, displacement):
				_set_squad_blocked(index, true)
				break
			_set_squad_blocked(index, false)
			for mate in living_mates:
				mate.position += displacement
				mate.set_walking(true, squad_move_speed)
			any_active = true
			any_positions_moved = true
			if jump_route.is_empty() and travel_distance + WAYPOINT_ARRIVAL_RADIUS >= distance:
				route.pop_front()
				_remove_completed_jump_waypoint(index, waypoint)
				route_changed = true
			break
	for squad_mates in _squad_mates:
		for mate in squad_mates:
			if mate != null and (mate.is_walking_animating() or mate.is_standing_turn_animating()):
				any_active = true
				break
	if any_active:
		view_changed.emit()
	if route_changed or any_positions_moved:
		if route_changed:
			_refresh_waypoint_visual()
		if any_positions_moved:
			_refresh_waypoint_origin_visual()
	return any_active


func _can_walk_displacement(mates: Array[MatePreview], displacement: Vector3) -> bool:
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = 0.35
	body_shape.height = 2.7
	var space := get_world_3d().direct_space_state
	for mate in mates:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = body_shape
		query.transform = Transform3D(Basis.IDENTITY, mate.global_position + Vector3.UP * body_shape.height * 0.5)
		query.motion = displacement
		query.collision_mask = 1
		query.collide_with_areas = false
		var motion_fractions := space.cast_motion(query)
		if not motion_fractions.is_empty() and motion_fractions[0] < 1.0:
			return false
	return true


func _set_squad_blocked(index: int, is_blocked: bool) -> void:
	if index < 0 or index >= _squad_blocked.size() or _squad_blocked[index] == is_blocked:
		return
	_squad_blocked[index] = is_blocked
	if _selected_squad_number == index + 1:
		_refresh_waypoint_visual()


func _find_jump_route(waypoint: Vector3, current_position: Vector3, traversed_connections: Array) -> Dictionary:
	var best_route: Dictionary = {}
	var best_route_progress := INF
	for node in get_tree().get_nodes_in_group("jump_connections"):
		var connection: JumpConnection = node as JumpConnection
		if connection == null:
			continue
		for reverse in [false, true]:
			if traversed_connections.has(connection):
				continue
			var takeoff: Vector3 = connection.get_takeoff_position(reverse)
			var landing: Vector3 = connection.get_landing_position(reverse)
			if absf(current_position.y - takeoff.y) > JUMP_TAKEOFF_HEIGHT_TOLERANCE:
				continue
			if connection.contains_landing_point(waypoint, reverse):
				if not connection.can_traverse(reverse, maximum_jump_height):
					return {"blocked": true}
				return _make_jump_route(connection, reverse, takeoff, landing)
			if not connection.can_traverse(reverse, maximum_jump_height):
				continue
			var route_progress := _jump_route_progress(current_position, waypoint, takeoff, landing)
			if route_progress >= 0.0 and route_progress < best_route_progress:
				best_route_progress = route_progress
				best_route = _make_jump_route(connection, reverse, takeoff, landing)
	return best_route


func _make_jump_route(connection: JumpConnection, reverse: bool, takeoff: Vector3, landing: Vector3) -> Dictionary:
	return {
		"connection": connection,
		"reverse": reverse,
		"takeoff": takeoff,
		"landing": landing,
	}


func _jump_route_progress(
	current_position: Vector3,
	waypoint: Vector3,
	takeoff: Vector3,
	landing: Vector3
) -> float:
	var route_start := Vector2(current_position.x, current_position.z)
	var route_vector := Vector2(waypoint.x - current_position.x, waypoint.z - current_position.z)
	var route_length_squared := route_vector.length_squared()
	if route_length_squared <= 0.0001:
		return -1.0
	var takeoff_point := Vector2(takeoff.x, takeoff.z)
	var landing_point := Vector2(landing.x, landing.z)
	var takeoff_progress := (takeoff_point - route_start).dot(route_vector) / route_length_squared
	var landing_progress := (landing_point - route_start).dot(route_vector) / route_length_squared
	if takeoff_progress < 0.0 or landing_progress > 1.0 or landing_progress <= takeoff_progress:
		return -1.0
	var takeoff_projection := route_start + route_vector * takeoff_progress
	var landing_projection := route_start + route_vector * landing_progress
	var takeoff_distance := takeoff_point.distance_to(takeoff_projection)
	var landing_distance := landing_point.distance_to(landing_projection)
	if takeoff_distance > JUMP_ROUTE_ALIGNMENT_TOLERANCE or landing_distance > JUMP_ROUTE_ALIGNMENT_TOLERANCE:
		return -1.0
	var jump_vector := landing_point - takeoff_point
	if jump_vector.dot(route_vector) <= 0.0:
		return -1.0
	return takeoff_progress


func _get_squad_jump_route(index: int, waypoint: Vector3, current_position: Vector3) -> Dictionary:
	if index < 0 or index >= _squad_traversed_jump_connections.size():
		return {}
	var connections_for_waypoint: Array = _squad_traversed_jump_connections[index].get(waypoint, [])
	return _find_jump_route(waypoint, current_position, connections_for_waypoint)


func _get_squad_jump_routes(index: int, waypoint: Vector3, current_position: Vector3) -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	if index < 0 or index >= _squad_traversed_jump_connections.size():
		return routes
	var traversed_connections: Array = _squad_traversed_jump_connections[index].get(waypoint, [])
	var planned_connections: Array = traversed_connections.duplicate()
	var planning_position := current_position
	var maximum_route_jumps := get_tree().get_nodes_in_group("jump_connections").size()
	for _jump_index in range(maximum_route_jumps):
		var jump_route := _find_jump_route(waypoint, planning_position, planned_connections)
		if jump_route.is_empty() or bool(jump_route.get("blocked", false)):
			break
		routes.append(jump_route)
		planned_connections.append(jump_route["connection"])
		planning_position = jump_route["landing"]
	return routes


func _remove_completed_jump_waypoint(index: int, waypoint: Vector3) -> void:
	_squad_traversed_jump_connections[index].erase(waypoint)


func _begin_squad_jump(
	index: int,
	mates: Array[MatePreview],
	squad_point: Vector3,
	jump_route: Dictionary,
	waypoint: Vector3
) -> bool:
	var starts: Array[Vector3] = []
	var targets: Array[Vector3] = []
	var takeoff: Vector3 = jump_route["takeoff"]
	var landing: Vector3 = jump_route["landing"]
	for mate in mates:
		if absf(mate.global_position.y - takeoff.y) > JUMP_TAKEOFF_HEIGHT_TOLERANCE:
			return false
		starts.append(mate.global_position)
		var formation_offset := mate.global_position - squad_point
		targets.append(landing + Vector3(formation_offset.x, 0.0, formation_offset.z))
	if not _has_clear_landing_slots(targets) or not _has_clear_jump_paths(starts, targets):
		return false
	_squad_jump_sequences[index] = {
		"active": true,
		"member_index": 0,
		"elapsed": 0.0,
		"starts": starts,
		"targets": targets,
		"reserved_targets": targets.duplicate(),
		"waypoint": waypoint,
		"connection": jump_route["connection"],
	}
	_reserved_jump_landings.append_array(targets)
	return true


func _has_clear_landing_slots(targets: Array[Vector3]) -> bool:
	var space := get_world_3d().direct_space_state
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = 0.35
	body_shape.height = 2.7
	var reserved: Array[Vector3] = []
	for target in targets:
		for other_target in reserved:
			if Vector2(target.x - other_target.x, target.z - other_target.z).length() < body_shape.radius * 2.0:
				return false
		for other_target in _reserved_jump_landings:
			if absf(target.y - other_target.y) < body_shape.height and Vector2(target.x - other_target.x, target.z - other_target.z).length() < body_shape.radius * 2.0:
				return false
		for squad_mates in _squad_mates:
			for other_mate in squad_mates:
				if other_mate == null or not other_mate.is_alive():
					continue
				var occupant: Vector3 = other_mate.global_position
				if absf(target.y - occupant.y) < body_shape.height and Vector2(target.x - occupant.x, target.z - occupant.z).length() < body_shape.radius * 2.0:
					return false
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = body_shape
		query.transform = Transform3D(Basis.IDENTITY, target + Vector3.UP * body_shape.height * 0.5)
		query.collision_mask = 1
		query.collide_with_areas = false
		if not space.intersect_shape(query, 1).is_empty():
			return false
		reserved.append(target)
	return true


func _has_clear_jump_paths(starts: Array[Vector3], targets: Array[Vector3]) -> bool:
	var space := get_world_3d().direct_space_state
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = 0.35
	body_shape.height = 2.7
	for index in range(starts.size()):
		for sample_index in range(1, 10):
			var progress := float(sample_index) / 10.0
			var center := starts[index].lerp(targets[index], progress) + Vector3.UP * sin(PI * progress) * jump_arc_height + Vector3.UP * body_shape.height * 0.5
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = body_shape
			query.transform = Transform3D(Basis.IDENTITY, center)
			query.collision_mask = 1
			query.collide_with_areas = false
			if not space.intersect_shape(query, 1).is_empty():
				return false
	return true


func _process_squad_jump(index: int, delta: float) -> void:
	var sequence := _squad_jump_sequences[index]
	var mates: Array[MatePreview] = _squad_mates[index]
	var member_index := int(sequence["member_index"])
	while member_index < mates.size() and not mates[member_index].is_alive():
		member_index += 1
		sequence["elapsed"] = 0.0
	if member_index >= mates.size():
		var reserved_targets: Array[Vector3] = sequence.get("reserved_targets", [])
		for reserved_target in reserved_targets:
			var reservation_index := _reserved_jump_landings.find(reserved_target)
			if reservation_index >= 0:
				_reserved_jump_landings.remove_at(reservation_index)
		var traversed_waypoint: Vector3 = sequence["waypoint"]
		var traversed_connections: Array = _squad_traversed_jump_connections[index].get(traversed_waypoint, [])
		var traversed_connection: JumpConnection = sequence["connection"]
		if not traversed_connections.has(traversed_connection):
			traversed_connections.append(traversed_connection)
		_squad_traversed_jump_connections[index][traversed_waypoint] = traversed_connections
		sequence["active"] = false
		_squad_jump_sequences[index] = sequence
		if _selected_squad_number == index + 1:
			_refresh_waypoint_visual()
		return
	sequence["member_index"] = member_index
	var mate := mates[member_index]
	var starts: Array[Vector3] = sequence["starts"]
	var targets: Array[Vector3] = sequence["targets"]
	var elapsed := float(sequence["elapsed"]) + delta
	var progress := clampf(elapsed / jump_duration_seconds, 0.0, 1.0)
	mate.set_walking(false)
	mate.set_standing_turn(false)
	var start_position: Vector3 = starts[member_index]
	var target_position: Vector3 = targets[member_index]
	mate.global_position = start_position.lerp(target_position, progress) + Vector3.UP * sin(PI * progress) * jump_arc_height
	var jet_level := 0.0
	if progress < 0.18:
		jet_level = 1.0 - progress / 0.18
	elif absf(progress - 0.70) < 0.06 or absf(progress - 0.88) < 0.06:
		jet_level = 1.0
	mate.set_jump_jet_intensity(jet_level)
	if progress >= 1.0:
		mate.global_position = target_position
		mate.set_jump_jet_intensity(0.0)
		sequence["member_index"] = member_index + 1
		sequence["elapsed"] = 0.0
	else:
		sequence["elapsed"] = elapsed
	_squad_jump_sequences[index] = sequence


func _minimum_enclosing_circle_center(points: Array[Vector2]) -> Vector2:
	if points.size() == 1:
		return points[0]
	var candidates: Array[Dictionary] = []
	for point in points:
		candidates.append({"center": point, "radius_squared": 0.0})
	for first_index in range(points.size()):
		for second_index in range(first_index + 1, points.size()):
			var first := points[first_index]
			var second := points[second_index]
			var center := (first + second) * 0.5
			candidates.append({"center": center, "radius_squared": center.distance_squared_to(first)})
	if points.size() == 3:
		var a := points[0]
		var b := points[1]
		var c := points[2]
		var determinant := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
		if not is_zero_approx(determinant):
			var a_squared := a.length_squared()
			var b_squared := b.length_squared()
			var c_squared := c.length_squared()
			var circumcenter := Vector2(
				(a_squared * (b.y - c.y) + b_squared * (c.y - a.y) + c_squared * (a.y - b.y)) / determinant,
				(a_squared * (c.x - b.x) + b_squared * (a.x - c.x) + c_squared * (b.x - a.x)) / determinant
			)
			candidates.append({"center": circumcenter, "radius_squared": circumcenter.distance_squared_to(a)})
	var best_center := points[0]
	var best_radius_squared := INF
	for candidate in candidates:
		var center: Vector2 = candidate["center"]
		var radius_squared: float = candidate["radius_squared"]
		var contains_all := true
		for point in points:
			if center.distance_squared_to(point) > radius_squared + 0.0001:
				contains_all = false
				break
		if contains_all and radius_squared < best_radius_squared:
			best_center = center
			best_radius_squared = radius_squared
	return best_center


func _refresh_waypoint_visual() -> void:
	if _waypoint_visual_mesh == null:
		return
	_waypoint_visual_mesh.clear_surfaces()
	_refresh_jump_visual()
	if _selected_squad_number <= 0 or _selected_squad_number > _squad_waypoints.size():
		_refresh_waypoint_origin_visual()
		return
	var route: Array = _squad_waypoints[_selected_squad_number - 1]
	if route.is_empty():
		_refresh_waypoint_origin_visual()
		return
	var selected_index := _selected_squad_number - 1
	var movement_point := _get_squad_movement_point(_selected_squad_number)
	_waypoint_visual_material.albedo_color = Color("#EF5757") if _squad_blocked[selected_index] else SQUAD_COLORS[selected_index]
	_waypoint_visual_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _waypoint_visual_material)
	var previous_point: Vector3 = route[0] + Vector3(0, WAYPOINT_VISUAL_HEIGHT, 0)
	for index in range(route.size()):
		var waypoint: Vector3 = route[index]
		var marker_center: Vector3 = waypoint + Vector3(0, WAYPOINT_VISUAL_HEIGHT, 0)
		if index > 0:
			var jump_routes := _get_squad_jump_routes(selected_index, waypoint, movement_point)
			if not jump_routes.is_empty():
				_waypoint_visual_mesh.surface_add_vertex(previous_point)
				for jump_route in jump_routes:
					_waypoint_visual_mesh.surface_add_vertex(jump_route["takeoff"] + Vector3.UP * WAYPOINT_VISUAL_HEIGHT)
					_waypoint_visual_mesh.surface_add_vertex(jump_route["landing"] + Vector3.UP * WAYPOINT_VISUAL_HEIGHT)
				_waypoint_visual_mesh.surface_add_vertex(marker_center)
			else:
				_waypoint_visual_mesh.surface_add_vertex(previous_point)
				_waypoint_visual_mesh.surface_add_vertex(marker_center)
		for segment in range(WAYPOINT_MARKER_SEGMENTS):
			var first_angle := TAU * float(segment) / WAYPOINT_MARKER_SEGMENTS
			var second_angle := TAU * float(segment + 1) / WAYPOINT_MARKER_SEGMENTS
			var first_marker_point := marker_center + Vector3(
				cos(first_angle) * WAYPOINT_MARKER_RADIUS,
				0.0,
				sin(first_angle) * WAYPOINT_MARKER_RADIUS
			)
			var second_marker_point := marker_center + Vector3(
				cos(second_angle) * WAYPOINT_MARKER_RADIUS,
				0.0,
				sin(second_angle) * WAYPOINT_MARKER_RADIUS
			)
			_waypoint_visual_mesh.surface_add_vertex(first_marker_point)
			_waypoint_visual_mesh.surface_add_vertex(second_marker_point)
		previous_point = marker_center
		movement_point = waypoint
	_waypoint_visual_mesh.surface_end()
	_refresh_waypoint_origin_visual()


func _refresh_waypoint_origin_visual() -> void:
	if _waypoint_origin_mesh == null:
		return
	_waypoint_origin_mesh.clear_surfaces()
	if _selected_squad_number <= 0 or _selected_squad_number > _squad_waypoints.size():
		return
	var route: Array = _squad_waypoints[_selected_squad_number - 1]
	if route.is_empty():
		return
	var first_waypoint: Vector3 = route[0]
	var squad_index := _selected_squad_number - 1
	var jump_routes := _get_squad_jump_routes(
		squad_index,
		first_waypoint,
		_get_squad_movement_point(_selected_squad_number)
	)
	var route_origin: Vector3 = get_squad_point(_selected_squad_number) + Vector3.UP * WAYPOINT_VISUAL_HEIGHT
	_waypoint_origin_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _waypoint_visual_material)
	_waypoint_origin_mesh.surface_add_vertex(route_origin)
	if not jump_routes.is_empty():
		for jump_route in jump_routes:
			_waypoint_origin_mesh.surface_add_vertex(jump_route["takeoff"] + Vector3.UP * WAYPOINT_VISUAL_HEIGHT)
			_waypoint_origin_mesh.surface_add_vertex(jump_route["landing"] + Vector3.UP * WAYPOINT_VISUAL_HEIGHT)
		_waypoint_origin_mesh.surface_add_vertex(first_waypoint + Vector3.UP * WAYPOINT_VISUAL_HEIGHT)
	else:
		_waypoint_origin_mesh.surface_add_vertex(first_waypoint + Vector3.UP * WAYPOINT_VISUAL_HEIGHT)
	_waypoint_origin_mesh.surface_end()


func _refresh_jump_visual() -> void:
	if _jump_visual_mesh == null:
		return
	_jump_visual_mesh.clear_surfaces()
	if _selected_squad_number <= 0 or _selected_squad_number > _squad_waypoints.size():
		return
	var route: Array = _squad_waypoints[_selected_squad_number - 1]
	if route.is_empty():
		return
	var jump_routes: Array[Dictionary] = []
	var movement_point := _get_squad_movement_point(_selected_squad_number)
	for waypoint in route:
		jump_routes.append_array(_get_squad_jump_routes(
			_selected_squad_number - 1,
			waypoint,
			movement_point
		))
		movement_point = waypoint
	if jump_routes.is_empty():
		return
	_jump_visual_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _jump_route_material)
	for jump_route in jump_routes:
		var takeoff: Vector3 = jump_route["takeoff"]
		var landing: Vector3 = jump_route["landing"]
		var previous_point := takeoff + Vector3.UP * WAYPOINT_VISUAL_HEIGHT
		for segment in range(1, JUMP_ARC_SEGMENTS + 1):
			var progress := float(segment) / JUMP_ARC_SEGMENTS
			var point := takeoff.lerp(landing, progress) + Vector3.UP * (sin(PI * progress) * jump_arc_height + WAYPOINT_VISUAL_HEIGHT)
			_jump_visual_mesh.surface_add_vertex(previous_point)
			_jump_visual_mesh.surface_add_vertex(point)
			previous_point = point
	_jump_visual_mesh.surface_end()
	_draw_jump_markers(jump_routes, _jump_takeoff_material, true)
	_draw_jump_markers(jump_routes, _jump_landing_material, false)


func _draw_jump_markers(jump_routes: Array[Dictionary], material: StandardMaterial3D, is_takeoff: bool) -> void:
	_jump_visual_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for jump_route in jump_routes:
		var position: Vector3 = jump_route["takeoff"] if is_takeoff else jump_route["landing"]
		var marker_center := position + Vector3.UP * (WAYPOINT_VISUAL_HEIGHT * 1.5)
		if is_takeoff:
			for segment in range(JUMP_ARC_SEGMENTS):
				var first_angle := TAU * float(segment) / JUMP_ARC_SEGMENTS
				var second_angle := TAU * float(segment + 1) / JUMP_ARC_SEGMENTS
				_jump_visual_mesh.surface_add_vertex(marker_center + Vector3(cos(first_angle) * JUMP_MARKER_RADIUS, 0.0, sin(first_angle) * JUMP_MARKER_RADIUS))
				_jump_visual_mesh.surface_add_vertex(marker_center + Vector3(cos(second_angle) * JUMP_MARKER_RADIUS, 0.0, sin(second_angle) * JUMP_MARKER_RADIUS))
			for axis in [Vector3.RIGHT, Vector3.FORWARD]:
				_jump_visual_mesh.surface_add_vertex(marker_center - axis * JUMP_MARKER_RADIUS)
				_jump_visual_mesh.surface_add_vertex(marker_center + axis * JUMP_MARKER_RADIUS)
		else:
			var diamond_points: Array[Vector3] = [
				marker_center + Vector3(JUMP_MARKER_RADIUS, 0.0, 0.0),
				marker_center + Vector3(0.0, 0.0, JUMP_MARKER_RADIUS),
				marker_center + Vector3(-JUMP_MARKER_RADIUS, 0.0, 0.0),
				marker_center + Vector3(0.0, 0.0, -JUMP_MARKER_RADIUS),
			]
			for index in range(diamond_points.size()):
				_jump_visual_mesh.surface_add_vertex(diamond_points[index])
				_jump_visual_mesh.surface_add_vertex(diamond_points[(index + 1) % diamond_points.size()])
	_jump_visual_mesh.surface_end()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if Input.is_action_just_pressed("toggle_tactical_pause"):
		get_tree().paused = not get_tree().paused
		tactical_pause_changed.emit(get_tree().paused)
		_set_continuous_rendering(false)
		_request_viewport_render()
		get_viewport().set_input_as_handled()
	elif Input.is_action_just_pressed("select_squad_1"):
		squad_selection_requested.emit(1)
		get_viewport().set_input_as_handled()
	elif Input.is_action_just_pressed("select_squad_2"):
		squad_selection_requested.emit(2)
		get_viewport().set_input_as_handled()
	elif Input.is_action_just_pressed("select_squad_3"):
		squad_selection_requested.emit(3)
		get_viewport().set_input_as_handled()
	if Input.is_action_just_pressed("camera_focus_selected"):
		if _selected_squad_number > 0:
			follow_squad(_selected_squad_number)
			get_viewport().set_input_as_handled()
	elif Input.is_action_just_pressed("camera_reset"):
		_follow_squad_number = 0
		_animate_camera_to(
			CAMERA_INITIAL_TARGET,
			0.0,
			atan2(CAMERA_INITIAL_OFFSET.y, CAMERA_INITIAL_OFFSET.z),
			CAMERA_INITIAL_OFFSET.length()
		)
		get_viewport().set_input_as_handled()


func _animate_camera_to(target: Vector3, yaw: float, elevation: float, distance: float) -> void:
	if _camera == null:
		return
	_cancel_camera_tween()
	_set_continuous_rendering(true)
	var start_target := _camera_target
	var start_yaw := _camera_yaw
	var start_elevation := _camera_elevation
	var start_distance := _camera_distance
	_camera_tween = create_tween()
	_camera_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_method(
		func(progress: float) -> void:
			_camera_target = start_target.lerp(target, progress)
			_camera_yaw = lerp_angle(start_yaw, yaw, progress)
			_camera_elevation = lerpf(start_elevation, elevation, progress)
			_camera_distance = lerpf(start_distance, distance, progress)
			_apply_camera_pose(),
		0.0,
		1.0,
		CAMERA_FOCUS_DURATION
	)
	_camera_tween.finished.connect(_finish_camera_transition)


func _apply_camera_pose() -> void:
	if _camera == null:
		return
	var horizontal_distance := cos(_camera_elevation) * _camera_distance
	_camera.position = _camera_target + Vector3(
		sin(_camera_yaw) * horizontal_distance,
		sin(_camera_elevation) * _camera_distance,
		cos(_camera_yaw) * horizontal_distance
	)
	_camera.look_at(_camera_target, Vector3.UP)
	view_changed.emit()


func request_render() -> void:
	var viewport := get_viewport() as SubViewport
	if viewport != null and not _continuous_rendering:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _cancel_camera_tween() -> void:
	if _camera_tween != null and _camera_tween.is_running():
		_camera_tween.kill()
	_camera_tween = null


func _set_continuous_rendering(enabled: bool) -> void:
	if _continuous_rendering == enabled:
		return
	_continuous_rendering = enabled
	var viewport := get_viewport() as SubViewport
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_ONCE


func _squad_focus_point(index: int) -> Vector3:
	return get_squad_point(index + 1) + Vector3(0, 1.3, 0)


func _register_camera_actions() -> void:
	_register_key_action("camera_pan_forward", KEY_W)
	_register_key_action("camera_pan_backward", KEY_S)
	_register_key_action("camera_pan_left", KEY_A)
	_register_key_action("camera_pan_right", KEY_D)
	_register_key_action("camera_focus_selected", KEY_F)
	_register_key_action("camera_reset", KEY_HOME)
	_register_key_action("select_squad_1", KEY_1)
	_register_key_action("select_squad_2", KEY_2)
	_register_key_action("select_squad_3", KEY_3)
	_register_key_action("toggle_tactical_pause", KEY_SPACE)


func _register_key_action(action_name: StringName, key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == key:
			return
	var key_event := InputEventKey.new()
	key_event.physical_keycode = key
	InputMap.action_add_event(action_name, key_event)


func _request_viewport_render() -> void:
	var viewport := get_viewport() as SubViewport
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#172229")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#9AAEB5")
	environment.ambient_light_energy = 0.55
	world.environment = environment
	add_child(world)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48, -28, 0)
	key_light.light_color = Color("#FFF0D4")
	key_light.light_energy = 1.35
	key_light.shadow_enabled = true
	add_child(key_light)

	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(2, 5, 8)
	fill_light.light_color = Color("#8CB9C8")
	fill_light.light_energy = 1.2
	fill_light.omni_range = 24.0
	add_child(fill_light)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "TestFieldGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(FLOOR_EXTENT * 2.0, FLOOR_EXTENT * 2.0)
	ground.mesh = plane
	ground.position.y = -0.08
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#252F33")
	ground_material.roughness = 0.94
	ground.material_override = ground_material
	add_child(ground)
	var ground_body := StaticBody3D.new()
	ground_body.name = "TestFieldGroundCollision"
	ground_body.collision_layer = 2
	ground_body.collision_mask = 0
	var ground_shape := CollisionShape3D.new()
	var ground_plane := WorldBoundaryShape3D.new()
	ground_plane.plane = Plane(Vector3.UP, 0.0)
	ground_shape.shape = ground_plane
	ground_body.add_child(ground_shape)
	add_child(ground_body)

	var landing_pad := MeshInstance3D.new()
	landing_pad.name = "JumpLandingPlatform"
	var landing_mesh := BoxMesh.new()
	landing_mesh.size = Vector3(8.0, 0.4, 7.0)
	landing_pad.mesh = landing_mesh
	landing_pad.position = Vector3(0.0, 1.4, 16.0)
	landing_pad.material_override = ground_material
	add_child(landing_pad)
	var landing_body := StaticBody3D.new()
	landing_body.name = "JumpLandingPlatformCollision"
	landing_body.collision_layer = 2
	landing_body.collision_mask = 0
	landing_body.position = landing_pad.position
	var landing_shape := CollisionShape3D.new()
	var landing_box := BoxShape3D.new()
	landing_box.size = landing_mesh.size
	landing_shape.shape = landing_box
	landing_body.add_child(landing_shape)
	add_child(landing_body)

	var grid_mesh := ImmediateMesh.new()
	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.albedo_color = Color("#3B4A4F")
	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES, grid_material)
	for coordinate in range(-int(FLOOR_EXTENT), int(FLOOR_EXTENT) + 1, 2):
		grid_mesh.surface_add_vertex(Vector3(coordinate, 0, -FLOOR_EXTENT))
		grid_mesh.surface_add_vertex(Vector3(coordinate, 0, FLOOR_EXTENT))
		grid_mesh.surface_add_vertex(Vector3(-FLOOR_EXTENT, 0, coordinate))
		grid_mesh.surface_add_vertex(Vector3(FLOOR_EXTENT, 0, coordinate))
	grid_mesh.surface_end()
	var grid := MeshInstance3D.new()
	grid.name = "TestFieldGrid"
	grid.mesh = grid_mesh
	grid.position.y = -0.065
	add_child(grid)
	_waypoint_visual_mesh = ImmediateMesh.new()
	_waypoint_visual_material = StandardMaterial3D.new()
	_waypoint_visual_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_waypoint_visual_material.albedo_color = Color.WHITE
	_waypoint_visual = MeshInstance3D.new()
	_waypoint_visual.name = "SelectedSquadWaypointRoute"
	_waypoint_visual.mesh = _waypoint_visual_mesh
	_waypoint_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_waypoint_visual)
	_jump_visual_mesh = ImmediateMesh.new()
	_jump_route_material = StandardMaterial3D.new()
	_jump_route_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_jump_route_material.albedo_color = Color("#FFE082")
	_jump_takeoff_material = StandardMaterial3D.new()
	_jump_takeoff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_jump_takeoff_material.albedo_color = Color("#FF7043")
	_jump_landing_material = StandardMaterial3D.new()
	_jump_landing_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_jump_landing_material.albedo_color = Color("#4DD0E1")
	_jump_visual = MeshInstance3D.new()
	_jump_visual.name = "SelectedSquadJumpPlan"
	_jump_visual.mesh = _jump_visual_mesh
	_jump_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_jump_visual)
	_waypoint_origin_mesh = ImmediateMesh.new()
	_waypoint_origin_visual = MeshInstance3D.new()
	_waypoint_origin_visual.name = "SelectedSquadWaypointOrigin"
	_waypoint_origin_visual.mesh = _waypoint_origin_mesh
	_waypoint_origin_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_waypoint_origin_visual)

	for index in range(3):
		var pad := MeshInstance3D.new()
		pad.name = "SamplePosition%02d" % (index + 1)
		var pad_mesh := BoxMesh.new()
		pad_mesh.size = Vector3(10.2, 0.08, 4.6)
		pad.mesh = pad_mesh
		pad.position = Vector3((index - 1) * SQUAD_SPACING, 0.0, 0)
		var pad_material := StandardMaterial3D.new()
		pad_material.albedo_color = Color("#303B40")
		pad_material.roughness = 0.82
		pad.material_override = pad_material
		add_child(pad)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "TestFieldCamera"
	_camera.fov = 48.0
	_camera.current = true
	add_child(_camera)
	_camera_target = CAMERA_INITIAL_TARGET
	_camera_distance = CAMERA_INITIAL_OFFSET.length()
	_camera_elevation = atan2(CAMERA_INITIAL_OFFSET.y, CAMERA_INITIAL_OFFSET.z)
	_apply_camera_pose()


func _build_sample_mates() -> void:
	# Place moving actors, enemies, and projectiles here so tree pause freezes them.
	_simulation_root = Node3D.new()
	_simulation_root.name = "SimulationRoot"
	_simulation_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_simulation_root)
	if equipment_catalog == null:
		push_error("Test field has no EquipmentCatalog resource.")
		return
	if equipment_catalog.sample_loadouts.size() < 2:
		push_error("Test field requires cannon and standard sample loadouts.")
		return
	for squad_index in range(3):
		var squad_center := Vector3((squad_index - 1) * SQUAD_SPACING, 0, 0)
		_squad_centers.append(squad_center)
		var squad_waypoints: Array[Vector3] = []
		_squad_waypoints.append(squad_waypoints)
		_squad_headings.append(0.0)
		_squad_turning_active.append(false)
		_squad_jump_sequences.append({"active": false})
		_squad_blocked.append(false)
		_squad_traversed_jump_connections.append({})
		var squad_states: Array[Resource] = []
		var squad_mates: Array[MatePreview] = []
		for mate_index in range(3):
			var loadout := equipment_catalog.sample_loadouts[0 if squad_index == 0 else 1]
			var unit_state: Variant = MATE_UNIT_STATE_SCRIPT.new()
			unit_state.loadout = loadout
			if not unit_state.initialize_full(equipment_catalog):
				push_warning("Could not initialize sample MATE state for squad %d, unit %d." % [squad_index + 1, mate_index + 1])
				continue
			var mate := MatePreview.new()
			mate.name = "SQUAD-%02d-MATE-%02d" % [squad_index + 1, mate_index + 1]
			mate.configure(
				unit_state,
				equipment_catalog,
				SQUAD_COLORS[squad_index],
				MatePreview.ModelStyle.WAW_BLOCK_FRAME if squad_index == 1 else MatePreview.ModelStyle.SKELETON
			)
			mate.walking_stride_length = walking_stride_length
			mate.leg_swing_degrees = leg_swing_degrees
			mate.walking_forward_lean_degrees = walking_forward_lean_degrees
			mate.torso_counter_ratio = torso_counter_ratio
			mate.arm_counter_swing_ratio = arm_counter_swing_ratio
			mate.foot_contact_pause_seconds = foot_contact_pause_seconds
			mate.turn_max_yaw_speed_degrees = turn_max_yaw_speed_degrees
			mate.turn_start_angle_degrees = turn_start_angle_degrees
			mate.turn_finish_angle_degrees = turn_finish_angle_degrees
			mate.foot_position_start_threshold = foot_position_start_threshold
			mate.foot_position_finish_threshold = foot_position_finish_threshold
			mate.foot_yaw_start_threshold_degrees = foot_yaw_start_threshold_degrees
			mate.foot_yaw_finish_threshold_degrees = foot_yaw_finish_threshold_degrees
			mate.foot_slide_max_distance = foot_slide_max_distance
			mate.step_duration = step_duration
			mate.step_lift_height = step_lift_height
			mate.step_lookahead_angle_degrees = step_lookahead_angle_degrees
			mate.step_target_correction_speed = step_target_correction_speed
			mate.turn_speed_during_step_factor = turn_speed_during_step_factor
			mate.step_cooldown = step_cooldown
			mate.body_weight_shift_amount = body_weight_shift_amount
			mate.show_turn_debug = show_turn_debug
			mate.position = Vector3(
				squad_center.x + (mate_index - 1) * MATE_SPACING,
				0.04,
				0
			)
			squad_states.append(unit_state)
			squad_mates.append(mate)
			_simulation_root.add_child(mate)
		_squad_states.append(squad_states)
		_squad_mates.append(squad_mates)
