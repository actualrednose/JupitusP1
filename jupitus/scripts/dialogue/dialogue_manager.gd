# dialogue_manager.gd
# -----------------------------------------------------------------------------
# This is an Autoload (singleton) — there's only ever one instance of it,
# accessible from anywhere via `DialogueManager`.
#
# What this script does:
#   - Holds the global dialogue box instance
#   - Provides start_dialogue() / end_dialogue() / is_dialogue_active()
#   - Maintains a flags dictionary for branching state
#   - Freezes the player while dialogue is active
#   - Manages the dialogue box lifecycle (creating it on first use,
#     keeping it across scene transitions)
#
# Why a singleton instead of putting this logic on the dialogue box itself?
#   - The dialogue box should be UI-only (display text, handle input).
#   - The manager handles cross-system concerns (freezing the player,
#     tracking flags, surviving scene transitions).
#   - Any NPC, cutscene, or quest script can call
#     `DialogueManager.start_dialogue(data)` without needing a reference
#     to the dialogue box.
#
# To set up:
#   1. Project Settings → Globals (Autoload) → Add
#   2. Path: res://scripts/dialogue/dialogue_manager.gd
#   3. Name: DialogueManager
#   4. Make sure "Enabled" is checked
# -----------------------------------------------------------------------------

extends Node

# --- Signals ---

# Emitted when a conversation starts. Passes the data so listeners can
# e.g., pause AI, change music, etc.
signal dialogue_started(data: DialogueData)

# Emitted when a conversation ends.
signal dialogue_ended()

# --- Public state ---

# Flags set by choices. Other systems can read this:
#   if DialogueManager.flags.get("met_robber", false): ...
#
# These should be cleared on game load / new game.
var flags: Dictionary = {}

# --- Internal state ---

# The dialogue box instance. Created lazily on first start_dialogue call.
var _dialogue_box: DialogueBox = null

# Whether dialogue is currently active. Read via is_dialogue_active().
var _active: bool = false

# Cached player reference, so we can freeze/unfreeze them.
var _player: Node = null


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

## Start a dialogue conversation. Creates the dialogue box if it doesn't
## exist yet. Freezes the player. The dialogue box will handle the rest.
##
## Returns true if the dialogue started, false if it was skipped (e.g.,
## the data's requires_flag wasn't set).
func start_dialogue(data: DialogueData) -> bool:
	if data == null:
		push_warning("DialogueManager: start_dialogue called with null data")
		return false

	# Check requires_flag — if set and not present in our flags, skip.
	if not data.requires_flag.is_empty():
		if not flags.get(data.requires_flag, false):
			return false

	# Don't start a new dialogue if one is already active.
	# (This prevents overlapping conversations — a common bug.)
	if _active:
		push_warning("DialogueManager: start_dialogue called but a dialogue is already active")
		return false

	# Create the dialogue box if needed
	_ensure_dialogue_box()

	# Find and freeze the player
	_player = get_tree().get_first_node_in_group(&"player")
	if _player and _player.has_method("set_frozen"):
		_player.set_frozen(true)

	_active = true
	dialogue_started.emit(data)

	# Tell the dialogue box to start playing. We use call_deferred so the
	# box has a frame to set itself up before starting (avoids race
	# conditions with the tween setup).
	_dialogue_box.start_dialogue.call_deferred(data)

	# Connect to the box's conversation_ended signal (once) so we know
	# when to unfreeze the player and clean up.
	# We use a one-shot connection via CONNECT_ONE_SHOT so we don't
	# accumulate connections over multiple conversations.
	if not _dialogue_box.conversation_ended.is_connected(_on_conversation_ended):
		_dialogue_box.conversation_ended.connect(_on_conversation_ended, CONNECT_ONE_SHOT)

	return true


## Force-end the current dialogue (e.g., if the player opens a menu
## and we want to abort). Usually not needed — dialogue ends naturally.
func end_dialogue() -> void:
	if _dialogue_box:
		_dialogue_box.end_dialogue()
	# _on_conversation_ended will handle cleanup


## Returns true if dialogue is currently active. Other systems should check
## this before doing things that would conflict (e.g., accepting movement input).
func is_dialogue_active() -> bool:
	return _active


## Clear all flags. Call this when starting a new game or loading a save.
func clear_flags() -> void:
	flags.clear()


# -----------------------------------------------------------------------------
# Internal
# -----------------------------------------------------------------------------

func _ensure_dialogue_box() -> void:
	if _dialogue_box != null and is_instance_valid(_dialogue_box):
		return

	# Load the dialogue box scene and instance it
	# The scene path is hardcoded here — if you move dialogue_box.tscn,
	# update this path.
	var box_scene: PackedScene = load("res://scenes/ui/dialogue_box.tscn")
	if box_scene == null:
		push_error("DialogueManager: couldn't load res://scenes/ui/dialogue_box.tscn")
		return

	_dialogue_box = box_scene.instantiate()

	# Add it to the scene tree as a child of the root. Using get_tree().root
	# means it persists across scene transitions (it's not parented to the
	# current scene, which would be freed when the scene changes).
	get_tree().root.add_child(_dialogue_box)

	# Set process mode so the dialogue box keeps running even if the
	# scene tree is paused (e.g., during a cutscene pause).
	_dialogue_box.process_mode = Node.PROCESS_MODE_ALWAYS


func _on_conversation_ended() -> void:
	# Unfreeze the player
	if _player and is_instance_valid(_player) and _player.has_method("set_frozen"):
		_player.set_frozen(false)
	_player = null

	_active = false
	dialogue_ended.emit()

	# Note: we don't free the dialogue box here — we keep it around for
	# reuse in the next conversation. This avoids re-instantiating it
	# every time, which would be wasteful.
