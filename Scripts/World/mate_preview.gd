class_name MatePreview
extends Node3D

const FRAME_COLOR := Color("#303B40")
const JOINT_COLOR := Color("#151C20")
const VISOR_COLOR := Color("#9BCAD6")
const METAL_COLOR := Color("#74848B")

var _accent_color := Color("#D39B4C")
var _unit_state: Resource
var _loadout: MateLoadout
var _catalog: EquipmentCatalog
var _unit_label := "SAMPLE MATE"


func configure(unit_state: Resource, catalog: EquipmentCatalog, accent_color: Color, unit_label: String) -> void:
	_unit_state = unit_state
	_loadout = unit_state.get("loadout") as MateLoadout if unit_state != null else null
	_catalog = catalog
	_accent_color = accent_color
	_unit_label = unit_label
	_build_model()


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

	_add_box("pelvis", Vector3(0.68, 0.32, 0.44), Vector3(0, 1.30, 0), FRAME_COLOR)
	_add_box("torso", Vector3(0.90, 0.92, 0.54), Vector3(0, 1.91, 0), _accent_color.darkened(0.28))
	_add_box("chest_plate", Vector3(0.62, 0.42, 0.10), Vector3(0, 2.02, 0.30), _accent_color)
	_add_box("shoulder_left", Vector3(0.48, 0.34, 0.44), Vector3(-0.78, 2.27, 0), _accent_color)
	_add_box("shoulder_right", Vector3(0.48, 0.34, 0.44), Vector3(0.78, 2.27, 0), _accent_color)
	_add_box("head", Vector3(0.40, 0.40, 0.38), Vector3(0, 2.61, 0.03), METAL_COLOR)
	_add_box("visor", Vector3(0.30, 0.11, 0.055), Vector3(0, 2.65, 0.23), VISOR_COLOR)
	_add_box("neck", Vector3(0.22, 0.17, 0.22), Vector3(0, 2.40, 0), JOINT_COLOR)

	for side in [-1.0, 1.0]:
		_add_box("upper_leg", Vector3(0.29, 0.59, 0.33), Vector3(side * 0.25, 0.91, 0), FRAME_COLOR)
		_add_cylinder("knee", 0.17, 0.12, Vector3(side * 0.25, 0.60, 0.02), JOINT_COLOR)
		_add_box("lower_leg", Vector3(0.24, 0.48, 0.29), Vector3(side * 0.25, 0.34, 0), FRAME_COLOR)
		_add_box("foot", Vector3(0.39, 0.15, 0.61), Vector3(side * 0.25, 0.075, 0.12), JOINT_COLOR)
		_add_box("arm", Vector3(0.25, 0.69, 0.27), Vector3(side * 0.77, 1.83, 0.02), FRAME_COLOR)
		_add_cylinder("elbow", 0.16, 0.12, Vector3(side * 0.77, 1.46, 0.03), JOINT_COLOR)
		_add_box("forearm", Vector3(0.29, 0.42, 0.31), Vector3(side * 0.77, 1.21, 0.03), METAL_COLOR)

	_add_equipment(parts)
	_add_nameplate(mate, parts["back_unit"] != null)


func _add_equipment(parts: Dictionary) -> void:
	if parts["shield"] != null:
		_add_box("shield_mount", Vector3(0.15, 0.18, 0.17), Vector3(-0.91, 1.37, 0.04), JOINT_COLOR)
		_add_box("shield", Vector3(0.68, 0.90, 0.16), Vector3(-1.12, 1.63, 0.18), _accent_color.lightened(0.15))
		_add_box("shield_marking", Vector3(0.45, 0.055, 0.025), Vector3(-1.12, 1.69, 0.274), METAL_COLOR)

	if parts["main_arm"] != null:
		_add_box("weapon_receiver", Vector3(0.22, 0.22, 0.42), Vector3(0.91, 1.25, 0.16), JOINT_COLOR)
		_add_box("weapon_barrel", Vector3(0.095, 0.095, 0.72), Vector3(0.91, 1.29, 0.69), METAL_COLOR)
		_add_box("weapon_stock", Vector3(0.13, 0.14, 0.28), Vector3(0.91, 1.26, -0.17), FRAME_COLOR)

	if parts["expansion"] != null:
		_add_box("expansion_pack", Vector3(0.31, 0.26, 0.24), Vector3(0.34, 2.05, -0.46), _accent_color)

	if parts["back_unit"] != null:
		_add_back_cannon()


func _add_back_cannon() -> void:
	# Static stowed silhouette; raising and aiming the cannon is future animation work.
	_add_box("cannon_mount", Vector3(0.48, 0.72, 0.40), Vector3(-0.42, 1.98, -0.43), JOINT_COLOR)
	_add_box("cannon_receiver", Vector3(0.40, 1.02, 0.38), Vector3(-0.42, 2.48, -0.55), FRAME_COLOR)
	_add_box("cannon_color_panel", Vector3(0.28, 0.48, 0.04), Vector3(-0.42, 2.56, -0.34), _accent_color)
	_add_cylinder("cannon_barrel", 0.14, 1.65, Vector3(-0.42, 2.98, -0.55), METAL_COLOR)
	_add_cylinder("cannon_muzzle", 0.18, 0.16, Vector3(-0.42, 3.83, -0.55), JOINT_COLOR)


func _add_nameplate(mate: MateDefinition, has_back_unit: bool) -> void:
	var label := Label3D.new()
	label.name = "SampleLabel"
	label.text = "%s\n%s\nLOAD %.0f / %.0f" % [_unit_label, mate.name, _loadout.total_weight(_catalog), mate.load_limit]
	label.position = Vector3(0, 4.05 if has_back_unit else 3.22, 0)
	label.font_size = 32
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color("#EDF3F4")
	label.outline_size = 8
	label.outline_modulate = Color("#10181D")
	add_child(label)


func _add_box(part_name: String, dimensions: Vector3, position: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	_add_mesh(part_name, mesh, position, color)


func _add_cylinder(part_name: String, radius: float, height: float, position: Vector3, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	_add_mesh(part_name, mesh, position, color)


func _add_mesh(part_name: String, mesh: PrimitiveMesh, position: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.position = position
	instance.material_override = _make_material(color)
	add_child(instance)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.35
	material.roughness = 0.62
	return material
