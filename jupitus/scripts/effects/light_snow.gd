extends GPUParticles3D
class_name LightSnow


@export_group("Snow")

## Number of flakes active around the camera.
@export_range(1, 500, 1) var flake_count: int = 90

## Width, height, and depth of the snowfall volume.
@export var area_size: Vector3 = Vector3(14.0, 8.0, 10.0)

## Average downward speed in metres per second.
@export_range(0.1, 5.0, 0.05) var fall_speed: float = 1.15

## Horizontal wind on the world's X and Z axes.
@export var wind: Vector2 = Vector2(0.18, 0.04)

## Diameter of a flake in world units.
@export_range(0.01, 0.25, 0.005) var flake_size: float = 0.055

@export var snow_color: Color = Color(0.92, 0.96, 1.0, 0.82)


@export_group("Following")

## Keep the snowfall volume centred on the active camera.
@export var follow_camera: bool = true

## Raises the centre of the volume so more flakes begin above the camera.
@export var height_above_camera: float = 2.5


func _ready() -> void:
	_configure_particles()
	_follow_active_camera()
	emitting = true
	restart()


func _process(_delta: float) -> void:
	if follow_camera:
		_follow_active_camera()


func _configure_particles() -> void:
	var safe_area_size := Vector3(
		maxf(area_size.x, 0.1),
		maxf(area_size.y, 0.1),
		maxf(area_size.z, 0.1)
	)
	var safe_fall_speed := maxf(fall_speed, 0.1)

	amount = maxi(flake_count, 1)
	lifetime = maxf(safe_area_size.y / safe_fall_speed, 1.0)
	preprocess = lifetime
	randomness = 0.35
	fixed_fps = 30
	local_coords = false
	visibility_aabb = AABB(
		-safe_area_size * 0.65,
		safe_area_size * 1.3
	)

	var particle_material := ParticleProcessMaterial.new()
	particle_material.emission_shape = (
		ParticleProcessMaterial.EMISSION_SHAPE_BOX
	)
	particle_material.emission_box_extents = safe_area_size * 0.5
	particle_material.direction = Vector3(wind.x, -1.0, wind.y).normalized()
	particle_material.spread = 8.0
	particle_material.initial_velocity_min = safe_fall_speed * 0.75
	particle_material.initial_velocity_max = safe_fall_speed * 1.25
	particle_material.gravity = Vector3(0.0, -0.08, 0.0)
	particle_material.scale_min = 0.65
	particle_material.scale_max = 1.35
	process_material = particle_material

	var flake_material := StandardMaterial3D.new()
	flake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake_material.albedo_color = snow_color
	flake_material.albedo_texture = _create_flake_texture()

	var flake_mesh := QuadMesh.new()
	flake_mesh.size = Vector2.ONE * maxf(flake_size, 0.01)
	flake_mesh.material = flake_material
	draw_pass_1 = flake_mesh


func _follow_active_camera() -> void:
	if not follow_camera:
		return

	var camera := get_viewport().get_camera_3d()

	if camera == null:
		return

	global_position = camera.global_position + Vector3.UP * height_above_camera


func _create_flake_texture() -> ImageTexture:
	const TEXTURE_SIZE := 16
	const CENTRE := Vector2(7.5, 7.5)
	const RADIUS := 7.5

	var image := Image.create(
		TEXTURE_SIZE,
		TEXTURE_SIZE,
		false,
		Image.FORMAT_RGBA8
	)

	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var distance_from_centre := (
				Vector2(x, y).distance_to(CENTRE) / RADIUS
			)
			var alpha := 1.0 - smoothstep(
				0.55,
				1.0,
				distance_from_centre
			)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	return ImageTexture.create_from_image(image)
