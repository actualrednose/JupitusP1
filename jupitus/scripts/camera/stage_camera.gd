# stage_camera.gd
# -----------------------------------------------------------------------------
# Attach to: Camera3D
#
# What this script does:
#   - Follows a target node (typically the player) with smooth motion
#   - Locks the camera at a fixed pitch angle (the "Paper Mario" look)
#   - Exposes the pitch angle, distance, and smoothing as Inspector values
#     so you can tweak the camera feel without editing code
#
# Required setup:
#   1. Create a Camera3D node in your scene
#   2. Attach this script
#   3. Either:
#        a) Drag the player node into the "Target" slot in the Inspector, OR
#        b) Add the player to a group called "player" and leave Target empty
#           (the script will auto-find it on _ready)
#
# How to use the Inspector values:
#   - Pitch Degrees: 0 = camera directly behind player (horizontal view).
#                     90 = camera directly above (top-down).
#                     25-40 = the "Paper Mario" sweet spot. Try 30 first.
#   - Distance: how far the camera sits from the player, in meters.
#               Higher = more of the world is visible. 6-10 is typical.
#   - Follow Smoothing: 0 = camera never moves, 1 = instant snap.
#                        0.05-0.15 feels smooth without being laggy.
# -----------------------------------------------------------------------------

extends Camera3D
class_name StageCamera

# --- Tweakable values ---

@export_group("Target")
## The node this camera follows. If null on _ready and auto_find_player is
## true, the script looks for a node in the "player" group.
@export var target: Node3D = null

## If true and target is null on _ready, auto-finds a node in the "player" group.
@export var auto_find_player: bool = true

@export_group("Angle")
## Camera pitch in degrees. 0 = horizontal (behind player), 90 = top-down.
## For Paper Mario style, try 25-40 degrees. Default 30 is a good starting point.
@export_range(0.0, 90.0) var pitch_degrees: float = 30.0

## Distance from the camera to the target, in meters. The camera sits on a
## sphere of this radius around the target. Higher = camera further away.
@export var distance: float = 8.0

@export_group("Smoothing")
## How quickly the camera catches up to the target.
## 0 = no movement, 1 = instant snap. 0.05-0.15 is the smooth zone.
@export_range(0.0, 1.0) var follow_smoothing: float = 0.1

## If true, the camera looks at the target every frame. Recommended true —
## it keeps the player centered. Set false only if you want to manually
## animate the camera rotation (e.g. for a cutscene).
@export var look_at_target: bool = true

# --- Internal state ---

# The offset from the target's position to the camera's desired position.
# Recomputed whenever pitch_degrees or distance changes. Stored as a member
# variable so we can recompute it lazily (only when needed).
var _follow_offset: Vector3 = Vector3.ZERO


# -----------------------------------------------------------------------------
# _ready runs once when the camera enters the scene tree.
# We use it to find the target and snap to the initial position (so the camera
# doesn't visibly lerp from origin to the target on the first frame).
# -----------------------------------------------------------------------------

func _ready() -> void:
	# Auto-find the player if no target was set in the inspector.
	if target == null and auto_find_player:
		var players := get_tree().get_nodes_in_group(&"player")
		if players.size() > 0:
			target = players[0]
			# push_warning is a non-fatal message that shows up in the editor
			# Output panel. Useful for "I made an assumption, here's what I did".
			push_warning("StageCamera: auto-found player '%s' as target" % target.name)
		else:
			push_error("StageCamera: no target set and no node in 'player' group found!")
			# We don't return here — the script will keep running, just doing
			# nothing in _process until a target appears.

	# Compute the initial offset.
	_update_follow_offset()

	# Snap to the desired position immediately so we don't see a long
	# camera lerp from (0,0,0) to the player on the first frame.
	if target != null:
		global_position = target.global_position + _follow_offset
		if look_at_target:
			look_at(target.global_position)


# -----------------------------------------------------------------------------
# _process runs every rendered frame. We use it (not _physics_process) for
# camera movement because:
#   - Camera movement is purely visual (doesn't affect physics)
#   - Running on every rendered frame gives smoother motion at high refresh
#     rates (144Hz monitors, etc.) than running at the fixed physics tick
# -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if target == null:
		return

	# Recompute the offset in case pitch_degrees or distance was changed at
	# runtime via the inspector or script. This is cheap (a few trig ops)
	# so doing it every frame is fine.
	_update_follow_offset()

	# Compute where we WANT to be this frame.
	var desired_position := target.global_position + _follow_offset

	# Frame-rate-independent smoothing.
	# The naive approach `position.lerp(desired, smoothing)` runs faster at
	# higher frame rates (more lerp calls per second → faster convergence),
	# which makes the camera feel "snappier" on a 144Hz monitor than on 60Hz.
	#
	# The fix: convert the per-frame smoothing factor to a per-second one
	# using the formula: t = 1 - (1 - smoothing)^(delta * 60)
	# This makes the camera converge at the same rate regardless of FPS.
	#
	# Math: at 60 FPS, delta = 1/60, so the exponent is 1.0, giving t = smoothing.
	# At 144 FPS, delta = 1/144, so the exponent is ~0.417, giving a smaller t
	# per frame — but we call it more times per second, so it converges identically.
	var t := 1.0 - pow(1.0 - follow_smoothing, delta * 60.0)
	global_position = global_position.lerp(desired_position, t)

	# Look at the target so the player stays centered.
	# Since the relative offset (and therefore the look-at angle) is constant
	# when the camera isn't moving, this is essentially free and never causes
	# visible rotation jitter.
	if look_at_target:
		look_at(target.global_position)


# -----------------------------------------------------------------------------
# _update_follow_offset computes where the camera should sit relative to the
# target, based on pitch_degrees and distance.
# -----------------------------------------------------------------------------

func _update_follow_offset() -> void:
	# Convert degrees to radians for the trig functions.
	# Godot's deg_to_rad() is just multiplication by PI/180.
	var pitch_rad := deg_to_rad(pitch_degrees)

	# Spherical coordinate math.
	# Imagine a sphere of radius `distance` around the target. The camera sits
	# on the surface of that sphere, at the given pitch angle.
	#
	# Pitch 0° → camera is directly behind target at the same height (pure
	#             third-person view, no top-down element).
	# Pitch 90° → camera is directly above the target (pure top-down).
	# Pitch 30° → camera is up and back at a 30° angle from horizontal.
	#
	# Components:
	#   X = 0 (no horizontal orbit — we don't want yaw for a fixed-angle camera)
	#   Y = sin(pitch) * distance  (height above the target)
	#   Z = cos(pitch) * distance  (horizontal distance behind the target)
	#
	# +Z puts the camera "behind" the player assuming the player faces -Z
	# (Godot's default forward direction). If your player faces +Z, negate this.
	_follow_offset = Vector3(
		0.0,
		sin(pitch_rad) * distance,
		cos(pitch_rad) * distance
	)


# =============================================================================
# FUTURE FEATURE: Foreground object transparency (occlusion handling)
# -----------------------------------------------------------------------------
# When the camera is positioned behind tall foreground objects (pillars, trees,
# roofs, shop shelves), they can block the player from view. The standard fix
# is to raycast from the camera to the player every frame, and any objects the
# ray passes through get their alpha reduced to ~0.3 so the player shows through.
#
# OUTLINE OF THE IMPLEMENTATION (to build later, when you actually have
# foreground occluders in your level):
#
#   1. Add a RayCast3D as a child of this camera.
#   2. Every frame, point it at the target and call force_raycast_update().
#   3. Use get_collider() to find what's blocking the view.
#   4. For each unique blocker encountered:
#        - Cache its original material (so you can restore it later)
#        - Set its material's transparency mode to ALPHA
#        - Tween the albedo color's alpha channel from 1.0 to 0.3 over 0.2s
#   5. For objects that ARE NO LONGER blocking:
#        - Tween their alpha back to 1.0
#        - Once fully opaque, restore the original transparency mode
#
# REQUIREMENTS FOR THIS TO WORK:
#   - Occluder objects need to use StandardMaterial3D (not just a plain mesh
#     material) so you can toggle transparency_mode.
#   - OR they need a custom shader that exposes an alpha uniform.
#   - You need a way to mark which objects SHOULD become transparent (don't
#     want to fade out walls the player is hiding behind intentionallyally).
#     Typically you put occludable objects on a specific collision layer or
#     give them a metadata flag.
#
# I'd recommend deferring this until you have a level where occlusion is
# actually a problem. The basic camera + movement should be solid first.
# When you're ready, ping me and I'll write the occlusion system as a
# separate script (camera_occlusion_handler.gd) that you can attach alongside
# this one.
# =============================================================================
