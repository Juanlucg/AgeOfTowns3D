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

@export var camera_path: NodePath

const GHOST_OK := Color(0.30, 1.0, 0.45, 0.45)
const GHOST_BAD := Color(1.0, 0.30, 0.30, 0.45)
const SELECT_COLOR := Color(1.0, 0.85, 0.2, 0.55)
const FOUNDATION_STEP := 1.0
const ROTATE_SPEED := 120.0
const FIELD_MIN := 1.2
const FIELD_MAX_AREA := 60.0
const FIELD_RATE := 0.4
## Hueco que se deja a la vista entre la casa de la granja y la tierra del
## huerto, para que se lean como dos cosas separadas.
const FIELD_HOUSE_GAP := 0.4
const STONE_COLOR := Color(0.58, 0.55, 0.49)   # gris arenoso: el gris neutro
											   # se volvia azul con la luz
											   # ambiental de primavera
const DEMOLISH_REFUND := 0.5   # fraccion del coste que se devuelve

const CROP_COLORS := {
	"trigo": Color(0.85, 0.70, 0.25),
	"zanahoria": Color(0.90, 0.50, 0.20),
	"bayas": Color(0.72, 0.16, 0.18),
}
const CROP_NAMES := {
	"trigo": "Trigo",
	"zanahoria": "Zanahorias",
	"bayas": "Bayas",
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
var _ghost_foundation: Node3D = null
var _placed: Array[BuildingRecord] = []
# Spatial hash: para evitar el O(N) de building_at/_is_valid.
# cell_size >= footprint_max + hit_radius = ~3 + 1.5 + margen.
const _GRID_CELL := 8.0
var _grid: Dictionary = {}   # clave: Vector2i(cell_x, cell_y) -> Array[BuildingRecord]
var _cam_rig: CameraController3D

var _field_mode := false
var _field_start := Vector2.ZERO
var _field_crop := "trigo"
var _field_ghost: Node3D = null
var _field_farm: BuildingRecord = null
var _field_yaw := 0.0
# Mientras el usuario mantiene R, la rotacion es manual y NO debe
# sobreescribirse con el face-camera automatico al soltar.
var _user_rotated := false

# Edificio actualmente seleccionado (para demolir con Delete). Null = nada.
var _selected: BuildingRecord = null
var _selection_marker: MeshInstance3D = null

# --- Herramientas dev ---
var dev_free_build := false

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


# Crea los BuildingDef por codigo (migrar a .tres en el futuro).
func _register_defs() -> void:
	# Los BuildingDef se cargan desde .tres en res://resources/buildings/.
	# Editables desde el inspector sin tocar codigo: ajustar un coste,
	# anadir un edificio o tunear produccion ya no requiere compilar.
	_register(preload("res://resources/buildings/granero.tres"))
	_register(preload("res://resources/buildings/granja.tres"))
	_register(preload("res://resources/buildings/aserradero.tres"))
	_register(preload("res://resources/buildings/cantera.tres"))
	_register(preload("res://resources/buildings/almacen.tres"))


func _register(d: BuildingDef) -> void:
	_defs[d.id] = d
	_ids.append(d.id)


# --- API publica ---

func get_def(id: StringName) -> BuildingDef:
	return _defs.get(id)


func get_ids() -> Array[StringName]:
	return _ids


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
	var out: Array[BuildingRecord] = []
	# Mira la celda del punto y las 8 adyacentes (un edificio cerca puede
	# ocupar hasta 2-3 celdas segun su tamano).
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var key := Vector2i(cell.x + dx, cell.y + dy)
			var bucket: Array = _grid.get(key, [])
			for b in bucket:
				out.append(b)
	return out


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
			var bucket: Array = _grid.get(key, [])
			bucket.erase(rec)


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


# OJO: a dia de hoy no la llama nadie, ni a ella ni a _face_ghost_to_camera().
# Ademas la direccion se mide desde el ORIGEN DEL MUNDO hasta la camara, no
# desde el edificio: para una casa en (150,150) el angulo sale practicamente
# igual la pongas donde la pongas. Si quieres revivir la funcion, hay que
# medir cam_pos - posicion_del_edificio, que es lo que si hace bien
# _face_ghost_to_camera().
#
# Rota la yaw actual para que la cara del edificio (su +Z local, donde
# esta la puerta) apunte a la camara. Se llama al COLOCAR el edificio
# (no al clicar uno existente), de modo que el jugador siempre ve la
# fachada del edificio que acaba de poner. Tambien se aplica al fantasma
# durante la colocacion para que el preview muestre la orientacion final.
func _face_camera_now() -> void:
	if _cam_rig == null:
		return
	var cam_pos := _cam_rig.global_position
	# El fantasma (si esta activo) rota con la yaw actual.
	if _ghost != null:
		_face_ghost_to_camera(cam_pos)
	# Yaw por defecto al colocar: hacia la camara.
	if cam_pos.length_squared() > 0.0001:
		var dir := Vector3(cam_pos.x, 0, cam_pos.z).normalized()
		_yaw = rad_to_deg(atan2(dir.x, dir.z))


func _face_ghost_to_camera(cam_pos: Vector3) -> void:
	var ghost_pos := Vector3(_ghost.position.x, 0, _ghost.position.z)
	var dir := cam_pos - ghost_pos
	if dir.length_squared() < 0.0001:
		return
	dir.y = 0
	dir = dir.normalized()
	# Se escribe en _yaw (grados) en vez de girar _ghost directamente: la raiz
	# del fantasma no debe rotar, porque de ella cuelga la cimentacion, que se
	# muestrea sobre una rejilla alineada con los ejes del mundo. _process se
	# encarga de aplicar la yaw al cuerpo.
	_yaw = rad_to_deg(atan2(dir.x, dir.z))


func deselect() -> void:
	if _selected == null:
		return
	_selected = null
	_update_selection_marker()
	building_focus_changed.emit(null, Vector2.ZERO)


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
		for k in d.cost:
			Economy.amounts[k] = Economy.amounts[k] + d.cost[k] * DEMOLISH_REFUND
		# Contadores de capacidad: cada granero/almacen demolido reduce su cap.
		# Produccion: el edificio deja de aportar al "+X.X/s" del HUD.
		if rec.type == &"granero":
			Economy.granary_count = maxi(0, Economy.granary_count - 1)
		elif rec.type == &"almacen":
			Economy.warehouse_count = maxi(0, Economy.warehouse_count - 1)
		if d.can_produce() and not dev_free_build:
			Economy.remove_production(d.prod_resource, d.prod_amount / d.prod_interval)
		Economy.changed.emit()
	# Limpia la seleccion si era este edificio (esto cierra el menu contextual).
	if _selected == rec:
		deselect()
	# Quita del registro ANTES de liberar los nodos para que is_placing() y
	# demas consultas ya no lo vean.
	_placed.erase(rec)
	_remove_from_grid(rec)
	# Libera los nodos visuales (casita y, si es granja, el campo).
	if rec.node != null and is_instance_valid(rec.node):
		rec.node.queue_free()
	if rec.field != null and is_instance_valid(rec.field):
		rec.field.queue_free()
	# Avisos finales (el menu ya esta oculto en este punto).
	if d != null:
		building_demolished.emit(rec.type, rec.pos)
		message_requested.emit("%s demolido (reembolso 50%%)" % d.display_name)


func _update_selection_marker() -> void:
	if _selection_marker != null:
		_selection_marker.queue_free()
		_selection_marker = null
	if _selected == null or _selected.node == null:
		return
	# Anillo amarillo translucido a la altura del suelo del edificio
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
	mi.position = Vector3(_selected.pos.x, Terrain.height_at(_selected.pos) + 0.05, _selected.pos.y)
	add_child(mi)
	_selection_marker = mi


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
	# Solo gira el cuerpo, no la raiz: la cimentacion se muestrea sobre una
	# rejilla alineada con los ejes del mundo.
	_ghost_building.rotation = Vector3(0.0, deg_to_rad(_yaw), 0.0)
	_ghost.add_child(_ghost_building)
	_ghost_foundation = Node3D.new()
	_ghost.add_child(_ghost_foundation)
	add_child(_ghost)
	selection_changed.emit(id)


func cancel_placement() -> void:
	_pending = &""
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
		_ghost_building = null
		_ghost_foundation = null
	selection_changed.emit(&"")


func _process(delta: float) -> void:
	if _field_mode:
		_update_field_ghost()
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
		var cam_pos := _cam_rig.global_position
		var dir := cam_pos - Vector3(ground.x, 0, ground.y)
		if dir.length_squared() > 0.0001:
			dir.y = 0
			dir = dir.normalized()
			# +180: la cara del edificio (puerta) en los meshes esta en -Z
			# local (no +Z como pensabamos). Empíricamente la puerta queda
			# detras si solo calculamos atan2; este offset lo corrige.
			_yaw = rad_to_deg(atan2(dir.x, dir.z)) + 180.0
	var d := get_def(_pending)
	var base_h := _base_height(ground, d.footprint)
	_ghost.position = Vector3(ground.x, base_h, ground.y)
	# Solo gira el cuerpo: la cimentacion se muestrea alineada con el mundo.
	_ghost_building.rotation = Vector3(0.0, deg_to_rad(_yaw), 0.0)
	var valid := _is_valid(ground, _pending)
	# Reconstruir la cimentacion son ~25 MeshInstance3D + BoxMesh nuevos, y
	# solo cambia si el raton se ha movido o si la validez ha cambiado. Antes
	# se tiraba y se rehacia entera en cada frame aunque el raton estuviera
	# quieto (el yaw no la afecta: ya no rota con el edificio).
	if valid == _ghost_last_valid and ground.is_equal_approx(_ghost_last_ground):
		return
	_ghost_last_valid = valid
	_ghost_last_ground = ground
	var mat := _ghost_mat_ok if valid else _ghost_mat_bad
	_update_ghost_material(mat)
	for c in _ghost_foundation.get_children():
		_ghost_foundation.remove_child(c)
		c.queue_free()
	_ghost_foundation.add_child(_make_foundation(ground, d.footprint, base_h, mat))


func _update_ghost_material(m: Material) -> void:
	for c in _ghost_building.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = m


func _attach_production_timer(rec: BuildingRecord) -> void:
	var d := get_def(rec.type)
	if rec.dev or not d.can_produce():
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
	var d := get_def(rec.type)
	var amt: float = rec.amount if rec.amount > 0.0 else d.prod_amount
	Economy.add(String(d.prod_resource), amt)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("select_building_1") and _field_mode:
		_field_crop = "trigo"
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("select_building_2") and _field_mode:
		_field_crop = "zanahoria"
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("select_building_3") and _field_mode:
		_field_crop = "bayas"
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cancel"):
		if _field_mode:
			_cancel_field()
		elif _pending != &"":
			cancel_placement()
		else:
			deselect()
		get_viewport().set_input_as_handled()
		return
	# Demoler: tecla Delete/Backspace con edificio seleccionado.
	if event is InputEventKey and event.pressed and not event.echo:
		if (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE) and _selected != null:
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
		# Sin colocar: clic izq = seleccionar edificio bajo el cursor; der = deseleccionar.
		if btn.pressed and btn.button_index == MOUSE_BUTTON_LEFT:
			var ground: Vector2 = _cam_rig.screen_to_ground(btn.position)
			var hit := building_at(ground)
			if hit != null:
				toggle_select(hit)
			else:
				deselect()
			get_viewport().set_input_as_handled()
			return
		if btn.pressed and btn.button_index == MOUSE_BUTTON_RIGHT and _selected != null:
			demolish_selected()
			get_viewport().set_input_as_handled()


func _place() -> void:
	var ground: Vector2 = _cam_rig.screen_to_ground(get_viewport().get_mouse_position())
	var d := get_def(_pending)
	if not _is_valid(ground, _pending):
		var reason := ""
		var cls: String = Terrain.terrain_type(ground)
		var biome_ok := _biome_matches(cls, d.biomes)
		if not biome_ok:
			reason = "Solo se puede construir en %s" % d.biomes_text(_BIOME_NAMES)
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
	if _pending == &"granero":
		Economy.granary_count += 1
		Economy.changed.emit()
	elif _pending == &"almacen":
		Economy.warehouse_count += 1
		Economy.changed.emit()
	# Registra la produccion del edificio para que el HUD muestre "+X.X/s".
	# En modo dev (gratis y sin produccion) no se registra.
	if d.can_produce() and not dev_free_build:
		Economy.add_production(d.prod_resource, d.prod_amount / d.prod_interval)
	var base_h := _base_height(ground, d.footprint)
	# Raiz sin rotar apoyada en el punto de apoyo: el cuerpo gira con el yaw,
	# la cimentacion no (sus pilares siguen la rejilla del terreno).
	var node := Node3D.new()
	node.position = Vector3(ground.x, base_h, ground.y)
	var body := BuildingMeshes.build(_pending, null)
	body.rotation = Vector3(0.0, deg_to_rad(_yaw), 0.0)
	node.add_child(body)
	node.add_child(_make_foundation(ground, d.footprint, base_h, null))
	add_child(node)
	var rec := BuildingRecord.new(_pending, ground, _yaw, node, dev_free_build)
	_placed.append(rec)
	# Spatial hash: edificios sin campo se indexan al colocar. Las granjas
	# se indexan en _confirm_field (tras tener los bounds del campo).
	if _pending != &"granja":
		_add_to_grid(rec)
	_attach_production_timer(rec)
	building_built.emit(_pending, ground)
	place_clear_requested.emit(ground, d.footprint + 1.0)
	message_requested.emit("%s construido" % d.display_name)
	if _pending == &"granja":
		# segundo paso: delimitar el campo de cultivo
		_field_mode = true
		_field_yaw = _yaw
		_field_start = ground + _field_back() * _field_offset(d, _field_back())
		_field_crop = "trigo"
		_field_farm = rec
		_field_ghost = Node3D.new()
		add_child(_field_ghost)
		_ghost.visible = false
		message_requested.emit("Elige la zona con el raton (clic) y el cultivo: 1 Trigo, 2 Zanahorias, 3 Bayas")
		return
	cancel_placement()


# Ejes del huerto: `back` se aleja de la puerta de la casa, `side` es el ancho.
func _field_back() -> Vector2:
	return Vector2(-sin(deg_to_rad(_field_yaw)), -cos(deg_to_rad(_field_yaw)))


# Cuanto hay que separar el borde sembrado del centro de la casa para que la
# casa quede fuera del huerto por completo.
#
# Antes era un 0.6 fijo sumado a medio footprint, que no daba: la losa de
# cimentacion sobresale otro 0.25 por lado, y FieldMesh rodea los cultivos de
# tierra desnuda y redondea a celdas enteras. El resultado era que la casa
# acababa siempre dentro del huerto, atravesada por la valla.
func _field_offset(d: BuildingDef, back: Vector2) -> float:
	# La losa de cimentacion es un cuadrado alineado con los ejes del mundo, no
	# gira con la casa. Lo que sobresale en la direccion `back` es
	# media_anchura * (|back.x| + |back.y|): con la granja a 45 grados, la
	# esquina de la losa esta un 41% mas lejos que su lado. Sin esto el hueco
	# se comia justo en las diagonales (medido: 0,06 m a 45 grados).
	var house_reach := (d.footprint + 0.5) * 0.5 * (absf(back.x) + absf(back.y))
	# FieldMesh rodea los cultivos de tierra desnuda y redondea a celdas
	# enteras, asi que por cada lado puede crecer hasta MARGIN + CELL/2.
	var soil_pad := FieldMesh.MARGIN + FieldMesh.CELL * 0.5
	return house_reach + soil_pad + FIELD_HOUSE_GAP


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


# Centro en el mundo de una zona sembrada dada en coordenadas de la granja.
func _field_center(rect: Rect2) -> Vector2:
	var back := _field_back()
	var side := Vector2(back.y, -back.x)
	return _field_start 		+ side * (rect.position.x + rect.size.x * 0.5) 		+ back * (rect.position.y + rect.size.y * 0.5)


func _confirm_field() -> void:
	var ground: Vector2 = _cam_rig.screen_to_ground(get_viewport().get_mouse_position())
	var rect := _field_rect(ground)
	var w := rect.size.x
	var d := rect.size.y
	if w * d > FIELD_MAX_AREA:
		message_requested.emit("Zona demasiado grande (max %0.0f m2)" % FIELD_MAX_AREA)
		return
	if not _field_terrain_ok(rect):
		message_requested.emit("Los cultivos necesitan llanura")
		return
	var center := _field_center(rect)
	var crop_color: Color = CROP_COLORS[_field_crop]
	var field := FieldMesh.build(center, rect.size, deg_to_rad(_field_yaw), crop_color, false)
	# El campo va suelto en el mundo, no colgado de la casita. Se guarda la
	# referencia en el record para que demolish() lo libere con ella.
	add_child(field)
	_field_farm.field = field
	# Caja envolvente del campo, para poder clicar en cualquier parte de el y
	# seleccionar la granja. Ahora el campo puede estar girado, asi que se
	# calcula desde sus cuatro esquinas y no desde el rectangulo en ejes de
	# granja: con la granja a 45 grados los dos no coinciden.
	var back := _field_back()
	var side := Vector2(back.y, -back.x)
	var fmin := Vector2(INF, INF)
	var fmax := Vector2(-INF, -INF)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var corner: Vector2 = center + side * (w * 0.5 * sx) + back * (d * 0.5 * sz)
			fmin = Vector2(minf(fmin.x, corner.x), minf(fmin.y, corner.y))
			fmax = Vector2(maxf(fmax.x, corner.x), maxf(fmax.y, corner.y))
	_field_farm.field_min = fmin
	_field_farm.field_max = fmax
	# AABB del campo (con la rotacion de la granja aplicada): el spatial
	# hash necesita este AABB en mundo para hit-testear correctamente.
	_add_to_grid(_field_farm)
	# Radio que cubre el campo entero incluidas las esquinas.
	place_clear_requested.emit(center, rect.size.length() * 0.5 + 1.0)
	_field_farm.amount = clampf(w * d * FIELD_RATE, 1.0, 25.0)
	_field_farm.crop = _field_crop
	Economy.changed.emit()
	var crop_name: String = CROP_NAMES[_field_crop]
	message_requested.emit("Campo de %d m2 sembrado de %s" % [int(round(w * d)), crop_name])
	_end_field_mode()


func _cancel_field() -> void:
	# Solo se devuelve lo que se llego a cobrar: en modo dev la granja fue
	# gratis, asi que devolverla regalaba recursos (colocar y cancelar en
	# bucle era madera infinita).
	var was_free := _field_farm != null and _field_farm.dev
	_placed.erase(_field_farm)
	if _field_farm != null and _field_farm.node != null:
		_field_farm.node.queue_free()
	if not was_free:
		Economy.refund(get_def(&"granja").cost)
	message_requested.emit("Granja cancelada (recursos devueltos)")
	_end_field_mode()
	cancel_placement()


func _end_field_mode() -> void:
	_field_mode = false
	if _field_ghost != null:
		_field_ghost.queue_free()
		_field_ghost = null
	_field_farm = null
	# Limpia la colocacion (pending + fantasma + boton del menu).
	cancel_placement()


func _update_field_ghost() -> void:
	if _field_ghost == null:
		return
	var ground: Vector2 = _cam_rig.screen_to_ground(get_viewport().get_mouse_position())
	var rect := _field_rect(ground)
	for c in _field_ghost.get_children():
		_field_ghost.remove_child(c)
		c.queue_free()
	var crop_color: Color = CROP_COLORS[_field_crop]
	if _field_valid(rect):
		crop_color.a = 0.55
	else:
		crop_color = Color(1.0, 0.3, 0.3, 0.4)
	_field_ghost.add_child(
		FieldMesh.build(_field_center(rect), rect.size, deg_to_rad(_field_yaw), crop_color, true))


func _field_valid(rect: Rect2) -> bool:
	if rect.size.x * rect.size.y > FIELD_MAX_AREA:
		return false
	return _field_terrain_ok(rect)


# Muestrea la zona sembrada metro a metro, en los ejes de la granja.
func _field_terrain_ok(rect: Rect2) -> bool:
	var back := _field_back()
	var side := Vector2(back.y, -back.x)
	var v := rect.position.y
	while v <= rect.end.y:
		var u := rect.position.x
		while u <= rect.end.x:
			if Terrain.terrain_type(_field_start + side * u + back * v) != "llanura":
				return false
			u += 1.0
		v += 1.0
	return true


const _BIOME_NAMES := {
	0: "llanura",
	1: "bosque",
	2: "montaña",
}


func _biome_matches(cls: String, biomes: Array[BuildingDef.Biome]) -> bool:
	var reverse := {"llanura": 0, "bosque": 1, "montaña": 2}
	var idx: int = reverse.get(cls, -1)
	return biomes.has(idx)


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
			x += FOUNDATION_STEP
		y += FOUNDATION_STEP
	return h


# Losa de piedra bajo el edificio y, donde el terreno baja, pilares/pared de
# piedras que rellenan hasta el suelo real.
#
# IMPORTANTE: devuelve geometria en espacio LOCAL, relativa al origen del
# edificio (pos.x, base_h, pos.y). `pos` y `base_h` solo se usan para muestrear
# el terreno, nunca para posicionar. Antes se devolvian coordenadas absolutas
# y el nodo se colgaba de un padre ya trasladado a esa misma posicion, asi que
# la cimentacion acababa dibujada al doble de coordenadas (un edificio en
# 150,150 plantaba su losa en 300,300).
#
# El nodo devuelto NO debe rotarse con el edificio: los pilares se muestrean
# en una rejilla alineada con los ejes del mundo.
func _make_foundation(pos: Vector2, footprint: float, base_h: float, mat: Material) -> Node3D:
	var n := Node3D.new()
	var stone := mat if mat != null else BuildingMeshes._mat(STONE_COLOR)
	var slab := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(footprint + 0.5, 0.3, footprint + 0.5)
	slab.mesh = sm
	slab.material_override = stone
	slab.position = Vector3(0.0, -0.15, 0.0)
	n.add_child(slab)
	var step := 0.5
	var half := footprint * 0.5 + 0.25
	var y := -half
	while y <= half:
		var x := -half
		while x <= half:
			var h: float = Terrain.height_at(pos + Vector2(x, y))
			var dh: float = base_h - h - 0.15
			if dh > 0.08:
				var col := MeshInstance3D.new()
				var cm := BoxMesh.new()
				cm.size = Vector3(step * 1.05, dh, step * 1.05)
				col.mesh = cm
				col.material_override = stone
				col.position = Vector3(x, h - base_h + dh * 0.5 + 0.05, y)
				n.add_child(col)
			x += step
		y += step
	return n


func _is_valid(pos: Vector2, type: StringName) -> bool:
	var d := get_def(type)
	if not _biome_matches(Terrain.terrain_type(pos), d.biomes):
		return false
	if not dev_free_build and not Economy.can_afford(d.cost):
		return false
	var min_dist: float = d.footprint + 1.5
	# Spatial hash: solo revisa edificios en la celda (o adyacentes) a pos.
	# 9 celdas * ~1 edificio/celda = ~10 checks en vez de N (cientos).
	for b in _nearby(pos):
		if (b.pos - pos).length() < min_dist:
			return false
	return true
