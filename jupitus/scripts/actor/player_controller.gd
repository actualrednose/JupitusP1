# player_controller.gd
# -----------------------------------------------------------------------------
# Attach to: CharacterBody3D (the player root node)
#
# What this script does:
#   - Reads WASD / arrow input and moves the character on the XZ plane
#   - Smoothly accelerates/decelerates so movement feels weighty, not robotic
#   - Flips the sprite horizontally based on movement direction
#   - Switches between "idle" and "walk" animations automatically
#
# Required node setup (see README for full details):
#   CharacterBody3D (Player)   <- this script
#   ├── AnimatedSprite3D       (name it "Sprite", needs "idle" + "walk" anims)
#   └── CollisionShape3D       (CapsuleShape3D recommended)
#
# Expected input actions (set up in Project Settings → Input Map):
#   move_up, move_down, move_left, move_right
# -----------------------------------------------------------------------------

extends CharacterBody3D
class_name PlayerController

# --- Tweakable values (these show up in the Inspector) ---

@export_group("Movement")
## Movement speed in meters per second.
## 3.0 = brisk walk, 5.0 = jog, 7.0+ = run. Tune to taste.
@export var move_speed: float = 3.0

## How fast the character accelerates toward the target velocity, in m/s².
## Higher = snappier response. Lower = "slippery" feel.
@export var acceleration: float = 10.0

## How fast the character decelerates when no input is held, in m/s².
## Usually slightly higher than acceleration for a responsive stop.
@export var friction: float = 12.0

@export_group("Sprite")
## If true, the sprite's flip_h property auto-updates to face movement direction.
## Set this to false if you have separate left/right animations in your
## SpriteFrames resource and want to swap animations instead of flipping.
@export var flip_sprite_to_face_direction: bool = true

## The path to the AnimatedSprite3D child node. Change this if you rename
## the node in your scene tree. Using NodePath (^"...") is the correct type
## for get_node() in Godot 4 — it supports paths like "Body/Sprite" if your
## sprite is nested under another node.
@export var sprite_node_name: NodePath = ^"Sprite"

# --- Internal references ---

# @onready means "look this up once when the node is ready, before _process".
# We use it to cache the sprite node so we don't call get_node() every frame.
@onready var _sprite: AnimatedSprite3D = get_node(sprite_node_name)

# Current input direction in 2D space (the raw stick / WASD vector).
# We cache it so _physics_process reads it once, then both the facing
# and animation update functions can use it without re-querying input.
var _input_direction: Vector2 = Vector2.ZERO

# When true, the player ignores all input and decelerates to a stop.
# Set by the DialogueManager (and cutscene system, later) via set_frozen().
# We use a private variable with a setter method rather than a public bool
# so we can add side-effects later (e.g., play a "frozen" sound, change
# animation to "idle") without changing the call sites.
var _frozen: bool = false


# -----------------------------------------------------------------------------
# _physics_process runs at a fixed rate (60 times per second by default).
# We use it for anything that affects physics: movement, collision, velocity.
# -----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# If frozen (e.g., during dialogue or cutscenes), skip all input processing.
	# We still call move_and_slide() so existing velocity decays naturally
	# (the player will slide to a stop rather than freeze instantly, which
	# would look jarring mid-step).
	if _frozen:
		# Decelerate to zero so the player stops gracefully
		velocity = velocity.move_toward(Vector3.ZERO, friction * delta)
		move_and_slide()
		_update_sprite_facing()
		_update_sprite_animation()
		return

	# Step 1: Read input.
	# Input.get_vector(negative_x, positive_x, negative_y, positive_y)
	# returns a normalized Vector2 representing the current stick / key state.
	# Pressing W (move_up) gives y = -1; S (move_down) gives y = +1.
	# This matches how a 2D stick works and is the convention Godot expects.
	_input_direction = Input.get_vector(
		&"move_left", &"move_right",
		&"move_up", &"move_down"
	)

	# Step 2: Convert the 2D input into a 3D velocity on the XZ plane.
	# Mapping logic:
	#   input.x (left/right) → world X (left/right)
	#   input.y (up/down on stick) → world Z (forward/back in world)
	#
	# Why input.y maps directly to world Z (not negated):
	#   - W = input.y = -1
	#   - We want W to move the character "into the screen" (away from camera)
	#   - With our camera placed at +Z behind the player, "away from camera" = -Z
	#   - So input.y = -1 should produce velocity.z = -1, which is exactly
	#     what `target_velocity.z = input.y` gives us.
	#
	# If your camera ends up on the opposite side, just negate this line.
	var target_velocity := Vector3.ZERO
	target_velocity.x = _input_direction.x
	target_velocity.z = _input_direction.y

	# Normalize and scale to move_speed.
	# We normalize so diagonal movement isn't 1.41x faster than cardinal movement.
	# (Input.get_vector already normalizes, but if you ever swap to a raw
	# Input.get_axis() approach, this normalization is what saves you.)
	if target_velocity.length() > 0.01:
		target_velocity = target_velocity.normalized() * move_speed

	# Step 3: Smoothly accelerate toward the target velocity.
	# move_toward(current, target, max_delta) moves `current` toward `target`
	# by at most `max_delta`. We multiply by `delta` so the rate is independent
	# of frame rate: at 60fps, total per-second change = acceleration * 60 * (1/60)
	# = acceleration. Same at 144fps. Same at 30fps.
	if _input_direction.length() > 0.01:
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
	else:
		# No input → decelerate using friction instead of acceleration.
		velocity = velocity.move_toward(Vector3.ZERO, friction * delta)

	# Step 4: Apply the movement.
	# CharacterBody3D.move_and_slide() handles collision detection and sliding
	# along walls automatically. It uses the `velocity` property we just set.
	# In Godot 4, you no longer pass velocity to move_and_slide() — it reads
	# the property directly. (This changed from Godot 3.)
	move_and_slide()

	# Step 5: Update sprite visuals (facing + animation).
	_update_sprite_facing()
	_update_sprite_animation()


# -----------------------------------------------------------------------------
# Sprite helpers
# -----------------------------------------------------------------------------

func _update_sprite_facing() -> void:
	if not flip_sprite_to_face_direction:
		return
	# Only update facing when there's clear horizontal input. This prevents
	# the sprite from flipping back and forth when input is released.
	# The 0.01 threshold filters out stick drift / barely-pressed keys.
	if abs(_input_direction.x) > 0.01:
		# flip_h = true mirrors the sprite horizontally.
		# Moving left (negative X) → flip so the sprite faces left.
		_sprite.flip_h = _input_direction.x < 0


func _update_sprite_animation() -> void:
	# Switch between "idle" and "walk" based on actual velocity, not input.
	# Using velocity means the walk animation only plays once the character
	# is actually moving, which looks better than animating in place during
	# the acceleration ramp.
	#
	# The 0.1 threshold filters out tiny residual velocities from physics
	# rounding so the animation doesn't flicker when standing still.
	if velocity.length() > 0.1:
		if _sprite.animation != &"walk":
			_sprite.play(&"walk")
	else:
		if _sprite.animation != &"idle":
			_sprite.play(&"idle")


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

## Freeze or unfreeze the player. When frozen, the player ignores input
## and decelerates to a stop. Used by the dialogue system (and cutscenes
## later) to prevent the player from walking around during conversations.
##
## Example:
##   player.set_frozen(true)   # player can't move
##   player.set_frozen(false)  # player can move again
func set_frozen(value: bool) -> void:
	_frozen = value
	# When unfreezing, clear the input direction so the player doesn't
	# suddenly start moving if a movement key is still being held from
	# before the freeze.
	if not value:
		_input_direction = Vector2.ZERO


## Returns whether the player is currently frozen.
func is_frozen() -> bool:
	return _frozen


## Set the player's facing direction based on a 3D direction vector.
## Used by SceneManager when placing the player at a spawn point — the
## spawn point's forward direction (-Z axis) determines which way the
## player should face.
##
## We only care about the X component for sprite flipping, since the
## player doesn't actually rotate in 3D (just flips the sprite).
##
## Example:
##   player.face_direction(Vector3(1, 0, 0))   # face right
##   player.face_direction(Vector3(-1, 0, 0))  # face left
##   player.face_direction(Vector3(0, 0, -1))  # face "away" (no flip change)
func face_direction(direction: Vector3) -> void:
	# Only update facing if there's a clear horizontal direction.
	# This prevents the sprite from flipping when the direction is mostly
	# forward/backward (which we don't represent visually).
	if abs(direction.x) > 0.1:
		_sprite.flip_h = direction.x < 0


# -----------------------------------------------------------------------------
# _ready
# -----------------------------------------------------------------------------

func _ready() -> void:
	# Register the player in the "player" group so other systems can find us
	# via get_tree().get_nodes_in_group("player"). We do this in code rather
	# than in the editor because:
	#   1. It's version-proof (survives editor layout changes)
	#   2. It survives scene re-imports
	#   3. It's explicit — you can see exactly what groups this node is in
	add_to_group(&"player")


# -----------------------------------------------------------------------------
# Future extensions (not implemented yet, just notes for later)
# -----------------------------------------------------------------------------
#
# DASH / SPRINT:
#   Add an Input.is_action_pressed("sprint") check, multiply move_speed by 1.5
#   when held. Add a "run" animation and switch to it when sprinting.
#
# INTERACT:
#   Add an Area3D in front of the player (child node). When the player presses
#   "interact", check what's currently inside that Area3D and call its
#   interact() method. We'll build this in Phase 2.
#
# COMBAT TRANSITION:
#   When the player triggers a battle, freeze input here (set a `frozen` bool
#   and early-return from _physics_process), then trigger the scene transition.
#   Unfreeze when returning from battle.
