extends RefCounted

# This test passage is defined by the two walls in TestField. The entry and exit
# remain mandatory route points so that pathfinding cannot bypass the passage.
const CENTER_X := -25.0
const FRONT_Z := -7.0
const BACK_Z := 9.0
const BODY_RADIUS := 0.35
const CLEARANCE := 0.12
const UNIT_CLEARANCE := 1.0
const POINT_EPSILON := 0.04
enum RouteKind { NORMAL, PASSAGE, BLOCKED }

var field: Node3D
var waypoint: Vector3
var direction: float
var entry: Vector3
var exit_point: Vector3
var members: Array = []
var failed_reason := ""
var stop_inside := false
var replan_requested := false
var route_correction: Dictionary = {}
var wait_point: Variant = null


func _init(owner: Node3D, destination: Vector3, squad: Array, previous = null) -> void:
	field = owner
	waypoint = destination
	stop_inside = absf(destination.x - CENTER_X) < 0.5 and destination.z > FRONT_Z and destination.z < BACK_Z
	var average_z := 0.0
	var living_count := 0
	for mate in squad:
		if mate != null and mate.is_alive():
			average_z += mate.position.z
			living_count += 1
	if living_count > 0:
		average_z /= living_count
	direction = 1.0 if (destination.z >= average_z if stop_inside else destination.z > (FRONT_Z + BACK_Z) * 0.5) else -1.0
	var entry_z := FRONT_Z if direction > 0.0 else BACK_Z
	var exit_z := BACK_Z if direction > 0.0 else FRONT_Z
	entry = Vector3(CENTER_X, 0.0, entry_z - direction * 0.65)
	exit_point = Vector3(CENTER_X, 0.0, exit_z + direction * 1.25)
	var living: Array = []
	for mate in squad:
		if mate != null and mate.is_alive():
			living.append(mate)
	# On a reversal, units already on the destination side clear the exit first.
	var destination_side := exit_z
	living.sort_custom(func(a, b):
		var a_past: bool = direction * (a.position.z - destination_side) > 0.0
		var b_past: bool = direction * (b.position.z - destination_side) > 0.0
		if a_past != b_past:
			return a_past
		var a_inside: bool = a.position.z > FRONT_Z and a.position.z < BACK_Z and absf(a.position.x - CENTER_X) < 0.5
		var b_inside: bool = b.position.z > FRONT_Z and b.position.z < BACK_Z and absf(b.position.x - CENTER_X) < 0.5
		if a_inside != b_inside:
			return a_inside
		if a_inside and b_inside:
			return direction * a.position.z > direction * b.position.z
		if previous != null and not a_past:
			return direction * a.position.z > direction * b.position.z
		return a.position.distance_squared_to(entry) < b.position.distance_squared_to(entry)
	)
	for i in range(living.size()):
		var mate = living[i]
		var already_out: bool = not stop_inside and direction * (mate.position.z - exit_z) > BODY_RADIUS
		var inside: bool = mate.position.z > FRONT_Z and mate.position.z < BACK_Z and absf(mate.position.x - CENTER_X) < 0.5
		var phase := 2 if already_out else (1 if inside else 0)
		members.append({"mate": mate, "phase": phase, "path": [], "slot": Vector3.ZERO, "retry": 0.0, "planned_target": null})
	_assign_slots()
	for state in members:
		if int(state["phase"]) == 2:
			continue
		var mate = state["mate"]
		var start: Vector3 = mate.position if int(state["phase"]) == 1 else entry
		var finish: Vector3 = state["slot"] if stop_inside else exit_point
		start.y = mate.position.y
		finish.y = start.y
		if not _segment_clear(mate, start, finish, false, false):
			failed_reason = "passage is blocked by terrain"
			break


func _assign_slots() -> void:
	var spacing := UNIT_CLEARANCE + 0.1
	if stop_inside:
		var half_length := float(maxi(members.size() - 1, 0)) * spacing * 0.5
		var stop_center := clampf(waypoint.z, FRONT_Z + BODY_RADIUS + CLEARANCE + half_length, BACK_Z - BODY_RADIUS - CLEARANCE - half_length)
		for i in range(members.size()):
			var mate = members[i]["mate"]
			members[i]["slot"] = Vector3(CENTER_X, mate.position.y, stop_center + direction * (half_length - float(i) * spacing))
		return
	var slots: Array[Vector3] = [
		Vector3(CENTER_X - 2.2, 0.0, exit_point.z),
		Vector3(CENTER_X + 2.2, 0.0, exit_point.z),
		Vector3(CENTER_X, 0.0, exit_point.z + direction * spacing),
	]
	# Units already outside retain the nearest free position, avoiding a
	# circular wait when an earlier unit's target is occupied by a later one.
	var already_out: Array = []
	for state in members:
		if int(state["phase"]) == 2:
			already_out.append(state)
	while not already_out.is_empty():
		var best_state := 0
		var best_slot := 0
		var best_distance := INF
		for i in range(already_out.size()):
			for j in range(slots.size()):
				var distance: float = already_out[i]["mate"].position.distance_squared_to(slots[j])
				if distance < best_distance:
					best_distance = distance
					best_state = i
					best_slot = j
		var state: Dictionary = already_out.pop_at(best_state)
		var slot: Vector3 = slots.pop_at(best_slot)
		slot.y = state["mate"].position.y
		state["slot"] = slot
	for state in members:
		if int(state["phase"]) == 2:
			continue
		var mate = state["mate"]
		var slot: Vector3 = slots.pop_front()
		slot.y = mate.position.y
		state["slot"] = slot


static func classify_route(squad_point: Vector3, destination: Vector3) -> RouteKind:
	# This test passage has two 4-unit-wide walls. Classify the player's actual
	# segment, not merely the area containing its destination.
	var start := Vector2(squad_point.x, squad_point.z)
	var finish := Vector2(destination.x, destination.z)
	var west_wall := Rect2(Vector2(CENTER_X - 4.5, FRONT_Z), Vector2(4.0, BACK_Z - FRONT_Z))
	var east_wall := Rect2(Vector2(CENTER_X + 0.5, FRONT_Z), Vector2(4.0, BACK_Z - FRONT_Z))
	if _segment_intersects_rect(start, finish, west_wall) or _segment_intersects_rect(start, finish, east_wall):
		return RouteKind.BLOCKED
	var passage := Rect2(Vector2(CENTER_X - 0.5, FRONT_Z), Vector2(1.0, BACK_Z - FRONT_Z))
	if _segment_intersects_rect(start, finish, passage):
		return RouteKind.PASSAGE
	return RouteKind.NORMAL


static func get_exit_correction(origin: Vector3, destination: Vector3, tolerance: float) -> Dictionary:
	# Assistance applies only when a unit is already inside and the direct
	# segment clips a side wall while aiming just outside an exit opening.
	if tolerance <= 0.0 or absf(origin.x - CENTER_X) >= 0.5 or origin.z <= FRONT_Z or origin.z >= BACK_Z:
		return {}
	if classify_route(origin, destination) != RouteKind.BLOCKED:
		return {}
	var exit_z: float
	var direction: float
	if destination.z < FRONT_Z:
		exit_z = FRONT_Z
		direction = -1.0
	elif destination.z > BACK_Z:
		exit_z = BACK_Z
		direction = 1.0
	else:
		return {}
	var progress := (exit_z - origin.z) / (destination.z - origin.z)
	var exit_x := lerpf(origin.x, destination.x, progress)
	var outside_opening := absf(exit_x - CENTER_X) - 0.5
	if outside_opening <= 0.0 or outside_opening > tolerance + 0.00001:
		return {}
	var corrected_exit := Vector3(CENTER_X, destination.y, exit_z + direction * 1.25)
	if classify_route(corrected_exit, destination) == RouteKind.BLOCKED:
		return {}
	return {"exit": corrected_exit}


static func get_entry_correction(origin: Vector3, destination: Vector3, tolerance: float) -> Dictionary:
	# Apply the same doorway tolerance to approaches from outside the passage.
	# Both crossings must remain close enough when the goal is beyond the exit.
	if tolerance <= 0.0 or classify_route(origin, destination) != RouteKind.BLOCKED:
		return {}
	var direction: float
	var entry_z: float
	var exit_z: float
	if origin.z < FRONT_Z:
		direction = 1.0
		entry_z = FRONT_Z
		exit_z = BACK_Z
	elif origin.z > BACK_Z:
		direction = -1.0
		entry_z = BACK_Z
		exit_z = FRONT_Z
	else:
		return {}
	var destination_inside := destination.z > FRONT_Z and destination.z < BACK_Z and absf(destination.x - CENTER_X) < 0.5
	var destination_beyond := direction * (destination.z - exit_z) > 0.0
	if not destination_inside and not destination_beyond:
		return {}
	var delta_z := destination.z - origin.z
	if is_zero_approx(delta_z):
		return {}
	var entry_progress := (entry_z - origin.z) / delta_z
	var entry_x := lerpf(origin.x, destination.x, entry_progress)
	if absf(entry_x - CENTER_X) - 0.5 > tolerance + 0.00001:
		return {}
	var correction := {"entry": Vector3(CENTER_X, destination.y, entry_z - direction * 0.65)}
	if destination_beyond:
		var exit_progress := (exit_z - origin.z) / delta_z
		var exit_x := lerpf(origin.x, destination.x, exit_progress)
		if absf(exit_x - CENTER_X) - 0.5 > tolerance + 0.00001:
			return {}
		correction["exit"] = Vector3(CENTER_X, destination.y, exit_z + direction * 1.25)
	return correction


static func _segment_intersects_rect(start: Vector2, finish: Vector2, rect: Rect2) -> bool:
	if rect.has_point(start) or rect.has_point(finish):
		return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in range(corners.size()):
		if Geometry2D.segment_intersects_segment(start, finish, corners[i], corners[(i + 1) % corners.size()]) != null:
			return true
	return false


func process(delta: float) -> bool:
	if not failed_reason.is_empty():
		return false
	var alive := 0
	var finished := 0
	for i in range(members.size()):
		var state: Dictionary = members[i]
		var mate = state["mate"]
		if not is_instance_valid(mate) or not mate.is_alive():
			continue
		alive += 1
		if int(state["phase"]) >= 3:
			finished += 1
			continue
		var phase: int = state["phase"]
		# Do not let the next unit occupy the exit while its predecessor is
		# still moving aside. Units already outside may move independently so
		# they can clear each other's parking targets after replanning.
		if not stop_inside and i > 0 and phase == 1:
			var predecessor: Dictionary = members[i - 1]
			var predecessor_mate = predecessor["mate"]
			if is_instance_valid(predecessor_mate) and predecessor_mate.is_alive() and int(predecessor["phase"]) == 2:
				continue
		var target: Vector3 = entry if phase == 0 else (state["slot"] if stop_inside or phase == 2 else exit_point)
		# Followers approach while the predecessor is still on its way. They hold
		# a short queue position until that predecessor reaches the entrance.
		var holding: bool = phase == 0 and i > 0 and int(members[i - 1]["phase"]) == 0 and members[i - 1]["mate"].is_alive()
		if holding:
			target.z -= direction * float(i) * (UNIT_CLEARANCE + 0.1)
		target.y = mate.position.y
		if state["planned_target"] != target:
			state["path"] = []
			state["planned_target"] = target
			state["retry"] = 0.0
		if mate.position.distance_to(target) <= POINT_EPSILON:
			if holding:
				continue
			state["phase"] = 3 if stop_inside and phase == 1 else phase + 1
			state["path"] = []
			if phase == 2 or (stop_inside and phase == 1):
				finished += 1
			continue
		state["retry"] = maxf(0.0, float(state["retry"]) - delta)
		var path: Array = state["path"]
		if path.is_empty():
			if not stop_inside:
				field._request_stationary_ally_yield(field._squad_passages.find(self), mate, target, delta, self)
			if float(state["retry"]) > 0.0:
				continue
			if phase == 1:
				# The reserved centre line is mandatory. A unit ahead makes the
				# follower wait; it must never route around the outside wall.
				path = [target]
			else:
				path = _find_path(mate, target, true, true)
			if path.is_empty():
				# A temporary unit obstruction is a wait, not terrain BLOCKED.
				if _find_path(mate, target, false, true).is_empty():
					failed_reason = "no walking path to passage point %s" % target
				else:
					state["retry"] = 0.2
				continue
			state["path"] = path
		var next: Vector3 = path[0]
		var offset: Vector3 = next - mate.position
		offset.y = 0.0
		if offset.length() <= POINT_EPSILON:
			path.pop_front()
			continue
		var target_heading := atan2(offset.x, offset.z)
		var difference: float = wrapf(target_heading - mate.rotation.y, -PI, PI)
		var turn_speed: float = deg_to_rad(field.squad_turn_speed_degrees_per_second)
		if absf(difference) > deg_to_rad(1.0):
			var turn: float = clampf(difference, -turn_speed * delta, turn_speed * delta)
			mate.rotation.y = wrapf(mate.rotation.y + turn, -PI, PI)
			mate.set_turn_debug_values(target_heading, rad_to_deg(turn / maxf(delta, 0.001)))
			mate.set_standing_turn(true)
			continue
		mate.set_standing_turn(false)
		if mate.is_standing_turn_animating():
			continue
		var step: Vector3 = offset.normalized() * minf(offset.length(), field.squad_move_speed * delta)
		if holding:
			var predecessor = members[i - 1]["mate"]
			var predecessor_distance: float = Vector2(predecessor.position.x - entry.x, predecessor.position.z - entry.z).length()
			var next_position: Vector3 = mate.position + step
			var next_distance := Vector2(next_position.x - entry.x, next_position.z - entry.z).length()
			var current_distance := Vector2(mate.position.x - entry.x, mate.position.z - entry.z).length()
			# A follower must not take an entrance-side position in front of
			# its predecessor while their individual approaches converge.
			if next_distance < predecessor_distance + UNIT_CLEARANCE and next_distance < current_distance:
				continue
		var blocked: String = field._get_walk_blocking_reason(mate, step)
		if not blocked.is_empty():
			if not stop_inside:
				field._request_stationary_ally_yield(field._squad_passages.find(self), mate, target, delta, self)
			if phase == 1 and blocked.begins_with("world collider"):
				failed_reason = blocked
			state["path"] = []
			state["retry"] = 0.2
			continue
		if not _segment_clear(mate, mate.position, mate.position + step, true, false):
			if not stop_inside:
				field._request_stationary_ally_yield(field._squad_passages.find(self), mate, target, delta, self)
			state["path"] = []
			state["retry"] = 0.2
			continue
		mate.position += step
		mate.set_walking(true, field.squad_move_speed)
	if alive != finished or alive == 0:
		return false
	# Restore a shared heading before handing movement back to the squad.
	var positions: Array[Vector2] = []
	for state in members:
		var mate = state["mate"]
		if is_instance_valid(mate) and mate.is_alive():
			positions.append(Vector2(mate.position.x, mate.position.z))
	var center: Vector2 = field._minimum_enclosing_circle_center(positions)
	var heading := (0.0 if direction > 0.0 else PI) if stop_inside else atan2(waypoint.x - center.x, waypoint.z - center.y)
	var turning := false
	for state in members:
		var mate = state["mate"]
		if not is_instance_valid(mate) or not mate.is_alive():
			continue
		var difference: float = wrapf(heading - mate.rotation.y, -PI, PI)
		if absf(difference) > deg_to_rad(1.0):
			var turn: float = clampf(difference, -deg_to_rad(field.squad_turn_speed_degrees_per_second) * delta, deg_to_rad(field.squad_turn_speed_degrees_per_second) * delta)
			mate.rotation.y = wrapf(mate.rotation.y + turn, -PI, PI)
			mate.set_standing_turn(true)
			turning = true
		else:
			mate.rotation.y = heading
			mate.set_standing_turn(false)
			turning = turning or mate.is_standing_turn_animating()
	return not turning


func resume_from_wait() -> void:
	# Waiting moves the members independently, so the order calculated when
	# the route was first requested no longer describes the entrance approach.
	members.sort_custom(func(a, b):
		return a["mate"].position.distance_squared_to(entry) < b["mate"].position.distance_squared_to(entry)
	)
	_assign_slots()
	for state in members:
		state["path"] = []
		state["planned_target"] = null
		state["retry"] = 0.0
	# The original order is unchanged; these are temporary passage anchors.
	route_correction["entry"] = entry
	if not stop_inside:
		route_correction["exit"] = exit_point
	wait_point = null


func wait_for_access(delta: float, point: Vector3) -> void:
	# Keep each member in a separate slot and never use the reserved passage
	# while walking to the temporary waiting area.
	wait_point = point
	for i in range(members.size()):
		var state: Dictionary = members[i]
		var mate = state["mate"]
		if not is_instance_valid(mate) or not mate.is_alive():
			continue
		var target := point + Vector3(0.0, 0.0, (float(i) - float(members.size() - 1) * 0.5) * (UNIT_CLEARANCE + 0.3))
		target.y = mate.position.y
		if state.get("wait_target") != target:
			state["wait_target"] = target
			state["wait_path"] = []
			state["wait_retry"] = 0.0
		if mate.position.distance_to(target) <= POINT_EPSILON:
			continue
		state["wait_retry"] = maxf(0.0, float(state.get("wait_retry", 0.0)) - delta)
		var path: Array = state.get("wait_path", [])
		if path.is_empty():
			if float(state["wait_retry"]) > 0.0:
				continue
			path = _find_path(mate, target, true, true)
			if path.is_empty():
				state["wait_retry"] = 0.2
				continue
			state["wait_path"] = path
		var offset: Vector3 = path[0] - mate.position
		offset.y = 0.0
		if offset.length() <= POINT_EPSILON:
			path.pop_front()
			continue
		var heading := atan2(offset.x, offset.z)
		var difference: float = wrapf(heading - mate.rotation.y, -PI, PI)
		if absf(difference) > deg_to_rad(1.0):
			var turn: float = clampf(difference, -deg_to_rad(field.squad_turn_speed_degrees_per_second) * delta, deg_to_rad(field.squad_turn_speed_degrees_per_second) * delta)
			mate.rotation.y = wrapf(mate.rotation.y + turn, -PI, PI)
			mate.set_turn_debug_values(heading, rad_to_deg(turn / maxf(delta, 0.001)))
			mate.set_standing_turn(true)
			continue
		mate.set_standing_turn(false)
		if mate.is_standing_turn_animating():
			continue
		var step: Vector3 = offset.normalized() * minf(offset.length(), field.squad_move_speed * delta)
		if not field._can_walk_displacement(mate, step) or not _segment_clear(mate, mate.position, mate.position + step, true, true):
			state["wait_path"] = []
			state["wait_retry"] = 0.2
			continue
		mate.position += step
		mate.set_walking(true, field.squad_move_speed)


func _find_path(mate, target: Vector3, include_units: bool, avoid_passage: bool) -> Array:
	var points: Array[Vector3] = [mate.position, target]
	var extra := BODY_RADIUS + CLEARANCE
	# Candidate corners let the capsule go around each solid box, including the
	# test walls. A swept-capsule query validates every edge.
	for body in field.get_children():
		if not body is StaticBody3D or (body.collision_layer & 1) == 0:
			continue
		for child in body.get_children():
			if not child is CollisionShape3D or not child.shape is BoxShape3D:
				continue
			var box: BoxShape3D = child.shape
			var center: Vector3 = child.global_position
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					points.append(Vector3(center.x + sx * (box.size.x * 0.5 + extra), mate.position.y, center.z + sz * (box.size.z * 0.5 + extra)))
	if include_units:
		for squad in field._squad_mates:
			for other in squad:
				if other == null or other == mate or not other.is_alive() or absf(other.position.y - mate.position.y) >= field.WALK_BODY_HEIGHT:
					continue
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						points.append(other.position + Vector3(sx * 0.85, 0.0, sz * 0.85))
	var graph := AStar3D.new()
	for i in range(points.size()):
		graph.add_point(i, points[i])
	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			if _segment_clear(mate, points[i], points[j], include_units, avoid_passage):
				graph.connect_points(i, j)
	if not graph.are_points_connected(0, 1) and graph.get_point_connections(0).is_empty():
		return []
	var result := graph.get_point_path(0, 1)
	var path: Array = []
	for i in range(1, result.size()):
		path.append(result[i])
	return path


func _segment_clear(mate, from: Vector3, to: Vector3, include_units: bool, avoid_passage: bool) -> bool:
	if avoid_passage:
		var passage := Rect2(Vector2(CENTER_X - 0.5, FRONT_Z), Vector2(1.0, BACK_Z - FRONT_Z))
		var start := Vector2(from.x, from.z)
		var finish := Vector2(to.x, to.z)
		if _segment_intersects_rect(start, finish, passage):
			return false
	var shape := CapsuleShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = field.WALK_BODY_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, from + Vector3.UP * shape.height * 0.5)
	query.motion = to - from
	query.collision_mask = 1
	var space := field.get_world_3d().direct_space_state
	var result := space.cast_motion(query)
	if not result.is_empty() and result[0] < 1.0:
		return false
	query.motion = Vector3.ZERO
	query.transform.origin = to + Vector3.UP * shape.height * 0.5
	if not space.intersect_shape(query, 1).is_empty():
		return false
	if include_units:
		var start := Vector2(from.x, from.z)
		var segment := Vector2(to.x - from.x, to.z - from.z)
		for squad in field._squad_mates:
			for other in squad:
				if other == null or other == mate or not other.is_alive() or absf(other.position.y - from.y) >= field.WALK_BODY_HEIGHT:
					continue
				var other_point := Vector2(other.position.x, other.position.z)
				var initial_distance := start.distance_to(other_point)
				if initial_distance < UNIT_CLEARANCE and (other_point - start).dot(segment) <= 0.0 and (start + segment).distance_to(other_point) > initial_distance:
					continue
				var t := clampf((other_point - start).dot(segment) / maxf(segment.length_squared(), 0.00001), 0.0, 1.0)
				if (start + segment * t).distance_to(other_point) < UNIT_CLEARANCE:
					return false
	return true
