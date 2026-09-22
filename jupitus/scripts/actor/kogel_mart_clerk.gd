extends NPC
class_name KogelMartClerk

@export_group("Milk Checkout")
## DialogueManager flag set when the milk has been collected.
@export var got_milk_flag: String = "got_milk"

## First cashier dialogue after the player collects the milk.
@export var got_milk_dialogue: DialogueData

## Dialogue used for later interactions after the milk dialogue.
@export var got_milk_repeat_dialogue: DialogueData

var _got_milk_dialogue_played: bool = false


func _on_interacted(
	interacting_player: Node
) -> void:
	if not _has_got_milk():
		super._on_interacted(
			interacting_player
		)
		return

	var dialogue := got_milk_dialogue

	if _got_milk_dialogue_played:
		dialogue = (
			got_milk_repeat_dialogue
			if got_milk_repeat_dialogue != null
			else got_milk_dialogue
		)

	if dialogue == null:
		push_warning(
			"KogelMartClerk '%s': no got-milk "
			% name
			+ "dialogue is assigned"
		)
		return

	if DialogueManager.start_dialogue(dialogue):
		_got_milk_dialogue_played = true


func _has_got_milk() -> bool:
	return bool(
		DialogueManager.flags.get(
			got_milk_flag,
			false
		)
	)
