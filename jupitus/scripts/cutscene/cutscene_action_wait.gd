# cutscene_action_wait.gd
# -----------------------------------------------------------------------------
# Pauses the cutscene for a fixed duration.
#
# Use for dramatic beats, letting the player absorb a moment, etc.
# Example: wait 1.0 second between a camera pan and a character speaking.
# -----------------------------------------------------------------------------

extends CutsceneAction
class_name CutsceneActionWait

## How long to wait, in seconds.
@export var duration: float = 1.0


func execute(cutscene_player: Node) -> void:
		# Create a one-shot timer and await its timeout signal.
		# This pauses this function (and therefore the cutscene) for `duration`.
		#
		# We use get_tree().create_timer() instead of a Timer node because it's
		# simpler — no node setup needed, just a one-shot async wait.
		await cutscene_player.get_tree().create_timer(duration).timeout


func skip(_cutscene_player: Node) -> void:
		# When skipping, we can't actually cancel the await above (it's already
		# pending). But the cutscene player will stop awaiting execute() after
		# the skip signal fires, so this is fine — the timer will fire in the
		# background and be cleaned up with the scene tree.
		pass
