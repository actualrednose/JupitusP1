# dialogue_data.gd
# -----------------------------------------------------------------------------
# A Resource representing a complete conversation. Contains an array of
# DialogueLine resources, played in order (with optional branching).
#
# Usage:
#   1. In the FileSystem, right-click res://resources/dialogue/ → New Resource
#   2. Pick "DialogueData" from the list
#   3. Save as e.g. "conv_intro.tres"
#   4. In the Inspector, click "Add Element" to add lines to the array
#   5. For each line, set the speaker (drag in a DialogueCharacter .tres),
#      type the text, optionally add choices
#   6. To start the conversation in code:
#        DialogueManager.start_dialogue(load("res://resources/dialogue/conv_intro.tres"))
#      or drag the .tres file into an NPC's @export dialogue_data slot
#      and have the NPC call DialogueManager.start_dialogue(dialogue_data)
# -----------------------------------------------------------------------------

extends Resource
class_name DialogueData

# --- Conversation properties ---

## The list of dialogue lines in this conversation. Lines are played in
## order unless a line's choices or next_line_id change the flow.
##
## In the Inspector, you'll see an array you can add/remove/reorder elements
## in. Each element expands to show its speaker, text, emotion, and choices.
@export var lines: Array[DialogueLine] = []

## Optional: a flag that must be set for this conversation to play.
## If non-empty and the flag is NOT set in DialogueManager.flags,
## the conversation is skipped (the start_dialogue call does nothing).
## Useful for "this conversation only plays after event X".
##
## Example: requires_flag = "met_robber"
## → conversation only plays if DialogueManager.flags.get("met_robber") == true
@export var requires_flag: String = ""

## Optional: a flag to set when this conversation ends (any ending).
## Useful for "this conversation only plays once" — set the flag, then
## check requires_flag on a different conversation that replaces it.
@export var sets_flag_on_complete: String = ""


# -----------------------------------------------------------------------------
# Convenience helpers
# -----------------------------------------------------------------------------

## Get a line by 1-based index (matches how next_line_id is interpreted).
## Returns null if index is out of range.
##
## Why 1-based? Because 0 is used as "continue linearly" in next_line_id.
## Using 1-based for explicit jumps makes "0 = default" and "N = line N"
## unambiguous. Slightly unusual but clearer once you see it in action.
func get_line(line_id: int) -> DialogueLine:
	if line_id < 1 or line_id > lines.size():
		return null
	return lines[line_id - 1]


## Total number of lines in this conversation.
func line_count() -> int:
	return lines.size()
