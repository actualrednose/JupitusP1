extends Interactable
class_name MilkInteractable

@export_group("Dialogue")
## Dialogue shown while the robbery is in progress.
@export var robbery_dialogue: DialogueData

## Dialogue shown after the robbery has finished.
@export var after_robbery_dialogue: DialogueData

@export_group("Story State")
## PlayerState flag set when the robbery begins.
@export var robbery_in_progress_flag: StringName = &"robbery_in_progress"

## PlayerState flag set when the robbery is over.
@export var robbery_finished_flag: StringName = &"robbery_finished"


func _on_interacted(_player: Node) -> void:
	var dialogue: DialogueData = null

	if PlayerState.has_flag(robbery_in_progress_flag):
		dialogue = robbery_dialogue
	elif PlayerState.has_flag(robbery_finished_flag):
		dialogue = after_robbery_dialogue
	else:
		push_warning(
			"MilkInteractable '%s': neither robbery state flag is set. " % name
			+ "Set '%s' when the robbery begins or '%s' when it ends."
			% [robbery_in_progress_flag, robbery_finished_flag]
		)
		return

	if dialogue == null:
		push_warning(
			"MilkInteractable '%s' has no dialogue assigned for the current state"
			% name
		)
		return

	DialogueManager.start_dialogue(dialogue)
