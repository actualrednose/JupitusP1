# dialogue_line.gd
# -----------------------------------------------------------------------------
# A Resource representing a single line of dialogue.
# A conversation is a list of these, played in sequence (or branched via
# the choices system).
#
# Structure of a DialogueLine:
#   - speaker:        which DialogueCharacter is talking
#   - text:           the actual line of dialogue
#   - emotion:        optional emotion name (looks up speaker's emotion_portraits)
#   - choices:        optional list of choices the player can pick (for branching)
#   - next_line_id:   optional explicit "go to this line next" (for non-linear)
#
# Two usage patterns:
#
# 1. LINEAR DIALOGUE (no choices, no next_line_id)
#    Each line plays in order. The conversation ends after the last line.
#    This is what 80% of your dialogue will be.
#
# 2. BRANCHING DIALOGUE (choices)
#    When a line has choices, the player picks one. Each choice has an
#    optional `next_line_id` that jumps to a specific line. If the choice
#    has no next_line_id, the conversation continues to the next line
#    in the array.
#
# 3. NON-LINEAR (no choices, but next_line_id set)
#    The line plays, then jumps to a specific next line. Useful for
#    "go to line 5" without showing the player a choice. Rare.
# -----------------------------------------------------------------------------

extends Resource
class_name DialogueLine

# --- Line properties ---

## The character speaking this line. Drag a DialogueCharacter .tres file here.
## If null, the line is treated as "narration" — no name plate, no portrait,
## just the text. Useful for things like "*the door creaks open*" or
## scene-setting descriptions.
@export var speaker: DialogueCharacter = null

## The actual dialogue text. Can be multiple sentences. The dialogue box
## will word-wrap automatically.
##
## Keep lines under ~120 characters when possible — longer lines make the
## typewriter effect drag on. Split long monologues into multiple lines.
@export_multiline var text: String = ""

## Optional emotion override. If non-empty, the dialogue box looks up this
## string in the speaker's `emotion_portraits` dictionary and shows that
## portrait instead of the default.
##
## Example: emotion = "happy" → uses speaker.emotion_portraits["happy"]
## If the emotion doesn't exist, falls back to the default portrait.
@export var emotion: String = ""

## Optional list of choices. If non-empty, after this line finishes typing,
## the dialogue box shows a numbered list of these choices. The player
## navigates with arrow keys and confirms with E.
##
## If empty, the line is non-branching — pressing E advances to the next
## line in the array (or ends the conversation if this was the last line).
@export var choices: Array[DialogueChoice] = []

## Optional explicit "next line index" to jump to after this line.
## - If 0 or negative: play the next line in the array (default linear flow)
## - If positive: jump to that line index (1-based: next_line_id=3 means
##   "go to the 3rd line in the array")
##
## This is overridden if the line has choices — choices control the flow.
@export var next_line_id: int = 0


# -----------------------------------------------------------------------------
# Convenience helpers
# -----------------------------------------------------------------------------

## Returns true if this line is narration (no speaker).
func is_narration() -> bool:
	return speaker == null


## Returns true if this line has player-selectable choices.
func has_choices() -> bool:
	return choices.size() > 0
