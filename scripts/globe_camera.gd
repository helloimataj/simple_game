class_name GlobeCamera
extends Camera3D
## Google Earth style camera that orbits a globe centred at the origin.
##
## - Left/right/middle drag: spin the globe (the surface follows the cursor)
## - Mouse wheel / pinch, Q/E, +/-: zoom
## - WASD / arrow keys: spin
## - Releasing a drag keeps a little momentum.
## The camera tilts towards the horizon as it gets close, like Google Earth.

signal moved

@export var globe_radius := 10.0
@export var min_altitude_factor := 0.04 ## closest altitude as a fraction of radius
@export var max_altitude_factor := 3.0
@export var zoom_step := 0.85
@export var key_spin_speed := 0.9 ## screen heights per second
@export var momentum_damping := 5.0
@export var max_tilt_degrees := 35.0

var latitude := 20.0   ## degrees, north positive
var longitude := 0.0   ## degrees, east positive
var altitude := 18.0   ## distance above the surface

## True from mouse press until release if the mouse moved far enough to count
## as a drag rather than a click.
var dragged := false

var _target_altitude := 18.0
var _dragging := false
var _press_position := Vector2.ZERO
var _velocity := Vector2.ZERO  # degrees/second (lon, lat)
var _last_drag_time := 0


func _ready() -> void:
	_target_altitude = altitude
	_apply()


func reset_view(radius: float) -> void:
	globe_radius = radius
	latitude = 20.0
	longitude = 0.0
	altitude = radius * 1.8
	_target_altitude = altitude
	_velocity = Vector2.ZERO
	_apply()


func set_view(lat: float, lon: float, alt: float) -> void:
	latitude = clampf(lat, -88.0, 88.0)
	longitude = wrapf(lon, -180.0, 180.0)
	altitude = clampf(alt, globe_radius * min_altitude_factor, globe_radius * max_altitude_factor)
	_target_altitude = altitude
	_velocity = Vector2.ZERO
	_apply()


## Degrees of surface arc per screen pixel at the point under the view centre.
func _degrees_per_pixel() -> float:
	var viewport_height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var visible := 2.0 * altitude * tan(deg_to_rad(fov) * 0.5)
	return rad_to_deg(visible / viewport_height / globe_radius)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_dragging = true
					dragged = false
					_press_position = mb.position
					_velocity = Vector2.ZERO
				else:
					_dragging = false
					if Time.get_ticks_msec() - _last_drag_time > 80:
						_velocity = Vector2.ZERO
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom(zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(1.0 / zoom_step)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_press_position) > 4.0:
			dragged = true
		if dragged:
			var dpp := _degrees_per_pixel()
			var delta_deg := Vector2(-mm.relative.x, mm.relative.y) * dpp
			# Longitude lines converge towards the poles.
			delta_deg.x /= maxf(cos(deg_to_rad(latitude)), 0.15)
			_rotate_by(delta_deg)
			var dt := maxf((Time.get_ticks_msec() - _last_drag_time) / 1000.0, 1.0 / 240.0)
			_velocity = _velocity.lerp(delta_deg / dt, 0.5) if dt < 0.1 else Vector2.ZERO
			_last_drag_time = Time.get_ticks_msec()
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / (event as InputEventMagnifyGesture).factor)
	elif event is InputEventPanGesture:
		_zoom(1.0 + (event as InputEventPanGesture).delta.y * 0.05)


func _zoom(factor: float) -> void:
	_target_altitude = clampf(_target_altitude * factor,
		globe_radius * min_altitude_factor, globe_radius * max_altitude_factor)


func _rotate_by(delta_deg: Vector2) -> void:
	longitude = wrapf(longitude + delta_deg.x, -180.0, 180.0)
	latitude = clampf(latitude + delta_deg.y, -88.0, 88.0)
	_apply()


func _process(delta: float) -> void:
	var changed := false

	var keys := Vector2(
		Input.get_axis(&"ui_left", &"ui_right") + _key_axis(KEY_A, KEY_D),
		Input.get_axis(&"ui_down", &"ui_up") + _key_axis(KEY_S, KEY_W))
	if keys != Vector2.ZERO:
		var viewport_height := get_viewport().get_visible_rect().size.y
		var deg := key_spin_speed * viewport_height * _degrees_per_pixel() * delta
		var step := keys.limit_length(1.0) * deg
		step.x /= maxf(cos(deg_to_rad(latitude)), 0.15)
		_rotate_by(step)
		changed = true

	var zoom_keys := _key_axis(KEY_Q, KEY_E) + _key_axis(KEY_MINUS, KEY_EQUAL)
	if zoom_keys != 0.0:
		_zoom(pow(zoom_step, zoom_keys * delta * 4.0))

	if not _dragging and _velocity.length_squared() > 0.0001:
		_rotate_by(_velocity * delta)
		_velocity *= exp(-momentum_damping * delta)
		changed = true

	if absf(altitude - _target_altitude) > 1e-4:
		altitude = lerpf(altitude, _target_altitude, 1.0 - exp(-12.0 * delta))
		changed = true

	if changed:
		_apply()


func _key_axis(negative: Key, positive: Key) -> float:
	return float(Input.is_physical_key_pressed(positive)) - float(Input.is_physical_key_pressed(negative))


func _apply() -> void:
	var lat := deg_to_rad(latitude)
	var lon := deg_to_rad(longitude)
	var dir := Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
	position = dir * (globe_radius + altitude)

	# Tilt towards the horizon when close to the ground.
	var closeness := 1.0 - clampf(
		(altitude - globe_radius * min_altitude_factor) / (globe_radius * 0.6), 0.0, 1.0)
	var tilt := deg_to_rad(max_tilt_degrees) * closeness * closeness
	var north := (Vector3.UP - dir * dir.y).normalized()
	var target := -dir * cos(tilt) + north * sin(tilt)
	look_at(position + target, dir * sin(tilt) + north * cos(tilt))
	near = maxf(altitude * 0.05, 0.01)
	far = (globe_radius + altitude) * 3.0
	moved.emit()
