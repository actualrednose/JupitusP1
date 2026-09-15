# interactable.gd
# -----------------------------------------------------------------------------
# Attach to: Area3D (the base node)
# Extend this class to make NPCs, signs, doors, items, levers, etc.
#
# What this script does:
#   - Detects when the player walks into an interaction range (Area3D)
#   - Shows a floating "Press E" prompt above the object when player is in range
#   - Listens for the "interact" input action (default: E key)
#   - Routes the interaction through virtual methods AND emits signals
#     so subclasses and external listeners can both hook in
#
# How to use:
#   1. Add an Area3D node to your scene, rename it (e.g., "NPC_Shopkeeper")
#   2. Attach this script
#   3. Add a CollisionShape3D child to define the interaction range
#      (a SphereShape3D with radius ~1.0 is a good default)
#   4. Set "Prompt Text" in the Inspector
#   5. Either:
#        a) Connect to the "interacted" signal in another script, OR
#        b) Create a subclass that overrides _on_interacted()
#
# Example subclass (npc.gd):
#   extends Interactable
#   func _on_interacted(player):
#       print("Hello, " + player.name)
#       # Start dialogue here in Phase 2
# -----------------------------------------------------------------------------

extends Area3D
class_name Interactable

# --- Tweakable values ---

@export_group("Prompt")
## Text shown above the object when the player is in range.
## You can also change this at runtime via set_prompt_text().
@export var prompt_text: String = "Press E"

## How high above the interactable's origin the prompt label floats, in meters.
## Adjust based on your object's height — for a 1m-tall NPC, 1.2 works.
## For a floor-level item, 0.5 is better.
@export var prompt_height: float = 1.2

## Font size for the prompt label. Higher = bigger text.
## 32 is readable at close range; 48+ is better for distant prompts.
@export var prompt_font_size: int = 32

@export_group("Input")
## Which input action triggers the interaction. Defaults to "interact".
## You might want different actions for different interactables — e.g., a
## door could use "interact" but a save point could use "save".
## Use StringName (&"...") since this is compared against InputEvent action names.
@export var input_action: StringName = &"interact"

@export_group("Behavior")
## When false, the interactable ignores the player entirely.
## Use this to disable an interactable during cutscenes, after it's been
## used once, while a dialogue is in progress, etc.
@export var enabled: bool = true

## If true, the prompt only shows when the player is roughly facing the
## interactable (within ±90° of the direction to it). Reduces screen clutter
## when multiple interactables are nearby. Set false for "always show when
## in range" behavior (simpler, but can be visually noisy).
@export var require_facing: bool = false

## Half-angle (in degrees) of the facing cone when require_facing is true.
## 60° = fairly forgiving, 30° = must be looking almost directly at it.
@export_range(10.0, 90.0) var facing_cone_degrees: float = 60.0

# --- Signals ---

# Signals are Godot's observer pattern. Other nodes can connect to these
# to react to events WITHOUT the Interactable needing to know about them.
# This keeps your code decoupled — the NPC script doesn't need to know
# about the dialogue system, and vice versa.

## Emitted when the player enters the interaction range.
## Passes the player node so listeners can do things like stop the player's
## movement, read the player's stats, etc.
signal focus_entered(player: Node)

## Emitted when the player leaves the interaction range.
signal focus_exited(player: Node)

## Emitted when the player triggers the interaction (presses the input key
## while in range). This is what most listeners will care about.
signal interacted(player: Node)

# --- Internal state ---

# Cached player reference. We grab this once on _ready (via the "player" group)
# rather than searching every frame. Set back to null if the player leaves.
var _player: Node = null

# Whether the player is currently inside our Area3D.
var _player_in_range: bool = false

# Auto-created Label3D for the prompt. Cached so we don't search children
# every time we want to update it.
var _prompt_label: Label3D = null


# -----------------------------------------------------------------------------
# _ready runs once when the interactable enters the scene tree.
# We use it to:
#   1. Set up sensible default collision layers (so the Area3D actually
#      detects the player and the player detects it)
#   2. Auto-create a prompt label if the user didn't add one manually
#   3. Connect our own Area3D signals (body_entered, body_exited)
# -----------------------------------------------------------------------------

func _ready() -> void:
	# --- Collision layer sanity check ---
	# Godot has 32 collision layers, each a yes/no bit. The convention we use:
	#   Layer 1 = Player (the player's CharacterBody3D lives here)
	#   Layer 2 = Interactables (this Area3D lives here)
	#
	# For detection to work, the Area3D's MASK must include layer 1 (player),
	# and the player's LAYER must include layer 1.
	#
	# The mask is which layers THIS area listens to. The layer is which
	# layers THIS area broadcasts on. An Area3D detects a body when:
	#   (body.collision_layer & area.collision_mask) != 0
	#
	# If you forget to set these, the Area3D won't fire body_entered and
	# the interactable will silently do nothing. This is the #1 bug source
	# for new Godot devs working with Area3D, so we add a warning here.
	#
	# We use a bitwise check: collision_mask & 1 checks if bit 1 (value 1)
	# is set in the mask. 1 << 0 = 1. Layer 2 would be 1 << 1 = 2.
	if (collision_mask & 1) == 0:
		push_warning(
			"Interactable '%s': collision_mask doesn't include layer 1 (player). " \
			% name + "Set Mask > Layer 1 in the Inspector or the Area3D won't detect the player."
		)

	# --- Set up the prompt label ---
	_setup_prompt_label()

	# --- Connect Area3D signals to our handler methods ---
	# In Godot 4, you can connect signals via code like this:
	#   signal_name.connect(callable)
	# This is equivalent to wiring them up in the editor's Node panel.
	# We use it here so the user doesn't have to manually wire anything.
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


# -----------------------------------------------------------------------------
# _unhandled_input receives input events that weren't consumed by UI.
# We use _unhandled_input (NOT _input) because:
#   - _input runs for every input event, including ones the UI will consume
#   - _unhandled_input only runs if no UI node consumed the event first
#   - This means when a dialogue box is open and "consumes" the E press to
#     advance dialogue, this interactable won't ALSO try to re-trigger
#     (which would cause a feedback loop of dialogue restarts)
#
# Important: this method is called for EVERY input event (mouse moves, key
# presses, key releases, gamepad axis changes). We early-return for anything
# that isn't our action.
# -----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Bail out fast if we shouldn't be processing input right now.
	# Order matters: check `enabled` first (cheapest), then `in_range`.
	if not enabled or not _player_in_range:
		return

	# DEFENSIVE: don't trigger interactions while dialogue is active.
	# The DialogueBox should consume input via set_input_as_handled(),
	# but we check here too in case:
	#   - The DialogueBox isn't active yet (race condition during startup)
	#   - Other UI systems are consuming input we don't know about
	#   - Future systems (menus, cutscenes) need to suppress interactions
	#
	# We use a try/catch-free pattern: check if DialogueManager exists as
	# an autoload (via get_node_or_null) before calling its methods. This
	# makes the Interactable robust even if the autoload isn't registered.
	var dm: Node = get_node_or_null("/root/DialogueManager")
	if dm and dm.has_method("is_dialogue_active") and dm.is_dialogue_active():
		return

	# is_action_pressed returns true only on the initial press, not on
	# key repeats or releases. This is what we want — one interaction per
	# key press, not a stream of them while held.
	#
	# Note: if event.is_action_pressed() returns false for any event that
	# isn't our action, so we don't need an explicit action check.
	if not event.is_action_pressed(input_action):
		return

	# Optional facing check — only fire if the player is looking at us.
	# Useful when multiple interactables overlap; prevents accidental triggers.
	if require_facing and not _is_player_facing_us():
		return

	# Get the player (cached from when they entered range).
	# If for some reason we lost the reference (player got freed, etc.),
	# bail out gracefully instead of crashing.
	if _player == null or not is_instance_valid(_player):
		push_warning("Interactable '%s': interacted called but player reference is invalid" % name)
		return

	# Fire the signal (for external listeners) AND call the virtual method
	# (for subclass overrides). Both patterns are valid:
	#   - Signals: good for "many possible listeners, decoupled" (e.g., a
	#     quest system that listens to all interactables)
	#   - Virtual methods: good for "this specific subclass does X" (e.g.,
	#     an NPC subclass that starts a dialogue)
	# We do both so you can pick whichever fits your use case.
	interacted.emit(_player)
	_on_interacted(_player)


# -----------------------------------------------------------------------------
# _process runs every frame. We use it for the optional facing check,
# updating prompt visibility when require_facing is true.
# If require_facing is false, this method does nothing visible.
# -----------------------------------------------------------------------------

func _process(_delta: float) -> void:
	# Only do work if we need to
	if not enabled or not _player_in_range:
		return

	if not require_facing:
		return

	# Update prompt visibility based on facing direction
	if _prompt_label:
		_prompt_label.visible = _is_player_facing_us()


# -----------------------------------------------------------------------------
# Detection handlers
# -----------------------------------------------------------------------------

# Called by Area3D.body_entered when ANY physics body enters our area.
# We need to filter to just the player — Area3Ds will fire for every
# CharacterBody3D, RigidBody3D, etc. that touches them.
func _on_body_entered(body: Node) -> void:
	# Check if this body is the player. We use the "player" group (set up
	# in the README) rather than checking the body's type or name. Groups
	# are more flexible — you can have multiple controllable characters
	# without changing this check.
	if not body.is_in_group(&"player"):
		return

	_player = body
	_player_in_range = true

	# Show the prompt (unless we're in facing-required mode, in which case
	# _process will handle visibility)
	if _prompt_label and not require_facing:
		_prompt_label.visible = true

	# Notify listeners
	focus_entered.emit(body)
	# Call the virtual method so subclasses can react (e.g., play a sound,
	# change animation to "notice player")
	_on_focus_entered(body)


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group(&"player"):
		return

	# Only clear if this is the same player we were tracking.
	# (Defensive — shouldn't normally happen, but prevents weirdness if
	# somehow two "player"-tagged bodies were in range.)
	if body != _player:
		return

	_player = null
	_player_in_range = false

	if _prompt_label:
		_prompt_label.visible = false

	focus_exited.emit(body)
	_on_focus_exited(body)


# -----------------------------------------------------------------------------
# Facing check
# -----------------------------------------------------------------------------

func _is_player_facing_us() -> bool:
	# Defensive: if we don't have a valid player reference, return false.
	if _player == null or not is_instance_valid(_player):
		return false

	# Vector from the player to us.
	var to_us: Vector3 = global_position - _player.global_position
	# Flatten to the XZ plane so we only consider horizontal facing
	# (we don't want to fail the check just because the player is below us).
	to_us.y = 0.0

	# If we're at the exact same position as the player, treat as facing.
	if to_us.length_squared() < 0.0001:
		return true

	to_us = to_us.normalized()

	# Player's forward direction. For a CharacterBody3D, "forward" depends on
	# how the model is oriented. Godot convention is -Z forward, but since
	# our sprite flips rather than the body rotating, we use the velocity
	# direction as a proxy for "where the player is looking."
	#
	# Fallback: if the player isn't moving, use their last movement direction.
	# We'd need the player controller to expose this — for now, we use velocity.
	# If velocity is zero, we assume the player is facing wherever they last
	# faced (which we approximate as "toward us" — generous default).
	var player_forward: Vector3 = _player.velocity
	if player_forward.length_squared() < 0.01:
		return true  # Player not moving — assume they could be facing us
	player_forward.y = 0.0
	player_forward = player_forward.normalized()

	# Dot product: 1.0 = same direction, 0 = perpendicular, -1.0 = opposite.
	# cos(facing_cone_degrees) is the threshold for "inside the cone".
	# E.g., 60° cone → cos(60°) = 0.5 → dot must be > 0.5 to count as facing.
	var threshold: float = cos(deg_to_rad(facing_cone_degrees))
	return player_forward.dot(to_us) >= threshold


# -----------------------------------------------------------------------------
# Public API (callable from other scripts)
# -----------------------------------------------------------------------------

## Change the prompt text at runtime. Useful for dynamic prompts like
## "Press E to talk" → "Press E to skip" during a conversation.
func set_prompt_text(text: String) -> void:
	prompt_text = text
	if _prompt_label:
		_prompt_label.text = text


## Manually trigger an interaction. Useful for cutscenes where you want
## an NPC to "interact" without the player pressing a key.
func trigger_interaction(player: Node = null) -> void:
	var p: Node = player if player != null else _player
	if p == null:
		p = get_tree().get_first_node_in_group(&"player")
	if p == null:
		push_warning("Interactable '%s': trigger_interaction called but no player found" % name)
		return
	interacted.emit(p)
	_on_interacted(p)


# -----------------------------------------------------------------------------
# Setup helpers
# -----------------------------------------------------------------------------

func _setup_prompt_label() -> void:
	# First, check if a Label3D already exists as a child. This lets the
	# user customize the label (font, color, etc.) in the editor if they
	# want to override our defaults.
	for child in get_children():
		if child is Label3D:
			_prompt_label = child
			break

	# If none exists, create one. We add it as a child of THIS node, so
	# it inherits our position. The prompt_height offset moves it up.
	if _prompt_label == null:
		_prompt_label = Label3D.new()
		_prompt_label.name = "PromptLabel"
		add_child(_prompt_label)
		# When you add a child via code in _ready, you need to set its
		# owner to the scene root for it to be saved with the scene.
		# This only matters if you save the scene after this runs — for
		# runtime instances it's irrelevant. We set it for cleanliness.
		_prompt_label.owner = owner

	# Configure the label.
	# These properties can also be set in the editor if the user prefers.
	_prompt_label.text = prompt_text
	_prompt_label.position = Vector3(0, prompt_height, 0)
	_prompt_label.font_size = prompt_font_size

	# Billboard mode makes the label always face the camera. Without this,
	# the label would face +Z by default and you'd see it edge-on from
	# certain angles.
	#
	# BILLBOARD_ENABLED: full billboard (always faces camera, also rotates
	#   up/down to face camera fully)
	# BILLBOARD_FIXED_Y: only rotates around the Y axis (good for signs
	#   that should always be readable but stay "grounded")
	# BILLBOARD_DISABLED: doesn't rotate (label faces whatever direction
	#   you set its rotation to)
	#
	# We use BILLBOARD_ENABLED because the prompt should always be readable
	# regardless of camera angle.
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED

	# no_depth_test = true means the label renders on top of everything
	# regardless of distance. This is what we want for UI prompts — you
	# don't want the prompt hidden behind a wall when the player is in range.
	#
	# Trade-off: with no_depth_test, the prompt will "show through" walls.
	# For our use case (the prompt only shows when player is in range, so
	# walls between player and object are unlikely), this is fine.
	_prompt_label.no_depth_test = true

	# Modulate color — slightly translucent so the prompt doesn't compete
	# visually with the world. 0.9 alpha is barely noticeable but softens
	# the edges. Adjust to taste.
	_prompt_label.modulate = Color(1, 1, 1, 0.9)

	# Start hidden. Will be shown when player enters range.
	_prompt_label.visible = false


# -----------------------------------------------------------------------------
# Virtual methods — override these in subclasses to add custom behavior.
# The underscore prefix is a Godot convention for "this is intended to be
# overridden" (similar to _ready, _process, etc.).
# -----------------------------------------------------------------------------

## Called when the player enters the interaction range. Override in subclasses
## to e.g., play a "noticed player" animation, play a sound, etc.
##
## The parameter is prefixed with `_` to indicate it's intentionally unused
## in the base class. Subclasses can rename it to `player` (no underscore) if
## they actually use it.
func _on_focus_entered(_p: Node) -> void:
	pass


## Called when the player leaves the interaction range. Override in subclasses
## to clean up any focus-related state.
func _on_focus_exited(_p: Node) -> void:
	pass


## Called when the player presses the interact button while in range.
## Override in subclasses to define what this object actually DOES when
## interacted with (start dialogue, open chest, trigger cutscene, etc.)
func _on_interacted(_p: Node) -> void:
	# Default implementation just prints. Useful for testing — you'll see
	# the message in the Output panel when you interact.
	# Replace this in subclasses or just delete the body entirely.
	print("Interactable '%s' was interacted with" % name)


# -----------------------------------------------------------------------------
# Future extensions (not implemented yet, just notes for later)
# -----------------------------------------------------------------------------
#
# 1. COOLDOWN / ONE-SHOT INTERACTIONS
#    Add a `one_shot: bool` property. When true, the interactable disables
#    itself after the first interaction. Useful for chests, switches, etc.
#    Implementation: set `enabled = false` at the end of _on_interacted().
#
# 2. INTERACTION ANIMATION
#    Play a subtle bob/pulse animation on the prompt when it appears.
#    Implementation: create a Tween in _on_focus_entered that scales the
#    label up from 0 to 1 over 0.15s. Reverse in _on_focus_exited.
#
# 3. PROMPT CUSTOMIZATION
#    Allow subclasses to override the prompt icon (e.g., a hand for "examine",
#    a speech bubble for "talk", a key for "open"). Implementation: replace
#    the Label3D with a more flexible Control-in-3D setup, or use a texture.
#
# 4. INTERACTION PRIORITY
#    When multiple interactables overlap, the closest one should win.
#    Current implementation: all overlapping interactables fire on E press.
#    Fix: have an InteractionManager that picks the closest one. See notes
#    in the next phase's README.
