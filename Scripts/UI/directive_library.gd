class_name DirectiveLibrary
extends Resource

@export var directives: Array[DirectiveDefinition] = []


func register_directive(display_name: String) -> DirectiveDefinition:
	var normalized_name := display_name.strip_edges()
	if normalized_name.is_empty() or _has_display_name(normalized_name):
		return null

	var directive := DirectiveDefinition.new()
	directive.identifier = _next_identifier()
	directive.display_name = normalized_name
	directive.behavior_profile = DirectiveDefinition.CUSTOM_BEHAVIOR_PROFILE
	directives.append(directive)
	return directive


func ensure_unique_identifiers() -> void:
	var used_identifiers: Dictionary = {"directive.basic": true}
	var has_basic_directive := false
	for directive in directives:
		if directive == null:
			continue
		if directive.behavior_profile == DirectiveDefinition.BASIC_BEHAVIOR_PROFILE and not has_basic_directive:
			directive.identifier = "directive.basic"
			has_basic_directive = true
			continue
		if directive.identifier.is_empty() or used_identifiers.has(directive.identifier):
			directive.identifier = _next_identifier(used_identifiers)
		used_identifiers[directive.identifier] = true


func _next_identifier(used_identifiers: Dictionary = {}) -> String:
	var suffix := 1
	var candidate := ""
	while true:
		candidate = "directive.%03d" % suffix
		if not used_identifiers.has(candidate) and not _has_identifier(candidate):
			return candidate
		suffix += 1
	return candidate


func _has_identifier(identifier: String) -> bool:
	for directive in directives:
		if directive != null and directive.identifier == identifier:
			return true
	return false


func _has_display_name(display_name: String) -> bool:
	for directive in directives:
		if directive != null and directive.display_name.strip_edges().to_lower() == display_name.to_lower():
			return true
	return false
