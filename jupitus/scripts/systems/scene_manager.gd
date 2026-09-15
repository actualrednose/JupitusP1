# scene_manager.gd
# -----------------------------------------------------------------------------
# Autoload singleton that handles scene transitions with fade in/out and
# spawn point placement.
#
# What this script does:
#   - Provides transition_to_scene(path, spawn_point) as the main API
#   - Fades the screen to black before loading the new scene
#   - Loads the new scene
#   - Finds the requested spawn point (a Marker3D in the "spawn_point" group)
#     and moves the player there
#   - Fades the screen back in
#   - Freezes the player during the transition so they can't move
#   - Prevents scene transitions while dialogue is active (safety check)
#
# The fade overlay is a CanvasLayer with a ColorRect, created in _ready.
# It persists across scene changes because it's a child of this autoload
# (which is never destroyed).
#
# To set up:
#   1. Project Settings → Globals → Add
#   2. Path: res://scripts/systems/scene_manager.gd
#   3. Name: SceneManager
#   4. Make sure "Enabled" is checked
#
# Spawn points:
#   - In each scene, add a Marker3D node where the player should appear
#   - Name it uniquely (e.g., "from_street", "from_shop")
#   - Add the Marker3D to a group called "spawn_point"
#   - When calling transition_to_scene, pass the spawn point's name
#
# Example:
#   SceneManager.transition_to_scene("res://scenes/shop_interior.tscn", "from_street")
#   → Fades out, loads shop_interior.tscn, finds Marker3D named "from_street"
#     in the "spawn_point" group, teleports player there, fades in.
# -----------------------------------------------------------------------------

extends Node

# --- Signals ---

# Emitted when a transition starts (just before fade-out begins).
# `target_scene` is the resource path of the scene being loaded.
signal transition_started(target_scene: String)

# Emitted when a transition fully completes (fade-in finished).
signal transition_finished()

# Emitted when the new scene is loaded but before fade-in starts.
# Useful for one-time scene initialization that needs to happen after
# the player is placed but before the player sees the scene.
signal scene_loaded()

# --- Tweakable values ---

@export_group("Fade")
## How long (seconds) the fade-out takes (transparent → black).
@export var fade_out_duration: float = 0.3

## How long (seconds) the fade-in takes (black → transparent).
## Usually same as fade_out, but can be longer for a more "cinematic" feel.
@export var fade_in_duration: float = 0.3

## Color of the fade overlay. Black is standard. Use white for a "flash"
## transition, or other colors for thematic effects.
@export var fade_color: Color = Color.BLACK

# --- Internal state ---

# The CanvasLayer that holds our fade overlay. High layer number so it
# renders on top of everything else (including dialogue).
var _canvas_layer: CanvasLayer = null

# The ColorRect that does the actual fading. We tween its modulate.a
# between 0 (transparent) and 1 (opaque).
var _overlay: ColorRect = null

# True while a transition is in progress. Used to prevent re-entrancy
# (calling transition_to_scene while one is already running).
var _is_transitioning: bool = false


# -----------------------------------------------------------------------------
# _ready — set up the overlay
# -----------------------------------------------------------------------------

func _ready() -> void:
	# Create a CanvasLayer for the fade overlay.
	# Layer 100 is high enough to be above the dialogue box (which doesn't
	# use a CanvasLayer and renders at the default layer 0).
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "TransitionOverlayLayer"
	_canvas_layer.layer = 100
	add_child(_canvas_layer)

	# Create the fade overlay itself.
	_overlay = ColorRect.new()
	_overlay.name = "FadeOverlay"
	_overlay.color = fade_color
	_overlay.modulate.a = 0.0  # Start transparent

	# Make the ColorRect fill the entire screen.
	# set_anchors_preset with PRESET_FULL_RECT sets all anchors to 0/1
	# so the rect expands to fill its parent.
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block mouse
	_canvas_layer.add_child(_overlay)


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

## Transition to a new scene with fade in/out.
##
## Parameters:
##   scene_path:        Resource path of the scene to load (e.g., "res://scenes/shop.tscn")
##   spawn_point_name:  Name of the Marker3D to teleport the player to.
##                       If empty, player stays at their default position in the new scene.
##
## Returns true if the transition started, false if it was blocked (e.g.,
## another transition is already in progress, or dialogue is active).
func transition_to_scene(scene_path: String, spawn_point_name: String = "") -> bool:
	# Prevent re-entrancy: don't start a new transition while one is running.
	if _is_transitioning:
		push_warning("SceneManager: transition already in progress, ignoring new request")
		return false

	# Safety check: don't transition while dialogue is active.
	# This prevents weird states where dialogue is mid-conversation but
	# the scene changes underneath it.
	var dm: Node = get_node_or_null("/root/DialogueManager")
	if dm and dm.has_method("is_dialogue_active") and dm.is_dialogue_active():
		push_warning("SceneManager: cannot transition while dialogue is active")
		return false

	# Validate the scene path before we start fading — no point fading out
	# only to discover the path is wrong.
	if not ResourceLoader.exists(scene_path):
		push_error("SceneManager: scene not found at path '%s'" % scene_path)
		return false

	_is_transitioning = true
	transition_started.emit(scene_path)

	# Freeze the player so they can't move during the transition.
	# We do this BEFORE fade-out so the player stops immediately, not after
	# the fade (which would let them walk around in the dark briefly).
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player and player.has_method("set_frozen"):
		player.set_frozen(true)

	# --- FADE OUT ---
	# Tween the overlay alpha from 0 (transparent) to 1 (opaque).
	# `await` pauses this function until the tween finishes.
	var fade_out_tween: Tween = create_tween()
	fade_out_tween.tween_property(_overlay, "modulate:a", 1.0, fade_out_duration)
	await fade_out_tween.finished

	# --- CHANGE SCENE ---
	# change_scene_to_file is deferred — it happens at the end of the current
	# frame. We need to wait for the new scene to be loaded AND for its _ready
	# to run before we can find spawn points.
	get_tree().change_scene_to_file(scene_path)

	# Wait two frames to be safe:
	#   - Frame 1: old scene is freed, new scene is instantiated
	#   - Frame 2: new scene's _ready has been called, all children are ready
	# Two frames is the standard pattern; one frame sometimes misses things.
	await get_tree().process_frame
	await get_tree().process_frame

	# --- PLACE PLAYER AT SPAWN POINT ---
	if spawn_point_name != "":
		_place_player_at_spawn(spawn_point_name)

	scene_loaded.emit()

	# --- FADE IN ---
	var fade_in_tween: Tween = create_tween()
	fade_in_tween.tween_property(_overlay, "modulate:a", 0.0, fade_in_duration)
	await fade_in_tween.finished

	# Unfreeze the player (find them again — the old player node was destroyed
	# with the old scene, the new scene has its own player instance).
	player = get_tree().get_first_node_in_group(&"player")
	if player and player.has_method("set_frozen"):
		player.set_frozen(false)

	_is_transitioning = false
	transition_finished.emit()
	return true


## Returns true if a transition is currently in progress.
## Other systems can check this to avoid doing things during transitions
## (e.g., accepting input, triggering other transitions).
func is_transitioning() -> bool:
	return _is_transitioning


# -----------------------------------------------------------------------------
# Internal: spawn point handling
# -----------------------------------------------------------------------------

func _place_player_at_spawn(spawn_point_name: String) -> void:
	# Find the spawn point in the new scene.
	# Spawn points are Marker3D nodes in the "spawn_point" group, identified
	# by their node name.
	var spawn: Marker3D = _find_spawn_point(spawn_point_name)
	if spawn == null:
		push_warning(
			"SceneManager: spawn point '%s' not found in new scene. " % spawn_point_name \
			+ "Add a Marker3D with this name to the 'spawn_point' group."
		)
		return

	# Find the player (in the new scene) and move them to the spawn point.
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player == null:
		push_warning("SceneManager: no player found in new scene. Add a Player instance to the scene.")
		return

	# Teleport the player to the spawn point.
	# We use global_position so it works regardless of the player's parent.
	if player is Node3D:
		var player_3d: Node3D = player as Node3D
		player_3d.global_position = spawn.global_position

		# Auto-adjust the Y position so the player's collision shape BOTTOM
		# rests on the spawn point, not the player's origin.
		#
		# Why we need this:
		#   - The player's origin (0,0,0) is typically at the center of the
		#     CharacterBody3D, but the collision capsule extends both above
		#     AND below the origin (e.g., from Y=-0.5 to Y=+0.5 for a
		#     capsule with height 1.0).
		#   - If we just place the origin at the Marker3D's position, the
		#     bottom half of the capsule ends up below the floor, causing
		#     the player to either fall through or get launched upward by
		#     physics on the first frame.
		#   - This calculation finds the collision shape, determines where
		#     its bottom is in player-local space, and offsets the player
		#     upward so the capsule bottom aligns with the spawn point.
		var offset_y: float = _calculate_spawn_y_offset(player_3d)
		player_3d.global_position.y += offset_y

		# Also copy rotation — useful if you want the player to face a specific
		# direction. Since our player doesn't rotate (just flips sprite), this
		# mostly affects collision shape orientation, which is symmetric anyway.
		player_3d.global_rotation = spawn.global_rotation

	# If the player has a face_direction method, use the spawn's forward direction.
	# Marker3D's -Z axis is "forward" by Godot convention.
	if player.has_method("face_direction"):
		var forward: Vector3 = -spawn.global_transform.basis.z
		player.face_direction(forward)


## Calculate how much to offset the player's Y position so the bottom of
## their collision shape rests on the spawn point.
##
## Returns the Y offset to ADD to the player's spawn position.
##
## Logic:
##   - Find the player's CollisionShape3D child
##   - Get its shape (CapsuleShape3D, BoxShape3D, SphereShape3D, etc.)
##   - Calculate where the bottom of the shape is in player-local space:
##       shape_local_bottom_y = collision_shape.position.y - shape_half_height
##   - The offset needed is the NEGATIVE of this (so the bottom aligns with 0):
##       offset = -shape_local_bottom_y = shape_half_height - collision_shape.position.y
##
## Examples:
##   - CapsuleShape3D (height=1.0) at player origin (y=0):
##       offset = 0.5 - 0 = 0.5 → player moves up 0.5m
##   - CapsuleShape3D (height=1.0) at y=0.5 (already offset for feet-at-origin):
##       offset = 0.5 - 0.5 = 0.0 → no offset needed
##   - BoxShape3D (height=2.0) at player origin:
##       offset = 1.0 - 0 = 1.0 → player moves up 1.0m
func _calculate_spawn_y_offset(player: Node3D) -> float:
	# Find the CollisionShape3D child. We use find_child with recursive=true
	# in case the collision shape is nested under another node (rare but possible).
	var cs: CollisionShape3D = player.find_child("CollisionShape3D", true, false)
	if cs == null or cs.shape == null:
		# No collision shape found — no offset needed (or unknown, default to 0)
		push_warning("SceneManager: player has no CollisionShape3D, can't auto-offset Y. Player may spawn embedded in floor.")
		return 0.0

	# Calculate the half-height of the shape along the Y axis
	var half_height: float = 0.0
	if cs.shape is CapsuleShape3D:
		half_height = (cs.shape as CapsuleShape3D).height / 2.0
	elif cs.shape is BoxShape3D:
		half_height = (cs.shape as BoxShape3D).size.y / 2.0
	elif cs.shape is SphereShape3D:
		half_height = (cs.shape as SphereShape3D).radius
	elif cs.shape is CylinderShape3D:
		half_height = (cs.shape as CylinderShape3D).height / 2.0
	else:
		# Unknown shape type — assume it's centered at the collision shape's position
		# with half-height of 0 (no offset). User may need to adjust manually.
		push_warning("SceneManager: unknown collision shape type '%s', using 0 offset" % cs.shape.get_class())
		return 0.0

	# Offset = half_height - collision_shape_local_y
	# This puts the bottom of the collision shape at y=0 (the spawn point's Y)
	return half_height - cs.position.y


func _find_spawn_point(spawn_point_name: String) -> Marker3D:
	# Look through all nodes in the "spawn_point" group for one with the
	# matching name. Returns null if not found.
	#
	# Using groups is fast (Godot maintains a list internally) and clear
	# (the user explicitly opts in by adding the Marker3D to the group).
	var candidates: Array[Node] = get_tree().get_nodes_in_group(&"spawn_point")
	for node in candidates:
		if node is Marker3D and node.name == spawn_point_name:
			return node
	return null


# -----------------------------------------------------------------------------
# Future extensions (notes for later)
# -----------------------------------------------------------------------------
#
# 1. TRANSITION EFFECTS
#    Currently we only do a simple fade-to-color. Other options:
#      - Slide transition (overlay wipes across screen)
#      - Iris transition (circular reveal)
#      - Pixelate/dissolve (shader-based)
#    Implementation: add a `transition_type: enum` parameter, branch in
#    transition_to_scene.
#
# 2. MID-TRANSITION ACTIONS
#    Sometimes you want to do something between fade-out and fade-in —
#    e.g., play a sound, show a brief "Loading..." text, run a cutscene
#    beat. Could add a `pre_load_callback: Callable` parameter.
#
# 3. ASYNC LOADING
#    For large scenes, change_scene_to_file blocks the main thread, causing
#    a visible hitch during fade-out. Use ResourceLoader.load_threaded_request
#    to load in the background, showing a progress bar during fade-out.
#
# 4. SCENE HISTORY / BACK NAVIGATION
#    Keep a stack of visited scenes so the player can press "back" to return
#    to the previous scene. Useful for menu systems.
