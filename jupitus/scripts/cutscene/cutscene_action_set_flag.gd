# cutscene_action_set_flag.gd
# -----------------------------------------------------------------------------
# Sets a flag in PlayerState or DialogueManager during a cutscene.
#
# Use to mark story progression: "met_robber", "robbery_seen", etc.
# Other systems can check these flags to change behavior.
#
# Usage:
#   - Set `flag_name` (e.g., "met_robber")
#   - Set `flag_value` (default true)
#   - Set `use_player_state` (default true):
#       true  → sets flag in PlayerState.flags (use for game progression)
#       false → sets flag in DialogueManager.flags (use for dialogue branching)
#
# Note: This action completes instantly — no await needed.
# -----------------------------------------------------------------------------

extends CutsceneAction
class_name CutsceneActionSetFlag

## Name of the flag to set. Use snake_case for consistency.
## Examples: "met_robber", "milk_bought", "talked_to_mom"
@export var flag_name: String = ""

## Value to set. Default is true. You can use any bool-ish value.
@export var flag_value: bool = true

## If true (default), set the flag in PlayerState (game progression state).
## If false, set the flag in DialogueManager (dialogue branching state).
##
## Convention:
##   - PlayerState.flags: "the player has done X" (game-affecting)
##   - DialogueManager.flags: "the player has heard about X" (dialogue-affecting)
@export var use_player_state: bool = true


func execute(_cutscene_player: Node) -> void:
	if flag_name.is_empty():
		push_warning("CutsceneActionSetFlag: flag_name is empty")
		return

	if use_player_state:
		PlayerState.set_flag(flag_name, flag_value)
	else:
		DialogueManager.flags[flag_name] = flag_value


func skip(_cutscene_player: Node) -> void:
	# Instant action, nothing to skip
	pass
