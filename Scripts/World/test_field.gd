class_name TestField
extends Node3D

signal squad_selection_requested(squad_number: int)
signal view_changed
signal walking_comparison_changed(enabled: bool)

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
const HEADING_ALIGNMENT_TOLERANCE := deg_to_rad(5.0)
const WAYPOINT_MARKER_RADIUS := 0.32
const WAYPOINT_MARKER_SEGMENTS := 16
const WAYPOINT_VISUAL_HEIGHT := 0.06

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

@export var equipment_catalog: EquipmentCatalog

var _camera: Camera3D
var _camera_tween: Tween
var _camera_target := CAMERA_INITIAL_TARGET
var _camera_yaw := 0.0
var _camera_elevation := 0.0
var _camera_distance := 0.0
var _follow_squad_number := 0
var _selected_squad_number := 0
var walking_comparison_enabled := true
var _is_rotating := false
var _continuous_rendering := false
var _squad_centers: Array[Vector3] = []
var _squad_states: Array[Array] = []
var _squad_mates: Array[Array] = []
var _squad_waypoints: Array[Array] = []
var _squad_headings: Array[float] = []
var _waypoint_visual: MeshInstance3D
var _waypoint_visual_mesh: ImmediateMesh
var _waypoint_origin_visual: MeshInstance3D
var _waypoint_origin_mesh: ImmediateMesh
var _waypoint_visual_material: StandardMaterial3D
var _prepared := false


func _ready() -> void:
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
	var squads_active := _process_squad_movement(delta)
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
	var ground_point: Variant = Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, ray_direction)
	if ground_point == null:
		return false
	var selected_index := _selected_squad_number - 1
	var selected_point := get_squad_point(_selected_squad_number)
	var targets: Array[int] = [selected_index]
	if walking_comparison_enabled and selected_index < 2:
		targets = [0, 1]
	for target_index in targets:
		var route: Array = _squad_waypoints[target_index]
		if not append:
			route.clear()
		var translation := get_squad_point(target_index + 1) - selected_point
		route.append(Vector3(ground_point.x + translation.x, 0.0, ground_point.z + translation.z))
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
		var route: Array = _squad_waypoints[index]
		if route.is_empty():
			continue
		var mates: Array[MatePreview] = _squad_mates[index]
		var living_mates: Array[MatePreview] = []
		for mate in mates:
			if mate != null and mate.is_alive():
				living_mates.append(mate)
		if living_mates.is_empty():
			route.clear()
			route_changed = true
			continue
		var movement_budget := squad_move_speed * delta
		while not route.is_empty():
			var point := get_squad_point(index + 1)
			var waypoint: Vector3 = route[0]
			var direction := Vector3(waypoint.x - point.x, 0.0, waypoint.z - point.z)
			var distance := direction.length()
			if distance <= WAYPOINT_ARRIVAL_RADIUS:
				route.pop_front()
				route_changed = true
				continue
			var target_heading := atan2(direction.x, direction.z)
			var heading: float = _squad_headings[index]
			var heading_difference := wrapf(target_heading - heading, -PI, PI)
			if absf(heading_difference) > HEADING_ALIGNMENT_TOLERANCE:
				var maximum_turn := deg_to_rad(squad_turn_speed_degrees_per_second) * delta
				var turn_delta := clampf(heading_difference, -maximum_turn, maximum_turn)
				heading = wrapf(heading + turn_delta, -PI, PI)
				_squad_headings[index] = heading
				for mate in living_mates:
					mate.rotation.y = heading
				any_active = true
				heading_difference = wrapf(target_heading - heading, -PI, PI)
				if absf(heading_difference) > HEADING_ALIGNMENT_TOLERANCE:
					break
			# Snap only the final sub-five-degree difference so forward movement
			# points exactly at the waypoint rather than drifting sideways.
			if not is_equal_approx(heading, target_heading):
				heading = target_heading
				_squad_headings[index] = heading
				for mate in living_mates:
					mate.rotation.y = heading
				any_active = true
			var travel_distance := minf(movement_budget, distance - WAYPOINT_ARRIVAL_RADIUS)
			if travel_distance <= 0.0:
				break
			var displacement := direction / distance * travel_distance
			for mate in living_mates:
				mate.position += displacement
				mate.set_walking(true, squad_move_speed)
			any_active = true
			any_positions_moved = true
			if travel_distance + WAYPOINT_ARRIVAL_RADIUS >= distance:
				route.pop_front()
				route_changed = true
			break
	for squad_mates in _squad_mates:
		for mate in squad_mates:
			if mate != null and mate.is_walking_animating():
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
	if _selected_squad_number <= 0 or _selected_squad_number > _squad_waypoints.size():
		_refresh_waypoint_origin_visual()
		return
	var route: Array = _squad_waypoints[_selected_squad_number - 1]
	if route.is_empty():
		_refresh_waypoint_origin_visual()
		return
	_waypoint_visual_material.albedo_color = SQUAD_COLORS[_selected_squad_number - 1]
	_waypoint_visual_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _waypoint_visual_material)
	var previous_point: Vector3 = route[0] + Vector3(0, WAYPOINT_VISUAL_HEIGHT, 0)
	for index in range(route.size()):
		var waypoint: Vector3 = route[index]
		var marker_center: Vector3 = waypoint + Vector3(0, WAYPOINT_VISUAL_HEIGHT, 0)
		if index > 0:
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
	_waypoint_origin_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _waypoint_visual_material)
	_waypoint_origin_mesh.surface_add_vertex(get_squad_point(_selected_squad_number) + Vector3(0, WAYPOINT_VISUAL_HEIGHT, 0))
	_waypoint_origin_mesh.surface_add_vertex(first_waypoint + Vector3(0, WAYPOINT_VISUAL_HEIGHT, 0))
	_waypoint_origin_mesh.surface_end()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if Input.is_action_just_pressed("select_squad_1"):
		squad_selection_requested.emit(1)
		get_viewport().set_input_as_handled()
	elif Input.is_action_just_pressed("select_squad_2"):
		squad_selection_requested.emit(2)
		get_viewport().set_input_as_handled()
	elif Input.is_action_just_pressed("select_squad_3"):
		squad_selection_requested.emit(3)
		get_viewport().set_input_as_handled()
	if Input.is_action_just_pressed("toggle_walking_comparison"):
		walking_comparison_enabled = not walking_comparison_enabled
		walking_comparison_changed.emit(walking_comparison_enabled)
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
	_register_key_action("toggle_walking_comparison", KEY_C)
	_register_key_action("select_squad_1", KEY_1)
	_register_key_action("select_squad_2", KEY_2)
	_register_key_action("select_squad_3", KEY_3)


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
			mate.position = Vector3(
				squad_center.x + (mate_index - 1) * MATE_SPACING,
				0.04,
				0
			)
			squad_states.append(unit_state)
			squad_mates.append(mate)
			add_child(mate)
		_squad_states.append(squad_states)
		_squad_mates.append(squad_mates)
