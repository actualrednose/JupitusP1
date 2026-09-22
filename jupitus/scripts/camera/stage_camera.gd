# stage_camera.gd
# -----------------------------------------------------------------------------
# Attach to: Camera3D
#
# Follows a target with smooth motion while maintaining a fixed pitch and
# distance.
# -----------------------------------------------------------------------------

extends Camera3D
class_name StageCamera


@export_group("Target")

## Node followed by the camera.
@export var target: Node3D = null

## Automatically find the first node in the "player" group when target is null.
@export var auto_find_player: bool = true


@export_group("Angle")

## Camera pitch in degrees.
@export_range(0.0, 90.0) var pitch_degrees: float = 30.0

## Distance from the camera to the target.
@export var distance: float = 8.0


@export_group("Smoothing")

## Camera follow smoothing. Zero does not move; one snaps immediately.
@export_range(0.0, 1.0) var follow_smoothing: float = 0.1

## Whether the camera should look at the target each frame.
@export var look_at_target: bool = true


var _follow_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	if target == null and auto_find_player:
		var players := get_tree().get_nodes_in_group(&"player")

		if not players.is_empty():
			target = players[0]

			# Successful automatic configuration is informational rather than
			# a warning. It only appears when verbose output is enabled.
			print_verbose(
				"StageCamera: auto-found player '%s' as target"
				% target.name
			)
		else:
			push_error(
				"StageCamera: no target set and no node in the "
				+ "'player' group was found"
			)

	_update_follow_offset()

	if target != null:
		global_position = (
			target.global_position
			+ _follow_offset
		)

		if look_at_target:
			look_at(target.global_position)


func _process(delta: float) -> void:
	if target == null:
		return

	_update_follow_offset()

	var desired_position := (
		target.global_position
		+ _follow_offset
	)

	# Convert the configured per-frame smoothing value to a
	# frame-rate-independent interpolation factor.
	var interpolation_weight := (
		1.0
		- pow(
			1.0 - follow_smoothing,
			delta * 60.0
		)
	)

	global_position = global_position.lerp(
		desired_position,
		interpolation_weight
	)

	if look_at_target:
		look_at(target.global_position)


func _update_follow_offset() -> void:
	var pitch_radians := deg_to_rad(pitch_degrees)

	_follow_offset = Vector3(
		0.0,
		sin(pitch_radians) * distance,
		cos(pitch_radians) * distance
	)
