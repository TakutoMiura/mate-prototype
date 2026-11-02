extends "res://Scripts/World/test_field.gd"


func _can_walk_displacement(_mate: MatePreview, displacement: Vector3) -> bool:
	return displacement.x < -0.00001


func _get_walk_blocking_reason(_mate: MatePreview, _displacement: Vector3) -> String:
	return "test obstacle"
