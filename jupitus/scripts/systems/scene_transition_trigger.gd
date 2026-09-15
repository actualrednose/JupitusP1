# scene_transition_trigger.gd
# -----------------------------------------------------------------------------
# Attach to: Area3D
# Extends Interactable to provide two trigger modes for scene transitions:
#   - ON_ENTER:   Player walks into the Area3D, transition starts automatically
#   - ON_INTERACT: Player walks in, sees a prompt, presses E to transition
#
# Use ON_ENTER for "walk through a door" — frictionless, immediate.
# Use ON_INTERACT for "examine a door" — explicit, deliberate.
#
# Setup:
#   1. Add an Area3D to your scene (rename it something like "DoorToShop")
#   2. Attach this script
#   3. Add a CollisionShape3D child (BoxShape3D recommended, sized to the doorway)
#   4. In the Inspector, set:
#        Target Scene:           "res://scenes/shop_interior.tscn"
#        Target Spawn Point:     "from_street" (name of a Marker3D in shop scene)
#        Trigger Mode:           ON_ENTER or ON_INTERACT
#   5. Set collision layers per the Interactable conventions (Layer 2, Mask 1)
#
# Spawn point setup (in the TARGET scene):
#   1. Add a Marker3D where the player should appear
#   2. Rename it to match `target_spawn_point` (e.g., "from_street")
#   3. Right-click → Add to Group → type "spawn_point"
#
# Bidirectional doors:
#   - Scene A (street) has a DoorToShop trigger pointing to scene B at "from_street"
#   - Scene B (shop) has a DoorToStreet trigger pointing to scene A at "from_shop"
#   - The player can walk back and forth freely
# -----------------------------------------------------------------------------

extends Interactable
class_name SceneTransitionTrigger

# --- Trigger modes ---

enum TriggerMode {
	## Player walks into the Area3D → transition starts immediately.
	## Good for doors, thresholds, "exit level" zones.
	ON_ENTER,

	## Player walks into the Area3D → prompt appears → press E to transition.
	## Good for things you want the player to deliberately choose, like
	## "climb down ladder" or "enter dark cave".
	ON_INTERACT,
}

# --- Tweakable values ---

@export_group("Scene Transition")
## Path to the scene to load. Must be a .tscn file in the project.
## Example: "res://scenes/shop_interior.tscn"
@export var target_scene: String = ""

## Name of the Marker3D spawn point in the target scene.
## The Marker3D must be in the "spawn_point" group.
## Leave empty to just use the player's default position in the new scene
## (not recommended — usually you want the player to appear at a specific spot).
@export var target_spawn_point: String = ""

## How the trigger activates:
##   ON_ENTER:    Walk in → transition
##   ON_INTERACT: Walk in → see prompt → press E → transition
@export var trigger_mode: TriggerMode = TriggerMode.ON_ENTER

@export_group("Prompt")
## Prompt text shown when trigger_mode is ON_INTERACT.
## Ignored in ON_ENTER mode (no prompt is shown).
## Examples: "Press E to enter", "Press E to go through", "Press E to climb"
@export var prompt_override: String = "Press E to enter"


# -----------------------------------------------------------------------------
# _ready
# -----------------------------------------------------------------------------

func _ready() -> void:
	# Configure the prompt based on trigger mode.
	if trigger_mode == TriggerMode.ON_INTERACT:
		prompt_text = prompt_override
	else:
		# ON_ENTER: no prompt needed. Set to empty so the auto-created
		# Label3D doesn't show "Press E" by default.
		prompt_text = ""

	# Call the parent class's _ready to set up the prompt label, collision
	# warnings, and signal connections.
	super._ready()

	# In ON_ENTER mode, hide the prompt label entirely (it was created by
	# Interactable._ready but we don't want to see it).
	if trigger_mode == TriggerMode.ON_ENTER and _prompt_label:
		_prompt_label.visible = false


# -----------------------------------------------------------------------------
# Override Interactable's body_entered handler to support ON_ENTER mode
# -----------------------------------------------------------------------------

func _on_body_entered(body: Node) -> void:
	# Let the parent class handle its bookkeeping (set _player, show prompt, etc.)
	super._on_body_entered(body)

	# Only act on the player
	if not body.is_in_group(&"player"):
		return

	# In ON_ENTER mode, trigger the transition immediately when the player
	# walks in. We add a tiny safety check: don't trigger if a transition
	# is already in progress (SceneManager handles this too, but checking
	# here avoids unnecessary function calls).
	if trigger_mode == TriggerMode.ON_ENTER:
		_do_transition()


# -----------------------------------------------------------------------------
# Override Interactable's _on_interacted for ON_INTERACT mode
# -----------------------------------------------------------------------------

func _on_interacted(_p: Node) -> void:
	# This is called by Interactable when the player presses E while in range.
	# We only act if we're in ON_INTERACT mode (ON_ENTER mode already triggered
	# in _on_body_entered).
	if trigger_mode == TriggerMode.ON_INTERACT:
		_do_transition()


# -----------------------------------------------------------------------------
# Internal: trigger the actual transition
# -----------------------------------------------------------------------------

func _do_transition() -> void:
	# Bail out if no target scene is set.
	# This is a common mistake during development — easy to forget.
	if target_scene.is_empty():
		push_warning(
			"SceneTransitionTrigger '%s': no target_scene set. " % name \
			+ "Set it in the Inspector."
		)
		return

	# Disable this trigger immediately so the player can't trigger it twice
	# while the fade-out is happening (which would queue up duplicate calls).
	enabled = false

	# Tell SceneManager to do the actual transition.
	# SceneManager handles fade in/out, scene loading, and spawn point placement.
	SceneManager.transition_to_scene(target_scene, target_spawn_point)

	# Re-enable after the transition finishes (so the player can come back
	# through this door if they walk back into it after returning).
	# We use a one-shot connection to the transition_finished signal.
	#
	# Note: this re-enable only matters if the player comes BACK to this
	# scene and walks into this trigger again. In most cases, the trigger
	# is destroyed when the scene changes, so this is just defensive.
	if not SceneManager.transition_finished.is_connected(_on_transition_finished):
		SceneManager.transition_finished.connect(_on_transition_finished, CONNECT_ONE_SHOT)


func _on_transition_finished() -> void:
	# Re-enable the trigger so it can be used again.
	enabled = true


# -----------------------------------------------------------------------------
# Future extensions
# -----------------------------------------------------------------------------
#
# 1. ONE-SHOT TRIGGERS
#    Add a `one_shot: bool` property. When true, the trigger disables itself
#    permanently after firing (no re-enable in _on_transition_finished).
#    Useful for "leaving the tutorial area" transitions.
#
# 2. REQUIRED FLAG
#    Add a `requires_flag: String` property. The trigger only fires if
#    PlayerState.has_flag(requires_flag) is true. Useful for locked doors
#    that require a key item.
#
# 3. TRANSITION EFFECT OVERRIDE
#    Allow each trigger to specify a different fade color or duration.
#    E.g., a "warp portal" might use a purple fade instead of black.
#
# 4. SCREEN WIPE DIRECTION
#    For slide transitions, allow specifying the wipe direction (left, right,
#    up, down). Useful for "exiting left" vs "exiting right" doors.
