extends Node3D
# Camara de estrategia: vista aerea navegable sobre el mapa.
#
# Estructura: CameraRig (pivote, este script) -> Camera3D (hija).
# El pivote marca el punto del suelo que se observa; la camara se coloca
# por trigonometria esferica alrededor de ese punto.
#
# Controles:
#   WASD / flechas   -> moverse por el mapa
#   Boton der/centro + arrastrar -> orbitar (girar e inclinar)
#   Rueda            -> zoom
#   Q / E            -> rotar la vista

@export var map_corner_min: Vector2 = Vector2(0.0, 0.0)
@export var map_corner_max: Vector2 = Vector2.ZERO   # si queda en cero, se toma el tamano del mapa

const YAW_DEFAULT := 0.0
const PITCH_DEFAULT := 55.0
const PITCH_MIN := 12.0
const PITCH_MAX := 82.0
const ZOOM_MIN := 6.0
const ZOOM_MAX := 150.0
const ZOOM_START := 20.0
const ZOOM_STEP := 4.0
const MOVE_SPEED := 40.0
const ROTATE_SPEED := 1.6
const ORBIT_SENSITIVITY := 0.006
const BORDER := 2.0
const CAMERA_CLEARANCE := 1.5   # distancia minima de la camara al terreno

var _cam: Camera3D
var _yaw := 0.0
var _pitch := deg_to_rad(PITCH_DEFAULT)
var _zoom := ZOOM_START
var _orbiting := false
var _drag_from := Vector2.ZERO
var _yaw_before := 0.0
var _pitch_before := 0.0


func _ready() -> void:
	_cam = $Camera3D
	_cam.current = true
	if map_corner_max == Vector2.ZERO:
		map_corner_max = Vector2(Terrain.WORLD_SIZE, Terrain.WORLD_SIZE)
	position = Vector3((map_corner_min.x + map_corner_max.x) * 0.5, 0.0, (map_corner_min.y + map_corner_max.y) * 0.5)
	_apply()


func _forward() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _apply() -> void:
	var rig := global_position
	var look := Vector3(rig.x, maxf(0.0, _height_at(rig)), rig.z)
	var horizontal: float = cos(_pitch) * _zoom
	var vertical: float = sin(_pitch) * _zoom
	var cam_world := look - _forward() * horizontal + Vector3(0.0, vertical, 0.0)
	cam_world.y = maxf(cam_world.y, _height_at(cam_world) + CAMERA_CLEARANCE)
	_cam.position = cam_world - rig
	_cam.look_at(look, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var btn := event as InputEventMouseButton
		if btn.button_index == MOUSE_BUTTON_MIDDLE or btn.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = btn.pressed
			_drag_from = btn.position
			_yaw_before = _yaw
			_pitch_before = _pitch
		elif btn.button_index == MOUSE_BUTTON_WHEEL_UP and btn.pressed:
			_zoom = clampf(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_apply()
		elif btn.button_index == MOUSE_BUTTON_WHEEL_DOWN and btn.pressed:
			_zoom = clampf(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_apply()

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			var delta := mm.position - _drag_from
			_yaw = _yaw_before + delta.x * ORBIT_SENSITIVITY
			_pitch = clampf(_pitch_before - delta.y * ORBIT_SENSITIVITY, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))
			_apply()


func _process(delta: float) -> void:
	if _orbiting and not (Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		_orbiting = false

	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1

	var yaw_input := 0.0
	if Input.is_key_pressed(KEY_Q):
		yaw_input -= 1
	if Input.is_key_pressed(KEY_E):
		yaw_input += 1

	var changed := false

	if dir != Vector2.ZERO:
		dir = dir.normalized()
		var speed: float = MOVE_SPEED * (_zoom / ZOOM_START) * delta
		position += _right() * dir.x * speed - _forward() * dir.y * speed
		position.x = clampf(position.x, map_corner_min.x - BORDER, map_corner_max.x + BORDER)
		position.z = clampf(position.z, map_corner_min.y - BORDER, map_corner_max.y + BORDER)
		changed = true

	if yaw_input != 0.0:
		_yaw += yaw_input * ROTATE_SPEED * delta
		changed = true

	if changed:
		_apply()


# Convierte una posicion de pantalla en el punto del suelo que se ve, teniendo
# en cuenta el relieve real (marcha de rayos sobre Terrain.height_at).
func screen_to_ground(screen_pos: Vector2) -> Vector2:
	var origin: Vector3 = _cam.project_ray_origin(screen_pos)
	var ray: Vector3 = _cam.project_ray_normal(screen_pos)
	var hit := _march(origin, ray)
	return Vector2(clampf(hit.x, map_corner_min.x - BORDER, map_corner_max.x + BORDER), clampf(hit.z, map_corner_min.y - BORDER, map_corner_max.y + BORDER))


# Mueve el punto observado al suelo indicado (p.ej. clic en el minimapa).
func move_to(ground: Vector2) -> void:
	position = Vector3(ground.x, 0.0, ground.y)
	_apply()


func _march(origin: Vector3, ray: Vector3) -> Vector3:
	var above := origin.y > _height_at(origin)
	var t := 0.0
	var step := 2.0
	while t < 300.0:
		t += step
		var p := origin + ray * t
		if p.y <= _height_at(p):
			return _refine(origin, ray, t - step, t)
		if not above:
			return _refine(origin, ray, 0.0, t)
	return origin + ray * 300.0


func _refine(origin: Vector3, ray: Vector3, lo: float, hi: float) -> Vector3:
	for i in range(12):
		var mid := (lo + hi) * 0.5
		var p := origin + ray * mid
		if p.y > _height_at(p):
			lo = mid
		else:
			hi = mid
	return origin + ray * ((lo + hi) * 0.5)


func _height_at(p: Vector3) -> float:
	if p.x < map_corner_min.x or p.x > map_corner_max.x or p.z < map_corner_min.y or p.z > map_corner_max.y:
		return -100.0
	return Terrain.height_at(Vector2(p.x, p.z))