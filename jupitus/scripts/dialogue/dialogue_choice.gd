# dialogue_choice.gd
# -----------------------------------------------------------------------------
# A Resource representing a single selectable choice in a branching dialogue.
#
# A DialogueLine can have an array of these. When the line finishes typing,
# the dialogue box displays them as a numbered list. The player navigates
# with Up/Down arrows and confirms with E.
#
# Each choice has:
#   - text:         the choice text shown to the player
#   - next_line_id: where to go after picking this choice (1-based line index,
#                   or 0/negative for "next line in array")
#   - sets_flag:    optional flag name to set when this choice is picked
#                   (for simple state tracking, e.g., "accepted_quest")
# -----------------------------------------------------------------------------

extends Resource
class_name DialogueChoice

# --- Choice properties ---

## The text shown for this choice in the numbered list.
## Keep it short — long choice text will wrap awkwardly in the UI.
@export var text: String = "Continue"

## Where to go after this choice is picked.
## - 0 or negative: continue to the next line in the array (linear flow)
## - positive: jump to that line index (1-based: next_line_id=3 → 3rd line)
##
## Most choices will use 0 (continue linearly) or jump to a specific line
## to skip ahead / branch to a different part of the conversation.
@export var next_line_id: int = 0

## Optional flag name to set in DialogueManager.flags when this choice is
## picked. Useful for simple state like "told_mom_about_robbery".
##
## If non-empty, DialogueManager will do: flags[sets_flag] = true
## Other systems can then check: DialogueManager.flags.get("told_mom_about_robbery", false)
##
## For more complex state, use a dedicated save/state system. This is just
## a convenience for simple flags.
@export var sets_flag: String = ""
