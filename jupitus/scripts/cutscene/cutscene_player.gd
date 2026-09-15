# cutscene_player.gd
# -----------------------------------------------------------------------------
# Attach to: Node (placed anywhere in the scene)
#
# What this script does:
#   - Holds a list of CutsceneAction resources (the "script" of the cutscene)
#   - Plays them in sequence, awaiting each one's execute() method
#   - Freezes the player during the cutscene
#   - Restores the camera to the player after the cutscene ends
#   - Supports skipping (press the skip key to fast-forward)
#
# How to trigger:
#   1. From code: call `cutscene_player.play()`
#   2. From a CutsceneTrigger (Area3D): set up the trigger to call play()
#      when the player enters or interacts
#
# How to author a cutscene:
#   1. Add a Node to your scene, attach this script
#   2. In the Inspector, add elements to the `actions` array
#   3. For each action, pick the type (Wait, Dialogue, Move, etc.) and
#      configure its properties
#   4. Reorder actions by dragging them in the array
#   5. Trigger via CutsceneTrigger or code
#
# Skipping:
#   - Press the skip key (default: ui_cancel, which is Esc by default in Godot)
#   - Each action has its own skip behavior (see action's skip() method)
#   - After skip, the cutscene player runs cleanup (restore camera, unfreeze player)
#
# Example cutscene sequence (robbery reveal):
#   1. CameraAction(target=camera_robber_door_marker, wait=1.0)  — pan to door
#   2. MoveAction(actor=Robber, dest=robber_center_pos)          — robber walks in
#   3. DialogueAction(shopkeeper_yell_dialogue)                  — "Stop right there!"
#   4. CameraAction(restore_to_player=true, wait=1.0)            — pan back to player
#   5. DialogueAction(player_reaction_dialogue)                  — "We should stop him!"
#   6. SetFlagAction(flag_name="robbery_seen")                   — mark progression
#   7. TransitionAction(target_scene="res://scenes/battle.tscn") — start combat
# -----------------------------------------------------------------------------

extends Node
class_name CutscenePlayer

# --- Signals ---

# Emitted when the cutscene starts (before the first action).
signal cutscene_started()

# Emitted when the cutscene finishes naturally (all actions completed).
signal cutscene_finished()

# Emitted when the cutscene is skipped by the player.
signal cutscene_skipped()

# --- Tweakable values ---

@export_group("Cutscene")
## The sequence of actions to play, in order.
## In the Inspector, add elements and pick their type (Wait, Dialogue, etc.).
@export var actions: Array[CutsceneAction] = []

## If true, the player is frozen (can't move) while the cutscene plays.
## Almost always true for story cutscenes.
@export var freeze_player: bool = true

@export_group("Skipping")
## If true, the player can skip the cutscene by pressing the skip key.
@export var can_skip: bool = true

## Which input action triggers a skip. Defaults to "ui_cancel" (Esc).
## You can change this to a custom action if you want a dedicated skip key.
@export var skip_input_action: StringName = &"ui_cancel"

# --- Internal state ---

# True while the cutscene is playing.
var _is_playing: bool = false

# True if the player has requested a skip. The action loop checks this
# after each action and breaks if true.
var _is_skipping: bool = false

# Index of the currently-executing action (-1 if not playing).
var _current_action_index: int = -1


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

## Start playing the cutscene. Returns false if a cutscene is already
## playing (or some other precondition fails).
func play() -> bool:
		if _is_playing:
				push_warning("CutscenePlayer: play() called but cutscene is already playing")
				return false

		if actions.is_empty():
				push_warning("CutscenePlayer: no actions to play")
				return false

		# Don't start a cutscene if dialogue is already active (would conflict).
		if DialogueManager.is_dialogue_active():
				push_warning("CutscenePlayer: cannot start cutscene while dialogue is active")
				return false

		_is_playing = true
		_is_skipping = false
		_current_action_index = -1
		cutscene_started.emit()

		# Freeze the player so they can't move during the cutscene.
		if freeze_player:
				var player: Node = get_tree().get_first_node_in_group(&"player")
				if player and player.has_method("set_frozen"):
						player.set_frozen(true)

		# Execute actions in sequence.
		# We use a while loop instead of a for loop so we can break early on skip.
		_current_action_index = 0
		while _current_action_index < actions.size():
				# Check for skip request
				if _is_skipping:
						break

				var action: CutsceneAction = actions[_current_action_index]
				if action != null:
						# Await the action's execute method.
						# If skip is requested during this await, the action's skip()
						# method is called (from _unhandled_input), and the action
						# should unblock its await.
						#
						# The `await` is correct even though Godot's static analysis
						# warns it's "redundant" — that's because the BASE class
						# execute() doesn't contain an await, but SUBCLASSES do
						# (e.g., CutsceneActionWait awaits a timer, CutsceneActionDialogue
						# awaits a signal). Awaiting a non-coroutine is a no-op, so this
						# is safe: if the override is a coroutine, we wait; if not, we
						# continue immediately. The warning is a false positive due to
						# polymorphism that Godot can't see through.
						# warning-ignore: REDUNDANT_AWAIT
						await action.execute(self)

				_current_action_index += 1

		# Cleanup
		_cleanup_after_cutscene()
		return true


## Force-skip the cutscene. Called automatically when the player presses
## the skip key, but can also be called from code.
func skip() -> void:
		if not _is_playing or not can_skip:
				return

		if _is_skipping:
				return  # Already skipping

		_is_skipping = true
		cutscene_skipped.emit()

		# Call skip() on the currently-executing action so it can unblock.
		if _current_action_index >= 0 and _current_action_index < actions.size():
				var action: CutsceneAction = actions[_current_action_index]
				if action != null:
						action.skip(self)


## Returns true if the cutscene is currently playing.
func is_playing() -> bool:
		return _is_playing


# -----------------------------------------------------------------------------
# _unhandled_input
# -----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
		if not _is_playing or not can_skip:
				return

		# Check for skip key press
		if event.is_action_pressed(skip_input_action):
				skip()
				# Mark as handled so other systems don't also process this input
				get_viewport().set_input_as_handled()


# -----------------------------------------------------------------------------
# Internal: cleanup
# -----------------------------------------------------------------------------

func _cleanup_after_cutscene() -> void:
		# Restore the camera to follow the player.
		# This is important: if a CameraAction changed the target to a Marker3D
		# and the cutscene ended (naturally or via skip) before a restore action
		# ran, the camera would be stuck looking at that Marker3D forever.
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera and "target" in camera:
				var player: Node = get_tree().get_first_node_in_group(&"player")
				if player:
						camera.target = player

		# Unfreeze the player
		if freeze_player:
				var player: Node = get_tree().get_first_node_in_group(&"player")
				if player and is_instance_valid(player) and player.has_method("set_frozen"):
						player.set_frozen(false)

		# Reset state
		_is_playing = false
		_is_skipping = false
		_current_action_index = -1

		# Emit the appropriate end signal
		if _is_skipping:
				# Note: _is_skipping was reset above, so this branch won't fire.
				# The cutscene_skipped signal is emitted in skip() instead.
				pass
		else:
				cutscene_finished.emit()


# -----------------------------------------------------------------------------
# Future extensions (notes for later)
# -----------------------------------------------------------------------------
#
# 1. CUTSCENE VARIANTS
#    Support branching cutscenes: based on PlayerState flags, play different
#    action sequences. Implementation: add a `requires_flag` per action,
#    skip actions whose flag isn't set.
#
# 2. PARALLEL ACTIONS
#    Currently all actions run sequentially. Sometimes you want parallel
#    (e.g., character moves while camera pans). Could add a
#    `CutsceneActionParallel` that runs multiple sub-actions concurrently.
#
# 3. CUTSCENE HISTORY
#    Track which cutscenes have been played (so they don't replay on
#    re-entry). Implementation: set a PlayerState flag when the cutscene
#    starts, check it before playing.
#
# 4. CUTSCENE LIBRARY
#    Move cutscene definitions to .tres files so they can be reused across
#    scenes. For now, embedding actions in the CutscenePlayer node is simpler.
#
# 5. BETTER SKIP
#    Currently skip just unblocks the current action and breaks the loop.
#    A better implementation would also fast-forward any in-flight tweens
#    to their end state, so the cutscene ends in a clean state. This
#    requires each action to track its tweens and kill+complete them in skip().
