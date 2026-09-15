# cutscene_action_camera.gd
# -----------------------------------------------------------------------------
# Changes the camera's target during a cutscene.
#
# The StageCamera (from Phase 1) follows a target node. This action lets
# you temporarily point the camera at a different node — e.g., a Marker3D
# positioned for a dramatic shot of the robber entering.
#
# Two pan modes are available:
#
#   INSTANT (default): Just changes the camera's target. The StageCamera's
#     smoothing will catch up over a few frames. With a low smoothing value,
#     this looks like a snap; with a high value, a fast glide.
#
#   SMOOTH: Temporarily takes over the camera's position via a Tween, gliding
#     it to the new target over `pan_duration` seconds. The StageCamera's
#     normal smoothing is bypassed during the pan, then restored after.
#     This gives precise control over the pan duration.
#
# Usage:
#   - Set `target` to the NodePath of the node the camera should follow
#     (typically a Marker3D positioned for the shot)
#   - Set `restore_to_player` to true to restore camera to follow the player
#     (use at the end of the cutscene)
#   - Set `pan_mode` to INSTANT or SMOOTH
#   - Set `pan_duration` (only used when pan_mode is SMOOTH) — how long the
#     tween takes to glide the camera
#   - Set `wait_duration` — how long the cutscene pauses after the pan
#     (gives time for the camera to settle before the next action)
#
# Example sequence for the robbery reveal:
#   1. CameraAction(target=camera_robber_door, mode=SMOOTH, pan=1.5, wait=0.5)
#      — smooth pan to back door over 1.5s, then wait 0.5s for player to absorb
#   2. MoveAction(actor=Robber, dest=robber_center_pos)
#   3. DialogueAction(shopkeeper_yell)
#   4. CameraAction(restore_to_player=true, mode=SMOOTH, pan=1.5, wait=0.5)
#      — smooth pan back to player
# -----------------------------------------------------------------------------

extends CutsceneAction
class_name CutsceneActionCamera

# --- Pan modes ---

enum PanMode {
	## Instantly change the camera's target. The StageCamera's smoothing
	## handles the catch-up. Fast and simple, but the speed depends on the
	## smoothing value and the distance to the new target.
	INSTANT,

	## Smoothly tween the camera's position to the new target over
	## `pan_duration` seconds. Temporarily disables StageCamera smoothing
	## during the pan, then restores it.
	SMOOTH,
}

# --- Tweakable values ---

## Path to the node the camera should follow. Leave empty if
## `restore_to_player` is true (in which case the camera goes back to
## following the player).
@export var target: NodePath = ""

## If true, the camera target is set back to the player.
## Use this at the end of the cutscene to restore normal camera behavior.
@export var restore_to_player: bool = false

## How the camera moves to the new target:
##   INSTANT — just change target, let StageCamera smoothing catch up
##   SMOOTH  — tween the camera position over `pan_duration` seconds
@export var pan_mode: PanMode = PanMode.SMOOTH

## How long (seconds) the smooth pan takes. Only used when pan_mode is SMOOTH.
## 1.0–2.0 seconds is typical for a cinematic pan.
@export var pan_duration: float = 1.5

## How long to wait (in seconds) AFTER the pan completes before moving to
## the next cutscene action. Use this to give the player time to absorb
## the new shot before something else happens.
##
## For INSTANT mode, this is the only wait — there's no pan tween.
## For SMOOTH mode, the total wait is pan_duration + wait_duration.
@export var wait_duration: float = 0.5

## Easing function for the smooth pan.
## SINE = smooth start and end (recommended for camera moves)
## QUAD = sharper ease, more dramatic
## LINEAR = constant speed, can feel mechanical
@export_enum("Linear", "Sine", "Quad", "Cubic", "Quart") var ease_type: int = 1  # Sine

# --- Internal state (for skip support) ---

# The active pan tween, if any. Stored so we can kill it on skip.
var _pan_tween: Tween = null


# -----------------------------------------------------------------------------
# Execute
# -----------------------------------------------------------------------------

func execute(cutscene_player: Node) -> void:
	# Get the active camera.
	var camera: Camera3D = cutscene_player.get_viewport().get_camera_3d()

	if camera == null:
		push_warning("CutsceneActionCamera: no active Camera3D found")
		return

	# Check that the camera is our StageCamera (has a `target` property)
	if not ("target" in camera):
		push_warning("CutsceneActionCamera: camera doesn't have a 'target' property (not a StageCamera?)")
		return

	# Determine the new target node
	var new_target: Node3D = null

	if restore_to_player:
		var player: Node = cutscene_player.get_tree().get_first_node_in_group(&"player")
		if player == null:
			push_warning("CutsceneActionCamera: no player found to restore camera to")
			return
		new_target = player as Node3D
	else:
		if target.is_empty():
			push_warning("CutsceneActionCamera: target is empty and restore_to_player is false")
			return

		new_target = cutscene_player.get_node_or_null(target) as Node3D
		if new_target == null:
			push_warning("CutsceneActionCamera: target node not found at path '%s'" % target)
			return

	# Perform the pan based on the mode
	match pan_mode:
		PanMode.INSTANT:
			_pan_instant(camera, new_target)
		PanMode.SMOOTH:
			await _pan_smooth(camera, new_target, cutscene_player)

	# Wait for the post-pan delay
	if wait_duration > 0.0:
		await cutscene_player.get_tree().create_timer(wait_duration).timeout


# -----------------------------------------------------------------------------
# Pan implementations
# -----------------------------------------------------------------------------

## INSTANT mode: just change the target. StageCamera's _process will catch up.
func _pan_instant(camera: Camera3D, new_target: Node3D) -> void:
	camera.target = new_target


## SMOOTH mode: tween the camera's position to the new target's offset,
## then set the target so StageCamera takes over from there.
##
## The StageCamera computes its desired position as:
##   desired = target.global_position + follow_offset
## where follow_offset depends on pitch_degrees and distance.
##
## During the smooth pan, we:
##   1. Compute the camera's CURRENT follow_offset (based on the OLD target)
##   2. Compute the camera's TARGET position (NEW target's position + same offset)
##   3. Disable StageCamera's _process by temporarily setting its target to null
##      (this stops it from fighting our tween)
##   4. Tween the camera's global_position to the target position
##   5. After the tween, set camera.target = new_target to resume normal following
##
## The follow_offset stays the same (we use the same pitch/distance for both
## the old and new shots), so the pan is purely translational — no rotation.
## This looks like a "track" or "dolly" shot.
func _pan_smooth(camera: Camera3D, new_target: Node3D, cutscene_player: Node) -> void:
	# Compute the follow_offset the camera is currently using.
	# The StageCamera caches this in _follow_offset, but we can't access
	# private vars from outside. Instead, we compute it from current state:
	#   follow_offset = camera.global_position - old_target.global_position
	#
	# This works because StageCamera maintains:
	#   global_position = target.global_position + follow_offset
	#
	# Note: this assumes the camera has converged (or nearly converged) on
	# its current target. If it's mid-smoothing, the offset will be slightly
	# off, but the tween will still look fine.
	var old_target: Node3D = camera.target
	var follow_offset: Vector3 = Vector3.ZERO
	if old_target != null:
		follow_offset = camera.global_position - old_target.global_position

	# Where we want the camera to end up
	var end_position: Vector3 = new_target.global_position + follow_offset

	# Temporarily set camera.target to null so StageCamera's _process
	# doesn't try to move the camera while our tween is running.
	# (StageCamera._process returns early if target == null.)
	camera.target = null

	# Create and run the tween
	_pan_tween = cutscene_player.create_tween()
	_pan_tween.tween_property(camera, "global_position", end_position, pan_duration)
	_pan_tween.set_trans(_get_tween_trans())
	_pan_tween.set_ease(Tween.EASE_IN_OUT)

	# Make the camera keep looking at the OLD target during the pan, so the
	# view doesn't whip around. We do this by tweening a "look_at target"
	# from old_target's position to new_target's position.
	#
	# StageCamera has `look_at_target = true` which makes it look at its
	# target every frame. But since we set target to null, that won't run.
	# Instead, we manually call look_at each frame via the tween's step_callback.
	#
	# Simpler approach: tween a Vector3 from old to new, and use a method
	# tween to call camera.look_at() with the interpolated position.
	if old_target != null:
		var start_look: Vector3 = old_target.global_position
		var end_look: Vector3 = new_target.global_position
		# Use tween_method to call our custom _look_at_during_pan helper,
		# which interpolates the look_at position along with the camera move.
		_pan_tween.parallel().tween_method(
			func(t: float) -> void:
				var look_pos: Vector3 = start_look.lerp(end_look, t)
				camera.look_at(look_pos),
			0.0, 1.0, pan_duration
		)

	# Wait for the tween to finish
	await _pan_tween.finished

	# Hand control back to StageCamera by setting the new target.
	# StageCamera._process will pick this up on the next frame.
	camera.target = new_target

	# Clear the tween reference
	_pan_tween = null


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

## Map the ease_type enum to Godot's Tween transition types.
func _get_tween_trans() -> int:
	match ease_type:
		0: return Tween.TRANS_LINEAR
		1: return Tween.TRANS_SINE
		2: return Tween.TRANS_QUAD
		3: return Tween.TRANS_CUBIC
		4: return Tween.TRANS_QUART
		_: return Tween.TRANS_SINE


# -----------------------------------------------------------------------------
# Skip
# -----------------------------------------------------------------------------

func skip(_cutscene_player: Node) -> void:
	# If a smooth pan is in progress, kill the tween and snap to the end.
	# This ensures the cutscene ends in a clean state.
	if _pan_tween != null and _pan_tween.is_valid():
		_pan_tween.kill()
		_pan_tween = null

	# Note: we don't snap the camera to the new target here — the
	# CutscenePlayer's cleanup code will restore the camera to the player
	# after the cutscene ends, so the intermediate state doesn't matter.
	#
	# However, if the cutscene ISN'T being skipped entirely (just this
	# action), the camera will be wherever it was when skip fired, and
	# the next action will start from there. That's acceptable.
	pass
