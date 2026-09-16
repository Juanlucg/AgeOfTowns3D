extends Node3D
class_name Bridges
## Puentes sobre el rio. Se crean de dos maneras:
##  - automaticamente, cuando un camino cruza agua (lo pide [Paths]);
##  - a mano, con la tecla B.
##
## Arquitectura: la malla de navegacion ([NavigationWorld]) es SOLO tierra. Cada
## puente anade un [NavigationLink3D] entre sus dos orillas (en tierra firme),
## de modo que los aldeanos cruzan el rio por el enlace sin que ninguna celda de
## agua se convierta en terreno navegable.
##
## [Villager] consulta [member instance] para la altura del tablero y el bonus
## de velocidad.

signal bridges_changed
signal message_requested(text: String)

@export var camera_path: NodePath

const DECK_H := 0.1            # altura minima del tablero sobre el agua
const DECK_THICK := 0.1
const RAIL_H := 0.22
const RAIL_W := 0.06
const COST_PER_METER := 2.0    # madera por metro de puente
const MAX_SPAN := 28.0
const EDGE_MARGIN := 0.6       # el puente se mete en la orilla
const MANUAL_WIDTH := 0.8
const SPEED_MULT := 1.6        # mismo bonus que los caminos
const LINK_INSET := 0.6        # el enlace se mete aun mas en tierra firme
const GHOST_OK := Color(0.45, 1.0, 0.55, 0.5)
const GHOST_BAD := Color(1.0, 0.35, 0.3, 0.45)
const WOOD_COLOR := Color(0.45, 0.30, 0.16)

## Acceso global rapido para aldeanos y caminos.
static var instance: Bridges = null

var _cam_rig: CameraController3D
var _bridges: Array = []       # { a, b, width, ya, yb, link }
var _placing := false
var _yaw := 0.0
var _ghost: Node3D = null
var _ghost_ok := false
var _ghost_span := {}
var _ghost_yaw := 1.0e9   # fuerza el primer reconstruido del fantasma


func _ready() -> void:
	instance = self
	_cam_rig = get_node_or_null(camera_path) as CameraController3D


# --- API ---

func count() -> int:
	return _bridges.size()


## True si ya existe un puente sobre el mismo cruce (para no duplicar).
func has_crossing(a: Vector2, b: Vector2) -> bool:
	for br in _bridges:
		if _same_crossing(br, a, b):
			return true
	return false


## Distancia (con tolerancia) al eje del puente mas cercano.
func is_bridge(p: Vector2, tol := 0.0) -> bool:
	for br in _bridges:
		var hw: float = br["width"] * 0.5 + tol
		if _dist_sq(p, br["a"], br["b"]) <= hw * hw:
			return true
	return false


## Altura del tablero en `p` (interpolada por la pendiente), o -INF si no pisa
## ningun puente.
func deck_height_at(p: Vector2, tol := 0.0) -> float:
	var h := -1.0e9
	for br in _bridges:
		var hw: float = br["width"] * 0.5 + tol
		if _dist_sq(p, br["a"], br["b"]) <= hw * hw:
			var t := _project_t(p, br["a"], br["b"])
			h = maxf(h, lerpf(br["ya"], br["yb"], t))
	return h


static func _project_t(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.000001:
		return 0.0
	return clampf((p - a).dot(ab) / denom, 0.0, 1.0)


static func _dist_sq(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	var t := 0.0
	if denom > 0.000001:
		t = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)


static func cost_for(length: float) -> int:
	return int(ceil(length * COST_PER_METER))


func can_afford_crossing(a: Vector2, b: Vector2) -> bool:
	return Economy.can_afford({"madera": float(cost_for(a.distance_to(b)))})


## Crea un puente recto de `a` a `b` (mas su enlace de navegacion). Si `charge`,
## cobra la madera. Devuelve true si se construyo (o si ya existia).
func add_bridge(a: Vector2, b: Vector2, width: float, charge := true) -> bool:
	var length := a.distance_to(b)
	if length < 0.8:
		return false
	# No duplicar el mismo cruce.
	for br in _bridges:
		if _same_crossing(br, a, b):
			return true
	if charge:
		var cost := cost_for(length)
		if not Economy.can_afford({"madera": float(cost)}):
			message_requested.emit("Falta madera para el puente (%d)" % cost)
			return false
		Economy.spend_all({"madera": float(cost)})
	var mid := (a + b) * 0.5
	var ends := _deck_ends(a, b, Terrain.water_level_at(mid))
	var ya: float = ends.x
	var yb: float = ends.y
	add_child(_bridge_node(a, b, width, ya, yb, _mat(WOOD_COLOR)))
	var link := _make_link(a, b, ya, yb)
	_bridges.append({"a": a, "b": b, "width": width, "ya": ya, "yb": yb, "link": link})
	bridges_changed.emit()
	return true


static func _same_crossing(br: Dictionary, a: Vector2, b: Vector2) -> bool:
	# Mismo cruce si el centro del nuevo puente cae sobre el existente y la
	# direccion es parecida (los extremos pueden variar por el margen o por
	# dibujar dos veces el mismo tramo).
	var br_a: Vector2 = br["a"]
	var br_b: Vector2 = br["b"]
	if _dist_sq((a + b) * 0.5, br_a, br_b) > 1.0:
		return false
	var d_br := (br_b - br_a).normalized()
	var d_new := (b - a).normalized()
	return absf(d_br.dot(d_new)) > 0.7


# Alturas de cada extremo: a ras de la orilla (con una pizca de despegue) y,
# como minimo, DECK_H sobre el agua. Permite una ligera pendiente entre orillas
# de distinta altura sin enterrar ningun extremo.
func _deck_ends(a: Vector2, b: Vector2, water: float) -> Vector2:
	var lift := 0.03
	var ya := maxf(Terrain.height_at(a), water + DECK_H) + lift
	var yb := maxf(Terrain.height_at(b), water + DECK_H) + lift
	return Vector2(ya, yb)


# Enlace de navegacion entre las dos orillas (en tierra firme). Es lo que
# permite a los aldeanos cruzar sin marcar el agua como navegable.
func _make_link(a: Vector2, b: Vector2, ya: float, yb: float) -> NavigationLink3D:
	var dir := (b - a).normalized()
	var start := _push_to_land(a - dir * LINK_INSET, -dir)
	var end := _push_to_land(b + dir * LINK_INSET, dir)
	var link := NavigationLink3D.new()
	link.start_position = Vector3(start.x, ya, start.y)
	link.end_position = Vector3(end.x, yb, end.y)
	link.bidirectional = true
	add_child(link)
	return link


static func _push_to_land(p: Vector2, dir: Vector2) -> Vector2:
	var q := p
	var t := 0.0
	while Terrain.is_water(q) and t < 8.0:
		q += dir * 0.3
		t += 0.3
	return q


func _bridge_node(a: Vector2, b: Vector2, width: float, ya: float, yb: float, mat: Material) -> Node3D:
	var dir := (b - a)
	var length := dir.length()
	var yaw := atan2(dir.x, dir.y)
	var pitch := atan2(yb - ya, length)
	var node := Node3D.new()
	node.position = Vector3((a.x + b.x) * 0.5, (ya + yb) * 0.5, (a.y + b.y) * 0.5)
	node.rotation = Vector3(0.0, yaw, 0.0)
	# Ligera pendiente a lo largo del tablero (eje local Z).
	node.rotate_object_local(Vector3.RIGHT, -pitch)
	var xform := node.transform

	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(width, DECK_THICK, length)
	deck.mesh = dm
	deck.material_override = mat
	node.add_child(deck)
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(RAIL_W, RAIL_H, length)
		rail.mesh = rm
		rail.material_override = mat
		rail.position = Vector3(
			side * (width * 0.5 - RAIL_W * 0.5),
			DECK_THICK * 0.5 + RAIL_H * 0.5,
			0.0)
		node.add_child(rail)

	# Pilares: bajan hasta el lecho (en el sistema local del tablero).
	var supports := maxi(1, int(round(length / 3.0)))
	var inv := xform.affine_inverse()
	for i in range(1, supports + 1):
		var t := float(i) / float(supports + 1)
		var p := a.lerp(b, t)
		var bed_local: Vector3 = inv * Vector3(p.x, Terrain.height_at(p) - 0.3, p.y)
		var top_y := -DECK_THICK * 0.5
		var h := top_y - bed_local.y
		if h <= 0.15:
			continue
		var z_local := t * length - length * 0.5
		for side in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.14, h, 0.14)
			post.mesh = pm
			post.material_override = mat
			post.position = Vector3(side * (width * 0.5 - 0.22), (top_y + bed_local.y) * 0.5, z_local)
			node.add_child(post)
	return node


static var _mat_cache: Dictionary = {}

static func _mat(c: Color) -> StandardMaterial3D:
	if _mat_cache.has(c):
		return _mat_cache[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	_mat_cache[c] = m
	return m


static func _ghost_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# --- Modo construccion manual (tecla B) ---

func toggle_build() -> void:
	if _placing:
		stop_build()
	else:
		start_build()


func start_build() -> void:
	if _cam_rig == null:
		return
	if Paths.instance != null:
		Paths.instance.stop_build()
	_placing = true
	if _ghost == null:
		_ghost = Node3D.new()
		add_child(_ghost)
	_ghost.visible = true
	_ghost_yaw = 1.0e9   # reconstruye el fantasma en el primer frame
	set_process(true)


func stop_build() -> void:
	if not _placing:
		return
	_placing = false
	if _ghost != null:
		_ghost.visible = false
	set_process(false)


func is_placing() -> bool:
	return _placing


func _process(delta: float) -> void:
	if not _placing or _cam_rig == null:
		return
	if Input.is_action_pressed("rotate_building"):
		_yaw = fmod(_yaw + deg_to_rad(90.0) * delta, TAU)
	var ground: Vector2 = _cam_rig.screen_to_ground(get_viewport().get_mouse_position())
	var span := _span(ground)
	var ok := not span.is_empty() and can_afford_crossing(span["a"], span["b"])
	# Reconstruir si cambia el cruce, la validez (por la madera) o la
	# orientacion (para el fantasma invalido). Si no, no se toca.
	if span == _ghost_span and ok == _ghost_ok and is_equal_approx(_yaw, _ghost_yaw):
		return
	_ghost_span = span
	_ghost_ok = ok
	_ghost_yaw = _yaw
	_rebuild_ghost(ground, span)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_bridge"):
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
		if not btn.pressed:
			return
		if btn.button_index == MOUSE_BUTTON_RIGHT:
			stop_build()
			get_viewport().set_input_as_handled()
		elif btn.button_index == MOUSE_BUTTON_LEFT:
			if _ghost_ok:
				add_bridge(_ghost_span["a"], _ghost_span["b"], MANUAL_WIDTH)
				stop_build()
			elif not _ghost_span.is_empty():
				message_requested.emit("Falta madera para el puente")
			elif _cam_rig != null and Terrain.is_water(_cam_rig.screen_to_ground(btn.position)) \
					and Terrain.water_kind_at(_cam_rig.screen_to_ground(btn.position)) != Terrain.WATER_RIVER:
				message_requested.emit("Solo se pueden construir puentes sobre ríos")
			else:
				message_requested.emit("El puente tiene que cruzar el rio")
			get_viewport().set_input_as_handled()


# Extremos del puente que cruza el rio bajo `center`, segun la orientacion
# actual. Vacio si no hay agua o no se llega a tierra por los dos lados.
func _span(center: Vector2) -> Dictionary:
	if not Terrain.is_water(center):
		return {}
	# Solo rios: ni mar abierto ni lagos.
	if Terrain.water_kind_at(center) != Terrain.WATER_RIVER:
		return {}
	var dir := Vector2(sin(_yaw), cos(_yaw))
	var near := _march(center, -dir)
	var far := _march(center, dir)
	if near == Vector2.INF or far == Vector2.INF:
		return {}
	return {"a": near, "b": far}


func _march(center: Vector2, dir: Vector2) -> Vector2:
	var step := 0.4
	var t := step
	while t <= MAX_SPAN:
		var p := center + dir * t
		if not Terrain.is_water(p):
			return p + dir * EDGE_MARGIN
		t += step
	return Vector2.INF


func _rebuild_ghost(center: Vector2, span: Dictionary) -> void:
	for c in _ghost.get_children():
		_ghost.remove_child(c)
		c.queue_free()
	var a: Vector2
	var b: Vector2
	if span.is_empty():
		# Sin cruce valido: se muestra igualmente un tramo corto en rojo, para
		# no dejar colgado el puente valido de una posicion anterior.
		var dir := Vector2(sin(_yaw), cos(_yaw))
		a = center - dir * 1.5
		b = center + dir * 1.5
	else:
		a = span["a"]
		b = span["b"]
	var mid := (a + b) * 0.5
	var ends := _deck_ends(a, b, Terrain.water_level_at(mid))
	var mat := _ghost_mat(GHOST_OK if _ghost_ok else GHOST_BAD)
	_ghost.add_child(_bridge_node(a, b, MANUAL_WIDTH, ends.x, ends.y, mat))
