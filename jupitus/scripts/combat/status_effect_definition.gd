extends Resource
class_name StatusEffectDefinition

@export_group("Identity")
@export var status_id: StringName = &"status"
@export var display_name: String = "Status"

@export_group("Duration and Stacking")
@export_range(1, 99) var duration_turns: int = 1
@export var stackable: bool = false
@export_range(1, 99) var max_stacks: int = 1
