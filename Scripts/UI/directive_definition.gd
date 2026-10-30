class_name DirectiveDefinition
extends Resource

const BASIC_BEHAVIOR_PROFILE := "basic"
const CUSTOM_BEHAVIOR_PROFILE := "custom"

@export var identifier: String = ""
@export var display_name: String = ""
@export var behavior_profile: String = CUSTOM_BEHAVIOR_PROFILE
