extends SceneTree

const FIELD := preload("res://Scenes/test_field.tscn")
const PASSAGE := preload("res://Scripts/World/narrow_passage.gd")
const DELTA := 1.0 / 60.0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
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
	if failures.is_empty():
		print("Narrow passage regression checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


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
