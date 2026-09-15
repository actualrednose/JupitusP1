# npc.gd
# -----------------------------------------------------------------------------
# Example subclass of Interactable. Demonstrates the pattern for making
# NPCs that talk back, now with actual dialogue support.
#
# Attach to: Area3D (the same as Interactable)
# This script EXTENDS Interactable — so the Area3D gets all the detection,
# prompt, and input handling from the base class automatically. We only
# override the methods we care about.
#
# When you build more NPC types (shopkeeper, questgiver, etc.), copy this
# file, rename it, and customize the dialogue data + behavior.
# -----------------------------------------------------------------------------

extends Interactable
class_name NPC

# --- NPC-specific properties ---

@export_group("NPC")
## The NPC's name. Shown in editor for identification; the dialogue box
## uses the speaker's DialogueCharacter.display_name instead.
@export var npc_name: String = "NPC"

## The dialogue to play the FIRST time the player talks to this NPC.
## Drag a DialogueData .tres file here in the Inspector.
## If null, the NPC will use fallback_dialogue (or just print to console
## if both are null).
@export var first_dialogue: DialogueData = null

## The dialogue to play on subsequent interactions (after first_dialogue
## has been seen once). If null, reuses first_dialogue.
@export var repeat_dialogue: DialogueData = null

## Whether this NPC has been talked to before. Used to pick between
## first_dialogue and repeat_dialogue. Reset to false when the game reloads
## (for a persistent version, store this in DialogueManager.flags).
var talked_to_before: bool = false


# We override _ready to set up sensible defaults for an NPC.
# (super._ready() calls the parent class's _ready, which sets up the
# prompt label and connects signals — we don't want to skip that.)
func _ready() -> void:
	# Set a more appropriate default prompt for an NPC.
	# We do this BEFORE calling super._ready() so the prompt label gets
	# created with the right text from the start.
	if prompt_text == "Press E":
		prompt_text = "Press E to talk"

	# Call the parent class's _ready to do the actual setup.
	super._ready()


# Override _on_focus_entered to play a "noticed player" reaction.
func _on_focus_entered(_p: Node) -> void:
	# Future: play a "noticed player" animation, turn to face them, etc.
	pass


# Override _on_focus_exited for cleanup if needed.
func _on_focus_exited(_p: Node) -> void:
	pass


# Override _on_interacted to start the dialogue system.
func _on_interacted(_p: Node) -> void:
	# Pick which dialogue to play
	var data: DialogueData = null
	if not talked_to_before:
		data = first_dialogue
		talked_to_before = true
	else:
		data = repeat_dialogue if repeat_dialogue != null else first_dialogue

	if data == null:
		# Fallback if no dialogue is set — useful during early dev when you
		# haven't authored the dialogue .tres files yet.
		print("NPC '%s' has no dialogue data — set first_dialogue in the Inspector" % npc_name)
		return

	# Start the dialogue via the global DialogueManager singleton.
	# The manager handles creating the dialogue box, freezing the player,
	# and playing the conversation.
	DialogueManager.start_dialogue(data)


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

## Reset the NPC's "talked to" state. Useful if you want the first dialogue
## to replay (e.g., after a story event changes their relationship).
func reset_talked_to() -> void:
	talked_to_before = false
