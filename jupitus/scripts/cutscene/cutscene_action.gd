# cutscene_action.gd
# -----------------------------------------------------------------------------
# Abstract base class for cutscene actions.
#
# A cutscene is a sequence of actions played in order. Each action is a
# Resource that knows how to execute itself (potentially asynchronously).
# The CutscenePlayer awaits each action's execute() method in turn.
#
# To create a new action type:
#   1. Create a new script: cutscene_action_<name>.gd
#   2. extends CutsceneAction
#   3. Add @export properties for any configurable parameters
#   4. Override execute(cutscene_player) — use `await` for async work
#
# Example (a simple "wait" action):
#   extends CutsceneAction
#   class_name CutsceneActionWait
#
#   @export var duration: float = 1.0
#
#   func execute(cutscene_player: Node) -> void:
#       await cutscene_player.get_tree().create_timer(duration).timeout
#
# The execute method receives the CutscenePlayer node so actions can:
#   - Access the scene tree (cutscene_player.get_tree())
#   - Create tweens (cutscene_player.create_tween())
#   - Find other nodes in the scene
#   - Check the player's skipping state (cutscene_player._is_skipping)
# -----------------------------------------------------------------------------

extends Resource
class_name CutsceneAction

# --- Virtual method ---

## Execute this action. Override in subclasses.
## Can use `await` for asynchronous operations (timers, tweens, signals).
## The cutscene player will wait for this method to return before moving
## to the next action.
##
## `cutscene_player` is the CutscenePlayer node that's running this action.
## Use it to access the scene tree, create tweens, etc.
func execute(_cutscene_player: Node) -> void:
	# Default implementation does nothing (instant completion)
	pass


## Optional: called when the cutscene is skipped while this action is running.
## Override in subclasses to clean up (e.g., kill tweens, end dialogue).
## The default implementation does nothing.
##
## After skip() is called, the cutscene player will stop awaiting execute()
## and move on (or end the cutscene entirely).
func skip(_cutscene_player: Node) -> void:
	pass
