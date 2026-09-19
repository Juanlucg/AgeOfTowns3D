extends Node3D
class_name Buildings
## Construcciones del pueblo. Gestionan colocacion, validacion, produccion
## y registro de edificios colocados.
##
## Se eligen desde el menu inferior (o teclas 1-4):
## granero (almacen), granja (casita + campo), aserradero, cantera.
## Mientras un tipo esta seleccionado se muestra un fantasma translucido que
## sigue al raton sobre el terreno; R lo rota y el clic lo coloca.
## La base se apoya en el punto mas alto del solar; donde el terreno baja,
## se genera una pared de piedras para que el edificio nunca quede flotando.
## La granja tiene un segundo paso: tras colocar la casita se delimita una zona
## y se elige el cultivo con 1/2/3.
##
## Modulos: [BuildingDef] (datos), [BuildingMeshes] (geometria), [FieldMesh] (campo).

signal building_built(type: StringName, pos: Vector2)
signal building_demolished(type: StringName, pos: Vector2)
signal selection_changed(type: StringName)
## Emitida al cambiar el edificio enfocado (clic izq). `rec` es null si no
## hay seleccion. `screen_pos` es la posicion del edificio en pantalla (o
## Vector2.ZERO si se ha deseleccionado). Los consumidores (BuildingInfoMenu)
## la usan para mostrar/ocultar el menu contextual.
signal building_focus_changed(rec: BuildingRecord, screen_pos: Vector2)
signal message_requested(text: String)
signal place_clear_requested(pos: Vector2, radius: float)
## Pide a la UI que el jugador elija cultivo para un campo ya delimitado.
## `options` es un Array de diccionarios {id, name, color} y `anchor` la posicion
## de mundo de la granja (la UI la proyecta para anclar el menu encima). La UI
## responde con choose_field_crop() o cancel_field_crop_selection().
signal crop_select_requested(options: Array, anchor: Vector3)
## Avisa de donde trabaja un edificio: en las granjas, el centro del campo (los
## aldeanos van alli a sembrar/cosechar) en vez de la casita.
signal work_area_changed(pos: Vector2, area: Vector2)

@export var camera_path: NodePath

const GHOST_OK := Color(0.30, 1.0, 0.45, 0.45)
const GHOST_BAD := Color(1.0, 0.30, 0.30, 0.45)
const SELECT_COLOR := Color(1.0, 0.85, 0.2, 0.55)
const ZONE_COLOR := Color(0.35, 0.80, 0.45, 0.20)
const HEIGHT_SAMPLE_STEP := 1.0
const ROTATE_SPEED := 120.0
const FIELD_MIN := 1.2
const FIELD_MAX_AREA := 60.0
## Comida base por m2 de campo en cada cosecha, antes del multiplicador del
## cultivo. La granja ya no produce de forma continua: acumula esta cosecha y
## la entrega de golpe cuando el cultivo madura (ver CROPS y _update_farms).
const FIELD_RATE := 0.30
## Segundos de cosecha por m2 de campo (y trabajador presente). El total se
## limita entre HARVEST_MIN y HARVEST_MAX. Los cultivos desaparecen durante ese
## rato, fila a fila.
const HARVEST_PER_M2 := 1.2
const HARVEST_MIN := 3.0
const HARVEST_MAX := 25.0
## Cuanto puede adelantarse el frente de cosecha a los granjeros (m). Debe ser
## mayor que el hueco del carril (0.4) + SPREAD_DISTANCE (0.6), o el deadlock
## vuelve: el frente no podria avanzar lo suficiente para recolocarlos.
const HARVEST_LEAD := 1.2
## Alcance de los granjeros mas alla de su cuerpo (m): el trigo que quitan con
## los brazos. Sin esto nunca alcanzan el borde del fondo y la cosecha no acaba.
const HARVEST_REACH := 0.5
## Cada cuantos metros de avance del frente se recoloca a los granjeros (mas
## pequeno = siguen el frente mas de cerca, a costa de mas vaiven).
const SPREAD_DISTANCE := 0.6
## Cuanto se mete la casa dentro de la valla del campo. La casa queda pegada al
## borde cercano y la valla se corta justo ahi (ver FieldMesh._add_fence).
const FIELD_OVERLAP := 0.12
const STONE_COLOR := Color(0.58, 0.55, 0.49)   # gris arenoso: el gris neutro
											   # se volvia azul con la luz
											   # ambiental de primavera
const DEMOLISH_REFUND := 0.5   # fraccion del coste que se devuelve

# Cultivos que se pueden sembrar. Cada uno tiene su color, lo que tarda en
# madurar y un multiplicador de rendimiento. La tasa sostenida de un cultivo
# es `yield / grow_seconds`: la zanahoria da menos por cosecha pero ciclos muy
# cortos (responde rapido en campos pequenos), las bayas tardan mas pero
# rinden mas por cosecha (mejor tasa a largo plazo) y el trigo es el termino
# medio.
const CROPS := {
	"trigo": {
		"name": "Trigo",
		"color": Color(0.85, 0.70, 0.25),
		"grow_seconds": 100.0,
		"yield": 1.0,
	},
	"zanahoria": {
		"name": "Zanahorias",
		"color": Color(0.90, 0.50, 0.20),
		"grow_seconds": 60.0,
		"yield": 0.55,
	},
	"bayas": {
		"name": "Bayas",
		"color": Color(0.72, 0.16, 0.18),
		"grow_seconds": 160.0,
		"yield": 1.9,
	},
}

# --- Registro de tipos (BuildingDef resources) ---
# Antes era un Dictionary gigante; ahora son Resources que se pueden editar
# como .tres o instanciar desde el inspector.
var _defs: Dictionary = {}   # id -> BuildingDef
var _ids: Array[StringName] = []   # orden estable para el menu

var _pending: StringName = &""
var _yaw := 0.0
var _ghost: Node3D = null
var _ghost_building: Node3D = null
var _placed: Array[BuildingRecord] = []
# Spatial hash: para evitar el O(N) de building_at/_is_valid.
# cell_size >= footprint_max + hit_radius = ~3 + 1.5 + margen.
const _GRID_CELL := 8.0
var _grid: Dictionary = {}   # clave: Vector2i(cell_x, cell_y) -> Array[BuildingRecord]
# Buffer reutilizado por _nearby para no asignar un Array nuevo en cada frame
# de colocacion. Los llamantes lo consumen al momento y no lo guardan.
var _nearby_scratch: Array[BuildingRecord] = []
var _cam_rig: CameraController3D

var _field_mode := false
var _field_start := Vector2.ZERO
var _field_crop := "trigo"
var _field_ghost: Node3D = null
var _field_farm: BuildingRecord = null
var _field_yaw := 0.0
# Zona ya delimitada y validada que espera a que la UI devuelva el cultivo
# elegido. Mientras _field_awaiting_crop es true se ignora el input de
# colocacion y el fantasma queda oculto (lo gestiona el popup de cultivos).
var _field_rect_confirmed := Rect2()
var _field_awaiting_crop := false
# El fantasma del campo se reconstruye entero (suelo, valla y plantas) cuando
# cambia de tamano: se limita a ~12 Hz en vez de rehacerse en cada frame. Si
# cambia el cultivo, se rehace al momento para que el color responda.
const FIELD_GHOST_INTERVAL := 0.08
var _field_ghost_timer := 0.0
var _field_ghost_last_crop := ""
# Mientras el usuario mantiene R, la rotacion es manual y NO debe
# sobreescribirse con el face-camera automatico al soltar.
var _user_rotated := false

# Edificio actualmente seleccionado (para demolir con Delete). Null = nada.
var _selected: BuildingRecord = null
var _selection_marker: Node3D = null

# --- Herramientas dev ---
var dev_free_build := false

# Turno de trabajo (dia). La produccion solo avanza mientras hay turno activo:
# de noche los aldeanos estan en casa y los edificios no producen. Lo gestiona
# Villagers al cambiar dia/noche con set_shift_active().
var _shift_active := true

# Estado del fantasma, para no reconstruirlo cuando nada ha cambiado.
var _ghost_mat_ok: StandardMaterial3D
var _ghost_mat_bad: StandardMaterial3D
var _ghost_last_ground := Vector2(INF, INF)
var _ghost_last_valid := false


func _ready() -> void:
	_cam_rig = get_node_or_null(camera_path) as CameraController3D
	if _cam_rig == null:
		push_error("Buildings: camera_path no apunta a un CameraController3D en el .tscn")
		set_process(false)
		return
	# Dos materiales para toda la partida: antes se creaba un
	# StandardMaterial3D nuevo en cada frame de colocacion.
	_ghost_mat_ok = BuildingMeshes.ghost_mat(GHOST_OK)
	_ghost_mat_bad = BuildingMeshes.ghost_mat(GHOST_BAD)
	_register_defs()


# Descubre los BuildingDef en res://resources/buildings/*.tres y los ordena por
# `order`. Anadir un edificio es soltar un .tres: antes habia que mantener
# listas paralelas (preloads aqui, TYPE_KEYS en BuildMenu y los atajos en
# project.godot).
func _register_defs() -> void:
	var dir := DirAccess.open("res://resources/buildings")
	if dir == null:
		push_error("Buildings: no se pudo abrir res://resources/buildings")
		return
	var defs: Array[BuildingDef] = []
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var res := load("res://resources/buildings/" + file)
		if res is BuildingDef:
			defs.append(res as BuildingDef)
	defs.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool:
		return a.order < b.order)
	for d in defs:
		_register(d)
	if _ids.is_empty():
		push_error("Buildings: no se cargo ningun BuildingDef desde resources/buildings")


func _register(d: BuildingDef) -> void:
	_defs[d.id] = d
	_ids.append(d.id)


# --- API publica ---

func get_def(id: StringName) -> BuildingDef:
	return _defs.get(id)


func get_ids() -> Array[StringName]:
	return _ids


# --- API de la plaza (reunion / crecimiento / felicidad) ---

## Posicion de la primera plaza (punto de reunion), o Vector2.INF si no hay.
func get_gathering_point() -> Vector2:
	for rec in _placed:
		var d := get_def(rec.type)
		if d != null and d.gathering_point:
			return rec.pos
	return Vector2.INF


## True si hay algun edificio que atraiga crecimiento (plaza).
func has_plaza() -> bool:
	for rec in _placed:
		var d := get_def(rec.type)
		if d != null and d.attracts_growth:
			return true
	return false


## Suma de felicidad diaria que aportan los edificios (plazas).
func total_happiness_bonus() -> float:
	var bonus := 0.0
	for rec in _placed:
		var d := get_def(rec.type)
		if d != null:
			bonus += d.happiness_bonus
	return bonus


func set_worker_count(pos: Vector2, count: int) -> void:
	var rec := _record_at(pos)
	if rec == null:
		return
	var old_rate := _registered_rate(rec)
	rec.workers = maxi(0, count)
	var d := get_def(rec.type)
	var new_rate := _registered_rate(rec)
	if d != null and d.can_produce() and not rec.dev and not is_equal_approx(old_rate, new_rate):
		_update_production_rate(d.prod_resource, new_rate - old_rate)
		Economy.changed.emit()


func set_worker_efficiency(pos: Vector2, efficiency: float) -> void:
	var rec := _record_at(pos)
	if rec == null:
		return
	var old_rate := _registered_rate(rec)
	rec.worker_efficiency = clampf(efficiency, 0.0, 1.0)
	var d := get_def(rec.type)
	var new_rate := _registered_rate(rec)
	if d != null and d.can_produce() and not rec.dev and not is_equal_approx(old_rate, new_rate):
		_update_production_rate(d.prod_resource, new_rate - old_rate)
		Economy.changed.emit()


## Cuantos asignados han llegado de verdad al puesto (lo emite Villagers). La
## produccion usa este numero, no el de asignados: asi el edificio empieza a
## producir cuando los aldeanos llegan, no mientras van de camino.
func set_workers_present(pos: Vector2, count: int) -> void:
	var rec := _record_at(pos)
	if rec == null:
		return
	var old_rate := _registered_rate(rec)
	rec.workers_present = maxi(0, count)
	var d := get_def(rec.type)
	var new_rate := _registered_rate(rec)
	if d != null and d.can_produce() and not rec.dev and not is_equal_approx(old_rate, new_rate):
		_update_production_rate(d.prod_resource, new_rate - old_rate)
		Economy.changed.emit()


func _worker_production_rate(rec: BuildingRecord) -> float:
	var d := get_def(rec.type)
	if rec.dev or d == null or not d.can_produce():
		return 0.0
	# Las granjas sobreescriben prod_amount segun el tamano del campo
	# (rec.amount) y producen por cosecha: el HUD debe calcular la tasa media
	# con el mismo valor y el mismo ciclo o mostraria algo distinto.
	# El factor de trabajadores es el de PRESENTES, no el de asignados.
	var amount: float = rec.amount if rec.amount > 0.0 else d.prod_amount
	var cycle := _cycle_seconds(rec, d)
	if cycle <= 0.0:
		return 0.0
	return amount / cycle * rec.workers_present * rec.worker_efficiency


# Segundos que dura un ciclo de produccion: la maduracion del cultivo en las
# granjas (cada cultivo la tiene distinta) y prod_interval en el resto.
func _cycle_seconds(rec: BuildingRecord, d: BuildingDef) -> float:
	if d.has_field:
		return float(crop_def(rec.crop)["grow_seconds"])
	return d.prod_interval


# Datos de un cultivo (color, nombre, maduracion y rendimiento). Cae al trigo
# si el id no existe o esta vacio.
func crop_def(id: String) -> Dictionary:
	return CROPS.get(id, CROPS["trigo"])


# Ids de los cultivos en el orden en que se declaran en CROPS (para el menu).
func crop_ids() -> Array:
	return CROPS.keys()


# Comida que da un campo de `area` m2 con el cultivo `crop_id` en cada cosecha,
# antes de multiplicar por los trabajadores.
func _farm_amount(area: float, crop_id: String) -> float:
	return clampf(area * FIELD_RATE, 0.5, 15.0) * float(crop_def(crop_id)["yield"])


## Cambia el cultivo de una granja ya sembrada sin demolerla: resiembra el campo
## y recalcula la produccion segun el rendimiento del nuevo cultivo. Devuelve
## false si el edificio no es una granja con campo o el cultivo no existe.
func set_farm_crop(rec: BuildingRecord, crop_id: String) -> bool:
	if rec == null or rec.crops == null or not is_instance_valid(rec.crops):
		return false
	var def := get_def(rec.type)
	if def == null or not def.has_field or not CROPS.has(crop_id):
		return false
	if rec.crop == crop_id:
		return true
	# La tasa registrada se calcula con el cultivo y el importe ya puestos: se
	# lee la de antes (cultivo viejo) y luego se corrige la diferencia.
	var rate_before := _registered_rate(rec)
	rec.crop = crop_id
	rec.amount = _farm_amount(rec.field_area, crop_id)
	var crop_data := crop_def(crop_id)
	_rebuild_field(rec)
	var rate_after := _registered_rate(rec)
	if def.can_produce() and not rec.dev and not is_equal_approx(rate_before, rate_after):
		_update_production_rate(def.prod_resource, rate_after - rate_before)
	Economy.changed.emit()
	message_requested.emit("Granja sembrada de %s" % crop_data["name"])
	return true


# Rehace la geometria del campo (suelo, valla y cultivos) con el cultivo actual.
# Cambiar de cultivo cambia la malla, el tamano y la densidad de las plantas, no
# solo el color, asi que hay que rehacer el campo y no basta con retintar.
func _rebuild_field(rec: BuildingRecord) -> void:
	rec.harvest = 0.0
	rec.harvest_time = 0.0
	rec.planting = 1.0
	rec.spread_harvest = -1.0
	var crop_data := crop_def(rec.crop)
	var back := Vector2(-sin(deg_to_rad(rec.yaw)), -cos(deg_to_rad(rec.yaw)))
	var side := Vector2(back.y, -back.x)
	var to_house := rec.pos - rec.field_center
	var house_local := Vector2(to_house.dot(side), to_house.dot(back))
	if rec.field != null and is_instance_valid(rec.field):
		rec.field.queue_free()
	var field := FieldMesh.build(rec.field_center, rec.field_size, deg_to_rad(rec.yaw),
		crop_data["color"], float(crop_data["grow_seconds"]), rec.crop, false,
		Callable(), house_local, BuildingMeshes.FARM_HALF_SIDE)
	add_child(field)
	rec.field = field
	rec.crops = field.get_node_or_null("CropField") as CropField


# Tasa que el edificio aporta AHORA al "+X/s" del HUD: 0 cuando no hay turno
# (de noche los aldeanos no trabajan, asi que el edificio no produce).
func _registered_rate(rec: BuildingRecord) -> float:
	return _worker_production_rate(rec) if _shift_active else 0.0


## Activa/desactiva el turno de trabajo. Al empezar el dia registra en Economy
## la produccion de cada edificio; de noche la retira. Lo llama Villagers desde
## _on_time_changed().
func set_shift_active(active: bool) -> void:
	if active == _shift_active:
		return
	_shift_active = active
	for rec in _placed:
		var d := get_def(rec.type)
		if d == null or not d.can_produce() or rec.dev or rec.workers <= 0:
			continue
		var nominal := _worker_production_rate(rec)
		if active:
			_update_production_rate(d.prod_resource, nominal)
		else:
			_update_production_rate(d.prod_resource, -nominal)
	Economy.changed.emit()


func _update_production_rate(resource: StringName, delta: float) -> void:
	if delta > 0.0:
		Economy.add_production(resource, delta)
	else:
		Economy.remove_production(resource, -delta)


func is_placing() -> bool:
	return _pending != &"" or _field_mode


func get_selected() -> BuildingRecord:
	return _selected


# Devuelve el BuildingRecord bajo el punto del mundo, o null.
# Para edificios con campo (granjas), un clic en cualquier parte del campo
# tambien selecciona la granja: el campo ocupa mucha superficie y bloquearia
# el clic a la casita.
func building_at(ground: Vector2) -> BuildingRecord:
	for b in _nearby(ground):
		var d := get_def(b.type)
		if d == null:
			continue
		# 1. Casita: radio = footprint/2
		if b.pos.distance_to(ground) < d.footprint * 0.5:
			return b
		# 2. Campo (si tiene): bounding box AABB en mundo
		if b.field != null and b.field_min != b.field_max:
			if ground.x >= b.field_min.x and ground.x <= b.field_max.x \
				and ground.y >= b.field_min.y and ground.y <= b.field_max.y:
				return b
	return null


# Devuelve los BuildingRecord cuyas celdas del spatial hash contienen el
# punto dado. Si no, los edificios de la misma celda (o adyacentes) que
# el cursor. Sin esto, building_at y _is_valid son O(N) sobre _placed.
func _nearby(ground: Vector2) -> Array[BuildingRecord]:
	var cell := Vector2i(int(floor(ground.x / _GRID_CELL)), int(floor(ground.y / _GRID_CELL)))
	_nearby_scratch.clear()
	# Mira la celda del punto y las 8 adyacentes (un edificio cerca puede
	# ocupar hasta 2-3 celdas segun su tamano).
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var key := Vector2i(cell.x + dx, cell.y + dy)
			# _grid.get(key, []) creaba un Array vacio por celda y frame.
			var bucket: Variant = _grid.get(key)
			if bucket == null:
				continue
			for b in bucket:
				_nearby_scratch.append(b)
	return _nearby_scratch


# Devuelve el registro colocado exactamente en `pos`. Primero mira el spatial
# hash y, si no aparece (p.ej. una granja aun sin campo, que no se indexa hasta
# confirmarlo), cae al recorrido lineal de _placed. Evita el O(N) en el caso
# comun de los cambios de trabajadores.
func _record_at(pos: Vector2) -> BuildingRecord:
	var cell := Vector2i(int(floor(pos.x / _GRID_CELL)), int(floor(pos.y / _GRID_CELL)))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var key := Vector2i(cell.x + dx, cell.y + dy)
			var bucket: Variant = _grid.get(key)
			if bucket == null:
				continue
			for b in bucket:
				var rec := b as BuildingRecord
				if rec.pos.is_equal_approx(pos):
					return rec
	for rec in _placed:
		if rec.pos.is_equal_approx(pos):
			return rec
	return null


# Anade un edificio a las celdas que ocupa. Llamar al colocar.
func _add_to_grid(rec: BuildingRecord) -> void:
	var d := get_def(rec.type)
	if d == null:
		return
	# Para edificios con campo, el AABB es el del campo. Si no, el cuadrado
	# de la casita centrado en pos, con lado footprint.
	var x0: float
	var z0: float
	var x1: float
	var z1: float
	if rec.field != null and rec.field_min != rec.field_max:
		x0 = rec.field_min.x
		z0 = rec.field_min.y
		x1 = rec.field_max.x
		z1 = rec.field_max.y
	else:
		var half := d.footprint * 0.5
		x0 = rec.pos.x - half
		z0 = rec.pos.y - half
		x1 = rec.pos.x + half
		z1 = rec.pos.y + half
	var cx0 := int(floor(x0 / _GRID_CELL))
	var cz0 := int(floor(z0 / _GRID_CELL))
	var cx1 := int(floor(x1 / _GRID_CELL))
	var cz1 := int(floor(z1 / _GRID_CELL))
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			var key := Vector2i(cx, cz)
			if not _grid.has(key):
				_grid[key] = []
			(_grid[key] as Array).append(rec)


# Quita un edificio del hash. Llamar al demoler.
func _remove_from_grid(rec: BuildingRecord) -> void:
	var d := get_def(rec.type)
	if d == null:
		return
	var x0: float
	var z0: float
	var x1: float
	var z1: float
	if rec.field != null and rec.field_min != rec.field_max:
		x0 = rec.field_min.x
		z0 = rec.field_min.y
		x1 = rec.field_max.x
		z1 = rec.field_max.y
	else:
		var half := d.footprint * 0.5
		x0 = rec.pos.x - half
		z0 = rec.pos.y - half
		x1 = rec.pos.x + half
		z1 = rec.pos.y + half
	var cx0 := int(floor(x0 / _GRID_CELL))
	var cz0 := int(floor(z0 / _GRID_CELL))
	var cx1 := int(floor(x1 / _GRID_CELL))
	var cz1 := int(floor(z1 / _GRID_CELL))
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			var key := Vector2i(cx, cz)
			var bucket: Variant = _grid.get(key)
			if bucket == null:
				continue
			bucket.erase(rec)
			# Limpia buckets vacios para no acumular claves muertas en _grid.
			if (bucket as Array).is_empty():
				_grid.erase(key)


# Selecciona un edificio. Si ya estaba seleccionado, lo deselecciona.
func toggle_select(rec: BuildingRecord) -> void:
	if _selected == rec:
		deselect()
		return
	_selected = rec
	_update_selection_marker()
	var screen := Vector2.ZERO
	if rec != null and rec.node != null and is_instance_valid(rec.node):
		# Punto del edificio proyectado al centro de la pantalla, cerca del suelo.
		var ground3 := Vector3(rec.pos.x, Terrain.height_at(rec.pos), rec.pos.y)
		screen = _cam_rig.world_to_screen(ground3)
	building_focus_changed.emit(_selected, screen)


# Rota el edificio para que su fachada (el -Z local, donde esta la puerta)
# apunte a la camara real, no al pivote de la camara.
func _face_camera_now() -> void:
	if _cam_rig == null:
		return
	var cam_pos := _camera_world_position()
	# El fantasma (si esta activo) rota con la yaw actual.
	if _ghost != null:
		_face_ghost_to_camera(cam_pos)
	# Yaw por defecto al colocar: hacia la camara.
	if cam_pos.length_squared() > 0.0001:
		var dir := Vector3(cam_pos.x, 0, cam_pos.z).normalized()
		_yaw = rad_to_deg(atan2(dir.x, dir.z)) + _facade_offset(_pending)


func _camera_world_position() -> Vector3:
	var camera := _cam_rig.get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		return camera.global_position
	return _cam_rig.global_position


func _facade_offset(type: StringName) -> float:
	# Desfase de fachada definido en el propio recurso (la casa importada mira
	# al contrario que los modelos procedurales).
	var d := get_def(type)
	return d.facade_offset if d != null else 0.0


func _face_ghost_to_camera(cam_pos: Vector3) -> void:
	var ghost_pos := Vector3(_ghost.position.x, 0, _ghost.position.z)
	var dir := cam_pos - ghost_pos
	if dir.length_squared() < 0.0001:
		return
	dir.y = 0
	dir = dir.normalized()
	# Se escribe en _yaw (grados) en vez de girar _ghost directamente: la raiz
	# del fantasma no debe rotar para que el cuerpo mantenga su orientacion.
	_yaw = rad_to_deg(atan2(dir.x, dir.z)) + 180.0


func deselect() -> void:
	if _selected == null:
		return
	_selected = null
	_update_selection_marker()
	building_focus_changed.emit(null, Vector2.ZERO)


# Quita la seleccion de edificio, puente y camino.
func _deselect_all() -> void:
	deselect()
	if Bridges.instance != null:
		Bridges.instance.deselect_bridge()
	if Paths.instance != null:
		Paths.instance.deselect_stroke()


# Demuele el edificio seleccionado. Refund parcial segun DEMOLISH_REFUND.
func demolish_selected() -> void:
	if _selected == null:
		return
	demolish(_selected)


func demolish(rec: BuildingRecord) -> void:
	if rec == null:
		return
	# Reembolso antes de cualquier cleanup para que el HUD lo vea.
	var d := get_def(rec.type)
	if d != null:
		# Reembolso parcial via Economy.refund(): respeta la capacidad por
		# recurso. Antes se sumaba directo a Economy.amounts y se podia pasar
		# del tope del almacen. Los edificios dev se colocaron gratis: si se
		# reembolsaran, construir y demoler en bucle daria recursos infinitos.
		if not rec.dev:
			var refund := {}
			for k in d.cost:
				refund[k] = d.cost[k] * DEMOLISH_REFUND
			Economy.refund(refund)
		# Contadores de capacidad: cada edificio de almacen demolido reduce su cap.
		# Produccion: el edificio deja de aportar al "+X.X/s" del HUD.
		match d.storage_kind:
			&"granary":
				Economy.granary_count = maxi(0, Economy.granary_count - 1)
			&"warehouse":
				Economy.warehouse_count = maxi(0, Economy.warehouse_count - 1)
		# La produccion se registro segun rec.dev (no segun dev_free_build, que
		# puede haber cambiado despues): si no se usa el mismo criterio, al
		# demoler se deja produccion fantasma o se resta la que nunca se sumo.
		if d.can_produce() and not rec.dev and rec.workers > 0:
			Economy.remove_production(d.prod_resource, _registered_rate(rec))
		Economy.changed.emit()
	# Limpia la seleccion si era este edificio (esto cierra el menu contextual).
	if _selected == rec:
		deselect()
	# Quita del registro ANTES de liberar los nodos para que is_placing() y
	# demas consultas ya no lo vean.
	_placed.erase(rec)
	_remove_from_grid(rec)
	unregister_fence(rec.pos)
	# Libera los nodos visuales (casita y, si es granja, el campo).
	if rec.node != null and is_instance_valid(rec.node):
		rec.node.queue_free()
	if rec.field != null and is_instance_valid(rec.field):
		rec.field.queue_free()
	# Avisos finales (el menu ya esta oculto en este punto).
	if d != null:
		building_demolished.emit(rec.type, rec.pos)
		if rec.dev:
			message_requested.emit("%s demolido" % d.display_name)
		else:
			message_requested.emit("%s demolido (reembolso %d%%)" % [
				d.display_name, int(round(DEMOLISH_REFUND * 100.0))])


func _update_selection_marker() -> void:
	if _selection_marker != null:
		_selection_marker.queue_free()
		_selection_marker = null
	if _selected == null or _selected.node == null:
		return
	# Raiz en el suelo del edificio: anillo de seleccion y, si tiene, la zona
	# de actuacion.
	var root := Node3D.new()
	root.position = Vector3(_selected.pos.x, Terrain.height_at(_selected.pos) + 0.05, _selected.pos.y)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.9
	ring.outer_radius = 1.1
	var mi := MeshInstance3D.new()
	mi.mesh = ring
	var m := StandardMaterial3D.new()
	m.albedo_color = SELECT_COLOR
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	root.add_child(mi)
	var d := get_def(_selected.type)
	if d != null and d.work_radius > 0.0:
		var zone := BuildingMeshes.zone_disc(d.work_radius, ZONE_COLOR)
		zone.position = Vector3(0.0, 0.01, 0.0)
		root.add_child(zone)
	add_child(root)
	_selection_marker = root


func select(id_str: String) -> void:
	if _field_mode:
		return
	var id := StringName(id_str)
	if not _defs.has(id):
		return
	if _pending == id:
		cancel_placement()
		return
	cancel_placement()
	_pending = id
	# Yaw inicial: 0. _process() la actualiza cada frame para que la cara
	# del edificio siga a la camara segun la posicion del cursor.
	_yaw = 0.0
	# Nueva colocacion = el usuario quiere la orientacion por defecto (cara
	# a camara). Si antes habia rotado manualmente con R, se reinicia.
	_user_rotated = false
	_ghost_last_ground = Vector2(INF, INF)
	_ghost = Node3D.new()
	_ghost_building = BuildingMeshes.build(id, _ghost_mat_ok)
	# Solo gira el cuerpo, no la raiz.
	_ghost_building.rotation = Vector3(0.0, deg_to_rad(_yaw), 0.0)
	_ghost.add_child(_ghost_building)
	# Zona de actuacion (aserradero): disco que no gira con el edificio.
	var gd := get_def(id)
	if gd != null and gd.work_radius > 0.0:
		var zone := BuildingMeshes.zone_disc(gd.work_radius, ZONE_COLOR)
		zone.position = Vector3(0.0, 0.06, 0.0)
		_ghost.add_child(zone)
	add_child(_ghost)
	selection_changed.emit(id)


func cancel_placement() -> void:
	_pending = &""
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
		_ghost_building = null
	selection_changed.emit(&"")


func _process(delta: float) -> void:
	# La cosecha se comprueba siempre, tambien mientras se coloca otro edificio
	# o se delimita un campo, para que las granjas ya existentes no se paren.
	_update_farms(delta)
	if _field_mode:
		_update_field_ghost(delta)
		return
	if _pending == &"" or _ghost == null:
		return
	var ground: Vector2 = _cam_rig.screen_to_ground(get_viewport().get_mouse_position())
	# Yaw: R = rotacion manual del usuario (persiste al soltar). Si no se ha
	# rotado manualmente, la cara del edificio sigue a la camara. Una vez
	# que el usuario toca R, _user_rotated=true y el auto-face se desactiva
	# hasta que vuelva a seleccionar el tipo (en select() reseteamos).
	if Input.is_action_pressed("rotate_building"):
		_yaw = fmod(_yaw + ROTATE_SPEED * delta, 360.0)
		_user_rotated = true
	elif not _user_rotated and _cam_rig != null:
		var cam_pos := _camera_world_position()
		var dir := cam_pos - Vector3(ground.x, 0, ground.y)
		if dir.length_squared() > 0.0001:
			dir.y = 0
			dir = dir.normalized()
			# +180: la cara del edificio (puerta) en los meshes esta en -Z
			# local (no +Z como pensabamos). Empíricamente la puerta queda
			# detras si solo calculamos atan2; este offset lo corrige.
			_yaw = rad_to_deg(atan2(dir.x, dir.z)) + _facade_offset(_pending)
	var d := get_def(_pending)
	var base_h := _base_height(ground, d.footprint)
	_ghost.position = Vector3(ground.x, base_h, ground.y)
	# Solo gira el cuerpo.
	_ghost_building.rotation = Vector3(0.0, deg_to_rad(_yaw), 0.0)
	var valid := _is_valid(ground, _pending)
	if valid == _ghost_last_valid and ground.is_equal_approx(_ghost_last_ground):
		return
	_ghost_last_valid = valid
	_ghost_last_ground = ground
	var mat := _ghost_mat_ok if valid else _ghost_mat_bad
	_update_ghost_material(mat)


func _update_ghost_material(m: Material) -> void:
	BuildingMeshes.apply_material_recursive(_ghost_building, m)


func _attach_production_timer(rec: BuildingRecord) -> void:
	var d := get_def(rec.type)
	if rec.dev or not d.can_produce():
		return
	# Las granjas no producen por timer: cosechan de golpe al madurar el cultivo
	# (ver _update_farms). La tasa media sigue registrandose para el HUD.
	if d.has_field:
		return
	var timer := Timer.new()
	timer.name = "ProductionTimer"
	timer.wait_time = d.prod_interval
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(_on_production_timer.bind(rec))
	rec.node.add_child(timer)


func _on_production_timer(rec: BuildingRecord) -> void:
	if rec == null or rec.node == null or not is_instance_valid(rec.node):
		return
	# Solo produce con trabajadores que hayan llegado al puesto, no asignados.
	if rec.workers_present <= 0:
		return
	# Sin turno activo (noche) los aldeanos no estan trabajando: no produce.
	if not _shift_active:
		return
	var d := get_def(rec.type)
	var amt: float = (rec.amount if rec.amount > 0.0 else d.prod_amount) * rec.workers_present * rec.worker_efficiency
	Economy.add(String(d.prod_resource), amt)


# Cosecha de las granjas. El cultivo crece solo (CropField, incluso de noche);
# cuando madura y hay trabajadores PRESENTES con turno activo, empieza la
# cosecha: durante `_harvest_seconds()` los cultivos van desapareciendo fila a
# fila y la comida entra poco a poco (no de golpe). Al terminar se resiembra.
# Sin turno o sin trabajadores el cultivo espera maduro: no produce nada.
func _update_farms(delta: float) -> void:
	if not _shift_active:
		return
	for rec in _placed:
		var d := get_def(rec.type)
		if d == null or not d.has_field or rec.dev:
			continue
		if rec.crops == null or not is_instance_valid(rec.crops):
			continue
		# Fase de siembra (tras una cosecha): se siembra del fondo hacia la casa.
		if rec.planting < 1.0:
			if rec.workers_present <= 0:
				continue
			rec.planting = minf(1.0, rec.planting + delta / _planting_seconds(rec))
			rec.crops.set_harvest(1.0 - rec.planting)
			# Se recolocan cada 0.6 m de avance del frente de siembra.
			var pfront := rec.planting * FieldMesh.outer_size(rec.field_size).y
			if rec.spread_harvest < 0.0 or absf(pfront - rec.spread_harvest) >= SPREAD_DISTANCE:
				rec.spread_harvest = pfront
				work_area_changed.emit(rec.pos, rec.field_center)
			if rec.planting >= 1.0:
				rec.crops.begin_growth()
			continue
		if not rec.crops.is_mature():
			rec.harvest = 0.0
			# Mientras crece, los granjeros se retiran a la casa. Al madurar
			# (spread_harvest vuelve a >=0) salen a cosechar.
			if rec.spread_harvest >= 0.0:
				rec.spread_harvest = -1.0
				work_area_changed.emit(rec.pos, rec.field_center)
			continue
		if rec.workers_present <= 0:
			continue
		# El avance deseado sube por tiempo, pero no se aleja de los granjeros; y
		# la retirada real no pasa de donde han llegado (su alcance). Asi el trigo
		# desaparece a su lado, no por delante, y de forma progresiva.
		var outer := FieldMesh.outer_size(rec.field_size)
		var lead := HARVEST_LEAD / maxf(0.001, outer.y)
		var reach := _worker_reach(rec)
		rec.harvest_time = minf(
			rec.harvest_time + delta / _harvest_seconds(rec),
			minf(1.0, reach + lead))
		var reach_arm := clampf(reach + HARVEST_REACH / maxf(0.001, outer.y), 0.0, 1.0)
		var new_h := maxf(rec.harvest, minf(rec.harvest_time, reach_arm))
		var applied := new_h - rec.harvest
		rec.harvest = new_h
		rec.crops.set_harvest(rec.harvest)
		if applied > 0.0:
			# La comida no entra al almacen aqui: se acumula y son los aldeanos
			# quienes la acarrean (take_farm_food / Villager.start_carry).
			var total := rec.amount * rec.workers_present * rec.worker_efficiency
			rec.pending += total * applied
		# Se recolocan cada 0.6 m de avance del frente, no por tramos fijos.
		var front_m := rec.harvest_time * outer.y
		if rec.spread_harvest < 0.0 or absf(front_m - rec.spread_harvest) >= SPREAD_DISTANCE:
			rec.spread_harvest = front_m
			work_area_changed.emit(rec.pos, rec.field_center)
		if rec.harvest_time >= 1.0 or reach_arm >= 0.995:
			# El avance deseado llego al fondo (o los granjeros ya estan a tiro
			# del ultimo trozo): se remata y se resiembra.
			if rec.harvest < 1.0:
				var pend_total := rec.amount * rec.workers_present * rec.worker_efficiency
				rec.pending += pend_total * (1.0 - rec.harvest)
				rec.harvest = 1.0
				rec.crops.set_harvest(1.0)
			# Cosecha terminada: el campo queda pelado y empieza la siembra.
			rec.crops.replant()
			rec.harvest = 0.0
			rec.harvest_time = 0.0
			rec.planting = 0.0
			rec.spread_harvest = -1.0


# Cuanto tarda la cosecha: mas largo cuanto mas grande es el campo y mas corto
# cuantos mas trabajadores (y mas eficientes) estan presentes.
func _harvest_seconds(rec: BuildingRecord) -> float:
	var crew := maxf(1.0, float(rec.workers_present) * maxf(0.1, rec.worker_efficiency))
	var base := clampf(rec.field_area * HARVEST_PER_M2, HARVEST_MIN, HARVEST_MAX)
	return base / crew


# Cuanto tarda la siembra: como la cosecha, mas larga cuanto mas grande es el
# campo y mas corta con mas trabajadores presentes.
func _planting_seconds(rec: BuildingRecord) -> float:
	return _harvest_seconds(rec)


## Coge hasta `amount` de comida ya cosechada de la granja en `farm_pos` para que
## un aldeano la acarree. Devuelve {} si no hay nada, no es una granja o no
## produce. El diccionario trae {amount, target, resource}.
func take_farm_food(farm_pos: Vector2, amount: float) -> Dictionary:
	var rec := _record_at(farm_pos)
	if rec == null or rec.pending <= 0.0:
		return {}
	var d := get_def(rec.type)
	if d == null or not d.has_field or not d.can_produce():
		return {}
	# Durante la cosecha no se manda a nadie a media carga: se espera a juntar
	# una carga completa (si no, el aldeano se iba tras 0.25 s de recogida, la
	# cosecha se pausaba y un campo tardaba casi un dia en cosecharse una vez).
	# Terminada la cosecha (cultivo ya res/embrado) se lleva lo que quede.
	if rec.crops != null and is_instance_valid(rec.crops) \
			and rec.crops.is_mature() and rec.pending < amount:
		return {}
	var taken := minf(amount, rec.pending)
	if taken <= 0.0:
		return {}
	rec.pending -= taken
	return {
		"amount": taken,
		"target": _food_storage_target(rec.pos),
		"resource": String(d.prod_resource),
	}


## Los granjeros presentes avisan de donde estan para que la cosecha no se les
## adelante (Villagers lo llama en su tick de presencia).
func report_farm_workers(farm_pos: Vector2, positions: PackedVector2Array) -> void:
	var rec := _record_at(farm_pos)
	if rec != null:
		rec.worker_positions = positions


# Hasta donde ha llegado (0..1, del borde de la casa al fondo) el granjero mas
# adelantado. La retirada del trigo no pasa de ahi.
func _worker_reach(rec: BuildingRecord) -> float:
	if rec.worker_positions.is_empty():
		return 0.0
	var back := Vector2(-sin(deg_to_rad(rec.yaw)), -cos(deg_to_rad(rec.yaw)))
	var outer := FieldMesh.outer_size(rec.field_size)
	var near := -outer.y * 0.5
	var best := near
	for p in rec.worker_positions:
		best = maxf(best, (p - rec.field_center).dot(back))
	return clampf((best - near) / maxf(0.001, outer.y), 0.0, 1.0)


## Punto de trabajo de un granjero. Mientras el cultivo no esta listo esperan
## dentro de la casa; cuando madura, se reparten por la franja ya recogida para
## cosechar. Entran y salen por el hueco de la casa; nunca cruzan la valla.
func random_field_point(farm_pos: Vector2, lane := 0) -> Vector2:
	var rec := _record_at(farm_pos)
	if rec == null:
		return farm_pos
	if rec.field_size.x <= 0.001 or rec.field_size.y <= 0.001:
		return farm_pos
	var back := Vector2(-sin(deg_to_rad(rec.yaw)), -cos(deg_to_rad(rec.yaw)))
	var side := Vector2(back.y, -back.x)
	var outer := FieldMesh.outer_size(rec.field_size)
	var hz := outer.y * 0.5
	# Carril estable segun el indice (proporcion aurea): cada aldeano mantiene
	# su columna y avanza recto al cosechar/sembrar.
	var lane_u := fmod(float(lane) * 0.6180339887 + 0.5, 1.0) * 0.9 - 0.45
	var u := lane_u * rec.field_size.x
	# Fase de siembra: sobre la tierra aun sin sembrar, avanzando del fondo
	# (+z) hacia la casa (-z).
	if rec.planting < 1.0:
		var front_p := hz - rec.planting * outer.y
		var vp := clampf(randf_range(front_p - 1.3, front_p - 0.15), -hz, hz)
		return rec.field_center + side * u + back * vp
	# Aun creciendo: se quedan en la casa (no pisan el cultivo ni la valla).
	if rec.crops == null or not rec.crops.is_mature():
		return rec.pos + Vector2(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15))
	# Cosechando: justo detras del frente deseado (que va algo por delante de la
	# retirada real), para que quiten el trigo a su lado. Banda estrecha.
	var front := -hz + rec.harvest_time * outer.y
	var v := clampf(randf_range(front - 0.4, front - 0.1), -hz + 0.1, hz)
	return rec.field_center + side * u + back * v


# --- Vallas del campo: bloqueo real de paso ---
# El NavigationObstacle3D solo "empuja" (evitacion blanda), asi que los aldeanos
# seguian cruzando la valla. Este registro estatico permite a Villager consultar
# si un paso cruza la valla de algun campo y deslizarse a lo largo. Clave: la
# posicion de la casa (unica por granja).
static var _fences: Dictionary = {}


static func register_fence(pos: Vector2, center: Vector2, side: Vector2, back: Vector2,
		hx: float, hz: float, gap0: float, gap1: float) -> void:
	_fences[pos] = {
		"center": center, "side": side, "back": back,
		"hx": hx, "hz": hz, "gap0": gap0, "gap1": gap1,
	}


static func unregister_fence(pos: Vector2) -> void:
	_fences.erase(pos)


## Normal (mundo) de la primera valla que cruza el paso `from`->`to`, o
## Vector2.ZERO si no cruza ninguna o cruza por el hueco de la casa.
static func fence_block_normal(from: Vector2, to: Vector2) -> Vector2:
	for key in _fences:
		var n := _fence_cross_normal(_fences[key], from, to)
		if n != Vector2.ZERO:
			return n
	return Vector2.ZERO


static func _fence_cross_normal(f: Dictionary, from: Vector2, to: Vector2) -> Vector2:
	var center: Vector2 = f["center"]
	var side: Vector2 = f["side"]
	var back: Vector2 = f["back"]
	var hx: float = f["hx"]
	var hz: float = f["hz"]
	var a := Vector2((from - center).dot(side), (from - center).dot(back))
	var b := Vector2((to - center).dot(side), (to - center).dot(back))
	# Bordes x = +-hx (normal +-side).
	var ex_pos := hx
	if (a.x - ex_pos) * (b.x - ex_pos) < 0.0:
		var t := (ex_pos - a.x) / (b.x - a.x)
		var zc := a.y + t * (b.y - a.y)
		if zc > -hz and zc < hz:
			return side
	var ex_neg := -hx
	if (a.x - ex_neg) * (b.x - ex_neg) < 0.0:
		var t2 := (ex_neg - a.x) / (b.x - a.x)
		var zc2 := a.y + t2 * (b.y - a.y)
		if zc2 > -hz and zc2 < hz:
			return -side
	# Bordes z = +-hz (normal +-back). El lado cercano (z=-hz) tiene el hueco.
	var ez_pos := hz
	if (a.y - ez_pos) * (b.y - ez_pos) < 0.0:
		var t3 := (ez_pos - a.y) / (b.y - a.y)
		var xc := a.x + t3 * (b.x - a.x)
		if xc > -hx and xc < hx:
			return back
	var ez_neg := -hz
	if (a.y - ez_neg) * (b.y - ez_neg) < 0.0:
		var t4 := (ez_neg - a.y) / (b.y - a.y)
		var xc2 := a.x + t4 * (b.x - a.x)
		if xc2 > -hx and xc2 < hx:
			if xc2 > f["gap0"] and xc2 < f["gap1"]:
				return Vector2.ZERO
			return -back
	return Vector2.ZERO


## Campo (valla) que contiene el punto, o {} si esta fuera de todos.
static func field_at(p: Vector2) -> Dictionary:
	for key in _fences:
		var f: Dictionary = _fences[key]
		var d := p - (f["center"] as Vector2)
		if absf(d.dot(f["side"])) <= float(f["hx"]) \
				and absf(d.dot(f["back"])) <= float(f["hz"]):
			return f
	return {}


## Puntos de paso para entrar o salir de un campo por el hueco de la casa: van
## de fuera a dentro (o al reves), de modo que el cruce de la valla ocurre
## siempre dentro del hueco y no en una esquina. Devuelve [] si no hace falta.
static func gap_route(from: Vector2, to: Vector2) -> Array:
	var f_from := field_at(from)
	var f_to := field_at(to)
	if not f_from.is_empty() and not f_to.is_empty():
		return []
	var entering := f_from.is_empty() and not f_to.is_empty()
	var f: Dictionary = f_to if entering else f_from
	if f.is_empty():
		return []
	var center: Vector2 = f["center"]
	var side: Vector2 = f["side"]
	var back: Vector2 = f["back"]
	var hz: float = f["hz"]
	var gx := (float(f["gap0"]) + float(f["gap1"])) * 0.5
	# La casa queda centrada en el hueco. Se pasa por DELANTE (fachada, +Z de la
	# casa) y luego por dentro del campo: asi cruza la casa por la puerta y no
	# por una pared lateral.
	var house_back := BuildingMeshes.FARM_HALF_BACK
	var house_cz := -(house_back - FIELD_OVERLAP + hz)   # centro de la casa (z local)
	var front_z := house_cz - (house_back + 0.5)
	var inside_z := -hz + 0.4
	var front := center + side * gx + back * front_z
	var inside := center + side * gx + back * inside_z
	return [front, inside] if entering else [inside, front]


# Almacen de comida (granero) mas cercano a `from`; si no hay ninguno, la propia
# granja (la comida acaba igualmente en el almacen del pueblo).
func _food_storage_target(from: Vector2) -> Vector2:
	var best := from
	var best_d := INF
	for rec in _placed:
		var d := get_def(rec.type)
		if d != null and d.storage_kind == &"granary":
			var dist := rec.pos.distance_squared_to(from)
			if dist < best_d:
				best_d = dist
				best = rec.pos
	return best


func _unhandled_input(event: InputEvent) -> void:
	# Sin camara (camera_path invalido) _ready sale temprano, pero el input
	# sigue activo y las conversiones pantalla->suelo serian null derefs.
	if _cam_rig == null:
		return
	# Mientras se elige el cultivo manda el popup: Buildings no procesa nada.
	if _field_awaiting_crop:
		return
	# Mientras se pintan caminos o se colocan puentes, Buildings no procesa la
	# colocacion.
	if Paths.instance != null and Paths.instance.is_placing():
		return
	if Bridges.instance != null and Bridges.instance.is_placing():
		return
	if event.is_action_pressed("cancel"):
		if _field_mode:
			_cancel_field()
		elif _pending != &"":
			cancel_placement()
		else:
			_deselect_all()
		get_viewport().set_input_as_handled()
		return
	# Demoler: Delete/Backspace. Prioridad: puente > camino > edificio.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			if Bridges.instance != null and Bridges.instance.has_selection():
				Bridges.instance.demolish_selected()
				get_viewport().set_input_as_handled()
				return
			if Paths.instance != null and Paths.instance.has_selection():
				Paths.instance.demolish_selected_stroke()
				get_viewport().set_input_as_handled()
				return
			if _selected != null:
				demolish_selected()
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseButton:
		var btn := event as InputEventMouseButton
		if _field_mode and btn.pressed:
			if btn.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_field()
			elif btn.button_index == MOUSE_BUTTON_LEFT:
				_confirm_field()
			get_viewport().set_input_as_handled()
			return
		if _pending != &"" and btn.pressed:
			if btn.button_index == MOUSE_BUTTON_RIGHT:
				cancel_placement()
				get_viewport().set_input_as_handled()
			elif btn.button_index == MOUSE_BUTTON_LEFT:
				_place()
				get_viewport().set_input_as_handled()
			return
		# Sin colocar: clic izq selecciona (prioridad puente > camino >
		# edificio); clic der deselecciona todo.
		if btn.pressed and btn.button_index == MOUSE_BUTTON_LEFT:
			var ground: Vector2 = _cam_rig.screen_to_ground(btn.position)
			if Bridges.instance != null and Bridges.instance.select_at(ground):
				if Paths.instance != null:
					Paths.instance.deselect_stroke()
				deselect()
				get_viewport().set_input_as_handled()
				return
			if Paths.instance != null and Paths.instance.select_at(ground):
				if Bridges.instance != null:
					Bridges.instance.deselect_bridge()
				deselect()
				get_viewport().set_input_as_handled()
				return
			if Bridges.instance != null:
				Bridges.instance.deselect_bridge()
			if Paths.instance != null:
				Paths.instance.deselect_stroke()
			var hit := building_at(ground)
			if hit != null:
				toggle_select(hit)
			else:
				deselect()
			get_viewport().set_input_as_handled()
			return
		if btn.pressed and btn.button_index == MOUSE_BUTTON_RIGHT:
			# Clic derecho = deseleccionar todo. Demoler es con Delete.
			_deselect_all()
			get_viewport().set_input_as_handled()


func _place() -> void:
	var ground: Vector2 = _cam_rig.screen_to_ground(get_viewport().get_mouse_position())
	var d := get_def(_pending)
	if not _is_valid(ground, _pending):
		var reason := ""
		var cls: String = Terrain.terrain_type(ground)
		var biome_ok := _biome_matches(cls, d.biomes)
		if not biome_ok:
			reason = "Solo se puede construir en %s" % d.biomes_text()
		elif not dev_free_build and not Economy.can_afford(d.cost):
			reason = "Recursos insuficientes (%s)" % d.cost_text()
		else:
			reason = "Demasiado cerca de otro edificio"
		message_requested.emit(reason)
		return
	if not dev_free_build:
		Economy.spend_all(d.cost)
	# Contadores de capacidad de almacenamiento. El granero amplia solo la
	# comida; el almacen ampla el resto. Cualquier edificio construido
	# registra su produccion en Economy para que el HUD muestre "+X.X/s".
	# El tipo de almacen lo declara el propio BuildingDef (storage_kind).
	match d.storage_kind:
		&"granary":
			Economy.granary_count += 1
			Economy.changed.emit()
		&"warehouse":
			Economy.warehouse_count += 1
			Economy.changed.emit()
	var base_h := _base_height(ground, d.footprint)
	# Raiz sin rotar apoyada en el punto de apoyo; el cuerpo gira con el yaw.
	var node := Node3D.new()
	node.position = Vector3(ground.x, base_h, ground.y)
	var body := BuildingMeshes.build(_pending, null)
	body.rotation = Vector3(0.0, deg_to_rad(_yaw), 0.0)
	node.add_child(body)
	# La granja no lleva obstaculo en la casita: es el paso hacia el campo (los
	# aldeanos entran por delante y salen por la puerta trasera). El resto de
	# edificios si bloquean.
	if not d.has_field:
		var obstacle := NavigationObstacle3D.new()
		obstacle.radius = d.footprint * 0.5
		obstacle.height = 2.5
		node.add_child(obstacle)
	add_child(node)
	var rec := BuildingRecord.new(_pending, ground, _yaw, node, dev_free_build)
	_placed.append(rec)
	# Spatial hash: edificios sin campo se indexan al colocar. Los edificios con
	# campo se indexan en _confirm_field (tras tener los bounds del campo).
	if not d.has_field:
		_add_to_grid(rec)
	_attach_production_timer(rec)
	building_built.emit(_pending, ground)
	# Solo se retira vegetacion dentro de la huella visual del modelo, con un
	# pequeno margen. Antes el radio era footprint + 1 y despejaba demasiado.
	place_clear_requested.emit(ground, d.footprint * 0.75)
	message_requested.emit("%s construido" % d.display_name)
	if d.has_field:
		# segundo paso: delimitar el campo de cultivo
		_field_mode = true
		_field_yaw = _yaw
		_field_start = ground + _field_back() * _field_offset(d, _field_back())
		_field_crop = "trigo"
		_field_farm = rec
		_field_ghost_timer = 0.0
		_field_ghost_last_crop = ""
		_field_ghost = Node3D.new()
		add_child(_field_ghost)
		_ghost.visible = false
		message_requested.emit("Delimita la zona del campo con el raton (clic). Despues elegiras el cultivo.")
		return
	cancel_placement()


# Ejes del huerto: `back` se aleja de la puerta de la casa, `side` es el ancho.
func _field_back() -> Vector2:
	return Vector2(-sin(deg_to_rad(_field_yaw)), -cos(deg_to_rad(_field_yaw)))


# Distancia del centro de la casa al origen del arrastre del campo. Deja el
# origen a ras del borde cercano de la valla; luego FieldMesh alinea el campo
# con la casa para que la toque (ver _field_center).
func _field_offset(_d: BuildingDef, _back: Vector2) -> float:
	return BuildingMeshes.FARM_HALF_BACK - FIELD_OVERLAP


# Zona sembrada que se esta delimitando, EN COORDENADAS DE LA GRANJA: x a lo
# ancho (eje `side`), y a lo largo (eje `back`), con el origen en _field_start.
#
# Antes esto devolvia un rectangulo en coordenadas de mundo, calculado con los
# ejes girados de la granja y luego aplastado a su caja envolvente. Con la
# granja girada el campo dejaba de seguir el arrastre: a 30 grados, arrastrar
# 6x3 m daba un campo de 7x5,5 m.
func _field_rect(ground: Vector2) -> Rect2:
	var back := _field_back()
	var side := Vector2(back.y, -back.x)
	var diff := ground - _field_start
	var depth := maxf(FIELD_MIN, diff.dot(back))
	var spread := diff.dot(side)
	var u0 := minf(spread, 0.0)
	var u1 := maxf(spread, 0.0)
	if u1 - u0 < FIELD_MIN:
		var mid := (u0 + u1) * 0.5
		u0 = mid - FIELD_MIN * 0.5
		u1 = mid + FIELD_MIN * 0.5
	return Rect2(Vector2(u0, 0.0), Vector2(u1 - u0, depth))


# Centro en el mundo del campo, alineado con la casa: el borde cercano de la
# valla queda a FARM_HALF_BACK - FIELD_OVERLAP del centro de la casa, de modo
# que la casa siempre esta pegada (y un poco metida) en la valla, con
# independencia del redondeo a celdas del suelo.
func _field_center(rect: Rect2) -> Vector2:
	var back := _field_back()
	var side := Vector2(back.y, -back.x)
	var outer := FieldMesh.outer_size(rect.size)
	var spread_center := rect.position.x + rect.size.x * 0.5
	return _field_farm.pos + side * spread_center \
		+ back * (BuildingMeshes.FARM_HALF_BACK - FIELD_OVERLAP + outer.y * 0.5)


func _confirm_field() -> void:
	var ground: Vector2 = _cam_rig.screen_to_ground(get_viewport().get_mouse_position())
	var rect := _field_rect(ground)
	if rect.size.x * rect.size.y > FIELD_MAX_AREA:
		message_requested.emit("Zona demasiado grande (max %0.0f m2)" % FIELD_MAX_AREA)
		return
	if not _field_terrain_ok(rect):
		message_requested.emit("Los cultivos necesitan llanura")
		return
	# La zona es valida: se guarda y se pide a la UI que elija el cultivo. El
	# campo no se siembra hasta que la UI llame a choose_field_crop().
	_field_rect_confirmed = rect
	_field_awaiting_crop = true
	if _field_ghost != null:
		_field_ghost.visible = false
	# El menu sale anclado a la granja: se pasa su posicion de mundo para que la
	# UI la reproyecte (y siga al edificio si se mueve la camara).
	var house := _field_farm.pos
	crop_select_requested.emit(crop_options(),
		Vector3(house.x, Terrain.height_at(house), house.y))


## La UI llama aqui con el cultivo elegido: siembra el campo ya delimitado y
## cierra el modo de dos pasos.
func choose_field_crop(crop_id: String) -> void:
	if not _field_awaiting_crop or not CROPS.has(crop_id):
		return
	_field_crop = crop_id
	_plant_confirmed_field(_field_rect_confirmed)
	_field_awaiting_crop = false
	_end_field_mode()


## La UI llama aqui si el jugador cancela la eleccion de cultivo: se vuelve a
## permitir delimitar la zona sin perder la granja ya colocada.
func cancel_field_crop_selection() -> void:
	if not _field_awaiting_crop:
		return
	_field_awaiting_crop = false
	if _field_ghost != null:
		_field_ghost.visible = true
	message_requested.emit("Delimita la zona del campo con el raton (clic)")


## Opciones de cultivo para el popup de la UI.
func crop_options() -> Array:
	var out := []
	for id in CROPS:
		var c: Dictionary = CROPS[id]
		out.append({"id": String(id), "name": c["name"], "color": c["color"]})
	return out


# Siembra y registra el campo confirmado con el cultivo ya elegido (_field_crop).
func _plant_confirmed_field(rect: Rect2) -> void:
	var w := rect.size.x
	var d := rect.size.y
	var center := _field_center(rect)
	var outer := FieldMesh.outer_size(rect.size)
	# Centro de la casa en coordenadas del campo, para abrir la valla justo
	# donde la toca. Por construccion de _field_center, el borde cercano queda a
	# FARM_HALF_BACK - FIELD_OVERLAP del centro de la casa.
	var house_local := Vector2(
		-(rect.position.x + rect.size.x * 0.5),
		-(BuildingMeshes.FARM_HALF_BACK - FIELD_OVERLAP + outer.y * 0.5))
	var crop_data := crop_def(_field_crop)
	var field := FieldMesh.build(center, rect.size, deg_to_rad(_field_yaw),
		crop_data["color"], float(crop_data["grow_seconds"]), _field_crop, false,
		Callable(), house_local, BuildingMeshes.FARM_HALF_SIDE)
	# El campo va suelto en el mundo, no colgado de la casita. Se guarda la
	# referencia en el record para que demolish() lo libere con ella.
	add_child(field)
	_field_farm.field = field
	_field_farm.crops = field.get_node_or_null("CropField") as CropField
	# El campo empieza sembrado por los granjeros, como al res sembrar: sin
	# brotes y con la fase de siembra activa (del fondo hacia la casa).
	_field_farm.planting = 0.0
	if _field_farm.crops != null:
		_field_farm.crops.replant()
	# Se fijan centro y tamano antes de avisar a los trabajadores: su punto de
	# trabajo (fase de siembra) los calcula.
	_field_farm.field_center = center
	_field_farm.field_size = rect.size
	# Los trabajadores pasan a trabajar en el campo (no en la casita): alli se
	# les vera sembrar y cosechar.
	work_area_changed.emit(_field_farm.pos, center)
	# Caja envolvente del campo, para poder clicar en cualquier parte de el y
	# seleccionar la granja. Ahora el campo puede estar girado, asi que se
	# calcula desde sus cuatro esquinas y no desde el rectangulo en ejes de
	# granja: con la granja a 45 grados los dos no coinciden.
	# El campo visual (suelo, valla y plantas) ocupa outer_size(), que anade el
	# margen de tierra y redondea a celdas. El AABB guardado debe cubrirlo, no
	# solo la zona sembrada, o la seleccion y la validacion de colocacion se
	# quedan cortas por la valla.
	var back := _field_back()
	var side := Vector2(back.y, -back.x)
	# Registra la valla (bloqueo real de paso) con el hueco de la casa.
	var fence_hx := outer.x * 0.5
	var fence_hz := outer.y * 0.5
	# El hueco de paso es algo mas ancho que la puerta para que no se enganchen
	# en las esquinas al entrar/salir.
	var gap_half := BuildingMeshes.FARM_HALF_SIDE + 0.25
	register_fence(_field_farm.pos, center, side, back, fence_hx, fence_hz,
		clampf(house_local.x - gap_half, -fence_hx, fence_hx),
		clampf(house_local.x + gap_half, -fence_hx, fence_hx))
	var fmin := Vector2(INF, INF)
	var fmax := Vector2(-INF, -INF)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var corner: Vector2 = center + side * (outer.x * 0.5 * sx) + back * (outer.y * 0.5 * sz)
			fmin = Vector2(minf(fmin.x, corner.x), minf(fmin.y, corner.y))
			fmax = Vector2(maxf(fmax.x, corner.x), maxf(fmax.y, corner.y))
	_field_farm.field_min = fmin
	_field_farm.field_max = fmax
	# AABB del campo (con la rotacion de la granja aplicada): el spatial
	# hash necesita este AABB en mundo para hit-testear correctamente.
	_add_to_grid(_field_farm)
	# Radio que cubre el campo entero incluidas las esquinas.
	place_clear_requested.emit(center, rect.size.length() * 0.5 + 1.0)
	# La produccion de la granja depende del tamano del campo (rec.amount) y del
	# rendimiento del cultivo. Hay que fijar el cultivo ANTES de recalcular la
	# tasa: _cycle_seconds usa su tiempo de maduracion, y si no el HUD mostraria
	# la tasa calculada con el ciclo del trigo para cualquier cultivo.
	_field_farm.crop = _field_crop
	_field_farm.field_area = w * d
	_field_farm.field_center = center
	_field_farm.field_size = rect.size
	_field_farm.spread_harvest = -1.0
	var def := get_def(_field_farm.type)
	var rate_before := _registered_rate(_field_farm)
	_field_farm.amount = _farm_amount(_field_farm.field_area, _field_crop)
	var rate_after := _registered_rate(_field_farm)
	if def != null and def.can_produce() and not _field_farm.dev \
			and not is_equal_approx(rate_before, rate_after):
		_update_production_rate(def.prod_resource, rate_after - rate_before)
	Economy.changed.emit()
	var crop_name: String = crop_data["name"]
	message_requested.emit("Campo de %d m2 sembrado de %s" % [int(round(w * d)), crop_name])


func _cancel_field() -> void:
	# Solo se devuelve lo que se llego a cobrar: en modo dev la granja fue
	# gratis, asi que devolverla regalaba recursos (colocar y cancelar en
	# bucle era madera infinita).
	if _field_farm == null:
		_end_field_mode()
		cancel_placement()
		return
	var was_free := _field_farm.dev
	var def := get_def(_field_farm.type)
	# La granja ya emitio building_built al colocarse, asi que pudo registrar
	# produccion y un grupo de trabajo. Hay que deshacerlo igual que demolish()
	# y avisar por la senal para que Villagers y Minimap limpien su estado.
	if def != null and def.can_produce() and not was_free and _field_farm.workers > 0:
		Economy.remove_production(def.prod_resource, _registered_rate(_field_farm))
	_placed.erase(_field_farm)
	if _field_farm.node != null:
		_field_farm.node.queue_free()
	if not was_free and def != null:
		Economy.refund(def.cost)
	building_demolished.emit(_field_farm.type, _field_farm.pos)
	Economy.changed.emit()
	message_requested.emit("Granja cancelada (recursos devueltos)")
	_end_field_mode()
	cancel_placement()


func _end_field_mode() -> void:
	_field_mode = false
	_field_awaiting_crop = false
	if _field_ghost != null:
		_field_ghost.queue_free()
		_field_ghost = null
	_field_farm = null
	# Limpia la colocacion (pending + fantasma + boton del menu).
	cancel_placement()


func _update_field_ghost(delta: float) -> void:
	# Con el popup de cultivo abierto no se redibuja ni se sigue el raton.
	if _field_ghost == null or _field_awaiting_crop:
		return
	# Reconstruir el campo entero (suelo + valla + plantas) es caro: se agrupa
	# a ~12 Hz. Un cambio de cultivo fuerza el rehacer inmediato (color).
	_field_ghost_timer -= delta
	if _field_crop == _field_ghost_last_crop and _field_ghost_timer > 0.0:
		return
	_field_ghost_timer = FIELD_GHOST_INTERVAL
	_field_ghost_last_crop = _field_crop
	var ground: Vector2 = _cam_rig.screen_to_ground(get_viewport().get_mouse_position())
	var rect := _field_rect(ground)
	for c in _field_ghost.get_children():
		_field_ghost.remove_child(c)
		c.queue_free()
	var crop_data := crop_def(_field_crop)
	var crop_color: Color = crop_data["color"]
	if _field_valid(rect):
		crop_color.a = 0.55
	else:
		crop_color = Color(1.0, 0.3, 0.3, 0.4)
	_field_ghost.add_child(
		FieldMesh.build(_field_center(rect), rect.size, deg_to_rad(_field_yaw),
			crop_color, float(crop_data["grow_seconds"]), _field_crop, true))


func _field_valid(rect: Rect2) -> bool:
	if rect.size.x * rect.size.y > FIELD_MAX_AREA:
		return false
	return _field_terrain_ok(rect)


# Muestrea metro a metro el campo fisico (el que ocupan suelo y valla), que es
# lo que tiene que ser llanura, centrado donde se plantara.
func _field_terrain_ok(rect: Rect2) -> bool:
	var outer := FieldMesh.outer_size(rect.size)
	var center := _field_center(rect)
	var back := _field_back()
	var side := Vector2(back.y, -back.x)
	var v := -outer.y * 0.5
	while v <= outer.y * 0.5 + 0.001:
		var u := -outer.x * 0.5
		while u <= outer.x * 0.5 + 0.001:
			if Terrain.terrain_type(center + side * u + back * v) != "llanura":
				return false
			u += 1.0
		v += 1.0
	return true


func _biome_matches(cls: String, biomes: Array[BuildingDef.Biome]) -> bool:
	return biomes.has(BuildingDef.BIOME_BY_NAME.get(cls, -1))


# Altura de apoyo del edificio: el punto mas alto del solar para que nunca se
# entierre en la ladera.
func _base_height(pos: Vector2, footprint: float) -> float:
	var half := footprint * 0.5
	var h := -1e9
	var y := -half
	while y <= half:
		var x := -half
		while x <= half:
			h = maxf(h, Terrain.height_at(pos + Vector2(x, y)))
			x += HEIGHT_SAMPLE_STEP
		y += HEIGHT_SAMPLE_STEP
	return h

func _is_valid(pos: Vector2, type: StringName) -> bool:
	var d := get_def(type)
	if not _biome_matches(Terrain.terrain_type(pos), d.biomes):
		return false
	if not dev_free_build and not Economy.can_afford(d.cost):
		return false
	# Spatial hash: solo revisa edificios en la celda (o adyacentes) a pos.
	# 9 celdas * ~1 edificio/celda = ~10 checks en vez de N (cientos).
	for b in _nearby(pos):
		var other_def := get_def(b.type)
		if other_def == null:
			continue
		# 1. Separacion entre casitas (aproximacion circular por huella).
		# Deja 0.25 m entre modelos; dos casas pueden quedar juntas sin
		# solaparse visualmente.
		var min_dist := d.footprint * 0.5 + other_def.footprint * 0.5 + 0.25
		# Si ambos tienen zona de actuacion (aserraderos), sus radios no pueden
		# solaparse: dos aserraderos no comparten arboles.
		if d.work_radius > 0.0 and other_def.work_radius > 0.0:
			min_dist = d.work_radius + other_def.work_radius
		if (b.pos - pos).length() < min_dist:
			return false
		# 2. Campo de una granja: no se puede construir encima. Se expande su
		# AABB por media huella del edificio nuevo para no rozar la valla.
		if b.field != null and b.field_min != b.field_max:
			var pad := d.footprint * 0.5
			if pos.x >= b.field_min.x - pad and pos.x <= b.field_max.x + pad \
				and pos.y >= b.field_min.y - pad and pos.y <= b.field_max.y + pad:
				return false
	return true
