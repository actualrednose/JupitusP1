extends RefCounted
class_name BattleActorView

var _host: CanvasItem
var _visual: CanvasItem
var _number_parent: Node
var _base_position: Vector2
var _base_scale: Vector2
var _base_modulate: Color
var _number_origin: Vector2
var _active_tweens: Array[Tween] = []


func setup(
	host: CanvasItem,
	visual: CanvasItem,
	number_parent: Node = null,
	number_origin: Vector2 = Vector2(-24.0, -70.0)
) -> void:
	_host = host
	_visual = visual if visual != null else host
	_number_parent = number_parent if number_parent != null else host
	_number_origin = number_origin
	_capture_base_values()


func get_presentation_position() -> Vector2:
	if _host is Node2D:
		return (_host as Node2D).global_position

	if _host is Control:
		var control := _host as Control
		return control.global_position + control.size * 0.5

	return Vector2.ZERO


func play_anticipation(
	duration: float,
	reduced_motion: bool
) -> void:
	if _visual == null:
		return

	_stop_tweens()

	if reduced_motion:
		return

	var tween := _track_tween(_host.create_tween())
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(
		_visual,
		"scale",
		_base_scale * Vector2(0.92, 1.08),
		duration
	)


func play_attack(
	target_position: Vector2,
	duration: float,
	reduced_motion: bool
) -> void:
	if _visual == null:
		return

	_stop_tweens()

	if reduced_motion:
		return

	var direction := (
		target_position - get_presentation_position()
	).normalized()
	var offset := direction * 32.0
	var tween := _track_tween(_host.create_tween())
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(
		_visual,
		"position",
		_base_position + offset,
		duration
	)


func play_hit(
	impact_direction: Vector2,
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	if _visual == null:
		return

	_stop_tweens()

	if reduced_motion and reduced_flashing:
		return

	var tween := _track_tween(_host.create_tween())
	tween.set_parallel()

	if not reduced_motion:
		var recoil := -impact_direction.normalized() * 18.0
		tween.tween_property(
			_visual,
			"position",
			_base_position + recoil,
			duration * 0.35
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(
			_visual,
			"position",
			_base_position,
			duration * 0.65
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if not reduced_flashing:
		tween.tween_property(
			_visual,
			"modulate",
			Color(1.8, 1.8, 1.8, 1.0),
			duration * 0.2
		)
		tween.chain().tween_property(
			_visual,
			"modulate",
			_base_modulate,
			duration * 0.8
		)


func play_guard(
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	if _visual == null:
		return

	_stop_tweens()

	if reduced_motion and reduced_flashing:
		return

	var tween := _track_tween(_host.create_tween())
	tween.set_parallel()

	if not reduced_motion:
		tween.tween_property(
			_visual,
			"scale",
			_base_scale * 1.08,
			duration * 0.4
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(
			_visual,
			"scale",
			_base_scale,
			duration * 0.6
		)

	if not reduced_flashing:
		tween.tween_property(
			_visual,
			"modulate",
			Color("#A8D8FF"),
			duration * 0.35
		)
		tween.chain().tween_property(
			_visual,
			"modulate",
			_base_modulate,
			duration * 0.65
		)


func play_heal(
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	if _visual == null:
		return

	_stop_tweens()

	if reduced_motion and reduced_flashing:
		return

	var tween := _track_tween(_host.create_tween())
	tween.set_parallel()

	if not reduced_motion:
		tween.tween_property(
			_visual,
			"position",
			_base_position + Vector2(0.0, -10.0),
			duration * 0.45
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(
			_visual,
			"position",
			_base_position,
			duration * 0.55
		)

	if not reduced_flashing:
		tween.tween_property(
			_visual,
			"modulate",
			Color("#9CFFB0"),
			duration * 0.35
		)
		tween.chain().tween_property(
			_visual,
			"modulate",
			_base_modulate,
			duration * 0.65
		)


func play_power_charge(
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	if _visual == null:
		return

	_stop_tweens()

	if reduced_motion and reduced_flashing:
		return

	var tween := _track_tween(_host.create_tween())
	tween.set_parallel()

	if not reduced_motion:
		tween.tween_property(
			_visual,
			"scale",
			_base_scale * 1.12,
			duration * 0.45
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(
			_visual,
			"scale",
			_base_scale,
			duration * 0.55
		)

	if not reduced_flashing:
		tween.tween_property(
			_visual,
			"modulate",
			Color("#FFB347"),
			duration * 0.35
		)
		tween.chain().tween_property(
			_visual,
			"modulate",
			_base_modulate,
			duration * 0.65
		)


func play_interrupt(
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	if _visual == null:
		return

	_stop_tweens()

	if reduced_motion and reduced_flashing:
		return

	var tween := _track_tween(_host.create_tween())
	tween.set_parallel()

	if not reduced_motion:
		for offset in [-14.0, 14.0, -9.0, 9.0, 0.0]:
			tween.chain().tween_property(
				_visual,
				"position:x",
				_base_position.x + offset,
				duration / 5.0
			)

	if not reduced_flashing:
		tween.tween_property(
			_visual,
			"modulate",
			Color("#FFF29A"),
			duration * 0.3
		)
		tween.chain().tween_property(
			_visual,
			"modulate",
			_base_modulate,
			duration * 0.7
		)


func play_defeat(
	duration: float,
	reduced_motion: bool
) -> void:
	if _visual == null:
		return

	_stop_tweens()
	var tween := _track_tween(_host.create_tween())
	tween.set_parallel()
	tween.tween_property(
		_visual,
		"modulate",
		Color(0.45, 0.45, 0.45, 1.0),
		duration
	)

	if not reduced_motion:
		tween.tween_property(
			_visual,
			"rotation",
			0.12,
			duration
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


func play_recovery(
	duration: float,
	reduced_motion: bool
) -> void:
	if _visual == null:
		return

	_stop_tweens()

	if reduced_motion:
		_restore_transform()
		return

	var tween := _track_tween(_host.create_tween())
	tween.set_parallel()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(
		_visual,
		"position",
		_base_position,
		duration
	)
	tween.tween_property(
		_visual,
		"scale",
		_base_scale,
		duration
	)
	tween.tween_property(
		_visual,
		"rotation",
		0.0,
		duration
	)


func show_number(
	text: String,
	color: Color,
	reduced_motion: bool
) -> void:
	if _number_parent == null:
		return

	var label := Label.new()
	label.text = text
	label.position = _number_origin
	label.z_index = 100
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override(
		"font_shadow_color",
		Color(0.0, 0.0, 0.0, 0.85)
	)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	_number_parent.add_child(label)

	var tween := label.create_tween()
	tween.set_parallel()

	if not reduced_motion:
		tween.tween_property(
			label,
			"position",
			label.position + Vector2(0.0, -42.0),
			0.65
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tween.tween_property(label, "modulate:a", 0.0, 0.65)
	tween.finished.connect(label.queue_free)


func skip_and_reset() -> void:
	_stop_tweens()
	_restore_transform()

	if _visual != null:
		_visual.modulate = _base_modulate


func recapture_base_modulate() -> void:
	if _visual != null:
		_base_modulate = _visual.modulate


func _capture_base_values() -> void:
	if _visual == null:
		return

	_base_position = _visual.get("position") as Vector2
	_base_scale = _visual.get("scale") as Vector2
	_base_modulate = _visual.modulate


func _restore_transform() -> void:
	if _visual == null:
		return

	_visual.set("position", _base_position)
	_visual.set("scale", _base_scale)
	_visual.set("rotation", 0.0)


func _track_tween(tween: Tween) -> Tween:
	_active_tweens.append(tween)
	tween.finished.connect(
		func() -> void:
			_active_tweens.erase(tween)
	)
	return tween


func _stop_tweens() -> void:
	for tween in _active_tweens:
		if tween != null and tween.is_valid():
			tween.kill()

	_active_tweens.clear()
