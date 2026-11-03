class_name TestField
extends Node3D

signal squad_selection_requested(squad_number: int)
signal view_changed
signal tactical_pause_changed(is_paused: bool)

const MATE_UNIT_STATE_SCRIPT := preload("res://Scripts/Data/mate_unit_state.gd")
const NARROW_PASSAGE_SCRIPT := preload("res://Scripts/World/narrow_passage.gd")
const SQUAD_COLORS := [Color("#D39B4C"), Color("#6A9AA9"), Color("#879C68")]
const FLOOR_EXTENT := 30.0
const SQUAD_SPACING := 12.0
const MATE_SPACING := 2.7
const CAMERA_FOCUS_DURATION := 0.9
const CAMERA_INITIAL_TARGET := Vector3(0, 1.35, 0)
const CAMERA_INITIAL_OFFSET := Vector3(0, 14.65, 29.0)
const CAMERA_FOCUS_DISTANCE := 14.0
const WAYPOINT_ARRIVAL_RADIUS := 0.5
const WAYPOINT_ARRIVAL_EPSILON := 0.0001
const WAYPOINT_MARKER_RADIUS := 0.32
const WAYPOINT_MARKER_SEGMENTS := 16
const WAYPOINT_VISUAL_HEIGHT := 0.06
const JUMP_MARKER_RADIUS := 0.55
const JUMP_ARC_SEGMENTS := 16
const JUMP_TAKEOFF_HEIGHT_TOLERANCE := 0.1
const JUMP_ROUTE_ALIGNMENT_TOLERANCE := MATE_SPACING * 0.5
const WALK_BODY_RADIUS := 0.35
const WALK_BODY_HEIGHT := 2.7

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
@export_range(0.5, 4.0, 0.25) var local_avoidance_max_widths := 2.0

@export_group("Narrow Passage")
@export_range(0.0, 4.0, 0.05) var passage_correction_tolerance := 1.0

@export_group("Jump Movement")
@export_range(0.5, 6.0, 0.1) var maximum_jump_height := 2.9
@export_range(0.2, 3.0, 0.05) var jump_duration_seconds := 0.8
@export_range(0.5, 6.0, 0.1) var jump_arc_height := 2.9
@export_range(0.05, 0.4, 0.01) var jump_anticipation_seconds := 0.15
@export_range(0.05, 0.4, 0.01) var jump_landing_recovery_seconds := 0.15
@export_range(0.0, 15.0, 0.5) var jump_body_pitch_degrees := 8.0

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
var _squad_jump_preparations: Array[Dictionary] = []
var _squad_passages: Array = []
var _passage_owner := -1
var _passage_waiters: Array[int] = []
var _squad_blocked: Array[bool] = []
var _squad_traversed_jump_connections: Array[Dictionary] = []
var _reserved_jump_landings: Array[Vector3] = []
var _mate_lateral_offsets: Dictionary = {}
var _mate_yield_holds: Dictionary = {}
var _yielded_mates: Dictionary = {}
var _jump_visual_fit_cache: Dictionary = {}
var _waypoint_visual: MeshInstance3D
var _waypoint_visual_mesh: ImmediateMesh
var _waypoint_origin_visual: MeshInstance3D
var _waypoint_origin_mesh: ImmediateMesh
var _waypoint_visual_material: StandardMaterial3D
var _automatic_waypoint_mesh: ImmediateMesh
var _automatic_waypoint_material: StandardMaterial3D
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
	return _set_squad_waypoint(_selected_squad_number, hit.position, append)


func _set_squad_waypoint(squad_number: int, position: Vector3, append: bool) -> bool:
	var index := squad_number - 1
	if index < 0 or index >= _squad_waypoints.size():
		return false
	var route: Array = _squad_waypoints[index]
	if not append:
		route.clear()
		_squad_jump_preparations[index].clear()
		_squad_traversed_jump_connections[index].clear()
		if _squad_passages[index] != null:
			_squad_passages[index].replan_requested = true
		_set_squad_blocked(index, false)
	route.append(position)
	_refresh_waypoint_visual()
	_set_continuous_rendering(true)
	return true


func _process_squad_movement(delta: float) -> bool:
	var any_active := false
	var any_positions_moved := false
	var route_changed := false
	_update_passage_access()
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
		if not route.is_empty() and _squad_blocked[index] and _recover_blocked_yield_offsets(mates, delta):
			any_active = true
			any_positions_moved = true
			continue
		if route.is_empty():
			_squad_jump_preparations[index].clear()
			_squad_passages[index] = null
			_passage_waiters.erase(index)
			var recovered := _recover_squad_lateral_offsets(mates, delta)
			any_active = any_active or recovered
			any_positions_moved = any_positions_moved or recovered
			continue
		var living_mates: Array[MatePreview] = []
		for mate in mates:
			if mate != null and mate.is_alive():
				living_mates.append(mate)
		if living_mates.is_empty():
			route.clear()
			_squad_jump_preparations[index].clear()
			_squad_traversed_jump_connections[index].clear()
			route_changed = true
			continue
		var passage = _squad_passages[index]
		var passage_waypoint: Vector3 = route[0]
		if passage == null or passage.replan_requested or passage.waypoint != passage_waypoint:
			var member_inside := false
			var route_origin := get_squad_point(index + 1)
			for mate in living_mates:
				if absf(mate.position.x - NARROW_PASSAGE_SCRIPT.CENTER_X) < 0.5 and mate.position.z > NARROW_PASSAGE_SCRIPT.FRONT_Z and mate.position.z < NARROW_PASSAGE_SCRIPT.BACK_Z:
					member_inside = true
					if absf(route_origin.x - NARROW_PASSAGE_SCRIPT.CENTER_X) >= 0.5 or route_origin.z <= NARROW_PASSAGE_SCRIPT.FRONT_Z or route_origin.z >= NARROW_PASSAGE_SCRIPT.BACK_Z:
						route_origin = mate.position
					break
			var route_kind: int = NARROW_PASSAGE_SCRIPT.RouteKind.NORMAL
			var correction: Dictionary = {}
			var blocked_reason := "the specified route crosses a narrow passage wall"
			if absf(_get_squad_movement_point(index + 1).y - passage_waypoint.y) < 0.1:
				route_kind = NARROW_PASSAGE_SCRIPT.classify_route(route_origin, passage_waypoint)
				if route_kind == NARROW_PASSAGE_SCRIPT.RouteKind.BLOCKED:
					correction = _get_route_correction(route_origin, passage_waypoint)
					if not correction.is_empty():
						route_kind = NARROW_PASSAGE_SCRIPT.RouteKind.PASSAGE
			if route_kind == NARROW_PASSAGE_SCRIPT.RouteKind.BLOCKED:
				_squad_passages[index] = null
				_passage_waiters.erase(index)
				_set_squad_blocked(index, true, blocked_reason)
				continue
			if route_kind == NARROW_PASSAGE_SCRIPT.RouteKind.PASSAGE or member_inside:
				passage = NARROW_PASSAGE_SCRIPT.new(self, passage_waypoint, living_mates, passage)
				passage.route_correction = correction
			else:
				passage = null
			_squad_passages[index] = passage
		if passage != null:
			if not passage.failed_reason.is_empty():
				_passage_waiters.erase(index)
				_set_squad_blocked(index, true, passage.failed_reason)
				continue
			if not _claim_passage(index):
				var wait_position := Vector3(NARROW_PASSAGE_SCRIPT.CENTER_X + 4.5 + MATE_SPACING * float(index + 1), passage.entry.y, passage.entry.z - passage.direction * (MATE_SPACING + WALK_BODY_RADIUS))
				passage.wait_for_access(delta, wait_position)
				_set_squad_blocked(index, false)
				any_active = true
				any_positions_moved = true
				continue
			if passage.wait_point != null:
				passage.resume_from_wait()
				route_changed = true
			for mate in living_mates:
				_mate_lateral_offsets.erase(mate.get_instance_id())
				_yielded_mates.erase(mate.get_instance_id())
			var passage_complete: bool = passage.process(delta)
			if not passage.failed_reason.is_empty():
				_set_squad_blocked(index, true, passage.failed_reason)
			else:
				_set_squad_blocked(index, false)
			if passage_complete:
				_squad_passages[index] = null
				_squad_headings[index] = living_mates[0].rotation.y
				_squad_turning_active[index] = false
				if passage.stop_inside:
					route.pop_front()
					_remove_completed_jump_waypoint(index, passage_waypoint)
					route_changed = true
			any_active = true
			any_positions_moved = true
			continue
		_passage_waiters.erase(index)
		var movement_budget := squad_move_speed * delta
		while not route.is_empty():
			var point := get_squad_point(index + 1)
			var waypoint: Vector3 = route[0]
			var movement_point := _get_squad_movement_point(index + 1)
			var preparation: Dictionary = _squad_jump_preparations[index]
			var has_matching_preparation: bool = not preparation.is_empty() and preparation.get("waypoint") == waypoint
			var jump_route: Dictionary = preparation["jump_route"] if has_matching_preparation else _get_squad_jump_route(index, waypoint, movement_point)
			if bool(jump_route.get("blocked", false)):
				_squad_jump_preparations[index].clear()
				_set_squad_blocked(index, true, String(jump_route.get("blocked_reason", "jump route is not traversable")))
				break
			var travel_target: Vector3 = jump_route["takeoff"] if not jump_route.is_empty() else waypoint
			if not jump_route.is_empty() and not has_matching_preparation:
				var approach := _get_fitted_jump_approach(mates, point, travel_target)
				if not bool(approach.get("valid", false)):
					_set_squad_blocked(index, true, String(approach.get("reason", "jump approach has no support")))
					break
				travel_target = approach["position"]
			if jump_route.is_empty():
				_squad_jump_preparations[index].clear()
			if not jump_route.is_empty() and (
				has_matching_preparation
				or _has_reached_travel_target(point, travel_target)
			):
				var preparation_result := _prepare_squad_jump(index, mates, point, jump_route, waypoint, delta)
				var preparation_status := String(preparation_result.get("status", "blocked"))
				if preparation_status == "ready":
					var jump_start_failure := _begin_squad_jump(
						index,
						mates,
						jump_route,
						waypoint,
						preparation_result["targets"]
					)
					var jump_started := jump_start_failure.is_empty()
					if jump_started:
						_restore_preparation_offsets(mates, _squad_jump_preparations[index])
					_squad_jump_preparations[index].clear()
					_set_squad_blocked(index, not jump_started, jump_start_failure)
					any_active = any_active or jump_started
					any_positions_moved = any_positions_moved or jump_started
				elif preparation_status == "moving":
					_set_squad_blocked(index, false)
					any_active = true
					any_positions_moved = true
				elif preparation_status == "waiting":
					_set_squad_blocked(index, false)
					var waiting_preparation: Dictionary = _squad_jump_preparations[index]
					if not bool(waiting_preparation.get("wait_reason_logged", false)):
						push_warning("Squad %d waiting to clear jump landing slots: %s" % [
							index + 1,
						String(preparation_result.get("reason", "no safe sidestep available")),
						])
						waiting_preparation["wait_reason_logged"] = true
						_squad_jump_preparations[index] = waiting_preparation
					any_active = true
				else:
					_squad_jump_preparations[index].clear()
					_set_squad_blocked(index, true, String(preparation_result.get("reason", "jump preparation failed")))
				break
			var direction := Vector3(travel_target.x - point.x, 0.0, travel_target.z - point.z)
			var distance := direction.length()
			if _has_reached_travel_target(point, travel_target):
				route.pop_front()
				_remove_completed_jump_waypoint(index, waypoint)
				route_changed = true
				break
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
			var lateral := Vector3(-direction.z / distance, 0.0, direction.x / distance)
			var any_member_moved := false
			var any_yield_moved := false
			var blocking_reason := ""
			for mate in living_mates:
				if _yield_hold_active(mate.get_instance_id()):
					mate.set_walking(false)
					continue
				var move_result := _get_member_walk_displacement(mate, displacement, lateral)
				var member_displacement: Vector3 = move_result["displacement"]
				if member_displacement.is_zero_approx():
					any_yield_moved = _request_stationary_ally_yield(index, mate, mate.position + direction.normalized() * (NARROW_PASSAGE_SCRIPT.UNIT_CLEARANCE * 2.0), delta) or any_yield_moved
					mate.set_walking(false)
					if blocking_reason.is_empty():
						blocking_reason = String(move_result.get("blocked_reason", "movement helper returned a zero displacement"))
					continue
				mate.position += member_displacement
				mate.set_walking(true, squad_move_speed)
				any_member_moved = true
			if not any_member_moved:
				_set_squad_blocked(index, not any_yield_moved, "all squad members blocked while moving toward %s: %s" % [travel_target, blocking_reason])
				any_active = any_active or any_yield_moved
				any_positions_moved = any_positions_moved or any_yield_moved
				break
			_set_squad_blocked(index, false)
			any_active = true
			any_positions_moved = true
			if jump_route.is_empty() and _has_reached_travel_target(get_squad_point(index + 1), travel_target):
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


func _squad_inside_passage(index: int) -> bool:
	for mate in _squad_mates[index]:
		if mate != null and mate.is_alive() and absf(mate.position.x - NARROW_PASSAGE_SCRIPT.CENTER_X) < 0.5 and mate.position.z > NARROW_PASSAGE_SCRIPT.FRONT_Z and mate.position.z < NARROW_PASSAGE_SCRIPT.BACK_Z:
			return true
	return false


func _update_passage_access() -> void:
	for index in _passage_waiters.duplicate():
		if _squad_waypoints[index].is_empty() or _squad_passages[index] == null:
			_passage_waiters.erase(index)
	if _passage_owner >= 0 and not _squad_inside_passage(_passage_owner):
		var owner_passage = _squad_passages[_passage_owner]
		if owner_passage == null or not owner_passage.failed_reason.is_empty():
			_passage_owner = -1


func _claim_passage(index: int) -> bool:
	if _passage_owner == index:
		return true
	if not _passage_waiters.has(index):
		_passage_waiters.append(index)
	if _passage_owner >= 0:
		return false
	# A stationary squad inside still occupies the passage, even without a route.
	for other in range(_squad_mates.size()):
		if other != index and _squad_inside_passage(other):
			return false
	if _passage_waiters[0] != index and not _squad_inside_passage(index):
		return false
	_passage_owner = index
	_passage_waiters.erase(index)
	return true


func _has_reached_travel_target(point: Vector3, target: Vector3) -> bool:
	return Vector2(point.x - target.x, point.z - target.z).length() <= WAYPOINT_ARRIVAL_RADIUS + WAYPOINT_ARRIVAL_EPSILON


func _recover_squad_lateral_offsets(mates: Array[MatePreview], delta: float) -> bool:
	var any_moved := false
	for mate in mates:
		if mate == null or not mate.is_alive():
			continue
		var mate_id := mate.get_instance_id()
		if _yield_hold_active(mate_id):
			continue
		var current_offset: Vector3 = _mate_lateral_offsets.get(mate_id, Vector3.ZERO)
		if current_offset.is_zero_approx():
			_mate_lateral_offsets.erase(mate_id)
			_yielded_mates.erase(mate_id)
			continue
		var return_move := -current_offset.normalized() * minf(current_offset.length(), squad_move_speed * delta)
		if not _can_walk_displacement(mate, return_move):
			continue
		mate.position += return_move
		mate.set_walking(true, squad_move_speed)
		var remaining_offset := current_offset + return_move
		if remaining_offset.is_zero_approx():
			_mate_lateral_offsets.erase(mate_id)
			_yielded_mates.erase(mate_id)
		else:
			_mate_lateral_offsets[mate_id] = remaining_offset
		any_moved = true
	return any_moved


func _recover_blocked_yield_offsets(mates: Array[MatePreview], delta: float) -> bool:
	var yielded: Array[MatePreview] = []
	for mate in mates:
		if mate != null and _yielded_mates.has(mate.get_instance_id()):
			yielded.append(mate)
	return _recover_squad_lateral_offsets(yielded, delta)


func _yield_hold_active(mate_id: int) -> bool:
	if not _mate_yield_holds.has(mate_id):
		return false
	var hold: Dictionary = _mate_yield_holds[mate_id]
	var requester = hold["requester"]
	var index: int = hold["squad"]
	if not is_instance_valid(requester) or not requester.is_alive() or _squad_waypoints[index].is_empty():
		_mate_yield_holds.erase(mate_id)
		return false
	var passage = hold["passage"]
	if passage != null:
		if _squad_passages[index] != passage or passage.replan_requested or not passage.failed_reason.is_empty():
			_mate_yield_holds.erase(mate_id)
			return false
	else:
		var origin: Vector3 = hold["origin"]
		var direction: Vector3 = hold["direction"]
		if _squad_waypoints[index][0] != hold["waypoint"] or (requester.position - origin).dot(direction) >= NARROW_PASSAGE_SCRIPT.UNIT_CLEARANCE:
			_mate_yield_holds.erase(mate_id)
			return false
	return true


func _request_stationary_ally_yield(index: int, requester: MatePreview, target: Vector3, delta: float, passage = null) -> bool:
	var start := Vector2(requester.position.x, requester.position.z)
	var segment := Vector2(target.x - start.x, target.z - start.y)
	if segment.length_squared() < 0.0001:
		return false
	var direction := Vector3(segment.x, 0.0, segment.y).normalized()
	var lateral := Vector3(-direction.z, 0.0, direction.x)
	var maximum_offset := local_avoidance_max_widths * WALK_BODY_RADIUS * 2.0
	var passage_rect := Rect2(Vector2(NARROW_PASSAGE_SCRIPT.CENTER_X - 0.5, NARROW_PASSAGE_SCRIPT.FRONT_Z), Vector2(1.0, NARROW_PASSAGE_SCRIPT.BACK_Z - NARROW_PASSAGE_SCRIPT.FRONT_Z))
	var moved := false
	for other_index in range(_squad_mates.size()):
		if other_index == index or (not _squad_waypoints[other_index].is_empty() and not _squad_blocked[other_index]) or bool(_squad_jump_sequences[other_index].get("active", false)):
			continue
		var other_passage = _squad_passages[other_index]
		if other_passage != null and other_passage.failed_reason.is_empty():
			continue
		for ally in _squad_mates[other_index]:
			if ally == null or not ally.is_alive() or absf(ally.position.y - requester.position.y) >= WALK_BODY_HEIGHT:
				continue
			var ally_point := Vector2(ally.position.x, ally.position.z)
			if passage_rect.has_point(ally_point):
				continue
			var t := clampf((ally_point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
			var closest := start + segment * t
			if ally_point.distance_to(closest) >= NARROW_PASSAGE_SCRIPT.UNIT_CLEARANCE:
				continue
			var mate_id: int = ally.get_instance_id()
			if _yield_hold_active(mate_id):
				var existing: Dictionary = _mate_yield_holds[mate_id]
				if existing["requester"] != requester:
					continue
			var offset: Vector3 = _mate_lateral_offsets.get(mate_id, Vector3.ZERO)
			var sign_order: Array[float] = [1.0, -1.0]
			if Vector3(ally_point.x - closest.x, 0.0, ally_point.y - closest.y).dot(lateral) < 0.0:
				sign_order.reverse()
			for side in sign_order:
				var step := lateral * side * minf(squad_move_speed * delta, maximum_offset)
				if (offset + step).length() > maximum_offset + 0.001:
					continue
				var end := ally_point + Vector2(step.x, step.z)
				if NARROW_PASSAGE_SCRIPT._segment_intersects_rect(ally_point, end, passage_rect) or not _can_walk_displacement(ally, step):
					continue
				ally.position += step
				ally.set_walking(true, squad_move_speed)
				_mate_lateral_offsets[mate_id] = offset + step
				_yielded_mates[mate_id] = true
				if not _mate_yield_holds.has(mate_id):
					_mate_yield_holds[mate_id] = {"requester": requester, "squad": index, "passage": passage, "origin": ally.position - step, "direction": direction, "waypoint": _squad_waypoints[index][0]}
				moved = true
				break
	return moved


func _get_member_walk_displacement(mate: MatePreview, desired_displacement: Vector3, lateral: Vector3) -> Dictionary:
	var mate_id := mate.get_instance_id()
	var current_offset: Vector3 = _mate_lateral_offsets.get(mate_id, Vector3.ZERO)
	var desired_path_clear := _can_walk_displacement(mate, desired_displacement)
	var failed_attempts: Array[String] = []
	if desired_path_clear:
		if current_offset.is_zero_approx():
			return {"displacement": desired_displacement}
		var return_distance := minf(current_offset.length(), desired_displacement.length())
		var return_move := -current_offset.normalized() * return_distance
		var return_candidate := desired_displacement + return_move
		if not return_candidate.is_zero_approx() and _can_walk_displacement(mate, return_candidate):
			var remaining_offset := current_offset + return_move
			if remaining_offset.is_zero_approx():
				_mate_lateral_offsets.erase(mate_id)
			else:
				_mate_lateral_offsets[mate_id] = remaining_offset
			return {"displacement": return_candidate}
		return {"displacement": desired_displacement}
	failed_attempts.append("forward: %s" % _get_walk_blocking_reason(mate, desired_displacement))

	var max_offset_distance := local_avoidance_max_widths * WALK_BODY_RADIUS * 2.0
	if not current_offset.is_zero_approx():
		var clearance_return_move := -current_offset.normalized() * minf(current_offset.length(), desired_displacement.length())
		var clearance_return_candidate := desired_displacement + clearance_return_move
		if not clearance_return_candidate.is_zero_approx() and _can_walk_displacement(mate, clearance_return_candidate):
			var clearance_remaining_offset := current_offset + clearance_return_move
			if clearance_remaining_offset.is_zero_approx():
				_mate_lateral_offsets.erase(mate_id)
			else:
				_mate_lateral_offsets[mate_id] = clearance_remaining_offset
			return {"displacement": clearance_return_candidate}
	var side_order: Array[float] = [1.0, -1.0]
	if current_offset.dot(lateral) > 0.0:
		side_order = [-1.0, 1.0]
	for side_sign: float in side_order:
		var side_amount: float = minf(desired_displacement.length(), max_offset_distance)
		var side_move: Vector3 = lateral * side_sign * side_amount
		var combined_move: Vector3 = (desired_displacement + side_move).normalized() * desired_displacement.length()
		var combined_side_amount: float = combined_move.dot(lateral)
		var combined_offset: Vector3 = current_offset + lateral * combined_side_amount
		if combined_offset.length() <= max_offset_distance + 0.001 and _can_walk_displacement(mate, combined_move):
			_mate_lateral_offsets[mate_id] = combined_offset
			return {"displacement": combined_move}
		if combined_offset.length() <= max_offset_distance + 0.001:
			failed_attempts.append("forward + lateral %.0f: %s" % [side_sign, _get_walk_blocking_reason(mate, combined_move)])
		var next_offset: Vector3 = current_offset + side_move
		if next_offset.length() > max_offset_distance + 0.001:
			continue
		if _can_walk_displacement(mate, side_move):
			_mate_lateral_offsets[mate_id] = next_offset
			return {"displacement": side_move}
		failed_attempts.append("lateral %.0f: %s" % [side_sign, _get_walk_blocking_reason(mate, side_move)])
	return {
		"displacement": Vector3.ZERO,
		"blocked_reason": "no clear forward or lateral step within %.2f world units (%s)" % [
			max_offset_distance,
			"; ".join(failed_attempts),
		],
	}


func _can_walk_displacement(mate: MatePreview, displacement: Vector3) -> bool:
	return _get_walk_blocking_reason(mate, displacement).is_empty()


func _get_walk_blocking_reason(mate: MatePreview, displacement: Vector3) -> String:
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = WALK_BODY_RADIUS
	body_shape.height = WALK_BODY_HEIGHT
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body_shape
	query.transform = Transform3D(Basis.IDENTITY, mate.global_position + Vector3.UP * body_shape.height * 0.5)
	query.motion = displacement
	query.collision_mask = 1
	query.collide_with_areas = false
	var motion_fractions := space.cast_motion(query)
	if not motion_fractions.is_empty() and motion_fractions[0] < 1.0:
		var collision := space.get_rest_info(query)
		var collider: Object = collision.get("collider") if not collision.is_empty() else null
		var collider_name := String(collider.get("name")) if collider != null else "unknown"
		return "world collider %s" % collider_name
	var segment_start := Vector2(mate.global_position.x, mate.global_position.z)
	var segment := Vector2(displacement.x, displacement.z)
	var segment_length_squared := segment.length_squared()
	if segment_length_squared == 0.0:
		return ""
	for squad_mates in _squad_mates:
		for other_mate in squad_mates:
			if other_mate == null or other_mate == mate or not other_mate.is_alive():
				continue
			if absf(other_mate.global_position.y - mate.global_position.y) >= WALK_BODY_HEIGHT:
				continue
			var other_position := Vector2(other_mate.global_position.x, other_mate.global_position.z)
			var initial_separation := segment_start.distance_to(other_position)
			if initial_separation < WALK_BODY_RADIUS * 2.0:
				var moving_away := (other_position - segment_start).dot(segment) <= 0.0
				if moving_away and (segment_start + segment).distance_to(other_position) > initial_separation:
					continue
			var closest_progress := clampf((other_position - segment_start).dot(segment) / segment_length_squared, 0.0, 1.0)
			var closest_point := segment_start + segment * closest_progress
			var separation := closest_point.distance_to(other_position)
			if separation < WALK_BODY_RADIUS * 2.0:
				return "unit %s at %.2f units (minimum %.2f)" % [other_mate.name, separation, WALK_BODY_RADIUS * 2.0]
	return ""


func _set_squad_blocked(index: int, is_blocked: bool, reason: String = "") -> void:
	if index < 0 or index >= _squad_blocked.size() or _squad_blocked[index] == is_blocked:
		return
	_squad_blocked[index] = is_blocked
	if is_blocked and not reason.is_empty():
		push_warning("Squad %d movement blocked: %s" % [index + 1, reason])
	if _selected_squad_number == index + 1:
		_refresh_waypoint_visual()


func _find_jump_route(waypoint: Vector3, current_position: Vector3, traversed_connections: Array) -> Dictionary:
	var best_route: Dictionary = {}
	var rejected_target: Dictionary = {}
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
					if rejected_target.is_empty():
						var reason := ""
						if reverse and not connection.bidirectional:
							reason = "connection %s reverse direction is disabled" % connection.name
						elif is_zero_approx(landing.y - takeoff.y):
							reason = "connection %s has no height difference" % connection.name
						else:
							reason = "connection %s %s height delta %.2f exceeds maximum %.2f" % [
								connection.name,
								"reverse" if reverse else "forward",
								absf(landing.y - takeoff.y),
								maximum_jump_height,
							]
						rejected_target = {"blocked": true, "blocked_reason": reason}
					continue
				return _make_jump_route(connection, reverse, takeoff, landing)
			if not connection.can_traverse(reverse, maximum_jump_height):
				continue
			var route_progress := _jump_route_progress(current_position, waypoint, takeoff, landing)
			if route_progress >= 0.0 and route_progress < best_route_progress:
				best_route_progress = route_progress
				best_route = _make_jump_route(connection, reverse, takeoff, landing)
	return rejected_target if not rejected_target.is_empty() else best_route


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
		var visual_route := jump_route.duplicate()
		visual_route["visual_takeoff"] = _get_visual_jump_position(index, jump_route, true)
		visual_route["visual_landing"] = _get_visual_jump_position(index, jump_route, false)
		routes.append(visual_route)
		planned_connections.append(jump_route["connection"])
		planning_position = jump_route["landing"]
	return routes


func _get_visual_jump_position(index: int, jump_route: Dictionary, is_takeoff: bool) -> Vector3:
	var marker: Vector3 = jump_route["takeoff"] if is_takeoff else jump_route["landing"]
	var connection: JumpConnection = jump_route["connection"]
	var preparation: Dictionary = _squad_jump_preparations[index]
	if not is_takeoff and not preparation.is_empty() and preparation.get("connection") == connection and preparation["jump_route"].get("reverse") == jump_route.get("reverse"):
		var prepared_targets: Array[Vector3] = preparation["targets"]
		var points: Array[Vector2] = []
		for target in _get_living_jump_positions(_squad_mates[index], prepared_targets):
			points.append(Vector2(target.x, target.z))
		if not points.is_empty():
			var center := _minimum_enclosing_circle_center(points)
			return Vector3(center.x, marker.y, center.y)
	var key := "%d:%d:%s:%s" % [index, connection.get_instance_id(), str(jump_route.get("reverse", false)), str(is_takeoff)]
	var cached: Dictionary = _jump_visual_fit_cache.get(key, {})
	if bool(_squad_jump_sequences[index].get("active", false)) and not cached.is_empty():
		return cached["position"]
	var squad_point := get_squad_point(index + 1)
	var formation: Array[Vector2] = []
	for mate in _squad_mates[index]:
		if mate != null and mate.is_alive():
			var offset: Vector3 = mate.global_position - squad_point
			formation.append(Vector2(snappedf(offset.x, 0.01), snappedf(offset.z, 0.01)))
	if not cached.is_empty() and cached.get("formation") == formation:
		return cached["position"]
	var fitted := _get_fitted_jump_approach(_squad_mates[index], squad_point, marker)
	var position: Vector3 = fitted.get("position", marker)
	_jump_visual_fit_cache[key] = {"formation": formation, "position": position}
	return position


func _jump_visual_position(jump_route: Dictionary, is_takeoff: bool) -> Vector3:
	var marker_key := "takeoff" if is_takeoff else "landing"
	var visual_key := "visual_takeoff" if is_takeoff else "visual_landing"
	return jump_route.get(visual_key, jump_route[marker_key])


func _remove_completed_jump_waypoint(index: int, waypoint: Vector3) -> void:
	_squad_traversed_jump_connections[index].erase(waypoint)


func _prepare_squad_jump(
	index: int,
	mates: Array[MatePreview],
	squad_point: Vector3,
	jump_route: Dictionary,
	waypoint: Vector3,
	delta: float
) -> Dictionary:
	var connection: JumpConnection = jump_route["connection"]
	var preparation: Dictionary = _squad_jump_preparations[index]
	if preparation.is_empty() or preparation.get("connection") != connection or preparation.get("waypoint") != waypoint:
		var landing: Vector3 = jump_route["landing"]
		var targets: Array[Vector3] = []
		var initial_offsets: Dictionary = {}
		for mate in mates:
			var formation_offset: Vector3 = mate.global_position - squad_point
			targets.append(landing + Vector3(formation_offset.x, 0.0, formation_offset.z))
			initial_offsets[mate.get_instance_id()] = _mate_lateral_offsets.get(mate.get_instance_id(), Vector3.ZERO)
		var support_result := _fit_landing_formation(mates, targets, landing)
		if not bool(support_result.get("valid", false)):
			return {"status": "blocked", "reason": String(support_result.get("reason", "landing surface unavailable"))}
		targets = support_result["targets"]
		preparation = {
			"connection": connection,
			"jump_route": jump_route.duplicate(),
			"waypoint": waypoint,
			"targets": targets,
			"initial_offsets": initial_offsets,
		}
		_squad_jump_preparations[index] = preparation
	var fixed_targets: Array[Vector3] = preparation["targets"]
	var living_targets := _get_living_jump_positions(mates, fixed_targets)
	var landing_issue := _get_landing_slot_issue(living_targets, index)
	if not landing_issue.is_empty():
		return {"status": landing_issue["status"], "reason": "jump preparation: connection=%s %s" % [connection.name, landing_issue["reason"]]}
	var occupant_result := _find_squad_landing_occupant(index, living_targets)
	if not occupant_result.is_empty():
		var occupant: MatePreview = occupant_result["mate"]
		var target: Vector3 = occupant_result["target"]
		var sidestep_result := _move_landing_occupant_aside(occupant, target, jump_route["takeoff"], delta)
		if bool(sidestep_result.get("moved", false)):
			return {"status": "moving"}
		return {
			"status": "waiting",
			"reason": "unit %s cannot clear landing slot %s: %s" % [
				occupant.name,
				target,
				String(sidestep_result.get("reason", "no safe sidestep")),
			],
		}
	var starts: Array[Vector3] = []
	var takeoff: Vector3 = jump_route["takeoff"]
	for mate in mates:
		if mate.is_alive() and absf(mate.global_position.y - takeoff.y) > JUMP_TAKEOFF_HEIGHT_TOLERANCE:
			return {
				"status": "blocked",
				"reason": "jump preparation rejected: unit=%s takeoff_height=%.2f expected=%.2f" % [
					mate.name,
					mate.global_position.y,
					takeoff.y,
				],
			}
		starts.append(mate.global_position)
	var path_block_reason := _get_jump_path_block_reason(_get_living_jump_positions(mates, starts), living_targets)
	if not path_block_reason.is_empty():
		return {"status": "blocked", "reason": "jump preparation blocked: connection=%s %s" % [connection.name, path_block_reason]}
	return {"status": "ready", "targets": fixed_targets}


func _fit_landing_formation(mates: Array[MatePreview], targets: Array[Vector3], landing: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(landing + Vector3.UP * 0.2, landing - Vector3.UP * 0.2, 2)
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return {"valid": false, "reason": "no support beneath jump landing %s" % landing}
	var collider: CollisionObject3D = hit["collider"] as CollisionObject3D
	var shape_owner := collider.shape_find_owner(int(hit["shape"]))
	var shape_node := collider.shape_owner_get_owner(shape_owner) as CollisionShape3D
	if shape_node == null:
		return {"valid": false, "reason": "landing support has no collision shape"}
	var shift := Vector3.ZERO
	if shape_node.shape is BoxShape3D:
		var half_size: Vector3 = (shape_node.shape as BoxShape3D).size * 0.5
		var basis := shape_node.global_transform.basis
		if absf(basis.y.normalized().dot(Vector3.UP)) < 0.999:
			return {"valid": false, "reason": "sloped landing support is not supported"}
		var margin_x := (WALK_BODY_RADIUS + 0.01) / basis.x.length()
		var margin_z := (WALK_BODY_RADIUS + 0.01) / basis.z.length()
		var minimum := Vector2(-INF, -INF)
		var maximum := Vector2(INF, INF)
		for target in _get_living_jump_positions(mates, targets):
			var local_target := shape_node.to_local(target)
			minimum.x = maxf(minimum.x, -half_size.x + margin_x - local_target.x)
			minimum.y = maxf(minimum.y, -half_size.z + margin_z - local_target.z)
			maximum.x = minf(maximum.x, half_size.x - margin_x - local_target.x)
			maximum.y = minf(maximum.y, half_size.z - margin_z - local_target.z)
		if minimum.x > maximum.x or minimum.y > maximum.y:
			return {"valid": false, "reason": "formation does not fit on landing support"}
		var local_shift := Vector3(clampf(0.0, minimum.x, maximum.x), 0.0, clampf(0.0, minimum.y, maximum.y))
		shift = basis * local_shift
		shift.y = 0.0
	var adjusted: Array[Vector3] = []
	for target in targets:
		adjusted.append(target + shift)
	for target in _get_living_jump_positions(mates, adjusted):
		for offset in [Vector3.ZERO, Vector3.RIGHT * WALK_BODY_RADIUS, Vector3.LEFT * WALK_BODY_RADIUS, Vector3.FORWARD * WALK_BODY_RADIUS, Vector3.BACK * WALK_BODY_RADIUS]:
			var point: Vector3 = target + offset
			var support_ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.2, point - Vector3.UP * 0.2, 2)
			var support_hit := space.intersect_ray(support_ray)
			if support_hit.is_empty() or support_hit.get("collider") != collider:
				return {"valid": false, "reason": "landing position %s lacks support" % target}
	return {"valid": true, "targets": adjusted}


func _get_fitted_jump_approach(mates: Array[MatePreview], squad_point: Vector3, takeoff: Vector3) -> Dictionary:
	var positions: Array[Vector3] = []
	var first_living := -1
	for member_index in range(mates.size()):
		var offset: Vector3 = mates[member_index].global_position - squad_point
		positions.append(takeoff + Vector3(offset.x, 0.0, offset.z))
		if first_living < 0 and mates[member_index].is_alive():
			first_living = member_index
	var fitted := _fit_landing_formation(mates, positions, takeoff)
	if not bool(fitted.get("valid", false)) or first_living < 0:
		return fitted
	var adjusted: Array[Vector3] = fitted["targets"]
	return {"valid": true, "position": takeoff + adjusted[first_living] - positions[first_living]}


func _get_living_jump_positions(mates: Array[MatePreview], positions: Array[Vector3]) -> Array[Vector3]:
	var living_positions: Array[Vector3] = []
	for member_index in range(mates.size()):
		if mates[member_index] != null and mates[member_index].is_alive():
			living_positions.append(positions[member_index])
	return living_positions


func _restore_preparation_offsets(mates: Array[MatePreview], preparation: Dictionary) -> void:
	var initial_offsets: Dictionary = preparation.get("initial_offsets", {})
	for mate in mates:
		var mate_id := mate.get_instance_id()
		var initial_offset: Vector3 = initial_offsets.get(mate_id, Vector3.ZERO)
		if initial_offset.is_zero_approx():
			_mate_lateral_offsets.erase(mate_id)
		else:
			_mate_lateral_offsets[mate_id] = initial_offset


func _find_squad_landing_occupant(index: int, targets: Array[Vector3]) -> Dictionary:
	var body_radius := WALK_BODY_RADIUS
	var body_height := WALK_BODY_HEIGHT
	var mates: Array[MatePreview] = _squad_mates[index]
	for target in targets:
		for mate in mates:
			if mate == null or not mate.is_alive():
				continue
			var occupant: Vector3 = mate.global_position
			var vertical_overlap := absf(target.y - occupant.y) < body_height
			var horizontal_overlap := Vector2(target.x - occupant.x, target.z - occupant.z).length() < body_radius * 2.0
			if vertical_overlap and horizontal_overlap:
				return {"mate": mate, "target": target}
	return {}


func _move_landing_occupant_aside(
	mate: MatePreview,
	target: Vector3,
	takeoff: Vector3,
	delta: float
) -> Dictionary:
	var max_offset_distance := local_avoidance_max_widths * WALK_BODY_RADIUS * 2.0
	var mate_id := mate.get_instance_id()
	var current_offset: Vector3 = _mate_lateral_offsets.get(mate_id, Vector3.ZERO)
	var away := Vector3(mate.global_position.x - target.x, 0.0, mate.global_position.z - target.z)
	if away.is_zero_approx():
		away = Vector3(mate.global_position.x - takeoff.x, 0.0, mate.global_position.z - takeoff.z)
	if away.is_zero_approx():
		away = Vector3.FORWARD
	away = away.normalized()
	var side_direction := Vector3(-away.z, 0.0, away.x)
	var directions: Array[Vector3] = [
		away,
		(away + side_direction).normalized(),
		(away - side_direction).normalized(),
	]
	var current_target_distance := Vector2(mate.global_position.x - target.x, mate.global_position.z - target.z).length()
	var needed_clearance := maxf(
		WALK_BODY_RADIUS * 2.0 + 0.05 - Vector2(mate.global_position.x - target.x, mate.global_position.z - target.z).length(),
		0.05
	)
	var failed_attempts: Array[String] = []
	for direction: Vector3 in directions:
		var offset_projection := current_offset.dot(direction)
		var available_distance := 0.0
		if current_offset.length() <= max_offset_distance + 0.001:
			var discriminant := offset_projection * offset_projection + max_offset_distance * max_offset_distance - current_offset.length_squared()
			available_distance = maxf(0.0, -offset_projection + sqrt(maxf(0.0, discriminant)))
		elif offset_projection < 0.0:
			available_distance = -2.0 * offset_projection
		var step_distance := minf(minf(squad_move_speed * delta, available_distance), needed_clearance)
		if step_distance <= 0.000001:
			failed_attempts.append("%s: local avoidance limit %.2f" % [direction, max_offset_distance])
			continue
		var displacement: Vector3 = direction * step_distance
		var candidate_position: Vector3 = mate.global_position + displacement
		var candidate_distance := Vector2(candidate_position.x - target.x, candidate_position.z - target.z).length()
		if candidate_distance <= current_target_distance + 0.001:
			continue
		if not _can_walk_displacement(mate, displacement):
			failed_attempts.append("%s: %s" % [direction, _get_walk_blocking_reason(mate, displacement)])
			continue
		mate.position += displacement
		mate.set_walking(true, squad_move_speed)
		_mate_lateral_offsets[mate_id] = current_offset + displacement
		return {"moved": true}
	return {"moved": false, "reason": "; ".join(failed_attempts) if not failed_attempts.is_empty() else "candidate step would not increase clearance"}


func _begin_squad_jump(
	index: int,
	mates: Array[MatePreview],
	jump_route: Dictionary,
	waypoint: Vector3,
	landing_targets: Array[Vector3]
) -> String:
	var starts: Array[Vector3] = []
	var takeoff: Vector3 = jump_route["takeoff"]
	var connection: JumpConnection = jump_route["connection"]
	var direction := "reverse" if bool(jump_route["reverse"]) else "forward"
	for mate in mates:
		if mate.is_alive() and absf(mate.global_position.y - takeoff.y) > JUMP_TAKEOFF_HEIGHT_TOLERANCE:
			return "jump start rejected: connection=%s direction=%s unit=%s takeoff_height=%.2f expected=%.2f tolerance=%.2f" % [
				connection.name,
				direction,
				mate.name,
				mate.global_position.y,
				takeoff.y,
				JUMP_TAKEOFF_HEIGHT_TOLERANCE,
			]
		starts.append(mate.global_position)
	var targets: Array[Vector3] = landing_targets.duplicate()
	var living_targets := _get_living_jump_positions(mates, targets)
	var landing_issue := _get_landing_slot_issue(living_targets, index)
	if not landing_issue.is_empty():
		return "jump start rejected: connection=%s direction=%s %s" % [connection.name, direction, landing_issue["reason"]]
	var path_block_reason := _get_jump_path_block_reason(_get_living_jump_positions(mates, starts), living_targets)
	if not path_block_reason.is_empty():
		return "jump start rejected: connection=%s direction=%s %s" % [connection.name, direction, path_block_reason]
	var pending_members: Array[int] = []
	for member_index in range(mates.size()):
		if mates[member_index].is_alive():
			pending_members.append(member_index)
	var landing: Vector3 = jump_route["landing"]
	var travel_direction := Vector3(landing.x - takeoff.x, 0.0, landing.z - takeoff.z).normalized()
	pending_members.sort_custom(func(first: int, second: int) -> bool:
		return starts[first].dot(travel_direction) > starts[second].dot(travel_direction)
	)
	_squad_jump_sequences[index] = {
		"active": true,
		"member_index": -1,
		"pending_members": pending_members,
		"phase": "waiting",
		"elapsed": 0.0,
		"starts": starts,
		"targets": targets,
		"reserved_targets": living_targets.duplicate(),
		"waypoint": waypoint,
		"connection": jump_route["connection"],
	}
	_reserved_jump_landings.append_array(living_targets)
	return ""


func _get_landing_slot_issue(targets: Array[Vector3], ignored_squad_index: int = -1) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = WALK_BODY_RADIUS
	body_shape.height = WALK_BODY_HEIGHT
	var reserved: Array[Vector3] = []
	for target in targets:
		for other_target in reserved:
			if Vector2(target.x - other_target.x, target.z - other_target.z).length() < body_shape.radius * 2.0:
				return {"status": "blocked", "reason": "landing slots overlap within this squad at %s and %s" % [target, other_target]}
		for other_target in _reserved_jump_landings:
			if absf(target.y - other_target.y) < body_shape.height and Vector2(target.x - other_target.x, target.z - other_target.z).length() < body_shape.radius * 2.0:
				return {"status": "waiting", "reason": "landing slot %s overlaps a reserved landing at %s" % [target, other_target]}
		for squad_index in range(_squad_mates.size()):
			if squad_index == ignored_squad_index:
				continue
			var squad_mates: Array = _squad_mates[squad_index]
			for other_mate in squad_mates:
				if other_mate == null or not other_mate.is_alive():
					continue
				var occupant: Vector3 = other_mate.global_position
				if absf(target.y - occupant.y) < body_shape.height and Vector2(target.x - occupant.x, target.z - occupant.z).length() < body_shape.radius * 2.0:
					return {"status": "waiting", "reason": "landing slot %s occupied by squad %d unit %s at %s" % [target, squad_index + 1, other_mate.name, occupant]}
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = body_shape
		query.transform = Transform3D(Basis.IDENTITY, target + Vector3.UP * body_shape.height * 0.5)
		query.collision_mask = 1
		query.collide_with_areas = false
		var collisions := space.intersect_shape(query, 1)
		if not collisions.is_empty():
			var collider: Object = collisions[0].get("collider")
			var collider_name := String(collider.get("name")) if collider != null else "unknown"
			return {"status": "blocked", "reason": "landing slot %s intersects collider %s" % [target, collider_name]}
		reserved.append(target)
	return {}


func _get_jump_path_block_reason(starts: Array[Vector3], targets: Array[Vector3]) -> String:
	var space := get_world_3d().direct_space_state
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = WALK_BODY_RADIUS
	body_shape.height = WALK_BODY_HEIGHT
	for index in range(starts.size()):
		for sample_index in range(1, 10):
			var progress := float(sample_index) / 10.0
			var center := starts[index].lerp(targets[index], progress) + Vector3.UP * _get_jump_arc_offset(progress) + Vector3.UP * body_shape.height * 0.5
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = body_shape
			query.transform = Transform3D(Basis.IDENTITY, center)
			query.collision_mask = 1
			query.collide_with_areas = false
			var collisions := space.intersect_shape(query, 1)
			if not collisions.is_empty():
				var collider: Object = collisions[0].get("collider")
				var collider_name := String(collider.get("name")) if collider != null else "unknown"
				return "jump path for unit %d collides at progress %.2f with %s near %s" % [
					index + 1,
					progress,
					collider_name,
					center,
				]
	return ""


func _get_jump_arc_offset(progress: float) -> float:
	var normalized_progress := clampf(progress, 0.0, 1.0)
	return 4.0 * jump_arc_height * normalized_progress * (1.0 - normalized_progress)


func _get_jump_unit_block_reason(mate: MatePreview, start: Vector3, target: Vector3, simulated_positions: Dictionary = {}) -> String:
	var radius_sum := WALK_BODY_RADIUS * 2.0
	var whole_segment := Vector2(target.x - start.x, target.z - start.z)
	var whole_length_squared := whole_segment.length_squared()
	for squad_mates in _squad_mates:
		for other_mate in squad_mates:
			if other_mate == null or other_mate == mate or not other_mate.is_alive():
				continue
			var other: Vector3 = simulated_positions.get(other_mate.get_instance_id(), other_mate.global_position)
			var whole_relative := Vector2(other.x - start.x, other.z - start.z)
			var whole_fraction := 0.0
			if whole_length_squared > 0.0:
				whole_fraction = clampf(whole_relative.dot(whole_segment) / whole_length_squared, 0.0, 1.0)
			if (whole_relative - whole_segment * whole_fraction).length_squared() >= radius_sum * radius_sum:
				continue
			for segment_index in range(32):
				var from_progress := float(segment_index) / 32.0
				var to_progress := float(segment_index + 1) / 32.0
				var from_point: Vector3 = start.lerp(target, from_progress)
				var to_point: Vector3 = start.lerp(target, to_progress)
				var segment := Vector2(to_point.x - from_point.x, to_point.z - from_point.z)
				var relative := Vector2(other.x - from_point.x, other.z - from_point.z)
				var fraction := 0.0
				if segment.length_squared() > 0.0:
					fraction = clampf(relative.dot(segment) / segment.length_squared(), 0.0, 1.0)
				var progress := lerpf(from_progress, to_progress, fraction)
				var foot: Vector3 = start.lerp(target, progress) + Vector3.UP * _get_jump_arc_offset(progress)
				var horizontal_distance := Vector2(foot.x - other.x, foot.z - other.z).length()
				var vertical_distance := maxf(0.0, maxf((foot.y + WALK_BODY_RADIUS) - (other.y + WALK_BODY_HEIGHT - WALK_BODY_RADIUS), (other.y + WALK_BODY_RADIUS) - (foot.y + WALK_BODY_HEIGHT - WALK_BODY_RADIUS)))
				if horizontal_distance * horizontal_distance + vertical_distance * vertical_distance < radius_sum * radius_sum:
					return "unit %s blocks flight of %s near %.2f" % [other_mate.name, mate.name, progress]
	return ""


func _find_safe_jump_order(mates: Array[MatePreview], targets: Array[Vector3], pending: Array[int], simulated_positions: Dictionary = {}) -> Array[int]:
	for candidate_index in pending:
		var candidate: MatePreview = mates[candidate_index]
		var start: Vector3 = simulated_positions.get(candidate.get_instance_id(), candidate.global_position)
		if not _get_jump_unit_block_reason(candidate, start, targets[candidate_index], simulated_positions).is_empty():
			continue
		var remaining: Array[int] = pending.duplicate()
		remaining.erase(candidate_index)
		if remaining.is_empty():
			return [candidate_index]
		var next_positions := simulated_positions.duplicate()
		next_positions[candidate.get_instance_id()] = targets[candidate_index]
		var following := _find_safe_jump_order(mates, targets, remaining, next_positions)
		if not following.is_empty():
			following.push_front(candidate_index)
			return following
	return []


func _process_squad_jump(index: int, delta: float) -> void:
	var sequence := _squad_jump_sequences[index]
	var mates: Array[MatePreview] = _squad_mates[index]
	var pending_members: Array[int] = sequence["pending_members"]
	for pending_index in pending_members.duplicate():
		if not mates[pending_index].is_alive():
			pending_members.erase(pending_index)
	if pending_members.is_empty():
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
	var targets: Array[Vector3] = sequence["targets"]
	var starts: Array[Vector3] = sequence["starts"]
	var member_index := int(sequence["member_index"])
	if member_index < 0 or not pending_members.has(member_index):
		member_index = -1
		var waiting_reason := ""
		var safe_order := _find_safe_jump_order(mates, targets, pending_members)
		if not safe_order.is_empty():
			member_index = safe_order[0]
			starts[member_index] = mates[member_index].global_position
		else:
			var first_candidate: MatePreview = mates[pending_members[0]]
			waiting_reason = _get_jump_unit_block_reason(first_candidate, first_candidate.global_position, targets[pending_members[0]])
			if waiting_reason.is_empty():
				waiting_reason = "no collision-free order for remaining units"
		if member_index < 0:
			if not bool(sequence.get("wait_reason_logged", false)):
				push_warning("Squad %d waiting for jump path: %s" % [index + 1, waiting_reason])
				sequence["wait_reason_logged"] = true
			_squad_jump_sequences[index] = sequence
			return
		sequence["phase"] = "anticipation"
		sequence["elapsed"] = 0.0
		sequence["wait_reason_logged"] = false
	sequence["member_index"] = member_index
	var mate := mates[member_index]
	var elapsed := float(sequence["elapsed"]) + delta
	mate.set_walking(false)
	mate.set_standing_turn(false)
	var start_position: Vector3 = starts[member_index]
	var target_position: Vector3 = targets[member_index]
	var phase := String(sequence.get("phase", "anticipation"))
	if phase == "anticipation":
		var anticipation_progress := clampf(elapsed / jump_anticipation_seconds, 0.0, 1.0)
		mate.set_jump_animation(smoothstep(0.0, 1.0, anticipation_progress), 0.0, 5.0)
		mate.set_jump_jet_intensity(0.0)
		if anticipation_progress >= 1.0:
			var path_reason := _get_jump_unit_block_reason(mate, start_position, target_position)
			if path_reason.is_empty():
				sequence["phase"] = "flight"
			else:
				mate.set_jump_animation(0.0, 0.0, 0.0)
				sequence["member_index"] = -1
				sequence["phase"] = "waiting"
			sequence["elapsed"] = 0.0
		else:
			sequence["elapsed"] = elapsed
	elif phase == "flight":
		var progress := clampf(elapsed / jump_duration_seconds, 0.0, 1.0)
		mate.global_position = start_position.lerp(target_position, progress) + Vector3.UP * _get_jump_arc_offset(progress)
		var tuck_amount := sin(PI * progress)
		var body_pitch := lerpf(-jump_body_pitch_degrees, jump_body_pitch_degrees, progress)
		mate.set_jump_animation(0.0, tuck_amount, body_pitch)
		var jet_level := 0.0
		if progress < 0.18:
			jet_level = 1.0 - progress / 0.18
		elif absf(progress - 0.70) < 0.06 or absf(progress - 0.88) < 0.06:
			jet_level = 1.0
		mate.set_jump_jet_intensity(jet_level)
		if progress >= 1.0:
			mate.global_position = target_position
			mate.set_jump_jet_intensity(0.0)
			mate.set_jump_animation(1.0, 0.0, jump_body_pitch_degrees)
			sequence["phase"] = "landing"
			sequence["elapsed"] = 0.0
		else:
			sequence["elapsed"] = elapsed
	else:
		var landing_progress := clampf(elapsed / jump_landing_recovery_seconds, 0.0, 1.0)
		var compression := 1.0 - smoothstep(0.0, 1.0, landing_progress)
		mate.set_jump_animation(compression, 0.0, jump_body_pitch_degrees * compression)
		mate.set_jump_jet_intensity(0.0)
		if landing_progress >= 1.0:
			mate.set_jump_animation(0.0, 0.0, 0.0)
			pending_members.erase(member_index)
			sequence["member_index"] = -1
			sequence["phase"] = "waiting"
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
			var correction: Dictionary = {}
			if absf(movement_point.y - waypoint.y) < 0.1:
				correction = _get_route_correction(movement_point, waypoint)
			if not jump_routes.is_empty():
				_waypoint_visual_mesh.surface_add_vertex(previous_point)
				for jump_route in jump_routes:
					_waypoint_visual_mesh.surface_add_vertex(_jump_visual_position(jump_route, true) + Vector3.UP * WAYPOINT_VISUAL_HEIGHT)
					_waypoint_visual_mesh.surface_add_vertex(_jump_visual_position(jump_route, false) + Vector3.UP * WAYPOINT_VISUAL_HEIGHT)
				_waypoint_visual_mesh.surface_add_vertex(marker_center)
			elif not correction.is_empty():
				_waypoint_visual_mesh.surface_add_vertex(previous_point)
				for key in ["entry", "exit"]:
					if correction.has(key):
						var anchor: Vector3 = correction[key] + Vector3.UP * WAYPOINT_VISUAL_HEIGHT
						_waypoint_visual_mesh.surface_add_vertex(anchor)
						_waypoint_visual_mesh.surface_add_vertex(anchor)
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
	_refresh_automatic_waypoint_visual()
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
	var correction := _get_passage_route_correction(squad_index, first_waypoint)
	_waypoint_origin_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _waypoint_visual_material)
	_waypoint_origin_mesh.surface_add_vertex(route_origin)
	var active_passage = _squad_passages[squad_index]
	if active_passage != null and active_passage.wait_point != null and not active_passage.replan_requested:
		_waypoint_origin_mesh.surface_add_vertex(active_passage.wait_point + Vector3.UP * WAYPOINT_VISUAL_HEIGHT)
	elif not jump_routes.is_empty():
		for jump_route in jump_routes:
			_waypoint_origin_mesh.surface_add_vertex(_jump_visual_position(jump_route, true) + Vector3.UP * WAYPOINT_VISUAL_HEIGHT)
			_waypoint_origin_mesh.surface_add_vertex(_jump_visual_position(jump_route, false) + Vector3.UP * WAYPOINT_VISUAL_HEIGHT)
		_waypoint_origin_mesh.surface_add_vertex(first_waypoint + Vector3.UP * WAYPOINT_VISUAL_HEIGHT)
	elif not correction.is_empty():
		for key in ["entry", "exit"]:
			if correction.has(key):
				var anchor: Vector3 = correction[key] + Vector3.UP * WAYPOINT_VISUAL_HEIGHT
				_waypoint_origin_mesh.surface_add_vertex(anchor)
				_waypoint_origin_mesh.surface_add_vertex(anchor)
		_waypoint_origin_mesh.surface_add_vertex(first_waypoint + Vector3.UP * WAYPOINT_VISUAL_HEIGHT)
	else:
		_waypoint_origin_mesh.surface_add_vertex(first_waypoint + Vector3.UP * WAYPOINT_VISUAL_HEIGHT)
	_waypoint_origin_mesh.surface_end()


func _refresh_automatic_waypoint_visual() -> void:
	if _automatic_waypoint_mesh == null:
		return
	_automatic_waypoint_mesh.clear_surfaces()
	if _selected_squad_number <= 0 or _selected_squad_number > _squad_waypoints.size():
		return
	var index := _selected_squad_number - 1
	var route: Array = _squad_waypoints[index]
	if route.is_empty():
		return
	var points: Array[Vector3] = []
	var passage = _squad_passages[index]
	if passage != null and passage.wait_point != null and not passage.replan_requested:
		points.append(passage.wait_point)
	var origin := _get_squad_movement_point(_selected_squad_number)
	for i in range(route.size()):
		var destination: Vector3 = route[i]
		var correction: Dictionary = _get_passage_route_correction(index, destination) if i == 0 else _get_route_correction(origin, destination)
		for key in ["entry", "exit"]:
			if correction.has(key):
				points.append(correction[key])
		origin = destination
	if points.is_empty():
		return
	_automatic_waypoint_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _automatic_waypoint_material)
	for point in points:
		var center := point + Vector3.UP * (WAYPOINT_VISUAL_HEIGHT * 1.5)
		for segment in range(WAYPOINT_MARKER_SEGMENTS):
			var a := TAU * float(segment) / WAYPOINT_MARKER_SEGMENTS
			var b := TAU * float(segment + 1) / WAYPOINT_MARKER_SEGMENTS
			_automatic_waypoint_mesh.surface_add_vertex(center + Vector3(cos(a), 0.0, sin(a)) * WAYPOINT_MARKER_RADIUS)
			_automatic_waypoint_mesh.surface_add_vertex(center + Vector3(cos(b), 0.0, sin(b)) * WAYPOINT_MARKER_RADIUS)
	_automatic_waypoint_mesh.surface_end()


func _get_passage_route_correction(squad_index: int, waypoint: Vector3) -> Dictionary:
	var passage = _squad_passages[squad_index]
	if passage != null and not passage.replan_requested and passage.waypoint == waypoint:
		var remaining: Dictionary = passage.route_correction.duplicate()
		var point := get_squad_point(squad_index + 1)
		var entry_z: float = NARROW_PASSAGE_SCRIPT.FRONT_Z if passage.direction > 0.0 else NARROW_PASSAGE_SCRIPT.BACK_Z
		var exit_z: float = NARROW_PASSAGE_SCRIPT.BACK_Z if passage.direction > 0.0 else NARROW_PASSAGE_SCRIPT.FRONT_Z
		if passage.direction * (point.z - entry_z) >= 0.0:
			remaining.erase("entry")
		if passage.direction * (point.z - exit_z) >= 0.0:
			remaining.erase("exit")
		return remaining
	var origin := get_squad_point(squad_index + 1)
	if passage != null:
		for mate in _squad_mates[squad_index]:
			if mate != null and mate.is_alive() and absf(mate.position.x - NARROW_PASSAGE_SCRIPT.CENTER_X) < 0.5 and mate.position.z > NARROW_PASSAGE_SCRIPT.FRONT_Z and mate.position.z < NARROW_PASSAGE_SCRIPT.BACK_Z:
				origin = mate.position
				break
	if absf(_get_squad_movement_point(squad_index + 1).y - waypoint.y) >= 0.1:
		return {}
	return _get_route_correction(origin, waypoint)


func _get_route_correction(origin: Vector3, waypoint: Vector3) -> Dictionary:
	var correction: Dictionary = NARROW_PASSAGE_SCRIPT.get_exit_correction(origin, waypoint, passage_correction_tolerance)
	if correction.is_empty():
		correction = NARROW_PASSAGE_SCRIPT.get_entry_correction(origin, waypoint, passage_correction_tolerance)
	if correction.has("entry") and not _is_correction_segment_clear(origin, correction["entry"]):
		return {}
	if correction.has("exit") and not _is_correction_segment_clear(correction["exit"], waypoint):
		return {}
	return correction


func _is_correction_segment_clear(start: Vector3, waypoint: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = WALK_BODY_RADIUS
	shape.height = WALK_BODY_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, start + Vector3.UP * shape.height * 0.5)
	query.motion = waypoint - start
	query.collision_mask = 1
	var space := get_world_3d().direct_space_state
	var motion := space.cast_motion(query)
	if not motion.is_empty() and motion[0] < 1.0:
		return false
	query.motion = Vector3.ZERO
	query.transform.origin = waypoint + Vector3.UP * shape.height * 0.5
	return space.intersect_shape(query, 1).is_empty()


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
		var takeoff: Vector3 = _jump_visual_position(jump_route, true)
		var landing: Vector3 = _jump_visual_position(jump_route, false)
		var previous_point := takeoff + Vector3.UP * WAYPOINT_VISUAL_HEIGHT
		for segment in range(1, JUMP_ARC_SEGMENTS + 1):
			var progress := float(segment) / JUMP_ARC_SEGMENTS
			var point := takeoff.lerp(landing, progress) + Vector3.UP * (_get_jump_arc_offset(progress) + WAYPOINT_VISUAL_HEIGHT)
			_jump_visual_mesh.surface_add_vertex(previous_point)
			_jump_visual_mesh.surface_add_vertex(point)
			previous_point = point
	_jump_visual_mesh.surface_end()
	_draw_jump_markers(jump_routes, _jump_takeoff_material, true)
	_draw_jump_markers(jump_routes, _jump_landing_material, false)


func _draw_jump_markers(jump_routes: Array[Dictionary], material: StandardMaterial3D, is_takeoff: bool) -> void:
	_jump_visual_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for jump_route in jump_routes:
		var position: Vector3 = _jump_visual_position(jump_route, is_takeoff)
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


func _add_jump_platform(platform_name: String, size: Vector3, position: Vector3, material: Material) -> void:
	var platform := MeshInstance3D.new()
	platform.name = platform_name
	var platform_mesh := BoxMesh.new()
	platform_mesh.size = size
	platform.mesh = platform_mesh
	platform.position = position
	platform.material_override = material
	add_child(platform)
	var platform_body := StaticBody3D.new()
	platform_body.name = "%sCollision" % platform_name
	platform_body.collision_layer = 2
	platform_body.collision_mask = 0
	platform_body.position = position
	var platform_shape := CollisionShape3D.new()
	var platform_box := BoxShape3D.new()
	platform_box.size = size
	platform_shape.shape = platform_box
	platform_body.add_child(platform_shape)
	add_child(platform_body)


func _add_corridor_wall(wall_name: String, size: Vector3, position: Vector3, material: Material) -> void:
	var wall := MeshInstance3D.new()
	wall.name = wall_name
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = size
	wall.mesh = wall_mesh
	wall.position = position
	wall.material_override = material
	add_child(wall)

	var wall_body := StaticBody3D.new()
	wall_body.name = "%sCollision" % wall_name
	wall_body.collision_layer = 1
	wall_body.collision_mask = 0
	wall_body.position = position
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = size
	wall_shape.shape = wall_box
	wall_body.add_child(wall_shape)
	add_child(wall_body)


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

	_add_jump_platform("JumpLandingPlatform", Vector3(8.0, 0.4, 7.0), Vector3(0.0, 1.4, 16.0), ground_material)
	var highland_material := StandardMaterial3D.new()
	highland_material.albedo_color = Color("#34464B")
	highland_material.roughness = 0.94
	_add_jump_platform("JumpHighland", Vector3(8.0, 0.4, 7.0), Vector3(0.0, 3.0, 26.0), highland_material)

	var corridor_material := StandardMaterial3D.new()
	corridor_material.albedo_color = Color("#58666A")
	corridor_material.roughness = 0.9
	_add_corridor_wall("NarrowPassageWestWall", Vector3(4.0, 3.0, 16.0), Vector3(-27.5, 1.5, 1.0), corridor_material)
	_add_corridor_wall("NarrowPassageEastWall", Vector3(4.0, 3.0, 16.0), Vector3(-22.5, 1.5, 1.0), corridor_material)

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
	_automatic_waypoint_mesh = ImmediateMesh.new()
	_automatic_waypoint_material = StandardMaterial3D.new()
	_automatic_waypoint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_automatic_waypoint_material.albedo_color = Color("#69D96B")
	var automatic_visual := MeshInstance3D.new()
	automatic_visual.name = "SelectedSquadAutomaticWaypoints"
	automatic_visual.mesh = _automatic_waypoint_mesh
	automatic_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(automatic_visual)
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
		_squad_jump_preparations.append({})
		_squad_passages.append(null)
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
