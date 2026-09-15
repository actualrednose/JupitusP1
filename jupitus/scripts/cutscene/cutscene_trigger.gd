# cutscene_trigger.gd
# -----------------------------------------------------------------------------
# Attach to: Area3D
# Extends Interactable to trigger a CutscenePlayer when the player enters
# or interacts.
#
# Use this for "walk into the room, cutscene starts" scenarios.
#
# Setup:
#   1. Add an Area3D to your scene (e.g., "RobberyRevealTrigger")
#   2. Attach this script
#   3. Add a CollisionShape3D child (BoxShape3D, sized to cover the trigger zone)
#   4. Add a CutscenePlayer node to your scene (separate node) and configure
#      its actions
#   5. In the Inspector for this trigger:
#        Cutscene Player: drag the CutscenePlayer node here
#        Trigger Mode:    ON_ENTER (walk in) or ON_INTERACT (press E)
#   6. Set collision layers per the Interactable conventions (Layer 2, Mask 1)
#
# One-shot behavior:
#   By default, the trigger only fires ONCE. After the cutscene plays, the
#   trigger disables itself. This prevents the cutscene from replaying if
#   the player walks back through the trigger zone.
#
#   To change this, set `one_shot = false` in the Inspector.
# -----------------------------------------------------------------------------

extends Interactable
class_name CutsceneTrigger

# --- Trigger modes ---

enum TriggerMode {
	## Player walks into the Area3D → cutscene starts immediately.
	ON_ENTER,

	## Player walks into the Area3D → prompt appears → press E to start cutscene.
	ON_INTERACT,
}

# --- Tweakable values ---

@export_group("Cutscene")
## The CutscenePlayer node to trigger. Drag the CutscenePlayer from your
## scene tree into this slot.
@export var cutscene_player: CutscenePlayer = null

## How the trigger activates:
##   ON_ENTER:    Walk in → cutscene starts
##   ON_INTERACT: Walk in → see prompt → press E → cutscene starts
@export var trigger_mode: TriggerMode = TriggerMode.ON_ENTER

@export_group("Behavior")
## If true (default), the trigger only fires once. After the cutscene plays,
## the trigger disables itself.
##
## Set to false if you want the cutscene to replay every time the player
## walks in (rarely what you want, but useful for testing).
@export var one_shot: bool = true

@export_group("Prompt")
## Prompt text shown when trigger_mode is ON_INTERACT.
@export var prompt_override: String = "Press E to continue"


# -----------------------------------------------------------------------------
# _ready
# -----------------------------------------------------------------------------

func _ready() -> void:
	# Configure the prompt based on trigger mode.
	if trigger_mode == TriggerMode.ON_INTERACT:
		prompt_text = prompt_override
	else:
		# ON_ENTER: no prompt needed.
		prompt_text = ""

	super._ready()

	# In ON_ENTER mode, hide the prompt label entirely.
	if trigger_mode == TriggerMode.ON_ENTER and _prompt_label:
		_prompt_label.visible = false


# -----------------------------------------------------------------------------
# Override Interactable's body_entered handler for ON_ENTER mode
# -----------------------------------------------------------------------------

func _on_body_entered(body: Node) -> void:
	super._on_body_entered(body)

	if not body.is_in_group(&"player"):
		return

	if trigger_mode == TriggerMode.ON_ENTER:
		_trigger_cutscene()


# -----------------------------------------------------------------------------
# Override Interactable's _on_interacted for ON_INTERACT mode
# -----------------------------------------------------------------------------

func _on_interacted(_p: Node) -> void:
	if trigger_mode == TriggerMode.ON_INTERACT:
		_trigger_cutscene()


# -----------------------------------------------------------------------------
# Internal: trigger the cutscene
# -----------------------------------------------------------------------------

func _trigger_cutscene() -> void:
	# Bail out if no cutscene player is assigned.
	if cutscene_player == null:
		push_warning(
			"CutsceneTrigger '%s': no cutscene_player assigned. " % name \
			+ "Drag a CutscenePlayer node into the slot in the Inspector."
		)
		return

	# Bail out if the cutscene is already playing (e.g., player walked
	# back into the trigger zone mid-cutscene — shouldn't happen, but defensive).
	if cutscene_player.is_playing():
		push_warning("CutsceneTrigger '%s': cutscene is already playing" % name)
		return

	# Disable this trigger immediately so the player can't trigger it twice.
	# (For one_shot triggers, this is permanent. For non-one-shot, we'll
	# re-enable after the cutscene ends.)
	enabled = false

	# Start the cutscene.
	cutscene_player.play()

	# For non-one-shot triggers, re-enable after the cutscene finishes.
	if not one_shot:
		if not cutscene_player.cutscene_finished.is_connected(_on_cutscene_finished):
			cutscene_player.cutscene_finished.connect(_on_cutscene_finished, CONNECT_ONE_SHOT)
		# Also re-enable if the cutscene was skipped
		if not cutscene_player.cutscene_skipped.is_connected(_on_cutscene_finished):
			cutscene_player.cutscene_skipped.connect(_on_cutscene_finished, CONNECT_ONE_SHOT)


func _on_cutscene_finished() -> void:
	# Re-enable the trigger so it can fire again.
	enabled = true


# -----------------------------------------------------------------------------
# Future extensions
# -----------------------------------------------------------------------------
#
# 1. REQUIRED FLAG
#    Add a `requires_flag: String` property. The trigger only fires if
#    PlayerState.has_flag(requires_flag) is true. Useful for "this cutscene
#    only plays after the player has done X".
#
# 2. SETS FLAG ON TRIGGER
#    Auto-set a flag when the cutscene triggers, so other systems know
#    "this cutscene has been played". Currently one_shot handles this
#    within a single session, but a flag would persist across saves.
#
# 3. MULTIPLE CUTSCENES
#    Support multiple CutscenePlayers, picking which one to play based on
#    a flag check. E.g., play "robbery_first_time" if !has_flag, else
#    play "robbery_revisit".
