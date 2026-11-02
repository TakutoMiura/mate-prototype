extends SceneTree

const FIELD_SCENE: PackedScene = preload("res://Scenes/test_field.tscn")
const SIDESTEP_TEST_FIELD = preload("res://tests/fixtures/sidestep_test_field.gd")
const FRAME_DELTA := 1.0 / 60.0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_side_jump(1.0)
	await _check_side_jump(-1.0)
	await _check_through_route()
	await _check_staircase_route()
	await _check_preparation_route_lock()
	await _check_destroyed_member(false)
	await _check_destroyed_member(true)
	await _check_overlapping_connections()
	await _check_walk_overlap()
	_check_sidestep_offset()
	if failures.is_empty():
		print("Jump movement regression checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _new_field() -> Node:
	var field := FIELD_SCENE.instantiate()
	field.set_process(false)
	root.add_child(field)
	return field


func _check_side_jump(side: float) -> void:
	var field := _new_field()
	await physics_frame
	var mates: Array = field._squad_mates[1]
	var start_x := side * (8.5 + 0.500005)
	for i in range(mates.size()):
		mates[i].position = Vector3(start_x + (i - 1) * 2.7, 0.04, 16.0)
		mates[i].rotation.y = -side * PI * 0.5
	var expected_offsets: Dictionary = {}
	if side < 0.0:
		expected_offsets[mates[2].get_instance_id()] = Vector3(0.0, 0.0, 0.1)
		field._mate_lateral_offsets[mates[2].get_instance_id()] = Vector3(0.0, 0.0, 0.1)
	field._squad_headings[1] = -side * PI * 0.5
	field._squad_waypoints[1].append(Vector3(side * 3.0, 1.6, 16.0))
	var jump_started := false
	var stage_moved := false
	var preparation_targets: Array = []
	var original_position: Vector3 = mates[0 if side > 0.0 else 2].position
	for frame in range(500):
		field._process_squad_movement(FRAME_DELTA)
		if bool(field._squad_blocked[1]):
			failures.append("side %s: squad became BLOCKED at frame %d" % [side, frame])
			break
		var preparation: Dictionary = field._squad_jump_preparations[1]
		if not preparation.is_empty():
			if preparation_targets.is_empty():
				preparation_targets = preparation["targets"].duplicate()
			elif preparation_targets != preparation["targets"]:
				failures.append("side %s: landing targets changed while clearing" % side)
			if mates[0 if side > 0.0 else 2].position.distance_to(original_position) > 0.01:
				stage_moved = true
		if bool(field._squad_jump_sequences[1].get("active", false)):
			jump_started = true
		if jump_started and not bool(field._squad_jump_sequences[1].get("active", false)):
			break
	if not jump_started:
		failures.append("side %s: jump never started" % side)
	elif bool(field._squad_jump_sequences[1].get("active", false)):
		failures.append("side %s: jump did not finish" % side)
	else:
		for mate in mates:
			if absf(mate.position.y - 1.6) > 0.01:
				failures.append("side %s: %s did not land on platform" % [side, mate.name])
			var expected_offset: Vector3 = expected_offsets.get(mate.get_instance_id(), Vector3.ZERO)
			var actual_offset: Vector3 = field._mate_lateral_offsets.get(mate.get_instance_id(), Vector3.ZERO)
			if not actual_offset.is_equal_approx(expected_offset):
				failures.append("side %s: %s retained a jump preparation offset after landing" % [side, mate.name])
	if not stage_moved:
		failures.append("side %s: occupied landing slot was not cleared" % side)
	if jump_started and not bool(field._squad_jump_sequences[1].get("active", false)):
		field._squad_waypoints[1].clear()
		field._squad_traversed_jump_connections[1].clear()
		field._squad_waypoints[1].append(Vector3(side * 8.5, 0.0, 16.0))
		var descent_started := false
		for frame in range(500):
			field._process_squad_movement(FRAME_DELTA)
			if bool(field._squad_blocked[1]):
				failures.append("side %s: descent became BLOCKED at frame %d" % [side, frame])
				break
			if bool(field._squad_jump_sequences[1].get("active", false)):
				descent_started = true
			if descent_started and not bool(field._squad_jump_sequences[1].get("active", false)):
				break
		if not descent_started or bool(field._squad_jump_sequences[1].get("active", false)):
			failures.append("side %s: descent did not complete" % side)
		else:
			for mate in mates:
				if absf(mate.position.y) > 0.01:
					failures.append("side %s: %s did not return to ground" % [side, mate.name])
	field.queue_free()
	await process_frame


func _check_walk_overlap() -> void:
	var field := _new_field()
	await physics_frame
	var mates: Array = field._squad_mates[1]
	mates[0].position = Vector3(0.0, 0.04, 15.0)
	mates[1].position = Vector3(0.699, 0.04, 15.0)
	mates[2].position = Vector3(4.0, 0.04, 15.0)
	if field._can_walk_displacement(mates[0], Vector3(0.002, 0.0, 0.0)):
		failures.append("walk collision: a short step toward another unit was accepted")
	if not field._can_walk_displacement(mates[0], Vector3(-0.02, 0.0, 0.0)):
		failures.append("walk collision: a step that resolves an existing overlap was rejected")
	mates[1].position = Vector3(2.7, 0.04, 15.0)
	field._mate_lateral_offsets[mates[0].get_instance_id()] = Vector3(1.4, 0.0, 0.0)
	var clearance: Dictionary = field._move_landing_occupant_aside(
		mates[0], Vector3(0.2, 1.6, 15.0), Vector3(0.0, 0.0, 15.0), FRAME_DELTA
	)
	if not bool(clearance.get("moved", false)):
		failures.append("jump preparation: movement toward the formation was rejected at the offset limit")
	field.queue_free()
	await process_frame


func _check_through_route() -> void:
	var field := _new_field()
	await physics_frame
	var mates: Array = field._squad_mates[1]
	for i in range(mates.size()):
		mates[i].position = Vector3(9.000005 + (i - 1) * 2.7, 0.04, 16.0)
		mates[i].rotation.y = -PI * 0.5
	field._squad_headings[1] = -PI * 0.5
	field._squad_waypoints[1].append(Vector3(-10.0, 0.0, 16.0))
	var jumps_started := 0
	var was_jumping := false
	for frame in range(1200):
		field._process_squad_movement(FRAME_DELTA)
		if bool(field._squad_blocked[1]):
			failures.append("through route: squad became BLOCKED at frame %d" % frame)
			break
		var jumping := bool(field._squad_jump_sequences[1].get("active", false))
		if jumping and not was_jumping:
			jumps_started += 1
		was_jumping = jumping
		if field._squad_waypoints[1].is_empty() and not jumping:
			break
	if jumps_started != 2 or not field._squad_waypoints[1].is_empty():
		failures.append("through route: expected two jumps and arrival, got %d jumps" % jumps_started)
	for mate in mates:
		if absf(mate.position.y) > 0.01:
			failures.append("through route: %s did not return to ground" % mate.name)
	field.queue_free()
	await process_frame


func _check_preparation_route_lock() -> void:
	var field := _new_field()
	await physics_frame
	var mates: Array = field._squad_mates[1]
	for i in range(mates.size()):
		mates[i].position = Vector3(9.000005 + (i - 1) * 2.7, 0.04, 16.0)
		mates[i].rotation.y = -PI * 0.5
	field._squad_headings[1] = -PI * 0.5
	var waypoint := Vector3(-10.0, 0.0, 16.0)
	field._squad_waypoints[1].append(waypoint)
	field._process_squad_movement(FRAME_DELTA)
	var preparation: Dictionary = field._squad_jump_preparations[1]
	if preparation.is_empty():
		failures.append("jump preparation: no pending landing plan to preserve")
	else:
		var targets: Array = preparation["targets"].duplicate()
		for mate in mates:
			mate.position.x -= 1.0
		var recalculated_route: Dictionary = field._get_squad_jump_route(1, waypoint, field._get_squad_movement_point(2))
		if not recalculated_route.is_empty():
			failures.append("jump preparation: route-lock fixture did not move beyond the takeoff")
		field._process_squad_movement(FRAME_DELTA)
		preparation = field._squad_jump_preparations[1]
		if preparation.is_empty() or preparation["targets"] != targets:
			failures.append("jump preparation: planned targets were discarded during local movement")
		field._squad_waypoints[1].clear()
		field._process_squad_movement(FRAME_DELTA)
		if not field._squad_jump_preparations[1].is_empty():
			failures.append("jump preparation: clearing the route did not cancel the landing plan")
	field.queue_free()
	await process_frame


func _check_staircase_route() -> void:
	var field := _new_field()
	await physics_frame
	var mates: Array = field._squad_mates[1]
	for i in range(mates.size()):
		mates[i].position = Vector3(9.000005 + (i - 1) * 2.7, 0.04, 16.0)
		mates[i].rotation.y = -PI * 0.5
	field._squad_headings[1] = -PI * 0.5
	field._squad_waypoints[1].append_array([
		Vector3(3.0, 1.6, 16.0),
		Vector3(0.0, 1.6, 19.0),
		Vector3(0.0, 3.2, 26.0),
		Vector3(0.0, 1.6, 19.0),
		Vector3(3.0, 1.6, 16.0),
		Vector3(8.5, 0.0, 16.0),
	])
	var jumps_started := 0
	var was_jumping := false
	for frame in range(4000):
		field._process_squad_movement(FRAME_DELTA)
		for mate in mates:
			mate._process(FRAME_DELTA)
		if bool(field._squad_blocked[1]):
			failures.append("staircase route: squad became BLOCKED at frame %d" % frame)
			break
		var jumping := bool(field._squad_jump_sequences[1].get("active", false))
		if jumping and not was_jumping:
			jumps_started += 1
		was_jumping = jumping
		if field._squad_waypoints[1].is_empty() and not jumping:
			break
	if jumps_started != 4 or not field._squad_waypoints[1].is_empty():
		failures.append("staircase route: expected four jumps and arrival, got %d jumps and %d waypoints left" % [jumps_started, field._squad_waypoints[1].size()])
	for mate in mates:
		if absf(mate.position.y) > 0.01:
			failures.append("staircase route: %s did not return to ground" % mate.name)
	field.queue_free()
	await process_frame


func _check_destroyed_member(overlap: bool) -> void:
	var field := _new_field()
	await physics_frame
	var mates: Array = field._squad_mates[1]
	mates[0]._unit_state.current_hp = 0.0
	var destroyed_position := Vector3(7.15 if overlap else 50.0, 3.2, 16.0)
	mates[0].position = destroyed_position
	mates[1].position = Vector3(7.15, 0.04, 16.0)
	mates[2].position = Vector3(9.85, 0.04, 16.0)
	field._squad_waypoints[1].append(Vector3(3.0, 1.6, 16.0))
	var jump_started := false
	for frame in range(400):
		field._process_squad_movement(FRAME_DELTA)
		if bool(field._squad_blocked[1]):
			failures.append("destroyed member: surviving squad became BLOCKED at frame %d" % frame)
			break
		if bool(field._squad_jump_sequences[1].get("active", false)):
			jump_started = true
		if jump_started and not bool(field._squad_jump_sequences[1].get("active", false)):
			break
	if not jump_started or absf(mates[1].position.y - 1.6) > 0.01 or absf(mates[2].position.y - 1.6) > 0.01:
		failures.append("destroyed member: surviving units did not complete the jump")
	if mates[0].position != destroyed_position:
		failures.append("destroyed member: inactive unit was moved")
	if not field._reserved_jump_landings.is_empty():
		failures.append("destroyed member: jump reservations were not released")
	field.queue_free()
	await process_frame


func _check_overlapping_connections() -> void:
	var field := _new_field()
	await physics_frame
	var original: JumpConnection = field.get_node("JumpConnectionRight")
	original.bidirectional = false
	var alternate: JumpConnection = original.duplicate()
	alternate.name = "AlternateRightConnection"
	alternate.bidirectional = true
	field.add_child(alternate)
	var target := Vector3(8.5, 0.0, 16.0)
	var start := Vector3(3.0, 1.6, 16.0)
	var route: Dictionary = field._find_jump_route(target, start, [])
	if bool(route.get("blocked", false)) or route.get("connection") != alternate:
		failures.append("jump routing: forbidden direction hid a valid overlapping connection")
	alternate.queue_free()
	await process_frame
	route = field._find_jump_route(target, start, [])
	if not bool(route.get("blocked", false)) or not String(route.get("blocked_reason", "")).contains("direction"):
		failures.append("jump routing: forbidden direction did not report the correct reason")
	field.queue_free()
	await process_frame


func _check_sidestep_offset() -> void:
	var field = SIDESTEP_TEST_FIELD.new()
	var mate := MatePreview.new()
	var result: Dictionary = field._get_member_walk_displacement(mate, Vector3(0.0, 0.0, 0.1), Vector3.RIGHT)
	var displacement: Vector3 = result["displacement"]
	var offset: Vector3 = field._mate_lateral_offsets.get(mate.get_instance_id(), Vector3.ZERO)
	if displacement.x >= 0.0 or not is_equal_approx(offset.x, displacement.x):
		failures.append("walk avoidance: recorded offset %s differs from sidestep %s" % [offset, displacement])
	mate.free()
	field.free()
