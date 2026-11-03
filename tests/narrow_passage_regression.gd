extends SceneTree

const FIELD := preload("res://Scenes/test_field.tscn")
const PASSAGE := preload("res://Scripts/World/narrow_passage.gd")
const DELTA := 1.0 / 60.0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_review_fixes()
	await _check_squad_exclusion()
	await _check_route_classification()
	await _check_passage(false)
	await _check_passage(true, -6.0)
	await _check_passage(true, -3.0)
	await _check_passage(true, 9.5)
	await _check_side_approach()
	await _check_repeated_passages()
	await _check_repeated_passages(1.0 / 30.0)
	await _check_stop_inside(0.0, false)
	await _check_stop_inside(0.0, false, -14.0)
	await _check_stop_inside(-6.5, false)
	await _check_stop_inside(8.5, true, -14.0)
	await _check_retarget_inside(4.0, 0.0)
	await _check_retarget_inside(-3.0, -5.0)
	await _check_inside_then_exit_queued()
	await _check_inside_reposition()
	await _check_stop_before_obstacle()
	await _check_blocked_terrain()
	await _check_reissue_blocked_waypoint()
	await _check_reissue_during_passage()
	await _check_exit_correction()
	await _check_entry_correction()
	await _check_entry_correction_obstacles()
	await _check_entry_correction_queued()
	if failures.is_empty():
		print("Narrow passage regression checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check_squad_exclusion() -> void:
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	for squad_index in range(2):
		for i in range(3):
			field._squad_mates[squad_index][i].position = Vector3(-25 + (i - 1) * 2.7, 0.04, -12.0 if squad_index == 0 else 14.0)
	field._squad_waypoints[0].append(Vector3(-25, 0, 15))
	field._squad_waypoints[1].append(Vector3(-25, 0, -14))
	var waited := false
	var finished := false
	for frame in range(15000):
		field._process_squad_movement(DELTA)
		for squad in field._squad_mates:
			for mate in squad:
				mate._process(DELTA)
		if field._squad_passages[1] != null and field._squad_passages[1].wait_point != null:
			waited = true
		if field._squad_inside_passage(0) and field._squad_inside_passage(1):
			failures.append("opposing squads entered the passage at the same time")
			break
		if field._squad_waypoints[0].is_empty() and field._squad_waypoints[1].is_empty():
			finished = true
			break
	if not waited or not finished:
		failures.append("opposing squads failed to wait and pass: waited=%s owner=%s waypoints=%s positions=%s" % [waited, field._passage_owner, field._squad_waypoints, field._squad_mates.slice(0, 2).map(func(squad): return squad.map(func(mate): return mate.position))])
	field.queue_free()
	await process_frame


func _check_review_fixes() -> void:
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	var mates: Array = field._squad_mates[0]
	for i in range(3):
		mates[i].position = Vector3(-25.0 + (i - 1) * 2.7, 0.04, -12.0)
	var goal := Vector3(-25, 0, 0)
	var passage = PASSAGE.new(field, goal, mates)
	# Move the members into the reverse of their original entrance order.
	for i in range(3):
		passage.members[i]["mate"].position = Vector3(-18.0, 0.04, -12.0 + i * 1.3)
	passage.wait_point = Vector3(-18, 0, -10.7)
	passage.resume_from_wait()
	for i in range(2):
		if passage.members[i]["slot"].z <= passage.members[i + 1]["slot"].z:
			failures.append("waiting reordered members without reassigning inside slots")
	field._squad_waypoints[0].append(goal)
	field._squad_passages[0] = passage
	field._passage_owner = 0
	var finished := false
	for frame in range(9000):
		field._process_squad_movement(DELTA)
		for mate in mates:
			mate._process(DELTA)
		if field._squad_waypoints[0].is_empty():
			finished = true
			break
	if not finished:
		failures.append("squad failed to line up inside after waiting")
	field.queue_free()
	await process_frame

	field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	mates = field._squad_mates[0]
	mates[0].position = Vector3(-22.8, 0.04, 10.25)
	mates[1].position = Vector3(-27.2, 0.04, 10.25)
	mates[2].position = Vector3(-25.0, 0.04, 5.0)
	passage = PASSAGE.new(field, Vector3(-25, 0, 15), mates)
	for state in passage.members:
		if int(state["phase"]) == 2 and state["mate"].position.distance_to(state["slot"]) > 0.1:
			failures.append("already exited unit was assigned an occupied opposite parking slot")
	field._squad_waypoints[0].append(Vector3(-25, 0, 15))
	field._squad_passages[0] = passage
	field._passage_owner = 0
	finished = false
	for frame in range(9000):
		field._process_squad_movement(DELTA)
		for mate in mates:
			mate._process(DELTA)
		if field._squad_waypoints[0].is_empty():
			finished = true
			break
	if not finished:
		failures.append("replanned passage failed to clear already occupied exit slots")
	field.queue_free()
	await process_frame

	field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	var requester = field._squad_mates[0][0]
	var blocker = field._squad_mates[1][0]
	requester.position = Vector3(10, 0.04, 0)
	blocker.position = Vector3(10, 0.04, 1)
	for i in range(1, 3):
		field._squad_mates[0][i].position = Vector3(20 + i * 3, 0.04, 0)
		field._squad_mates[1][i].position = Vector3(20 + i * 3, 0.04, 5)
	field._squad_waypoints[0].append(Vector3(10, 0, 10))
	field._squad_waypoints[1].append(Vector3(10, 0, 20))
	field._squad_blocked[1] = true
	var before: Vector3 = blocker.position
	if not field._request_stationary_ally_yield(0, requester, Vector3(10, 0.04, 2), DELTA) or blocker.position.is_equal_approx(before):
		failures.append("blocked squad with an outstanding order did not yield")
	for frame in range(20):
		field._request_stationary_ally_yield(0, requester, Vector3(10, 0.04, 2), DELTA)
	var shifted: Vector3 = blocker.position
	field._squad_waypoints[0].clear()
	# The blocked squad keeps its own order while returning from the sidestep.
	for frame in range(100):
		field._process_squad_movement(DELTA)
		if blocker.position.distance_to(before) < 0.01:
			break
	if shifted.distance_to(before) < 0.1 or blocker.position.distance_to(before) > 0.01:
		failures.append("yielded unit did not return after the requester cleared")
	field.queue_free()
	await process_frame


func _check_entry_correction() -> void:
	var start := Vector3(-25, 0, -12)
	var near := Vector3(-23.2, 0, 15)
	var too_far_at_exit := Vector3(-23.0, 0, 15)
	var too_far_at_entry := Vector3(-22, 0, -12)
	var boundary := Vector3(-23.0714286, 0, 15)
	if PASSAGE.get_entry_correction(start, near, 1.0).is_empty() or PASSAGE.get_entry_correction(start, boundary, 1.0).is_empty():
		failures.append("valid entry correction was not selected")
	if not PASSAGE.get_entry_correction(start, too_far_at_exit, 1.0).is_empty() or not PASSAGE.get_entry_correction(too_far_at_entry, Vector3(-25, 0, 15), 1.0).is_empty():
		failures.append("entry correction ignored the tolerance at one opening")
	if not PASSAGE.get_entry_correction(start, near, 0.0).is_empty() or not PASSAGE.get_entry_correction(Vector3(0, 0, -12), Vector3(-21, 0, 15), 1.0).is_empty():
		failures.append("entry correction ignored a disabled setting or redirected a clear route")
	var cases := [
		{"start": start, "goal": near, "entry": Vector3(-25, 0.06, -7.65), "exit": Vector3(-25, 0.06, 10.25)},
		{"start": Vector3(-25, 0, 14), "goal": Vector3(-23, 0, -14), "entry": Vector3(-25, 0.06, 9.65), "exit": Vector3(-25, 0.06, -8.25)},
		{"start": Vector3(-23, 0, -12), "goal": Vector3(-25, 0, 0), "entry": Vector3(-25, 0.06, -7.65)},
	]
	for example in cases:
		var field = FIELD.instantiate()
		field.set_process(false)
		root.add_child(field)
		await physics_frame
		var start_point: Vector3 = example["start"]
		var target: Vector3 = example["goal"]
		var mates: Array = field._squad_mates[0]
		for i in range(3):
			mates[i].position = start_point + Vector3((i - 1) * 2.7, 0.04, 0)
		field._selected_squad_number = 1
		field._set_squad_waypoint(1, target, false)
		var vertices: PackedVector3Array = field._waypoint_origin_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var expected_size := 6 if example.has("exit") else 4
		if vertices.size() != expected_size or not vertices[1].is_equal_approx(example["entry"]) or (example.has("exit") and not vertices[3].is_equal_approx(example["exit"])) or not vertices[expected_size - 1].is_equal_approx(target + Vector3.UP * 0.06):
			failures.append("entry correction preview did not show anchors and the original waypoint: %s" % example)
		var completed := false
		var passed_entry_preview := false
		for frame in range(9000):
			field._process_squad_movement(DELTA)
			for mate in mates:
				mate._process(DELTA)
			var point: Vector3 = field.get_squad_point(1)
			if not passed_entry_preview and field._squad_passages[0] != null and point.z > -6.8 and point.z < 8.8:
				field._refresh_waypoint_origin_visual()
				var remaining: PackedVector3Array = field._waypoint_origin_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var expected_remaining := 4 if example.has("exit") else 2
				if remaining.size() != expected_remaining or (example.has("exit") and not remaining[1].is_equal_approx(example["exit"])):
					failures.append("passed entry remained in the displayed route: %s" % example)
				passed_entry_preview = true
			if field._squad_blocked[0]:
				break
			if field._squad_waypoints[0].is_empty():
				completed = true
				break
			if field._squad_waypoints[0][0] != target:
				failures.append("entry correction changed the waypoint")
				break
		if not completed:
			failures.append("entry correction failed to reach the original waypoint: %s" % example)
		if not passed_entry_preview:
			failures.append("entry correction did not reach the passage for preview: %s" % example)
		field.queue_free()
		await process_frame
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	for i in range(3):
		field._squad_mates[0][i].position = start + Vector3((i - 1) * 2.7, 0.04, 0)
	field._set_squad_waypoint(1, too_far_at_exit, false)
	field._process_squad_movement(DELTA)
	if not field._squad_blocked[0] or field._squad_passages[0] != null:
		failures.append("entry correction outside the limit was not blocked")
	field.queue_free()
	await process_frame


func _check_entry_correction_obstacles() -> void:
	for obstacle_position in [Vector3(-25, 1.5, -9.5), Vector3(-24.1, 1.5, 12.6)]:
		var field = FIELD.instantiate()
		field.set_process(false)
		root.add_child(field)
		var obstacle := StaticBody3D.new()
		obstacle.collision_layer = 1
		obstacle.position = obstacle_position
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 3.0, 1.0)
		shape.shape = box
		obstacle.add_child(shape)
		field.add_child(obstacle)
		await physics_frame
		for i in range(3):
			field._squad_mates[0][i].position = Vector3(-25 + (i - 1) * 2.7, 0.04, -12)
		field._set_squad_waypoint(1, Vector3(-23.2, 0, 15), false)
		field._process_squad_movement(DELTA)
		if not field._squad_blocked[0] or field._squad_passages[0] != null:
			failures.append("obstacle at %s did not block the corrected entry route" % obstacle_position)
		field.queue_free()
		await process_frame


func _check_entry_correction_queued() -> void:
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	for i in range(3):
		field._squad_mates[0][i].position = Vector3(-25 + (i - 1) * 2.7, 0.04, -20)
	field._selected_squad_number = 1
	var target := Vector3(-23.2, 0, 15)
	field._set_squad_waypoint(1, Vector3(-25, 0, -12), false)
	field._set_squad_waypoint(1, target, true)
	var vertices: PackedVector3Array = field._waypoint_visual_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if vertices.size() < 38 or not vertices[33].is_equal_approx(Vector3(-25, 0.06, -7.65)) or not vertices[35].is_equal_approx(Vector3(-25, 0.06, 10.25)) or not vertices[37].is_equal_approx(target + Vector3.UP * 0.06):
		failures.append("queued entry correction did not display both openings and the waypoint")
	var completed := false
	for frame in range(9000):
		field._process_squad_movement(DELTA)
		for mate in field._squad_mates[0]:
			mate._process(DELTA)
		if field._squad_blocked[0]:
			break
		if field._squad_waypoints[0].is_empty():
			completed = true
			break
	if not completed:
		failures.append("queued entry correction failed to reach the waypoint")
	field.queue_free()
	await process_frame


func _check_exit_correction() -> void:
	var origin := Vector3(-25, 0, 0)
	var near := Vector3(-22.4, 0, -14)
	var boundary := Vector3(-22.0, 0, -14)
	var outside := Vector3(-21.98, 0, -14)
	var far := Vector3(-15, 0, -14)
	var north := Vector3(-22.0, 0, 18)
	if PASSAGE.get_exit_correction(origin, near, 1.0).is_empty() or PASSAGE.get_exit_correction(origin, boundary, 1.0).is_empty() or PASSAGE.get_exit_correction(origin, north, 1.0).is_empty():
		failures.append("valid exit correction was not selected")
	if not PASSAGE.get_exit_correction(origin, outside, 1.0).is_empty() or not PASSAGE.get_exit_correction(origin, far, 1.0).is_empty() or not PASSAGE.get_exit_correction(origin, near, 0.0).is_empty() or not PASSAGE.get_exit_correction(origin, near, 0.25).is_empty():
		failures.append("exit correction exceeded its limit or was not disabled")
	if not PASSAGE.get_exit_correction(Vector3(-25, 0, -12), near, 1.0).is_empty():
		failures.append("exit correction was applied outside the passage")
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	var mates: Array = field._squad_mates[0]
	for i in range(mates.size()):
		mates[i].position = Vector3(-25, 0.04, (i - 1) * 1.1)
	field._selected_squad_number = 1
	field._set_squad_waypoint(1, near, false)
	var vertices: PackedVector3Array = field._waypoint_origin_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if vertices.size() != 4 or not vertices[1].is_equal_approx(Vector3(-25.0, 0.06, -8.25)) or not vertices[3].is_equal_approx(near + Vector3.UP * 0.06):
		failures.append("corrected route preview did not show the exit and original waypoint")
	var completed := false
	for frame in range(9000):
		field._process_squad_movement(DELTA)
		for mate in mates:
			mate._process(DELTA)
		if field._squad_blocked[0]:
			break
		if field._squad_waypoints[0].is_empty():
			completed = true
			break
		if field._squad_waypoints[0][0] != near:
			failures.append("exit correction changed the waypoint")
			break
	if not completed:
		failures.append("corrected route did not reach the original waypoint")
	field.queue_free()
	await process_frame
	field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	for i in range(3):
		field._squad_mates[0][i].position = Vector3(-25, 0.04, (i - 1) * 1.1)
	field._set_squad_waypoint(1, far, false)
	field._process_squad_movement(DELTA)
	if not field._squad_blocked[0] or field._squad_passages[0] != null:
		failures.append("route outside the correction limit was not blocked")
	field.passage_correction_tolerance = 0.25
	field._set_squad_waypoint(1, near, false)
	field._process_squad_movement(DELTA)
	if not field._squad_blocked[0] or field._squad_passages[0] != null:
		failures.append("inspector correction limit was not applied")
	field.queue_free()
	await process_frame
	field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	var obstacle := StaticBody3D.new()
	obstacle.collision_layer = 1
	obstacle.position = Vector3(-23.7, 1.5, -11.1)
	var obstacle_shape := CollisionShape3D.new()
	var obstacle_box := BoxShape3D.new()
	obstacle_box.size = Vector3(1.0, 3.0, 1.0)
	obstacle_shape.shape = obstacle_box
	obstacle.add_child(obstacle_shape)
	field.add_child(obstacle)
	await physics_frame
	for i in range(3):
		field._squad_mates[0][i].position = Vector3(-25, 0.04, (i - 1) * 1.1)
	field._set_squad_waypoint(1, near, false)
	field._process_squad_movement(DELTA)
	if not field._squad_blocked[0] or field._squad_passages[0] != null:
		failures.append("obstructed route beyond the corrected exit was not blocked")
	field.queue_free()
	await process_frame
	field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	for i in range(3):
		field._squad_mates[0][i].position = Vector3(-25 + (i - 1) * 2.7, 0.04, -12)
	field._selected_squad_number = 1
	field._set_squad_waypoint(1, origin, false)
	field._set_squad_waypoint(1, near, true)
	var queued_vertices: PackedVector3Array = field._waypoint_visual_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if queued_vertices.size() < 36 or not queued_vertices[33].is_equal_approx(Vector3(-25.0, 0.06, -8.25)) or not queued_vertices[35].is_equal_approx(near + Vector3.UP * 0.06):
		failures.append("queued route did not display the corrected exit")
	completed = false
	for frame in range(9000):
		field._process_squad_movement(DELTA)
		for mate in field._squad_mates[0]:
			mate._process(DELTA)
		if field._squad_blocked[0]:
			break
		if field._squad_waypoints[0].is_empty():
			completed = true
			break
	if not completed:
		failures.append("queued corrected route did not reach the original waypoint")
	field.queue_free()
	await process_frame
	field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	for i in range(3):
		field._squad_mates[0][i].position = Vector3(-25, 0.04, (i - 1) * 1.1)
	field._set_squad_waypoint(1, north, false)
	completed = false
	for frame in range(9000):
		field._process_squad_movement(DELTA)
		for mate in field._squad_mates[0]:
			mate._process(DELTA)
		if field._squad_blocked[0]:
			break
		if field._squad_waypoints[0].is_empty():
			completed = true
			break
	if not completed:
		failures.append("northbound correction did not reach the original waypoint; blocked=%s positions=%s passage=%s" % [field._squad_blocked[0], field._squad_mates[0].map(func(mate): return mate.position), field._squad_passages[0].members if field._squad_passages[0] != null else null])
	field.queue_free()
	await process_frame


func _check_route_classification() -> void:
	var normal := PASSAGE.classify_route(Vector3(0, 0, -12), Vector3(-21, 0, 15))
	var wall := PASSAGE.classify_route(Vector3(-16.3, 0, -4), Vector3(-25, 0, 15))
	var through := PASSAGE.classify_route(Vector3(-25, 0, -12), Vector3(-25, 0, 15))
	var inside := PASSAGE.classify_route(Vector3(-25, 0, -12), Vector3(-25, 0, 0))
	if normal != PASSAGE.RouteKind.NORMAL or wall != PASSAGE.RouteKind.BLOCKED or through != PASSAGE.RouteKind.PASSAGE or inside != PASSAGE.RouteKind.PASSAGE:
		failures.append("incorrect route classification: %s" % [[normal, wall, through, inside]])
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	for i in range(3):
		field._squad_mates[0][i].position = Vector3((i - 1) * 2.7, 0.04, -12.0)
		field._squad_mates[1][i].position = Vector3(22.0 + i * 2.0, 0.04, -25.0)
		field._squad_mates[2][i].position = Vector3(22.0 + i * 2.0, 0.04, -22.0)
	field._squad_waypoints[0].append(Vector3(-21, 0, 15))
	var completed := false
	var selected_passage := false
	for frame in range(5000):
		field._process_squad_movement(DELTA)
		for mate in field._squad_mates[0]:
			mate._process(DELTA)
		selected_passage = selected_passage or field._squad_passages[0] != null
		if field._squad_blocked[0]:
			break
		if field._squad_waypoints[0].is_empty():
			completed = true
			break
	if selected_passage or not completed:
		failures.append("unobstructed route incorrectly selected the passage")
	field.queue_free()
	await process_frame


func _check_passage(reverse_midway: bool, reverse_at: float = -3.0) -> void:
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	var mates: Array = field._squad_mates[0]
	for i in range(mates.size()):
		mates[i].position = Vector3(-25.0 + (i - 1) * 2.7, 0.04, -12.0)
	field._squad_waypoints[0].append(Vector3(-25.0, 0.0, 15.0))
	var reversed := false
	var all_crossed := false
	var first_entered := -1
	var released := false
	var follower_approached := false
	for frame in range(9000):
		field._process_squad_movement(DELTA)
		for mate in mates:
			mate._process(DELTA)
		for i in range(mates.size()):
			for j in range(i + 1, mates.size()):
				if Vector2(mates[i].position.x, mates[i].position.z).distance_to(Vector2(mates[j].position.x, mates[j].position.z)) < 0.69:
					failures.append("units overlap at frame %d" % frame)
					field.queue_free()
					return
		if bool(field._squad_blocked[0]):
			failures.append("passage became blocked at frame %d" % frame)
			break
		if first_entered < 0:
			if mates[0].position.distance_to(Vector3(-27.7, 0.04, -12.0)) > 0.25 or mates[2].position.distance_to(Vector3(-22.3, 0.04, -12.0)) > 0.25:
				follower_approached = true
			for i in range(mates.size()):
				if mates[i].position.z > -7.0:
					first_entered = i
					break
		if reverse_midway and not reversed:
			for mate in mates:
				if mate.position.z > reverse_at:
					field._squad_waypoints[0].clear()
					field._squad_waypoints[0].append(Vector3(-25.0, 0.0, -14.0))
					reversed = true
					break
		if field._squad_passages[0] == null and (not reverse_midway or reversed):
			all_crossed = true
			for mate in mates:
				if (not reverse_midway and mate.position.z < 9.0) or (reverse_midway and mate.position.z > -7.0):
					all_crossed = false
			if all_crossed:
				released = true
		if released and field._squad_waypoints[0].is_empty():
			break
	if not all_crossed:
		var positions: Array = []
		for mate in mates:
			positions.append(mate.position)
		failures.append("passage did not finish (reverse=%s at %.1f, positions=%s)" % [reverse_midway, reverse_at, positions])
		if field._squad_passages[0] != null:
			for state in field._squad_passages[0].members:
				print("passage debug: phase=", state.phase, " slot=", state.slot, " path=", state.path)
	if first_entered != 1:
		failures.append("closest unit did not enter first: %d" % first_entered)
	if not follower_approached:
		failures.append("followers did not approach while the leading unit approached")
	if not field._squad_waypoints[0].is_empty():
		failures.append("squad did not resume its waypoint after passage (reverse=%s)" % reverse_midway)
	field.queue_free()
	await process_frame


func _check_side_approach() -> void:
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	var mates: Array = field._squad_mates[0]
	for i in range(mates.size()):
		mates[i].position = Vector3(-19.0 + i * 2.7, 0.04, -4.0)
	field._squad_waypoints[0].append(Vector3(-25.0, 0.0, 15.0))
	field._process_squad_movement(DELTA)
	if not field._squad_blocked[0] or field._squad_passages[0] != null:
		failures.append("side-wall route should be blocked instead of routing around the wall")
	field._squad_waypoints[0].clear()
	field._set_squad_blocked(0, false)
	field._squad_waypoints[0].append(Vector3(-17.0, 0.0, -11.0))
	field._squad_waypoints[0].append(Vector3(-25.0, 0.0, -11.0))
	field._squad_waypoints[0].append(Vector3(-25.0, 0.0, 15.0))
	var entered: Array = []
	var finished := false
	for frame in range(12000):
		field._process_squad_movement(DELTA)
		for i in range(mates.size()):
			var mate = mates[i]
			mate._process(DELTA)
			if mate.position.z > -7.0 and absf(mate.position.x + 25.0) < 0.5 and not entered.has(i):
				entered.append(i)
		if bool(field._squad_blocked[0]):
			break
		if field._squad_waypoints[0].is_empty():
			finished = true
			break
	if not finished or entered.size() != 3:
		var positions: Array = []
		for mate in mates:
			positions.append(mate.position)
		failures.append("side approach failed: finished=%s entered=%s positions=%s" % [finished, entered, positions])
	field.queue_free()
	await process_frame


func _check_blocked_terrain() -> void:
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	var obstacle := StaticBody3D.new()
	obstacle.collision_layer = 1
	obstacle.position = Vector3(-25.0, 1.5, 1.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 3.0, 1.0)
	shape.shape = box
	obstacle.add_child(shape)
	field.add_child(obstacle)
	await physics_frame
	var mates: Array = field._squad_mates[0]
	for i in range(mates.size()):
		mates[i].position = Vector3(-25.0 + (i - 1) * 2.7, 0.04, -12.0)
	field._squad_waypoints[0].append(Vector3(-25.0, 0.0, 15.0))
	field._process_squad_movement(DELTA)
	if not field._squad_blocked[0] or mates[1].position.z != -12.0:
		failures.append("blocked passage was not detected before entering")
	field.queue_free()
	await process_frame


func _check_reissue_blocked_waypoint() -> void:
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	var obstacle := StaticBody3D.new()
	obstacle.collision_layer = 1
	obstacle.position = Vector3(-25.0, 1.5, 1.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 3.0, 1.0)
	shape.shape = box
	obstacle.add_child(shape)
	field.add_child(obstacle)
	await physics_frame
	for i in range(3):
		field._squad_mates[0][i].position = Vector3(-25.0 + (i - 1) * 2.7, 0.04, -12.0)
	var target := Vector3(-25.0, 0.0, 15.0)
	field._set_squad_waypoint(1, target, false)
	field._process_squad_movement(DELTA)
	var old_plan = field._squad_passages[0]
	if old_plan == null or not field._squad_blocked[0]:
		failures.append("reissue setup did not report blocked terrain")
		field.queue_free()
		return
	field._set_squad_waypoint(1, target, false)
	field._process_squad_movement(DELTA)
	if field._squad_passages[0] == old_plan or not field._squad_blocked[0]:
		failures.append("same blocked waypoint did not create a fresh plan")
	old_plan = field._squad_passages[0]
	obstacle.queue_free()
	await process_frame
	await physics_frame
	field._set_squad_waypoint(1, target, false)
	var completed := false
	for frame in range(9000):
		field._process_squad_movement(DELTA)
		for mate in field._squad_mates[0]:
			mate._process(DELTA)
		if field._squad_blocked[0]:
			break
		if field._squad_waypoints[0].is_empty():
			completed = true
			break
	if field._squad_passages[0] == old_plan or not completed:
		failures.append("same waypoint did not recover after the obstacle was removed")
	field.queue_free()
	await process_frame


func _check_reissue_during_passage() -> void:
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	for i in range(3):
		field._squad_mates[0][i].position = Vector3(-25.0 + (i - 1) * 2.7, 0.04, -12.0)
	var target := Vector3(-25.0, 0.0, 15.0)
	field._set_squad_waypoint(1, target, false)
	var reissued := false
	var completed := false
	var old_plan = null
	for frame in range(9000):
		field._process_squad_movement(DELTA)
		for mate in field._squad_mates[0]:
			mate._process(DELTA)
			if not reissued and mate.position.z > -3.0:
				old_plan = field._squad_passages[0]
				field._set_squad_waypoint(1, target, false)
				reissued = true
		if field._squad_blocked[0]:
			break
		if reissued and field._squad_waypoints[0].is_empty():
			completed = true
			break
	if not reissued or not completed or field._squad_passages[0] == old_plan:
		failures.append("same waypoint could not be replanned during passage")
	field.queue_free()
	await process_frame


func _check_repeated_passages(delta: float = DELTA) -> void:
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	var mates: Array = field._squad_mates[0]
	for i in range(mates.size()):
		mates[i].position = Vector3(-25.0 + (i - 1) * 2.7, 0.04, -12.0)
	for trip in range(9):
		var target_z := 16.0 if trip % 2 == 0 else -15.0
		var target_x := -25.0
		field._squad_waypoints[0].clear()
		field._squad_waypoints[0].append(Vector3(target_x, 0.0, target_z))
		var complete := false
		for frame in range(9000):
			field._process_squad_movement(delta)
			for mate in mates:
				mate._process(delta)
			for i in range(mates.size()):
				for j in range(i + 1, mates.size()):
					var a := Vector2(mates[i].position.x, mates[i].position.z)
					var b := Vector2(mates[j].position.x, mates[j].position.z)
					var minimum := 0.99 if field._squad_passages[0] != null else 0.69
					if a.distance_to(b) < minimum:
						failures.append("repeated trip %d: units overlap at frame %d" % [trip, frame])
						field.queue_free()
						return
			if field._squad_waypoints[0].is_empty():
				complete = true
				break
		if not complete:
			var positions: Array = []
			for mate in mates:
				positions.append(mate.position)
			failures.append("repeated trip %d at delta %.3f stopped: %s" % [trip, delta, positions])
			if field._squad_passages[0] != null:
				for state in field._squad_passages[0].members:
					print("repeat debug ", state.mate.name, " phase=", state.phase, " target=", state.planned_target, " path=", state.path)
			break
	field.queue_free()
	await process_frame


func _check_stop_inside(target_z: float, from_back: bool, resume_z: float = 15.0) -> void:
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	var mates: Array = field._squad_mates[0]
	for i in range(mates.size()):
		mates[i].position = Vector3(-25.0 + (i - 1) * 2.7, 0.04, 14.0 if from_back else -12.0)
	field._squad_waypoints[0].append(Vector3(-25.0, 0.0, target_z))
	var stopped := false
	for frame in range(9000):
		field._process_squad_movement(DELTA)
		for mate in mates:
			mate._process(DELTA)
		if field._squad_waypoints[0].is_empty() and field._squad_passages[0] == null:
			stopped = true
			break
		if field._squad_blocked[0]:
			break
	if stopped:
		for mate in mates:
			if absf(mate.position.x + 25.0) > 0.2 or mate.position.z < -7.0 or mate.position.z > 9.0:
				stopped = false
		for i in range(mates.size()):
			for j in range(i + 1, mates.size()):
				if mates[i].position.distance_to(mates[j].position) < 0.99:
					stopped = false
	if not stopped:
		var positions: Array = []
		for mate in mates:
			positions.append(mate.position)
		failures.append("stop in passage failed at %.1f from_back=%s: %s" % [target_z, from_back, positions])
	else:
		field._squad_waypoints[0].append(Vector3(-25.0, 0.0, resume_z))
		var resumed := false
		for frame in range(9000):
			field._process_squad_movement(DELTA)
			for mate in mates:
				mate._process(DELTA)
			if field._squad_waypoints[0].is_empty():
				resumed = true
				break
			if field._squad_blocked[0]:
				break
		if not resumed:
			var positions: Array = []
			for mate in mates:
				positions.append(mate.position)
			failures.append("resume after stopping at %.1f towards %.1f failed: %s" % [target_z, resume_z, positions])
	field.queue_free()
	await process_frame


func _check_retarget_inside(trigger_z: float, target_z: float) -> void:
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	var mates: Array = field._squad_mates[0]
	for i in range(mates.size()):
		mates[i].position = Vector3(-25.0 + (i - 1) * 2.7, 0.04, -12.0)
	field._squad_waypoints[0].append(Vector3(-25.0, 0.0, 15.0))
	var changed := false
	var completed := false
	for frame in range(9000):
		field._process_squad_movement(DELTA)
		for mate in mates:
			mate._process(DELTA)
			if not changed and mate.position.z > trigger_z:
				field._squad_waypoints[0].clear()
				field._squad_waypoints[0].append(Vector3(-25.0, 0.0, target_z))
				changed = true
		if changed and field._squad_waypoints[0].is_empty():
			completed = true
			break
		if field._squad_blocked[0]:
			break
	if not completed:
		var positions: Array = []
		for mate in mates:
			positions.append(mate.position)
		failures.append("retarget inside to %.1f at %.1f failed: %s" % [target_z, trigger_z, positions])
	field.queue_free()
	await process_frame


func _check_inside_then_exit_queued() -> void:
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	var mates: Array = field._squad_mates[0]
	for i in range(mates.size()):
		mates[i].position = Vector3(-25.0 + (i - 1) * 2.7, 0.04, -12.0)
	field._squad_waypoints[0].append(Vector3(-25.0, 0.0, 0.0))
	field._squad_waypoints[0].append(Vector3(-25.0, 0.0, 15.0))
	var lined_up := false
	var complete := false
	for frame in range(9000):
		field._process_squad_movement(DELTA)
		for mate in mates:
			mate._process(DELTA)
		if not lined_up and field._squad_waypoints[0].size() == 1:
			lined_up = true
			for mate in mates:
				if absf(mate.position.x + 25.0) > 0.2 or absf(mate.position.z) > 1.3:
					lined_up = false
		if field._squad_waypoints[0].is_empty():
			complete = true
			break
		if field._squad_blocked[0]:
			break
	if not lined_up or not complete:
		failures.append("queued inside waypoint did not line up and then exit")
	field.queue_free()
	await process_frame


func _check_stop_before_obstacle() -> void:
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	var obstacle := StaticBody3D.new()
	obstacle.collision_layer = 1
	obstacle.position = Vector3(-25.0, 1.5, 5.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 3.0, 1.0)
	shape.shape = box
	obstacle.add_child(shape)
	field.add_child(obstacle)
	await physics_frame
	var mates: Array = field._squad_mates[0]
	for i in range(mates.size()):
		mates[i].position = Vector3(-25.0 + (i - 1) * 2.7, 0.04, -12.0)
	field._squad_waypoints[0].append(Vector3(-25.0, 0.0, 0.0))
	var stopped := false
	for frame in range(9000):
		field._process_squad_movement(DELTA)
		for mate in mates:
			mate._process(DELTA)
		if field._squad_waypoints[0].is_empty():
			stopped = true
			break
		if field._squad_blocked[0]:
			break
	if not stopped:
		failures.append("terrain beyond an inside waypoint blocked the approach")
	field.queue_free()
	await process_frame


func _check_inside_reposition() -> void:
	var field = FIELD.instantiate()
	field.set_process(false)
	root.add_child(field)
	await physics_frame
	var mates: Array = field._squad_mates[0]
	for i in range(mates.size()):
		mates[i].position = Vector3(-25.0, 0.04, -1.1 + i * 1.1)
	for target_z in [4.0, -4.0]:
		field._squad_waypoints[0].append(Vector3(-25.0, 0.0, target_z))
		var completed := false
		for frame in range(9000):
			field._process_squad_movement(DELTA)
			for mate in mates:
				mate._process(DELTA)
			if field._squad_waypoints[0].is_empty():
				completed = true
				break
			if field._squad_blocked[0]:
				break
		if not completed or absf(field.get_squad_point(1).z - target_z) > 0.2:
			failures.append("reposition inside to %.1f failed" % target_z)
			break
	field.queue_free()
	await process_frame
