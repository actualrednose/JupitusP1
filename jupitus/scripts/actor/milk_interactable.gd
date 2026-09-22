extends Interactable
class_name MilkInteractable

@export_group("Dialogue")
## Dialogue shown while the robbery is in progress.
@export var robbery_dialogue: DialogueData

## Dialogue shown after the robbery has finished.
@export var after_robbery_dialogue: DialogueData

@export_group("Story State")
## PlayerState flag set when the robbery begins.
@export var robbery_in_progress_flag: StringName = (
	&"robbery_in_progress"
)

## PlayerState flag set when the robbery is over.
@export var robbery_finished_flag: StringName = (
	&"robbery_finished"
)

## DialogueManager flag set after the player collects the milk.
@export var got_milk_flag: String = "got_milk"


func _ready() -> void:
	super._ready()

	if _has_got_milk():
		enabled = false


func _on_interacted(
	_interacting_player: Node
) -> void:
	if _has_got_milk():
		enabled = false
		return

	var dialogue: DialogueData = null

	if PlayerState.has_flag(
		robbery_in_progress_flag
	):
		dialogue = robbery_dialogue

	elif PlayerState.has_flag(
		robbery_finished_flag
	):
		dialogue = after_robbery_dialogue

	else:
		push_warning(
			"MilkInteractable '%s': neither robbery "
			% name
			+ "state flag is set. Set '%s' when the "
			% robbery_in_progress_flag
			+ "robbery begins or '%s' when it ends."
			% robbery_finished_flag
		)
		return

	if dialogue == null:
		push_warning(
			"MilkInteractable '%s' has no dialogue "
			% name
			+ "assigned for the current state"
		)
		return

	if not DialogueManager.start_dialogue(
		dialogue
	):
		return

	if dialogue != after_robbery_dialogue:
		return

	await DialogueManager.dialogue_ended

	if _has_got_milk():
		enabled = false


func _has_got_milk() -> bool:
	return bool(
		DialogueManager.flags.get(
			got_milk_flag,
			false
		)
	)
