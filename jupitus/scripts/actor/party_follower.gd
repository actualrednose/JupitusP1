extends Node3D
class_name PartyFollower


@export_group("Following")

## Node whose movement this party member should retrace.
@export var target_path: NodePath = ^".."

## Distance the follower remains behind the target along its recorded path.
@export_range(0.1, 5.0, 0.05) var trail_distance: float = 0.9

## Movement larger than this is considered a teleport and resets the trail.
@export_range(0.5, 20.0, 0.5) var teleport_distance: float = 3.0

## Initial local-space direction in which the follower is placed.
@export var initial_trail_direction: Vector3 = Vector3.BACK


@export_group("Sprite")

@export var sprite_path: NodePath = ^"Sprite"
@export var flip_sprite_to_face_direction: bool = true


@onready var _target: Node3D = (
	get_node_or_null(target_path) as Node3D
)

@onready var _sprite: AnimatedSprite3D = (
	get_node_or_null(sprite_path) as AnimatedSprite3D
)


var _trail: Array[Vector3] = []
var _last_target_position: Vector3
var _last_follower_position: Vector3


func _ready() -> void:
	add_to_group(&"party_follower")

	if _target == null:
		push_error(
			"PartyFollower: target_path does not point to a Node3D"
		)
		set_physics_process(false)
		return

	if _sprite == null:
		push_error(
			"PartyFollower: sprite_path does not point to an "
			+ "AnimatedSprite3D"
		)
		set_physics_process(false)
		return

	reset_trail()


func _physics_process(_delta: float) -> void:
	var target_position := _target.global_position

	var target_displacement := target_position.distance_to(
		_last_target_position
	)

	if target_displacement >= teleport_distance:
		reset_trail()
		return

	if target_displacement > 0.0001:
		_trail.append(target_position)
		_last_target_position = target_position

	var next_position := _position_along_trail()
	var movement := next_position - _last_follower_position

	global_position = next_position

	_update_sprite(movement)

	_last_follower_position = next_position


## Recreates the initial path behind the target.
##
## Call this after manually teleporting the player if the teleport is shorter
## than teleport_distance but should still reset the party formation.
func reset_trail() -> void:
	var direction := (
		_target.global_transform.basis
		* initial_trail_direction
	).normalized()

	if direction.length_squared() <= 0.000001:
		direction = Vector3.BACK

	var target_position := _target.global_position
	var start_position := (
		target_position
		+ direction * trail_distance
	)

	start_position.y = target_position.y

	global_position = start_position

	_trail.clear()
	_trail.append(start_position)
	_trail.append(target_position)

	_last_target_position = target_position
	_last_follower_position = start_position

	_sprite.play(&"idle")


func _position_along_trail() -> Vector3:
	var remaining_distance := trail_distance

	for index in range(
		_trail.size() - 1,
		0,
		-1
	):
		var newer_point := _trail[index]
		var older_point := _trail[index - 1]

		var segment_length := newer_point.distance_to(
			older_point
		)

		if (
			remaining_distance <= segment_length
			and segment_length > 0.0
		):
			var follower_position := newer_point.lerp(
				older_point,
				remaining_distance / segment_length
			)

			_trim_trail(index - 1)
			return follower_position

		remaining_distance -= segment_length

	return _trail[0]


func _trim_trail(points_before_follower: int) -> void:
	for _point in range(points_before_follower):
		_trail.remove_at(0)


func _update_sprite(movement: Vector3) -> void:
	if (
		flip_sprite_to_face_direction
		and abs(movement.x) > 0.001
	):
		_sprite.flip_h = movement.x < 0.0

	if movement.length_squared() > 0.000001:
		if _sprite.animation != &"walk":
			_sprite.play(&"walk")
	elif _sprite.animation != &"idle":
		_sprite.play(&"idle")
