class_name MatePreview
extends Node3D

enum ModelStyle { SKELETON, WAW_BLOCK_FRAME }

const FRAME_COLOR := Color("#303B40")
const JOINT_COLOR := Color("#151C20")
const VISOR_COLOR := Color("#9BCAD6")
const METAL_COLOR := Color("#74848B")
const BONE_COLOR := Color("#C9D0C8")
const BONE_HIGHLIGHT := Color("#E4E5D9")
const JOINT_RADIUS := 0.13
const PELVIS_HEIGHT := 1.34

@export_group("Walking Motion")
@export_range(0.0, 60.0, 1.0) var default_elbow_bend_degrees := 45.0
@export_range(0.0, 15.0, 1.0) var default_thigh_forward_degrees := 8.0
@export_range(0.0, 40.0, 1.0) var default_knee_bend_degrees := 30.0
@export_range(0.8, 3.0, 0.1) var walking_stride_length := 1.8
@export_range(0.5, 0.8, 0.01) var stance_ratio := 0.62
@export_range(10.0, 40.0, 1.0) var leg_swing_degrees := 24.0
@export_range(2.0, 18.0, 0.5) var pelvis_twist_degrees := 16.0
@export_range(1.0, 1.8, 0.05) var torso_counter_ratio := 1.6
@export_range(0.0, 0.15, 0.005) var lateral_weight_shift := 0.07
@export_range(0.0, 0.08, 0.002) var contact_dip := 0.035
@export_range(0.0, 5.0, 0.25) var arm_inertia_degrees := 2.5
@export_range(1.0, 12.0, 0.5) var stop_blend_speed := 5.0

var _accent_color := Color("#D39B4C")
var _unit_state: Resource
var _loadout: MateLoadout
var _catalog: EquipmentCatalog
var _model_style := ModelStyle.SKELETON
var _status_bounds_corners: Array[Vector3] = []
var _pelvis_rig: Node3D
var _upper_body_rig: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _left_shin: Node3D
var _right_shin: Node3D
var _left_foot: Node3D
var _right_foot: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_forearm: Node3D
var _right_forearm: Node3D
var _left_hand: Node3D
var _walking := false
var _walk_blend := 0.0
var _gait_phase := 0.0
var _gait_rate := 0.0


func configure(
	unit_state: Resource,
	catalog: EquipmentCatalog,
	accent_color: Color,
	model_style: ModelStyle = ModelStyle.SKELETON
) -> void:
	_unit_state = unit_state
	_loadout = unit_state.get("loadout") as MateLoadout if unit_state != null else null
	_catalog = catalog
	_accent_color = accent_color
	_model_style = model_style
	_build_model()


func get_status_bounds_corners() -> Array[Vector3]:
	return _status_bounds_corners

func is_alive() -> bool:
	return _unit_state != null and float(_unit_state.get('current_hp')) > 0.0


func set_walking(active: bool, forward_speed: float = 2.5) -> void:
	_walking = active and is_alive() and forward_speed > 0.0
	_gait_rate = TAU * forward_speed / maxf(walking_stride_length, 0.1)


func is_walking_animating() -> bool:
	return _walking or _walk_blend > 0.0


func _process(delta: float) -> void:
	if _pelvis_rig == null:
		return
	if _walking:
		_gait_phase = fposmod(_gait_phase + delta * _gait_rate, TAU)
	_walk_blend = move_toward(_walk_blend, 1.0 if _walking else 0.0, delta * stop_blend_speed)
	_update_walking_pose()


func _update_walking_pose() -> void:
	var phase := _gait_phase
	var blend := _walk_blend
	var leg_swing := deg_to_rad(leg_swing_degrees)
	var pelvis_twist := deg_to_rad(pelvis_twist_degrees)
	var arm_inertia := deg_to_rad(arm_inertia_degrees)
	var right_pose := _leg_pose(phase, leg_swing)
	var left_pose := _leg_pose(phase + PI, leg_swing)
	# Lean the thigh forward and fold the shin back from the knee. The ankle
	# cancels the combined pitch so the foot remains nearly level.
	var knee_bend := deg_to_rad(default_knee_bend_degrees)
	var thigh_forward := deg_to_rad(default_thigh_forward_degrees)
	_right_leg.rotation.x = -thigh_forward + right_pose.x * blend
	_right_shin.rotation.x = knee_bend + right_pose.y * blend
	_right_foot.rotation.x = thigh_forward - knee_bend + right_pose.z * blend
	_left_leg.rotation.x = -thigh_forward + left_pose.x * blend
	_left_shin.rotation.x = knee_bend + left_pose.y * blend
	_left_foot.rotation.x = thigh_forward - knee_bend + left_pose.z * blend

	# UpperBodyRig is parented to PelvisRig. Cancel the inherited pelvis yaw first,
	# then apply the requested counter rotation as a visible world-space angle.
	var counter_signal := sin(phase)
	var pelvis_yaw := -counter_signal * pelvis_twist
	_pelvis_rig.rotation.y = pelvis_yaw * blend
	_upper_body_rig.rotation.y = -pelvis_yaw * (1.0 + torso_counter_ratio) * blend
	var support_side := cos(phase)
	_pelvis_rig.position = Vector3(
		support_side * lateral_weight_shift * blend,
		PELVIS_HEIGHT - _contact_compression(phase) * contact_dip * blend,
		0.0
	)
	_pelvis_rig.rotation.z = -support_side * deg_to_rad(2.0) * blend

	# Equipment remains carried by its arm; only a small delayed inertial motion is applied.
	var arm_lag := sin(phase - 0.55) * arm_inertia * blend
	_left_arm.rotation.x = arm_lag
	_right_arm.rotation.x = -arm_lag
	_left_forearm.rotation.x = -deg_to_rad(default_elbow_bend_degrees) - arm_lag * 0.35
	_right_forearm.rotation.x = -deg_to_rad(default_elbow_bend_degrees) + arm_lag * 0.35


func _leg_pose(phase: float, swing_angle: float) -> Vector3:
	var cycle := fposmod(phase, TAU) / TAU
	var stance := clampf(stance_ratio, 0.5, 0.8)
	if cycle < stance:
		var progress := cycle / stance
		var eased := _smooth_unit(progress)
		var hip_angle := lerpf(-swing_angle, swing_angle, eased)
		var knee_push := smoothstep(0.68, 1.0, progress) * deg_to_rad(5.0)
		return Vector3(hip_angle, -knee_push, knee_push * 0.4)
	var swing_progress := (cycle - stance) / (1.0 - stance)
	var swing_eased := _smooth_unit(swing_progress)
	var lift := sin(swing_progress * PI)
	var hip_angle := lerpf(swing_angle, -swing_angle, swing_eased)
	var knee_flex := lift * deg_to_rad(34.0)
	var ankle_lift := -lift * deg_to_rad(10.0)
	return Vector3(hip_angle, knee_flex, ankle_lift)


func _contact_compression(phase: float) -> float:
	# A short compression at each alternating foot contact gives the body weight.
	return pow(maxf(0.0, cos(phase * 2.0)), 4.0)


func _smooth_unit(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _cache_status_bounds(has_back_unit: bool) -> void:
	_status_bounds_corners.clear()
	var top := 4.05 if has_back_unit else 2.9
	for x in [-1.45, 1.45]:
		for y in [0.0, top]:
			for z in [-1.35, 1.15]:
				_status_bounds_corners.append(Vector3(x, y, z))


func _build_model() -> void:
	if _loadout == null or _catalog == null:
		return
	var parts := _loadout.resolve(_catalog)
	var mate: MateDefinition = parts["mate"]
	if mate == null:
		push_warning("Test-field loadout references a missing MATE: %s" % _loadout.mate_id)
		return
	if not _loadout.is_compatible(_catalog):
		push_warning("Test-field loadout contains incompatible equipment: %s" % _loadout.mate_id)
	_cache_status_bounds(parts["back_unit"] != null)

	_build_skeleton()

	_add_equipment(parts)


func _build_skeleton() -> void:
	# Both silhouettes use this same articulated rig and gait controller.
	_pelvis_rig = Node3D.new()
	_pelvis_rig.name = "PelvisRig"
	_pelvis_rig.position.y = PELVIS_HEIGHT
	add_child(_pelvis_rig)
	if _model_style == ModelStyle.SKELETON:
		_add_bone(_pelvis_rig, "pelvis_bar", 0.58, Vector3(0, -0.02, 0), Vector3(0, 0, PI * 0.5))
	else:
		_add_box_to(_pelvis_rig, "waist_housing", Vector3(0.62, 0.28, 0.46), Vector3(0, -0.02, 0), FRAME_COLOR)
		_add_box_to(_pelvis_rig, "waist_front_plate", Vector3(0.48, 0.22, 0.12), Vector3(0, -0.02, 0.28), _accent_color.darkened(0.15))

	_upper_body_rig = Node3D.new()
	_upper_body_rig.name = "UpperBodyRig"
	_upper_body_rig.position.y = 0.02
	_pelvis_rig.add_child(_upper_body_rig)
	if _model_style == ModelStyle.SKELETON:
		_build_skeleton_torso()
	else:
		_build_waw_torso()

	_left_leg = _create_leg(_pelvis_rig, -1.0, "LeftLeg")
	_right_leg = _create_leg(_pelvis_rig, 1.0, "RightLeg")
	_left_shin = _left_leg.get_node("LowerLeg") as Node3D
	_right_shin = _right_leg.get_node("LowerLeg") as Node3D
	_left_foot = _left_shin.get_node("FootRig") as Node3D
	_right_foot = _right_shin.get_node("FootRig") as Node3D
	_left_arm = _create_arm(_upper_body_rig, -1.0, "LeftArm")
	_right_arm = _create_arm(_upper_body_rig, 1.0, "RightArm")
	_left_forearm = _left_arm.get_node("ForearmRig") as Node3D
	_right_forearm = _right_arm.get_node("ForearmRig") as Node3D
	_left_hand = _left_forearm.get_node("HandRig") as Node3D


func _build_skeleton_torso() -> void:
	# Preserve the existing first-squad skeleton silhouette.
	_add_bone(_upper_body_rig, "spine", 0.78, Vector3(0, 0.45, 0))
	_add_bone(_upper_body_rig, "shoulder_bar", 1.05, Vector3(0, 0.92, 0), Vector3(0, 0, PI * 0.5))
	_add_joint(_upper_body_rig, "chest_joint", Vector3(0, 0.90, 0), 0.17)
	_add_bone(_upper_body_rig, "neck", 0.23, Vector3(0, 1.05, 0))
	_add_joint(_upper_body_rig, "head", Vector3(0, 1.27, 0), 0.22, BONE_HIGHLIGHT)


func _build_waw_torso() -> void:
	# Broad, forward-set chest and small head create a compact WAW-like silhouette.
	_add_box_to(_upper_body_rig, "thorax_frame", Vector3(0.68, 0.78, 0.42), Vector3(0, 0.60, -0.02), FRAME_COLOR)
	_add_box_to(_upper_body_rig, "chest_block", Vector3(0.94, 0.78, 0.56), Vector3(0, 0.70, 0.20), METAL_COLOR)
	_add_box_to(_upper_body_rig, "projecting_chest_plate", Vector3(0.82, 0.56, 0.42), Vector3(0, 0.72, 0.59), _accent_color.darkened(0.12))
	_add_box_to(_upper_body_rig, "chest_reinforcement", Vector3(0.68, 0.10, 0.08), Vector3(0, 0.45, 0.82), _accent_color)
	_add_box_to(_upper_body_rig, "collar_frame", Vector3(0.54, 0.18, 0.38), Vector3(0, 1.05, 0.02), JOINT_COLOR)
	_add_box_to(_upper_body_rig, "head_mount", Vector3(0.20, 0.22, 0.20), Vector3(0, 1.19, 0), FRAME_COLOR)
	_add_box_to(_upper_body_rig, "small_head", Vector3(0.25, 0.22, 0.25), Vector3(0, 1.34, 0.07), METAL_COLOR)
	_add_box_to(_upper_body_rig, "head_sensor", Vector3(0.14, 0.045, 0.025), Vector3(0, 1.35, 0.202), VISOR_COLOR)
	_add_box_to(_upper_body_rig, "shoulder_bridge", Vector3(1.14, 0.18, 0.32), Vector3(0, 0.98, -0.04), FRAME_COLOR)
	for side in [-1.0, 1.0]:
		_add_box_to(_upper_body_rig, "shoulder_mount", Vector3(0.34, 0.40, 0.38), Vector3(side * 0.62, 0.83, 0), _accent_color.darkened(0.22))
		_add_box_to(_upper_body_rig, "chest_side_guard", Vector3(0.16, 0.60, 0.42), Vector3(side * 0.53, 0.65, 0.24), FRAME_COLOR)


func _create_leg(parent: Node3D, side: float, rig_name: String) -> Node3D:
	var hip := Node3D.new()
	hip.name = rig_name
	hip.position = Vector3(side * 0.25, 0.0, 0)
	parent.add_child(hip)
	if _model_style == ModelStyle.SKELETON:
		_add_joint(hip, "HipJoint", Vector3.ZERO, JOINT_RADIUS, _accent_color)
		_add_bone(hip, "UpperLegBone", 0.61, Vector3(0, -0.31, 0))
		_add_joint(hip, "KneeJoint", Vector3(0, -0.62, 0), JOINT_RADIUS)
	else:
		_add_box_to(hip, "hip_socket", Vector3(0.30, 0.22, 0.32), Vector3(0, -0.04, 0), FRAME_COLOR)
		_add_box_to(hip, "thigh_strut", Vector3(0.22, 0.54, 0.26), Vector3(0, -0.32, 0.02), METAL_COLOR)
		_add_box_to(hip, "knee_housing", Vector3(0.32, 0.18, 0.32), Vector3(0, -0.62, 0.02), _accent_color.darkened(0.10))
		for rail_side in [-1.0, 1.0]:
			_add_box_to(hip, "thigh_guide", Vector3(0.07, 0.48, 0.09), Vector3(rail_side * 0.15, -0.31, 0.12), BONE_HIGHLIGHT)
	var shin := Node3D.new()
	shin.name = "LowerLeg"
	shin.position = Vector3(0, -0.62, 0)
	hip.add_child(shin)
	if _model_style == ModelStyle.SKELETON:
		_add_bone(shin, "LowerLegBone", 0.56, Vector3(0, -0.28, 0))
		_add_joint(shin, "AnkleJoint", Vector3(0, -0.56, 0), 0.095)
	else:
		_add_box_to(shin, "shin_strut", Vector3(0.20, 0.50, 0.22), Vector3(0, -0.28, 0), METAL_COLOR)
		_add_box_to(shin, "ankle_housing", Vector3(0.26, 0.14, 0.26), Vector3(0, -0.55, 0), FRAME_COLOR)
		for rail_side in [-1.0, 1.0]:
			_add_box_to(shin, "shin_guide", Vector3(0.065, 0.46, 0.08), Vector3(rail_side * 0.13, -0.28, 0.11), BONE_HIGHLIGHT)
	var foot := Node3D.new()
	foot.name = "FootRig"
	foot.position = Vector3(0, -0.56, 0)
	shin.add_child(foot)
	if _model_style == ModelStyle.SKELETON:
		_add_bone(foot, "FootBone", 0.32, Vector3(0, 0.0, 0.12), Vector3(PI * 0.5, 0, 0))
	else:
		_add_box_to(foot, "foot_plate", Vector3(0.42, 0.12, 0.55), Vector3(0, 0, 0.16), FRAME_COLOR)
	return hip


func _create_arm(parent: Node3D, side: float, rig_name: String) -> Node3D:
	var shoulder := Node3D.new()
	shoulder.name = rig_name
	shoulder.position = Vector3(side * 0.52, 0.91, 0)
	parent.add_child(shoulder)
	var forearm := Node3D.new()
	forearm.name = "ForearmRig"
	forearm.position.y = -0.51
	forearm.rotation.x = -deg_to_rad(default_elbow_bend_degrees)
	shoulder.add_child(forearm)
	var hand := Node3D.new()
	hand.name = "HandRig"
	hand.position.y = -0.45
	forearm.add_child(hand)
	if _model_style == ModelStyle.SKELETON:
		_add_joint(shoulder, "ShoulderJoint", Vector3.ZERO, 0.15, _accent_color)
		_add_bone(shoulder, "UpperArmBone", 0.49, Vector3(0, -0.25, 0))
		_add_joint(shoulder, "ElbowJoint", Vector3(0, -0.51, 0), 0.11)
		_add_bone(forearm, "ForearmBone", 0.45, Vector3(0, -0.225, 0))
		_add_joint(hand, "HandJoint", Vector3.ZERO, 0.10, BONE_HIGHLIGHT)
	else:
		_add_joint(shoulder, "shoulder_axle", Vector3.ZERO, 0.14, _accent_color)
		_add_box_to(shoulder, "upper_support_frame", Vector3(0.24, 0.48, 0.24), Vector3(0, -0.25, 0), FRAME_COLOR)
		_add_box_to(shoulder, "upper_hydraulic_link_left", Vector3(0.065, 0.44, 0.08), Vector3(-0.15, -0.25, -0.08), BONE_HIGHLIGHT)
		_add_box_to(shoulder, "upper_hydraulic_link_right", Vector3(0.065, 0.44, 0.08), Vector3(0.15, -0.25, -0.08), BONE_HIGHLIGHT)
		_add_joint(shoulder, "elbow_axle", Vector3(0, -0.51, 0), 0.11, JOINT_COLOR)
		_add_box_to(forearm, "forearm_support_frame", Vector3(0.28, 0.42, 0.28), Vector3(0, -0.23, 0.03), METAL_COLOR)
		_add_box_to(hand, "wrist_mount", Vector3(0.24, 0.15, 0.24), Vector3.ZERO, JOINT_COLOR)
		_add_box_to(forearm, "forearm_rail_left", Vector3(0.065, 0.38, 0.08), Vector3(-0.16, -0.23, -0.08), BONE_COLOR)
		_add_box_to(forearm, "forearm_rail_right", Vector3(0.065, 0.38, 0.08), Vector3(0.16, -0.23, -0.08), BONE_COLOR)
	return shoulder


func _add_bone(parent: Node3D, bone_name: String, length: float, local_position: Vector3, local_rotation := Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.065
	mesh.bottom_radius = 0.095
	mesh.height = length
	var bone := MeshInstance3D.new()
	bone.name = bone_name
	bone.mesh = mesh
	bone.position = local_position
	bone.rotation = local_rotation
	bone.material_override = _make_material(BONE_COLOR)
	parent.add_child(bone)


func _add_joint(parent: Node3D, joint_name: String, local_position: Vector3, radius: float, color := BONE_HIGHLIGHT) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var joint := MeshInstance3D.new()
	joint.name = joint_name
	joint.mesh = mesh
	joint.position = local_position
	joint.material_override = _make_material(color)
	parent.add_child(joint)


func _add_equipment(parts: Dictionary) -> void:
	if parts["shield"] != null:
		# Cant the hand-held shield outward so its face is visible in a side view.
		var shield_mount := Node3D.new()
		shield_mount.name = "ShieldHandMount"
		shield_mount.rotation.y = -PI * 0.5
		_left_hand.add_child(shield_mount)
		_add_box_to(shield_mount, "shield_grip", Vector3(0.12, 0.14, 0.18), Vector3(0, 0, 0.08), JOINT_COLOR)
		_add_box_to(shield_mount, "shield", Vector3(0.42, 0.64, 0.10), Vector3(0, 0, 0.22), _accent_color.lightened(0.15))
		_add_box_to(shield_mount, "shield_marking", Vector3(0.28, 0.035, 0.015), Vector3(0, 0.04, 0.278), METAL_COLOR)

	if parts["main_arm"] != null:
		_add_box_to(_right_forearm, "weapon_receiver", Vector3(0.22, 0.22, 0.42), Vector3(0.39, -0.51, 0.16), JOINT_COLOR)
		_add_box_to(_right_forearm, "weapon_barrel", Vector3(0.095, 0.095, 0.72), Vector3(0.39, -0.47, 0.69), METAL_COLOR)
		_add_box_to(_right_forearm, "weapon_stock", Vector3(0.13, 0.14, 0.28), Vector3(0.39, -0.50, -0.17), FRAME_COLOR)

	if parts["expansion"] != null:
		_add_box_to(_upper_body_rig, "expansion_pack", Vector3(0.31, 0.26, 0.24), Vector3(0.34, 0.69, -0.46), _accent_color)

	if parts["back_unit"] != null:
		_add_back_cannon()


func _add_back_cannon() -> void:
	# Static stowed silhouette; raising and aiming the cannon is future animation work.
	_add_box_to(_upper_body_rig, "cannon_mount", Vector3(0.48, 0.72, 0.40), Vector3(-0.42, 0.62, -0.43), JOINT_COLOR)
	_add_box_to(_upper_body_rig, "cannon_receiver", Vector3(0.40, 1.02, 0.38), Vector3(-0.42, 1.12, -0.55), FRAME_COLOR)
	_add_box_to(_upper_body_rig, "cannon_color_panel", Vector3(0.28, 0.48, 0.04), Vector3(-0.42, 1.20, -0.34), _accent_color)
	_add_cylinder_to(_upper_body_rig, "cannon_barrel", 0.14, 1.65, Vector3(-0.42, 1.62, -0.55), METAL_COLOR)
	_add_cylinder_to(_upper_body_rig, "cannon_muzzle", 0.18, 0.16, Vector3(-0.42, 2.47, -0.55), JOINT_COLOR)


func _add_box_to(parent: Node3D, part_name: String, dimensions: Vector3, position: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	_add_mesh_to(parent, part_name, mesh, position, color)


func _add_cylinder_to(parent: Node3D, part_name: String, radius: float, height: float, position: Vector3, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	_add_mesh_to(parent, part_name, mesh, position, color)


func _add_mesh_to(parent: Node3D, part_name: String, mesh: PrimitiveMesh, position: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.position = position
	instance.material_override = _make_material(color)
	parent.add_child(instance)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.35
	material.roughness = 0.62
	return material
