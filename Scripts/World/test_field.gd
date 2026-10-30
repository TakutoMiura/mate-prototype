class_name TestField
extends Node3D

const MATE_UNIT_STATE_SCRIPT := preload("res://Scripts/Data/mate_unit_state.gd")
const SQUAD_COLORS := [Color("#D39B4C"), Color("#6A9AA9"), Color("#879C68")]
const FLOOR_EXTENT := 30.0
const SQUAD_SPACING := 12.0
const MATE_SPACING := 2.7

@export var equipment_catalog: EquipmentCatalog

var _camera: Camera3D
var _squad_centers: Array[Vector3] = []
var _squad_states: Array[Array] = []
var _prepared := false


func _ready() -> void:
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


func focus_squad(squad_number: int) -> void:
	if _camera == null or _squad_centers.is_empty():
		return
	var index := clampi(squad_number - 1, 0, _squad_centers.size() - 1)
	var target := _squad_centers[index] + Vector3(0, 1.3, 0)
	_camera.position = target + Vector3(0, 5.8, 12.5)
	_camera.look_at(target, Vector3.UP)
	_request_viewport_render()


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
	_camera.position = Vector3(0, 16.0, 29.0)
	_camera.fov = 48.0
	_camera.current = true
	add_child(_camera)
	_camera.look_at(Vector3(0, 1.35, 0), Vector3.UP)


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
		var squad_states: Array[Resource] = []
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
				"SQUAD %02d / UNIT %02d" % [squad_index + 1, mate_index + 1]
			)
			mate.position = Vector3(
				squad_center.x + (mate_index - 1) * MATE_SPACING,
				0.04,
				0
			)
			squad_states.append(unit_state)
			add_child(mate)
		_squad_states.append(squad_states)
