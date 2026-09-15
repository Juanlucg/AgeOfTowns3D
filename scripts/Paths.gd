extends Node3D
class_name Paths
## Red de caminos. El jugador los dibuja a mano alzada con el raton (tecla P o
## boton del menu): mantiene el boton izquierdo y va trazando; clic derecho o
## Esc para salir.
##
## Los caminos se pintan en una MASCARA que se pasa al shader del terreno, en
## vez de ser geometria aparte: asi se funden entre si (las uniones no se pintan
## por encima), no hay z-fighting y quedan pegados al suelo.
##
## [Villager] consulta [member instance] para saber si esta sobre un camino.

signal message_requested(text: String)

@export var camera_path: NodePath
@export var terrain_path: NodePath
## Ancho total del camino (m).
@export var path_width := 0.4

const SPEED_MULT := 1.6
const MIN_STEP := 0.25          # separacion minima entre puntos del trazo (m)
const MASK_SIZE := 2048         # resolucion de la mascara (px sobre el mapa)
const MASK_UPDATE_INTERVAL := 0.1
const PATH_COLOR := Color(0.62, 0.54, 0.42)
const GHOST_COLOR := Color(0.92, 0.84, 0.55, 0.35)

## Acceso global rapido para los aldeanos (como el autoload Terrain).
static var instance: Paths = null

var _cam_rig: CameraController3D
var _strokes: Array = []        # Array[ { pts: PackedVector2Array, bounds: Rect2 } ]
var _current := PackedVector2Array()
var _placing := false
var _drawing := false
var _ghost: MeshInstance3D

var _mask: Image
var _tex: ImageTexture
var _mask_dirty := false
var _tex_timer := 0.0


func _ready() -> void:
	instance = self
	_cam_rig = get_node_or_null(camera_path) as CameraController3D
	_ghost = _make_disc(path_width * 0.5, GHOST_COLOR)
	_ghost.visible = false
	add_child(_ghost)

	_mask = Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_R8)
	_mask.fill(Color(0, 0, 0, 1))
	_tex = ImageTexture.create_from_image(_mask)
	_bind_terrain_material()
	set_process(false)


func _bind_terrain_material() -> void:
	var terrain := get_node_or_null(terrain_path) as TerrainMesh
	if terrain == null and get_parent() != null:
		terrain = get_parent().get_node_or_null("Ground") as TerrainMesh
	if terrain == null or terrain.terrain_material == null:
		return
	terrain.terrain_material.set_shader_parameter("u_path_mask", _tex)
	terrain.terrain_material.set_shader_parameter("u_path_color", Vector3(PATH_COLOR.r, PATH_COLOR.g, PATH_COLOR.b))


static func _make_mat(color: Color, translucent: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	if translucent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_disc(radius: float, color: Color) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = 0.02
	m.radial_segments = 24
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _make_mat(color, true)
	return mi


# --- API de consulta ---

func is_placing() -> bool:
	return _placing


func is_path(p: Vector2) -> bool:
	var hw := path_width * 0.5
	for s in _strokes:
		if _near(s, p, hw):
			return true
	if _current.size() >= 2:
		return _near_points(_current, p, hw)
	return false


func speed_multiplier_at(p: Vector2) -> float:
	return SPEED_MULT if is_path(p) else 1.0


func count() -> int:
	return _strokes.size() + (1 if _current.size() >= 2 else 0)


func _near(s: Dictionary, p: Vector2, hw: float) -> bool:
	var b: Rect2 = s["bounds"]
	if p.x < b.position.x - hw or p.x > b.end.x + hw \
			or p.y < b.position.y - hw or p.y > b.end.y + hw:
		return false
	return _near_points(s["pts"], p, hw)


func _near_points(pts: PackedVector2Array, p: Vector2, hw: float) -> bool:
	var hw2 := hw * hw
	for i in range(pts.size() - 1):
		if _dist_sq_to_segment(p, pts[i], pts[i + 1]) <= hw2:
			return true
	return false


static func _dist_sq_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	var t := 0.0
	if denom > 0.000001:
		t = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)


# --- Modo construccion ---

func toggle_build() -> void:
	if _placing:
		stop_build()
	else:
		start_build()


func start_build() -> void:
	if _cam_rig == null:
		return
	_placing = true
	_ghost.visible = true
	set_process(true)


func stop_build() -> void:
	if not _placing:
		return
	_placing = false
	_drawing = false
	_finish_stroke()
	_ghost.visible = false
	set_process(false)


func _process(delta: float) -> void:
	if _mask_dirty:
		_tex_timer -= delta
		if _tex_timer <= 0.0:
			_tex.update(_mask)
			_mask_dirty = false
			_tex_timer = MASK_UPDATE_INTERVAL
	if not _placing or _cam_rig == null:
		return
	var mouse := get_viewport().get_mouse_position()
	if _drawing and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_append_point(_cam_rig.screen_to_ground(mouse))
	var ground: Vector2 = _cam_rig.screen_to_ground(mouse)
	_ghost.position = Vector3(ground.x, Terrain.height_at(ground) + 0.05, ground.y)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_path"):
		toggle_build()
		get_viewport().set_input_as_handled()
		return
	if not _placing:
		return
	if event.is_action_pressed("cancel"):
		stop_build()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var btn := event as InputEventMouseButton
		if btn.button_index == MOUSE_BUTTON_RIGHT:
			if btn.pressed:
				stop_build()
			get_viewport().set_input_as_handled()
		elif btn.button_index == MOUSE_BUTTON_LEFT:
			if btn.pressed and _cam_rig != null:
				_drawing = true
				_begin_stroke(_cam_rig.screen_to_ground(btn.position))
			else:
				_drawing = false
				_finish_stroke()
			get_viewport().set_input_as_handled()


func _begin_stroke(p: Vector2) -> void:
	_finish_stroke()
	if not Terrain.is_water(p):
		_current = PackedVector2Array([p])
		_stamp(p)


func _append_point(p: Vector2) -> void:
	# Un camino no puede cruzar el agua: se corta el trazo.
	if Terrain.is_water(p):
		_finish_stroke()
		return
	if _current.is_empty():
		_current = PackedVector2Array([p])
		_stamp(p)
		return
	if _current[_current.size() - 1].distance_to(p) < MIN_STEP:
		return
	_stamp_segment(_current[_current.size() - 1], p)
	_current.append(p)


func _finish_stroke() -> void:
	if _current.size() >= 2:
		_strokes.append({"pts": _current, "bounds": _bounds(_current)})
	_current = PackedVector2Array()
	# Al cerrar el trazo se vuelca la mascara ya, para que el camino aparezca
	# de inmediato (aunque se salga del modo construccion en el mismo frame).
	_flush_mask()


# Fuerza el volcado de la mascara a la textura si hay cambios pendientes.
func _flush_mask() -> void:
	if _mask_dirty and _tex != null:
		_tex.update(_mask)
		_mask_dirty = false
		_tex_timer = MASK_UPDATE_INTERVAL


static func _bounds(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn.x = minf(mn.x, p.x)
		mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x)
		mx.y = maxf(mx.y, p.y)
	return Rect2(mn, mx - mn)


# --- Mascara ---

func _stamp_segment(a: Vector2, b: Vector2) -> void:
	var radius := path_width * 0.5
	var steps := maxi(1, int(ceil(a.distance_to(b) / maxf(0.05, radius * 0.5))))
	for i in range(steps + 1):
		_stamp(a.lerp(b, float(i) / float(steps)))


# Marca un disco suave (con borde difuminado) en la mascara. Se guarda el
# maximo, de modo que dos trazos que se cruzan se funden en uno solo.
func _stamp(c: Vector2) -> void:
	if _mask == null:
		return
	var n := MASK_SIZE
	var scale := float(n) / Terrain.WORLD_SIZE
	var px := c.x * scale
	var py := c.y * scale
	var rpx := (path_width * 0.5) * scale
	# Disco de radio rpx con un borde de ~1 px (el filtrado lineal de la
	# textura lo suaviza). Asi el ancho pintado coincide con path_width.
	var x0 := maxi(0, int(floor(px - rpx - 1.0)))
	var x1 := mini(n - 1, int(ceil(px + rpx + 1.0)))
	var y0 := maxi(0, int(floor(py - rpx - 1.0)))
	var y1 := mini(n - 1, int(ceil(py + rpx + 1.0)))
	for y in range(y0, y1 + 1):
		var dy := float(y) + 0.5 - py
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - px
			var d := sqrt(dx * dx + dy * dy)
			var v := clampf(rpx + 0.5 - d, 0.0, 1.0)
			if v <= 0.0:
				continue
			if _mask.get_pixel(x, y).r < v:
				_mask.set_pixel(x, y, Color(v, 0, 0, 1))
	_mask_dirty = true
