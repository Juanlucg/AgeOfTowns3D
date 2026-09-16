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
## Pide retirar vegetacion/rocas al paso del camino (lo consumen Vegetation y
## Rocks via Main), como hace la colocacion de edificios.
signal path_clear_requested(pos: Vector2, radius: float)
## Emitida al seleccionar/deseleccionar un camino (vacio = nada).
signal stroke_selection_changed(stroke: Dictionary)
## Emitida al eliminar un camino.
signal stroke_demolished(id: int)

@export var camera_path: NodePath
@export var terrain_path: NodePath
## Ancho total del camino (m).
@export var path_width := 0.4

const SPEED_MULT := 1.6
const MIN_STEP := 0.25          # separacion minima entre puntos del trazo (m)
const AUTO_MARGIN := 0.25       # el puente automatico se apoya un poco en la orilla
const CLEAR_R := 0.8            # radio de limpieza de vegetacion/rocas del camino
## Longitud maxima de un tramo de camino: un trazo mas largo se parte en varios
## tramos para poder borrar por partes sin perder todo el camino.
const MAX_STROKE_LEN := 10.0
## Longitud minima de un tramo (evita trozos minusculos en los cruces).
const MIN_PIECE := 1.0
const MASK_SIZE := 2048         # resolucion de la mascara (px sobre el mapa)
const MASK_UPDATE_INTERVAL := 0.1
## Lado de la celda del indice espacial (m) para consultas "cerca de un punto".
const GRID_CELL := 8.0
## Tolerancia para considerar que un punto cae sobre un puente.
const BRIDGE_TOL := 0.8
## El camino solo se sigue si no alarga el viaje mas que esto respecto a ir
## recto: `via <= directa * ACCEPT_FACTOR + ACCEPT_SLACK`.
const ACCEPT_FACTOR := 1.6
const ACCEPT_SLACK := 2.5
## Avance minimo por el camino entre dos objetivos (evita bucles en el sitio).
const MIN_ADVANCE := 0.6
const PATH_COLOR := Color(0.62, 0.54, 0.42)
const GHOST_COLOR := Color(0.92, 0.84, 0.55, 0.35)

## Acceso global rapido para los aldeanos (como el autoload Terrain).
static var instance: Paths = null

var _cam_rig: CameraController3D
var _strokes: Array = []        # Array[ { id, pts: PackedVector2Array, bounds: Rect2 } ]
var _next_stroke_id := 0
## Indice espacial: Vector2i(celda) -> Array[int] indices de `_strokes`.
## Se reconstruye al cambiar los caminos (no en cada frame).
var _grid: Dictionary = {}
var _selected_stroke: Dictionary = {}
var _stroke_marker: MeshInstance3D = null
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
	_rebuild_grid()
	set_process(false)


# Limpia la referencia estatica al recargar la escena: sin esto, `instance`
# quedaba apuntando a un objeto liberado hasta el _ready de la nueva instancia.
func _exit_tree() -> void:
	if instance == self:
		instance = null


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
	# Itera el bucket del indice espacial directamente: antes _strokes_near()
	# creaba un Array nuevo en cada llamada, y esto corre por aldeano y frame.
	var bucket: Variant = _grid.get(Vector2i(
		int(floor(p.x / GRID_CELL)), int(floor(p.y / GRID_CELL))))
	if bucket != null:
		for i in bucket:
			if _near(_strokes[i], p, hw):
				return true
	if _current.size() >= 2:
		return _near_points(_current, p, hw)
	return false


# Bonus de velocidad sobre el camino. Sobre agua solo se acelera si se pisa un
# puente (el trazado puede cruzar el rio, pero ahi no hay camino pintado).
func speed_multiplier_at(p: Vector2) -> float:
	if not is_path(p):
		return 1.0
	if Terrain.is_water(p) and (Bridges.instance == null \
			or not Bridges.instance.is_bridge(p, BRIDGE_TOL)):
		return 1.0
	return SPEED_MULT


func count() -> int:
	return _strokes.size() + (1 if _current.size() >= 2 else 0)


# --- Seleccion y demolicion de caminos ---

func has_selection() -> bool:
	return not _selected_stroke.is_empty()


func get_selected_stroke() -> Dictionary:
	return _selected_stroke


## Camino MAS CERCANO a `pos` dentro del margen (ancho del camino +
## tolerancia), o {}. No depende del orden interno de `_strokes`.
##
## Desempate: si la distancia es practicamente igual (cruce exacto), gana el
## camino con el ID mayor, es decir, el creado mas recientemente.
func stroke_at(pos: Vector2) -> Dictionary:
	var hw := path_width * 0.5 + 0.3
	var hw2 := hw * hw
	var best: Dictionary = {}
	var best_d := 1.0e18
	for s in _strokes:
		var b: Rect2 = s["bounds"]
		if pos.x < b.position.x - hw or pos.x > b.end.x + hw \
				or pos.y < b.position.y - hw or pos.y > b.end.y + hw:
			continue
		var d2 := distance_sq_to_stroke(s["pts"], pos)
		if d2 > hw2:
			continue
		if best.is_empty() or d2 < best_d - 0.0001 \
				or (absf(d2 - best_d) <= 0.0001 and int(s["id"]) > int(best["id"])):
			best_d = d2
			best = s
	return best


## Distancia cuadrada minima de `pos` a la polilinea `pts`.
static func distance_sq_to_stroke(pts: PackedVector2Array, pos: Vector2) -> float:
	var best := 1.0e18
	for i in range(pts.size() - 1):
		best = minf(best, _dist_sq_to_segment(pos, pts[i], pts[i + 1]))
	return best


## Punto de la polilinea `pts` mas cercano a `pos`.
static func closest_point_on_stroke(pts: PackedVector2Array, pos: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := 1.0e18
	for i in range(pts.size() - 1):
		var a := pts[i]
		var ab := pts[i + 1] - a
		var denom := ab.length_squared()
		var t := 0.0
		if denom > 0.000001:
			t = clampf((pos - a).dot(ab) / denom, 0.0, 1.0)
		var q := a + ab * t
		var d := pos.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best


## True si el camino con ese id sigue existiendo (p. ej. no fue demolido).
func has_stroke(id: int) -> bool:
	for s in _strokes:
		if int(s["id"]) == id:
			return true
	return false


## Camino MAS CERCANO a `pos` a `max_dist` metros como maximo, o {}.
## Consulta solo las celdas del indice espacial dentro de ese radio.
func nearest_stroke(pos: Vector2, max_dist: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := max_dist * max_dist
	var r := int(ceil(max_dist / GRID_CELL))
	var cx := int(floor(pos.x / GRID_CELL))
	var cy := int(floor(pos.y / GRID_CELL))
	var seen := {}
	for gx in range(cx - r, cx + r + 1):
		for gy in range(cy - r, cy + r + 1):
			var bucket: Variant = _grid.get(Vector2i(gx, gy))
			if bucket == null:
				continue
			for i in bucket:
				if seen.has(i):
					continue
				seen[i] = true
				var s: Dictionary = _strokes[i]
				var d2 := distance_sq_to_stroke(s["pts"], pos)
				if d2 <= best_d:
					best_d = d2
					best = s
	return best


## Plan para seguir `stroke` desde `from` hacia `dest`, avanzando `lookahead`
## metros por el camino hasta el proximo objetivo. Devuelve:
##   { use:bool, point:Vector2, entry:Vector2, exit:Vector2 }
## `use` es false si el camino no ayuda (se aleja/detour) o si no hay avance.
## Nunca devuelve un punto sobre agua sin puente.
func plan_along_stroke(stroke: Dictionary, from: Vector2, dest: Vector2,
		lookahead: float) -> Dictionary:
	var out := {"use": false, "point": dest, "entry": from, "exit": dest,
		"via": 0.0, "path_len": 0.0}
	var pts: PackedVector2Array = stroke.get("pts", PackedVector2Array())
	if pts.size() < 2:
		return out
	var cum := _cum_lengths(pts)
	var ce := _closest_param(pts, cum, from)
	var cx := _closest_param(pts, cum, dest)
	var se: float = ce["arc"]
	var sx: float = cx["arc"]
	var path_len := absf(sx - se)
	var direct := from.distance_to(dest)
	var via: float = ce["dist"] + path_len + cx["dist"]
	if via > direct * ACCEPT_FACTOR + ACCEPT_SLACK:
		return out
	# Objetivo: `lookahead` metros por el camino hacia el punto de salida.
	var arc := sx
	if path_len > lookahead:
		arc = se + signf(sx - se) * lookahead
	var point := _point_at_arc(pts, cum, arc)
	if not _point_usable(point):
		point = _nearest_usable_arc(pts, cum, arc, se)
	if not _point_usable(point):
		return out
	# Evitar quedarnos clavados en el sitio (no hay avance real).
	if point.distance_to(from) < MIN_ADVANCE and path_len <= MIN_ADVANCE:
		return out
	out["use"] = true
	out["point"] = point
	out["entry"] = ce["point"]
	out["exit"] = cx["point"]
	out["via"] = via
	out["path_len"] = path_len
	return out


## Elige el camino cercano cuyo seguimiento hacia `dest` sea mejor (menor
## desvio) desde `from`. Devuelve {} o el mejor plan mas su trazo:
##   { use:true, stroke, point, entry, exit, via }
func plan_via_nearest(from: Vector2, dest: Vector2, max_dist: float,
		lookahead: float) -> Dictionary:
	var best := {"use": false}
	var best_via := 1.0e18
	var max2 := max_dist * max_dist
	var r := int(ceil(max_dist / GRID_CELL))
	var cx := int(floor(from.x / GRID_CELL))
	var cy := int(floor(from.y / GRID_CELL))
	var seen := {}
	for gx in range(cx - r, cx + r + 1):
		for gy in range(cy - r, cy + r + 1):
			var bucket: Variant = _grid.get(Vector2i(gx, gy))
			if bucket == null:
				continue
			for i in bucket:
				if seen.has(i):
					continue
				seen[i] = true
				var s: Dictionary = _strokes[i]
				if distance_sq_to_stroke(s["pts"], from) > max2:
					continue
				var plan := plan_along_stroke(s, from, dest, lookahead)
				if not bool(plan["use"]):
					continue
				if float(plan["via"]) < best_via:
					best_via = float(plan["via"])
					best = plan.duplicate()
					best["stroke"] = s
	return best


# --- Indice espacial ---

func _rebuild_grid() -> void:
	_grid.clear()
	var pad := path_width * 0.5 + 0.5
	for i in range(_strokes.size()):
		var b: Rect2 = _strokes[i]["bounds"]
		var x0 := int(floor((b.position.x - pad) / GRID_CELL))
		var x1 := int(floor((b.end.x + pad) / GRID_CELL))
		var y0 := int(floor((b.position.y - pad) / GRID_CELL))
		var y1 := int(floor((b.end.y + pad) / GRID_CELL))
		for gx in range(x0, x1 + 1):
			for gy in range(y0, y1 + 1):
				var key := Vector2i(gx, gy)
				if not _grid.has(key):
					_grid[key] = []
				(_grid[key] as Array).append(i)




# --- Geometria de polilineas ---

static func _cum_lengths(pts: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	for i in range(1, pts.size()):
		cum[i] = cum[i - 1] + pts[i - 1].distance_to(pts[i])
	return cum


# Punto mas cercano de la polilinea a `pos`: { arc, dist, point }.
static func _closest_param(pts: PackedVector2Array, cum: PackedFloat32Array,
		pos: Vector2) -> Dictionary:
	var best_d := 1.0e18
	var best_arc := 0.0
	var best_point := pts[0]
	for i in range(pts.size() - 1):
		var a := pts[i]
		var ab := pts[i + 1] - a
		var seglen := sqrt(ab.length_squared())
		var denom := ab.length_squared()
		var t := 0.0
		if denom > 0.000001:
			t = clampf((pos - a).dot(ab) / denom, 0.0, 1.0)
		var q := a + ab * t
		var d := pos.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best_arc = cum[i] + seglen * t
			best_point = q
	return {"arc": best_arc, "dist": sqrt(best_d), "point": best_point}


static func _point_at_arc(pts: PackedVector2Array, cum: PackedFloat32Array,
		arc: float) -> Vector2:
	var total := cum[cum.size() - 1]
	arc = clampf(arc, 0.0, total)
	for i in range(pts.size() - 1):
		var seg := cum[i + 1] - cum[i]
		if arc <= cum[i + 1] or i == pts.size() - 2:
			var t := 0.0 if seg <= 0.000001 else (arc - cum[i]) / seg
			return pts[i].lerp(pts[i + 1], clampf(t, 0.0, 1.0))
	return pts[pts.size() - 1]


# Punto valido para caminar: tierra, o un puente si esta sobre agua.
static func _point_usable(p: Vector2) -> bool:
	if not is_finite(p.x) or not is_finite(p.y):
		return false
	if not Terrain.is_water(p):
		return true
	return Bridges.instance != null and Bridges.instance.is_bridge(p, BRIDGE_TOL)


# Desde `arc` (sobre agua sin puente) retrocede hacia `back_to` hasta tierra.
static func _nearest_usable_arc(pts: PackedVector2Array, cum: PackedFloat32Array,
		arc: float, back_to: float) -> Vector2:
	var dir := signf(back_to - arc)
	if dir == 0.0:
		return Vector2.INF
	var a := arc
	for _k in range(80):
		a += dir * 0.25
		if (dir > 0.0 and a >= back_to) or (dir < 0.0 and a <= back_to):
			a = back_to
		if _point_usable(_point_at_arc(pts, cum, a)):
			return _point_at_arc(pts, cum, a)
		if is_equal_approx(a, back_to):
			break
	return Vector2.INF


## Selecciona el camino bajo `pos`. Devuelve true si habia uno.
func select_at(pos: Vector2) -> bool:
	var s := stroke_at(pos)
	if s.is_empty():
		return false
	select_stroke(s)
	return true


func select_stroke(s: Dictionary) -> void:
	if not _selected_stroke.is_empty() and int(_selected_stroke["id"]) == int(s["id"]):
		return
	deselect_stroke()
	_selected_stroke = s
	_add_stroke_marker(s)
	stroke_selection_changed.emit(_selected_stroke)


func deselect_stroke() -> void:
	if _selected_stroke.is_empty():
		return
	_remove_stroke_marker()
	_selected_stroke = {}
	stroke_selection_changed.emit({})


func demolish_selected_stroke() -> void:
	if not _selected_stroke.is_empty():
		demolish_stroke(int(_selected_stroke["id"]))


## Elimina un camino y, de paso, sus puentes automaticos.
func demolish_stroke(id: int) -> bool:
	var idx := -1
	for i in _strokes.size():
		if int((_strokes[i] as Dictionary)["id"]) == id:
			idx = i
			break
	if idx == -1:
		return false
	if not _selected_stroke.is_empty() and int(_selected_stroke["id"]) == id:
		deselect_stroke()
	if Bridges.instance != null:
		for br in Bridges.instance.bridges_for_stroke(id):
			Bridges.instance.remove_bridge(br)
	_strokes.remove_at(idx)
	_rebuild_mask_from_strokes()
	_rebuild_grid()
	_flush_mask()
	stroke_demolished.emit(id)
	return true


# Marca todo el camino: una cinta resaltada que sigue su trazado (no un punto).
func _add_stroke_marker(s: Dictionary) -> void:
	_remove_stroke_marker()
	var pts: PackedVector2Array = s["pts"]
	if pts.size() < 2:
		return
	var hw := path_width * 0.5 + 0.22
	var n := pts.size()
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	for i in range(n):
		var dir: Vector2
		if i == 0:
			dir = (pts[1] - pts[0]).normalized()
		elif i == n - 1:
			dir = (pts[i] - pts[i - 1]).normalized()
		else:
			dir = (pts[i + 1] - pts[i - 1]).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		var nrm := Vector2(-dir.y, dir.x)
		lefts.append(_highlight_point(pts[i] + nrm * hw))
		rights.append(_highlight_point(pts[i] - nrm * hw))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n - 1):
		st.add_vertex(lefts[i])
		st.add_vertex(rights[i])
		st.add_vertex(lefts[i + 1])
		st.add_vertex(rights[i])
		st.add_vertex(rights[i + 1])
		st.add_vertex(lefts[i + 1])
	st.generate_normals()
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	add_child(m)
	_stroke_marker = m


static func _highlight_point(p: Vector2) -> Vector3:
	return Vector3(p.x, Terrain.height_at(p) + 0.05, p.y)


func _remove_stroke_marker() -> void:
	if _stroke_marker != null and is_instance_valid(_stroke_marker):
		_stroke_marker.queue_free()
	_stroke_marker = null


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
	# Camino y puente son excluyentes.
	if Bridges.instance != null:
		Bridges.instance.stop_build()
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
	if Terrain.is_water(p):
		message_requested.emit("Los caminos deben comenzar en tierra")
		return
	_current = PackedVector2Array([p])
	_stamp(p)
	_clear_at(p)


func _append_point(p: Vector2) -> void:
	if _current.is_empty():
		_current = PackedVector2Array([p])
		if not Terrain.is_water(p):
			_stamp(p)
		return
	var last := _current[_current.size() - 1]
	if last.distance_to(p) < MIN_STEP:
		return
	_current.append(p)
	# El color del camino se pinta solo en tierra (sobre el agua iria bajo la
	# superficie); el tramo de agua lo cubre el puente. Al entrar/salir del agua
	# se pinta hasta la orilla exacta para que el camino no quede cortado.
	var last_w := Terrain.is_water(last)
	var cur_w := Terrain.is_water(p)
	if not last_w and not cur_w:
		_stamp_segment(last, p)
	elif not last_w and cur_w:
		_stamp_segment(last, _water_edge(last, p))
	elif last_w and not cur_w:
		_stamp_segment(_water_edge(last, p), p)
	_clear_at(p)


# Retira vegetacion/rocas alrededor del punto del camino.
func _clear_at(p: Vector2) -> void:
	path_clear_requested.emit(p, path_width * 0.5 + CLEAR_R)


func _finish_stroke() -> void:
	if _current.size() >= 2:
		var crossings := _find_crossings(_current)
		var err := _validate_crossings(crossings)
		if err == "":
			var stroke := {"id": _next_stroke_id, "pts": _current, "bounds": _bounds(_current)}
			_next_stroke_id += 1
			_strokes.append(stroke)
			for c in crossings:
				Bridges.instance.add_bridge(
					c["a"], c["b"], path_width + 0.4, true, false, int(stroke["id"]))
			# Re-trocea TODOS los caminos por cruces (sin importar el orden en
			# que se dibujaron) y por longitud.
			_resegment_all()
		else:
			# No se pudo cruzar: no queda camino atravesando el agua.
			_rebuild_mask_from_strokes()
			message_requested.emit(err)
	_current = PackedVector2Array()
	_flush_mask()


# Re-trocea todos los caminos por cruces (para que un tramo acabe en cada
# cruce) y por longitud, y reasocia los puentes automaticos a su tramo.
func _resegment_all() -> void:
	deselect_stroke()
	var polys: Array = []
	for s in _strokes:
		polys.append({"pts": s["pts"], "bounds": s["bounds"]})
	var new_polys: Array = []
	for i in range(polys.size()):
		for seg in _cut_at_intersections(polys[i]["pts"], polys, i):
			new_polys.append_array(_cut_by_length(seg))
	_strokes.clear()
	for p in new_polys:
		var stroke := {"id": _next_stroke_id, "pts": p, "bounds": _bounds(p)}
		_next_stroke_id += 1
		_strokes.append(stroke)
	if Bridges.instance != null:
		for br in Bridges.instance.bridges_auto():
			var mid: Vector2 = ((br["a"] as Vector2) + (br["b"] as Vector2)) * 0.5
			var s := stroke_at(mid)
			if not s.is_empty():
				br["stroke_id"] = int(s["id"])
	_rebuild_mask_from_strokes()
	_rebuild_grid()


# Crea puentes en los tramos del trazo que cruzan agua (con tierra a los dos
# lados). [Bridges] cobra la madera y crea el [NavigationLink3D]; devuelve false
# si no hay madera (para revertir el trazo).
# Cruces de agua de una polilinea, escaneando los segmentos COMPLETOS: asi se
# detecta un rio aunque los dos puntos muestreados esten en tierra.
func _find_crossings(pts: PackedVector2Array) -> Array:
	var crossings: Array = []
	if Bridges.instance == null or pts.size() < 2:
		return crossings
	var inside := false
	var entry := Vector2.ZERO
	for i in range(1, pts.size()):
		var prev := pts[i - 1]
		var cur := pts[i]
		var steps := maxi(1, int(ceil(prev.distance_to(cur) / 0.3)))
		var a := prev
		var a_w := Terrain.is_water(a)
		for k in range(1, steps + 1):
			var b := prev.lerp(cur, float(k) / float(steps))
			var b_w := Terrain.is_water(b)
			if not a_w and b_w:
				entry = _water_edge(a, b)
				inside = true
			elif a_w and not b_w and inside:
				inside = false
				var exit_edge := _water_edge(b, a)
				var dir := exit_edge - entry
				if dir.length() > 0.5:
					dir = dir.normalized()
					crossings.append({
						"a": entry - dir * AUTO_MARGIN,
						"b": exit_edge + dir * AUTO_MARGIN,
					})
			a = b
			a_w = b_w
	return crossings


# Valida TODOS los cruces antes de crear nada: solo rios y madera suficiente.
func _validate_crossings(crossings: Array) -> String:
	var total := 0
	for c in crossings:
		var ca: Vector2 = c["a"]
		var cb: Vector2 = c["b"]
		if Terrain.water_kind_at((ca + cb) * 0.5) != Terrain.WATER_RIVER:
			return "Solo se pueden construir puentes sobre ríos"
		if Bridges.instance.has_crossing(ca, cb):
			continue
		total += Bridges.cost_for(ca.distance_to(cb))
	if total > 0 and not Economy.can_afford({"madera": float(total)}):
		return "Camino cancelado: falta madera para el puente"
	return ""


# --- Troceado en tramos ---

# Corta el trazo donde cruza transversalmente CUALQUIER OTRO camino.
func _cut_at_intersections(pts: PackedVector2Array, polys: Array, self_idx: int) -> Array:
	var out: Array = []
	var n := pts.size()
	if n < 2:
		return out
	var start := 0
	for i in range(1, n):
		if not _hits_other_path(pts[i - 1], pts[i], polys, self_idx):
			continue
		if pts[i - 1].distance_to(pts[start]) >= MIN_PIECE:
			out.append(_sub(pts, start, i - 1))
			start = i - 1
	if start < n - 1:
		out.append(_sub(pts, start, n - 1))
	if out.is_empty():
		out.append(pts)
	return out


func _cut_by_length(pts: PackedVector2Array) -> Array:
	var chunks: Array = []
	var n := pts.size()
	if n < 2:
		return chunks
	var cum := PackedFloat32Array()
	cum.resize(n)
	for i in range(1, n):
		cum[i] = cum[i - 1] + pts[i - 1].distance_to(pts[i])
	var start := 0
	while start < n - 1:
		var target: float = cum[start] + MAX_STROKE_LEN
		var idx := start + 1
		while idx < n - 1 and cum[idx] < target:
			idx += 1
		if idx >= n - 1:
			chunks.append(_sub(pts, start, n - 1))
			break
		var cut := _safe_cut(pts, idx)
		if cut <= start + 1:
			chunks.append(_sub(pts, start, n - 1))
			break
		chunks.append(_sub(pts, start, cut))
		start = cut
	return chunks


# True si el segmento a-b cruza transversalmente algun camino de `polys`
# (excepto el de indice `skip`).
func _hits_other_path(a: Vector2, b: Vector2, polys: Array, skip: int) -> bool:
	for k in range(polys.size()):
		if k == skip:
			continue
		var d: Dictionary = polys[k]
		var bb: Rect2 = d["bounds"]
		if maxf(a.x, b.x) < bb.position.x or minf(a.x, b.x) > bb.end.x \
				or maxf(a.y, b.y) < bb.position.y or minf(a.y, b.y) > bb.end.y:
			continue
		var sp: PackedVector2Array = d["pts"]
		for j in range(sp.size() - 1):
			if _segments_cross(a, b, sp[j], sp[j + 1]):
				return true
	return false


static func _segments_cross(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var d1 := _cross(p3, p4, p1)
	var d2 := _cross(p3, p4, p2)
	var d3 := _cross(p1, p2, p3)
	var d4 := _cross(p1, p2, p4)
	return ((d1 > 0.0 and d2 < 0.0) or (d1 < 0.0 and d2 > 0.0)) \
		and ((d3 > 0.0 and d4 < 0.0) or (d3 < 0.0 and d4 > 0.0))


static func _cross(a: Vector2, b: Vector2, p: Vector2) -> float:
	return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)


static func _sub(pts: PackedVector2Array, a: int, b: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(a, b + 1):
		if i >= 0 and i < pts.size():
			out.append(pts[i])
	return out


# Indice de corte mas cercano a `idx` con tierra en el punto y en sus vecinos.
func _safe_cut(pts: PackedVector2Array, idx: int) -> int:
	var n := pts.size()
	for off in range(0, n):
		for cand in [idx - off, idx + off]:
			if cand <= 0 or cand >= n - 1:
				continue
			if not Terrain.is_water(pts[cand - 1]) \
					and not Terrain.is_water(pts[cand]) \
					and not Terrain.is_water(pts[cand + 1]):
				return cand
	return -1


# Rehace la mascara del camino desde los trazos guardados (para revertir el
# ultimo si no se pudo crear su puente).
func _rebuild_mask_from_strokes() -> void:
	_mask.fill(Color(0, 0, 0, 1))
	for s in _strokes:
		var pts: PackedVector2Array = s["pts"]
		for i in range(pts.size() - 1):
			var lw := Terrain.is_water(pts[i])
			var cw := Terrain.is_water(pts[i + 1])
			if not lw and not cw:
				_stamp_segment(pts[i], pts[i + 1])
			elif not lw and cw:
				_stamp_segment(pts[i], _water_edge(pts[i], pts[i + 1]))
			elif lw and not cw:
				_stamp_segment(_water_edge(pts[i], pts[i + 1]), pts[i + 1])
	_mask_dirty = true


# Punto del segmento a->b donde cambia tierra/agua (a y b son de distinto tipo).
static func _water_edge(a: Vector2, b: Vector2) -> Vector2:
	var lo := a
	var hi := b
	for _k in range(14):
		var mid := (lo + hi) * 0.5
		if Terrain.is_water(mid) == Terrain.is_water(b):
			hi = mid
		else:
			lo = mid
	return (lo + hi) * 0.5


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
