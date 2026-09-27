extends Node3D
class_name SawmillCrew
## Cuadrilla animada del aserradero: sustituye la produccion abstracta por timer.
##
## Tres aldeanos asignados:
##   - Dos lenadores (workers 0 y 1): van JUNTOS al mismo arbol, lo derriban
##     entre los dos, atan el tronco a la unica mula y esta lo arrastra hasta el
##     aserradero, donde lo cortan (madera a `pending`).
##   - Un sembrador (worker 2): recorre los sitios talados y replanta un brote
##     que crece hasta convertirse en un arbol adulto de la capa de vegetacion.
##
## Se crea como hijo del nodo del edificio (Buildings._spawn_crew) y Villagers le
## pasa los trabajadores y el estado del turno.

enum Log { IDLE, TO_TREE, FELLING, HAULING, CUTTING }
enum Plant { IDLE, TO_SPOT, PLANTING, GROWING }

## Tiempo de caida/derribo, corte y plantado (s).
const FELL_TIME := 1.1
const CUT_TIME := 2.0
const PLANT_TIME := 1.2
## Crecimiento del brote hasta arbol adulto (s).
const GROW_TIME := 18.0
## Velocidad de la mula (m/s). Cerca de la caminata del aldeano (0.7) para que
## los lenadores la acompasen.
const HORSE_SPEED := 0.9
## Distancia a la que el tronco va detras de la mula mientras lo arrastra (m).
const LOG_BEHIND := 0.6
## Madera que deja cada tronco cortado.
const WOOD_PER_LOG := 4.0
## Escala de la mula (un pelin mas pequena que el modelo base).
const MULE_SCALE := 0.82
## Separacion minima del arbol elegido respecto a los arboles ya talados en este
## ciclo (evita repetir el mismo).
const TREE_SEPARATION := 2.0


var _buildings: Buildings
var _rec: BuildingRecord
var _workers: Array = []
var _shift := false
var _work_radius := 8.0
var _rope_mesh: BoxMesh

var _log_state := Log.IDLE
var _timer := 0.0
var _tree_pos := Vector2.ZERO
var _tree_handle: Dictionary = {}
var _log: Node3D = null
var _active: Array = []
var _wait := 0.0
## La mula ya ha llegado al tronco y tira de el (enganche estable: sin esto se
## enganchaba y desenganchaba cada frame porque el tronco va 0.6 detras).
var _attached := false
var _horse: Node3D = null
var _rope: MeshInstance3D = null
var _horse_home := Vector2.ZERO

var _plant_state := Plant.IDLE
var _plant_timer := 0.0
var _plant_pos := Vector2.ZERO
var _plant_handle: Dictionary = {}
var _plant_queue: Array = []
var _sapling: Node3D = null


func bind(buildings: Buildings, rec: BuildingRecord) -> void:
	_buildings = buildings
	_rec = rec
	var d := buildings.get_def(rec.type)
	if d != null and d.work_radius > 0.0:
		_work_radius = d.work_radius
	_horse = BuildingMeshes.mule()
	_horse.scale = Vector3(MULE_SCALE, MULE_SCALE, MULE_SCALE)
	_horse.position = Vector3(1.0, 0.0, 0.6)
	_horse.rotation.y = deg_to_rad(-30.0)
	add_child(_horse)
	_horse_home = rec.pos + Vector2(1.0, 0.6)
	_rope_mesh = BoxMesh.new()
	_rope_mesh.size = Vector3(0.035, 0.035, 1.0)
	_rope = MeshInstance3D.new()
	_rope.mesh = _rope_mesh
	_rope.material_override = _rope_material()
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope.visible = false
	add_child(_rope)


func _exit_tree() -> void:
	# Demoler el aserradero puede cortar una tarea cuando la cuadrilla ya habia
	# reservado un arbol; no dejar esa instancia bloqueada para siempre.
	if _buildings != null:
		_buildings.release_tree(_tree_handle)


## Villagers llama a esto cada tick de presencia para mantener la lista fresca.
func set_workers(workers: Array) -> void:
	_workers = workers


func _worker(index: int):
	if index < _workers.size() and is_instance_valid(_workers[index]):
		return _workers[index]
	return null


func set_shift(active: bool) -> void:
	if active == _shift:
		return
	_shift = active
	if not _shift:
		_abort_tasks()


func _process(delta: float) -> void:
	if _buildings == null or _rec == null or not _shift:
		return
	_update_log_cycle(delta)
	_update_planter(delta, _worker(2))


# --- Ciclo de tala cooperativo (dos lenadores + una mula) ---

func _update_log_cycle(delta: float) -> void:
	_update_horse(delta)
	match _log_state:
		Log.IDLE:
			_start_tree()
		Log.TO_TREE:
			if _active_valid().is_empty():
				_reset_log()
				return
			# Basta con que los lenadores hayan llegado; la mula va de camino y
			# se le espera ya en el arrastre. Antes se exigia que la mula
			# llegara antes de talar y, si se atascaba, los lenadores se
			# quedaban "en modo talar" sin talar nunca.
			# Tope de seguridad: si por lo que sea no llegan, se reintenta.
			_wait += delta
			if _all_arrived():
				_log = _build_log(_tree_pos)
				_log_state = Log.FELLING
				_timer = FELL_TIME
			elif _wait > 12.0:
				_reset_log()
		Log.FELLING:
			_timer -= delta
			var t := clampf(1.0 - _timer / FELL_TIME, 0.0, 1.0)
			if _log != null:
				_log.rotation.x = deg_to_rad(88.0 * t)
			if _timer <= 0.0:
				if not _buildings.consume_tree(_tree_handle):
					# El arbol pudo retirarse por una construccion mientras la
					# cuadrilla iba hacia el. No producir ni replantar dos veces el
					# mismo recurso.
					_reset_log()
					return
				_plant_queue.append(_tree_handle)
				_tree_handle = {}
				_move_loggers(_stand_point())
				_log_state = Log.HAULING
		Log.HAULING:
			_update_log_follow()
			if _horse == null or _horse_pos().distance_to(_drop_point()) < 0.3:
				_set_rope_visible(false)
				_log_state = Log.CUTTING
				_timer = CUT_TIME
		Log.CUTTING:
			_timer -= delta
			if _timer <= 0.0:
				_rec.pending += WOOD_PER_LOG
				_free_log()
				_reset_log()


func _start_tree() -> void:
	_active = _available_loggers()
	if _active.is_empty():
		_rec.resource_depleted = true
		return
	var tree := _buildings.find_tree(_rec.pos, _work_radius, [], TREE_SEPARATION)
	if tree.is_empty():
		_rec.resource_depleted = true
		_active.clear()
		return
	_rec.resource_depleted = false
	_tree_handle = tree
	_tree_pos = tree["pos"]
	_move_loggers(_tree_pos)
	_wait = 0.0
	_attached = false
	_log_state = Log.TO_TREE


func _reset_log() -> void:
	_free_log()
	_buildings.release_tree(_tree_handle)
	_tree_handle = {}
	_tree_pos = Vector2.ZERO
	_active.clear()
	_wait = 0.0
	_attached = false
	_log_state = Log.IDLE


func _free_log() -> void:
	if _log != null:
		_log.queue_free()
		_log = null
	_set_rope_visible(false)


# Lenadores validos que no esten acarreando (esos van al almacen).
func _available_loggers() -> Array:
	var out: Array = []
	for i in 2:
		var w = _worker(i)
		if w != null and not w.is_carrying():
			out.append(w)
	return out


func _active_valid() -> Array:
	var out: Array = []
	for w in _active:
		if is_instance_valid(w) and not w.is_carrying():
			out.append(w)
	return out


func _all_arrived() -> bool:
	var valid := _active_valid()
	if valid.is_empty():
		return false
	for w in valid:
		if not w.task_arrived():
			return false
	return true


func _move_loggers(point: Vector2) -> void:
	for w in _active_valid():
		w.move_to_task(point)


# --- Mula ---

func _update_horse(delta: float) -> void:
	if _horse == null:
		return
	var target := _horse_target()
	var hp := _horse.global_position
	var goal := Vector3(target.x, _ground_y(target), target.y)
	var flat := Vector2(goal.x - hp.x, goal.z - hp.z)
	if flat.length() > 0.05:
		_horse.rotation.y = atan2(flat.x, flat.y)
	var newpos := _step_around(Vector2(hp.x, hp.z), Vector2(goal.x, goal.z), HORSE_SPEED * delta)
	_horse.global_position = Vector3(newpos.x, _ground_y(newpos), newpos.y)


# Un paso hacia `to` rodeando los edificios: si el paso recto entra en una
# huella, se desliza a lo largo de ella en vez de empujar contra el muro (que
# dejaba a la mula clavada y bloqueaba el ciclo de tala).
func _step_around(from: Vector2, to: Vector2, dist: float) -> Vector2:
	var dir := from.direction_to(to)
	if dir == Vector2.ZERO:
		return from
	var step := from + dir * dist
	var resolved := Buildings.resolve_block(step)
	if resolved.distance_squared_to(step) > 0.0001:
		var normal := step - resolved
		if normal.length_squared() > 0.0001:
			normal = normal.normalized()
			var slide := dir - normal * dir.dot(normal)
			if slide.length_squared() < 0.0001:
				slide = Vector2(-normal.y, normal.x)
			resolved = Buildings.resolve_block(from + slide.normalized() * dist)
	return resolved


func _horse_target() -> Vector2:
	match _log_state:
		Log.IDLE:
			return _horse_home
		Log.TO_TREE, Log.FELLING:
			return _tree_pos if _tree_pos != Vector2.ZERO else _horse_home
		Log.HAULING:
			# Primero va a por el tronco; cuando lo alcanza, tira de el.
			if not _attached:
				return _log_pos()
			return _drop_point()
		Log.CUTTING:
			return _drop_point()
	return _horse_home


func _horse_pos() -> Vector2:
	if _horse == null:
		return _rec.pos
	var p := _horse.global_position
	return Vector2(p.x, p.z)


func _log_pos() -> Vector2:
	if _log == null:
		return _rec.pos
	var p := _log.global_position
	return Vector2(p.x, p.z)


# El tronco va detras de la mula, tumbado y mirando hacia donde tira. Solo
# empieza a seguirla cuando la mula ya ha llegado a por el.
func _update_log_follow() -> void:
	if _log == null or _horse == null:
		return
	if not _attached:
		# La mula va a por el tronco; se engancha cuando lo alcanza.
		if _horse_pos().distance_to(_log_pos()) <= 0.5:
			_attached = true
		else:
			return
	var hp := _horse.global_position
	var to := _drop_point() - Vector2(hp.x, hp.z)
	var dir := to.normalized() if to.length() > 0.01 else Vector2(0.0, 1.0)
	var lp := Vector3(hp.x - dir.x * LOG_BEHIND, 0.0, hp.z - dir.y * LOG_BEHIND)
	lp.y = _ground_y(Vector2(lp.x, lp.z)) + 0.06
	_log.global_position = lp
	_log.rotation = Vector3(deg_to_rad(90.0), atan2(dir.x, dir.y), 0.0)
	_update_rope()


# Cuerda que ata el tronco a la mula mientras lo arrastra.
func _update_rope() -> void:
	if _rope == null or _log == null or _horse == null:
		return
	var a := _horse.global_position + Vector3(0.0, 0.18, 0.0)
	var b := _log.global_position + Vector3(0.0, 0.06, 0.0)
	var dist := a.distance_to(b)
	if dist < 0.05:
		_rope.visible = false
		return
	_rope.visible = true
	_rope.global_position = (a + b) * 0.5
	_rope.scale = Vector3(1.0, 1.0, dist)
	_rope.look_at(b, Vector3.UP)


func _set_rope_visible(v: bool) -> void:
	if _rope != null:
		_rope.visible = v


# --- Sembrador ---

func _update_planter(delta: float, planter) -> void:
	if planter == null:
		_plant_state = Plant.IDLE
		return
	match _plant_state:
		Plant.IDLE:
			if planter.is_carrying() or _plant_queue.is_empty():
				return
			_plant_handle = _plant_queue.pop_front()
			_plant_pos = _plant_handle["pos"]
			planter.move_to_task(_plant_pos)
			_plant_state = Plant.TO_SPOT
		Plant.TO_SPOT:
			if planter.task_arrived():
				_plant_state = Plant.PLANTING
				_plant_timer = PLANT_TIME
		Plant.PLANTING:
			_plant_timer -= delta
			if _plant_timer <= 0.0:
				_build_sapling(_plant_pos)
				_plant_state = Plant.GROWING
				_plant_timer = 0.0
		Plant.GROWING:
			_plant_timer += delta
			var t := clampf(_plant_timer / GROW_TIME, 0.0, 1.0)
			if _sapling != null:
				var s := lerpf(0.16, 1.0, t)
				_sapling.scale = Vector3(s, s, s)
			if _plant_timer >= GROW_TIME:
				_buildings.plant_tree(_plant_handle)
				_plant_handle = {}
				if _sapling != null:
					_sapling.queue_free()
					_sapling = null
				_plant_state = Plant.IDLE


func _abort_tasks() -> void:
	_reset_log()
	if _horse != null:
		_horse.global_position = Vector3(_horse_home.x, _ground_y(_horse_home), _horse_home.y)
	if _plant_state != Plant.GROWING:
		_plant_state = Plant.IDLE


func _build_log(pos: Vector2) -> Node3D:
	var log := BuildingMeshes.log_piece()
	add_child(log)
	log.global_position = Vector3(pos.x, _ground_y(pos), pos.y)
	log.rotation = Vector3.ZERO
	return log


func _build_sapling(pos: Vector2) -> void:
	if _sapling != null:
		_sapling.queue_free()
	_sapling = BuildingMeshes.sapling()
	add_child(_sapling)
	_sapling.global_position = Vector3(pos.x, _ground_y(pos), pos.y)
	_sapling.scale = Vector3(0.16, 0.16, 0.16)


# Punto donde la mula suelta el tronco (fuera del obstaculo del edificio).
func _drop_point() -> Vector2:
	return _rec.pos + Vector2(1.2, 0.0)


# Punto donde esperan los lenadores al volver (fuera del obstaculo, para no
# quedarse empujando en la puerta del aserradero).
func _stand_point() -> Vector2:
	return _rec.pos + Vector2(0.5, 1.05)


func _ground_y(p: Vector2) -> float:
	return Terrain.height_at(p)


func _rope_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.64, 0.42)
	m.roughness = 1.0
	return m
