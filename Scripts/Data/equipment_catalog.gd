class_name EquipmentCatalog
extends Resource

@export var mate_definitions: Array[MateDefinition] = []
@export var shields: Array[ShieldDefinition] = []
@export var main_arms: Array[MainArmDefinition] = []
@export var back_units: Array[BackUnitDefinition] = []
@export var expansion_parts: Array[ExpansionPartDefinition] = []
@export var sample_loadouts: Array[MateLoadout] = []


func get_mate(identifier: String) -> MateDefinition:
	return _find_by_id(mate_definitions, identifier) as MateDefinition


func get_shield(identifier: String) -> ShieldDefinition:
	return _find_by_id(shields, identifier) as ShieldDefinition


func get_main_arm(identifier: String) -> MainArmDefinition:
	return _find_by_id(main_arms, identifier) as MainArmDefinition


func get_back_unit(identifier: String) -> BackUnitDefinition:
	return _find_by_id(back_units, identifier) as BackUnitDefinition


func get_expansion(identifier: String) -> ExpansionPartDefinition:
	return _find_by_id(expansion_parts, identifier) as ExpansionPartDefinition


func _find_by_id(items: Array, identifier: String) -> PartDefinition:
	if identifier.is_empty():
		return null
	for item in items:
		if item != null and item.id == identifier:
			return item
	return null
