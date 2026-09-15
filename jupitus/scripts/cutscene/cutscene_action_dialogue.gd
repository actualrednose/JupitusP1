# cutscene_action_dialogue.gd
# -----------------------------------------------------------------------------
# Plays a dialogue conversation as part of a cutscene.
#
# The cutscene waits for the dialogue to fully complete before moving to
# the next action.
#
# Usage:
#   - Set `dialogue` to a DialogueData .tres file
#   - The action calls DialogueManager.start_dialogue() and awaits the
#     dialogue_ended signal
#
# Example: shopkeeper yells "Stop right there!" during a robbery cutscene.
# The cutscene pauses until the player has read all the dialogue lines.
# -----------------------------------------------------------------------------

extends CutsceneAction
class_name CutsceneActionDialogue

## The dialogue to play. Drag a DialogueData .tres file here.
@export var dialogue: DialogueData = null


func execute(_cutscene_player: Node) -> void:
	if dialogue == null:
		push_warning("CutsceneActionDialogue: no dialogue data set")
		return

	# Start the dialogue via the global DialogueManager.
	# Returns true if the dialogue started, false if it was blocked
	# (e.g., another dialogue is already active, or requires_flag not met).
	if not DialogueManager.start_dialogue(dialogue):
		push_warning("CutsceneActionDialogue: dialogue couldn't start (already active or requires_flag not met)")
		return

	# Wait for the dialogue to end.
	# DialogueManager emits `dialogue_ended` when a conversation finishes
	# (either naturally or via skip).
	await DialogueManager.dialogue_ended


func skip(_cutscene_player: Node) -> void:
	# When skipping, end the dialogue immediately.
	# This will cause DialogueManager to emit `dialogue_ended`, which
	# unblocks the await in execute().
	if DialogueManager.is_dialogue_active():
		DialogueManager.end_dialogue()
