class_name JumpConnection
extends Node3D

@export_node_path("Marker3D") var takeoff_marker_path: NodePath
@export_node_path("Marker3D") var landing_marker_path: NodePath
@export_node_path("CollisionShape3D") var landing_area_path: NodePath
@export var bidirectional := false


func get_takeoff_marker() -> Marker3D:
	return get_node_or_null(takeoff_marker_path) as Marker3D


func get_landing_marker() -> Marker3D:
	return get_node_or_null(landing_marker_path) as Marker3D


func _get_landing_shape() -> Shape3D:
	var shape_node := get_node_or_null(landing_area_path) as CollisionShape3D
	return shape_node.shape if shape_node != null else null


func contains_landing_point(world_point: Vector3, reverse: bool = false) -> bool:
	var marker := get_takeoff_marker() if reverse else get_landing_marker()
	var shape := _get_landing_shape()
	if marker == null or shape == null:
		return false
	var local_point := marker.to_local(world_point)
	if shape is BoxShape3D:
		var half_size: Vector3 = (shape as BoxShape3D).size * 0.5
		return absf(local_point.x) <= half_size.x and absf(local_point.z) <= half_size.z
	if shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius
		return Vector2(local_point.x, local_point.z).length() <= radius
	return false


func get_takeoff_position(reverse: bool = false) -> Vector3:
	var marker := get_landing_marker() if reverse else get_takeoff_marker()
	return marker.global_position if marker != null else global_position


func get_landing_position(reverse: bool = false) -> Vector3:
	var marker := get_takeoff_marker() if reverse else get_landing_marker()
	return marker.global_position if marker != null else global_position


func can_traverse(reverse: bool, maximum_height: float) -> bool:
	var takeoff := get_takeoff_marker()
	var landing := get_landing_marker()
	if takeoff == null or landing == null:
		return false
	if reverse and not bidirectional:
		return false
	var vertical_delta := landing.global_position.y - takeoff.global_position.y
	if reverse:
		vertical_delta = -vertical_delta
	return absf(vertical_delta) > 0.0 and absf(vertical_delta) <= maximum_height
