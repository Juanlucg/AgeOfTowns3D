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
const STONE_COLOR := Color(0.50, 0.50, 0.52)
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
var _cam_rig: CameraController3D

var _field_mode := false
var _field_start := Vector2.ZERO
var _field_crop := "trigo"
var _field_ghost: Node3D = null
var _field_farm: BuildingRecord = null
var _field_yaw := 0.0

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
	assert(_cam_rig != null, "Buildings: camera_path no asignado en el .tscn")
	# Dos materiales para toda la partida: antes se creaba un
	# StandardMaterial3D nuevo en cada frame de colocacion.
	_ghost_mat_ok = BuildingMeshes.ghost_mat(GHOST_OK)
	_ghost_mat_bad = BuildingMeshes.ghost_mat(GHOST_BAD)
	_register_defs()


# Crea los BuildingDef por codigo (migrar a .tres en el futuro).
func _register_defs() -> void:
	_register(_make_granero())
	_register(_make_granja())
	_register(_make_aserradero())
	_register(_make_cantera())


func _register(d: BuildingDef) -> void:
	_defs[d.id] = d
	_ids.append(d.id)


func _make_granero() -> BuildingDef:
	var d := BuildingDef.new()
	d.id = &"granero"
	d.display_name = "Granero"
	d.description = "Almacena comida y grano. Aumenta la capacidad maxima del almacen del pueblo."
	d.cost = {"madera": 25.0, "piedra": 15.0}
	d.footprint = 1.0
	d.biomes = [BuildingDef.Biome.LLANURA]
	d.hint = "+50 almacen"
	d.color = Color(0.95, 0.65, 0.2)
	d.capacity = 300
	d.capacity_resource = &"comida"
	return d


func _make_granja() -> BuildingDef:
	var d := BuildingDef.new()
	d.id = &"granja"
	d.display_name = "Granja"
	d.description = "Casita de campo con una parcela cultivable. Produce comida segun el tamano del campo."
	d.cost = {"madera": 25.0}
	d.prod_resource = &"comida"
	d.prod_amount = 2.0
	d.prod_interval = 5.0
	d.footprint = 1.0
	d.biomes = [BuildingDef.Biome.LLANURA]
	d.hint = "casita + campo a elegir"
	d.color = Color(0.55, 0.72, 0.3)
	d.worker_count = 3
	d.worker_names = PackedStringArray(["Campesino", "Jornalero", "Granjero"])
	return d


func _make_aserradero() -> BuildingDef:
	var d := BuildingDef.new()
	d.id = &"aserradero"
	d.display_name = "Aserradero"
	d.description = "Cabaña abierta con mesa de corte. Convierte tiempo en madera."
	d.cost = {"madera": 30.0}
	d.prod_resource = &"madera"
	d.prod_amount = 2.0
	d.prod_interval = 5.0
	d.footprint = 1.1
	d.biomes = [BuildingDef.Biome.BOSQUE]
	d.hint = "+2 madera / 5s"
	d.color = Color(0.62, 0.42, 0.22)
	d.worker_count = 2
	d.worker_names = PackedStringArray(["Leñador", "Carpintero"])
	return d


func _make_cantera() -> BuildingDef:
	var d := BuildingDef.new()
	d.id = &"cantera"
	d.display_name = "Cantera"
	d.description = "Bloques de piedra apilados al pie de la montana. Produce piedra."
	d.cost = {"madera": 20.0, "piedra": 10.0}
	d.prod_resource = &"piedra"
	d.prod_amount = 2.0
	d.prod_interval = 5.0
	d.footprint = 1.1
	d.biomes = [BuildingDef.Biome.MONTANA]
	d.hint = "+2 piedra / 5s"
	d.color = Color(0.55, 0.55, 0.58)
	d.worker_count = 2
	d.worker_names = PackedStringArray(["Cantero", "Picapedrero"])
	return d


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
	for b in _placed:
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
		_yaw = atan2(dir.x, dir.z)


func _face_ghost_to_camera(cam_pos: Vector3) -> void:
	var ghost_pos := Vector3(_ghost.position.x, 0, _ghost.position.z)
	var dir := cam_pos - ghost_pos
	if dir.length_squared() < 0.0001:
		return
	dir.y = 0
	dir = dir.normalized()
	_ghost.rotation = Vector3(0.0, atan2(dir.x, dir.z), 0.0)


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
	print("[BUILDINGS] demolish ENTER rec=", rec, " type=", rec.type if rec != null else "null")
	if rec == null:
		print("[BUILDINGS] abort: rec is null")
		return
	# Reembolso antes de cualquier cleanup para que el HUD lo vea.
	var d := get_def(rec.type)
	print("[BUILDINGS] def=", d)
	if d != null:
		for k in d.cost:
			Economy.amounts[k] = Economy.amounts[k] + d.cost[k] * DEMOLISH_REFUND
		Economy.changed.emit()
	# Limpia la seleccion si era este edificio (esto cierra el menu contextual).
	if _selected == rec:
		deselect()
	# Quita del registro ANTES de liberar los nodos para que is_placing() y
	# demas consultas ya no lo vean.
	_placed.erase(rec)
	# Libera los nodos visuales (casita y, si es granja, el campo).
	print("[BUILDINGS] node=", rec.node, " is_valid=", is_instance_valid(rec.node) if rec.node != null else false)
	if rec.node != null and is_instance_valid(rec.node):
		rec.node.queue_free()
	if rec.field != null and is_instance_valid(rec.field):
		rec.field.queue_free()
	# Avisos finales (el menu ya esta oculto en este punto).
	if d != null:
		building_demolished.emit(rec.type, rec.pos)
		message_requested.emit("%s demolido (reembolso 50%%)" % d.display_name)
	print("[BUILDINGS] demolish DONE")


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
	# Orientacion inicial: la cara del edificio mira a la camara.
	_yaw = 0.0
	if _cam_rig != null:
		var cam_pos := _cam_rig.global_position
		if cam_pos.length_squared() > 0.0001:
			var dir := Vector3(cam_pos.x, 0, cam_pos.z).normalized()
			_yaw = atan2(dir.x, dir.z)
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
	if Input.is_action_pressed("rotate_building"):
		_yaw = fmod(_yaw + ROTATE_SPEED * delta, 360.0)
	var ground: Vector2 = _cam_rig.screen_to_ground(get_viewport().get_mouse_position())
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
			deselect()
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
				deselect()
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
	if _pending == &"granero":
		Economy.granary_count += 1
		Economy.changed.emit()
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
	_attach_production_timer(rec)
	building_built.emit(_pending, ground)
	place_clear_requested.emit(ground, d.footprint + 1.0)
	message_requested.emit("%s construido" % d.display_name)
	if _pending == &"granja":
		# segundo paso: delimitar el campo de cultivo
		_field_mode = true
		var back_dir := Vector2(-sin(deg_to_rad(_yaw)), -cos(deg_to_rad(_yaw)))
		_field_start = ground + back_dir * (get_def(&"granja").footprint * 0.5 + 0.6)
		_field_yaw = _yaw
		_field_crop = "trigo"
		_field_farm = rec
		_field_ghost = Node3D.new()
		add_child(_field_ghost)
		_ghost.visible = false
		message_requested.emit("Elige la zona con el raton (clic) y el cultivo: 1 Trigo, 2 Zanahorias, 3 Bayas")
		return
	cancel_placement()


func _confirm_field() -> void:
	var ground: Vector2 = _cam_rig.screen_to_ground(get_viewport().get_mouse_position())
	var back := Vector2(-sin(deg_to_rad(_field_yaw)), -cos(deg_to_rad(_field_yaw)))
	var side := Vector2(back.y, -back.x)
	var diff := ground - _field_start
	var depth := maxf(0.0, diff.dot(back))
	var spread := diff.dot(side)
	depth = maxf(depth, FIELD_MIN)
	var rmin := _field_start + back * 0.0 + side * minf(spread, 0.0)
	var rmax := _field_start + back * depth + side * maxf(spread, 0.0)
	if rmin.x > rmax.x:
		var tmp := rmin.x
		rmin.x = rmax.x
		rmax.x = tmp
	if rmin.y > rmax.y:
		var tmp := rmin.y
		rmin.y = rmax.y
		rmax.y = tmp
	var w := rmax.x - rmin.x
	var d := rmax.y - rmin.y
	if w < FIELD_MIN or d < FIELD_MIN:
		message_requested.emit("Zona demasiado pequena (min %0.0fx%0.0f m)" % [FIELD_MIN, FIELD_MIN])
		return
	if w * d > FIELD_MAX_AREA:
		message_requested.emit("Zona demasiado grande (max %0.0f m2)" % FIELD_MAX_AREA)
		return
	if not _field_terrain_ok(rmin, rmax):
		message_requested.emit("Los cultivos necesitan llanura")
		return
	var crop_color: Color = CROP_COLORS[_field_crop]
	var field := FieldMesh.build(rmin, rmax, crop_color, false)
	# El campo queda en mundo (no hijo del edificio, porque la casita tiene
	# yaw y eso distorsionaria el campo). Se guarda la referencia en el
	# record para que demolish() lo limpie atomicamente con la casita.
	add_child(field)
	_field_farm.field = field
	# Bounds del campo (con margen para la valla): para que se pueda clicar
	# en cualquier parte del campo y seleccionar la granja.
	_field_farm.field_min = Vector2(minf(rmin.x, rmax.x), minf(rmin.y, rmax.y))
	_field_farm.field_max = Vector2(maxf(rmin.x, rmax.x), maxf(rmin.y, rmax.y))
	var center := Vector2((rmin.x + rmax.x) * 0.5, (rmin.y + rmax.y) * 0.5)
	var field_radius := maxf(w, d) + 1.5
	place_clear_requested.emit(center, field_radius)
	_field_farm.amount = clampf(w * d * FIELD_RATE, 1.0, 25.0)
	_field_farm.crop = _field_crop
	Economy.changed.emit()
	var area := int(round(w * d))
	var crop_name: String = CROP_NAMES[_field_crop]
	message_requested.emit("Campo de %d m2 sembrado de %s" % [area, crop_name])
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
	var back := Vector2(-sin(deg_to_rad(_field_yaw)), -cos(deg_to_rad(_field_yaw)))
	var side := Vector2(back.y, -back.x)
	var diff := ground - _field_start
	var depth := maxf(0.0, diff.dot(back))
	var spread := diff.dot(side)
	depth = maxf(depth, FIELD_MIN)
	var rmin := _field_start + back * 0.0 + side * minf(spread, 0.0)
	var rmax := _field_start + back * depth + side * maxf(spread, 0.0)
	if rmin.x > rmax.x:
		var tmp := rmin.x
		rmin.x = rmax.x
		rmax.x = tmp
	if rmin.y > rmax.y:
		var tmp := rmin.y
		rmin.y = rmax.y
		rmax.y = tmp
	for c in _field_ghost.get_children():
		_field_ghost.remove_child(c)
		c.queue_free()
	var valid := _field_valid(rmin, rmax)
	var soil_color := Color(0.3, 0.25, 0.15, 0.5) if valid else Color(1.0, 0.3, 0.3, 0.4)
	var crop_color: Color = CROP_COLORS[_field_crop]
	crop_color.a = 0.55 if valid else 0.35
	if not valid:
		crop_color = Color(1.0, 0.3, 0.3, 0.4)
	_field_ghost.add_child(FieldMesh.build(rmin, rmax, crop_color, true))


func _field_valid(rmin: Vector2, rmax: Vector2) -> bool:
	var w := rmax.x - rmin.x
	var d := rmax.y - rmin.y
	if w < FIELD_MIN or d < FIELD_MIN or w * d > FIELD_MAX_AREA:
		return false
	return _field_terrain_ok(rmin, rmax)


func _field_terrain_ok(rmin: Vector2, rmax: Vector2) -> bool:
	var y := rmin.y
	while y <= rmax.y:
		var x := rmin.x
		while x <= rmax.x:
			if Terrain.terrain_type(Vector2(x, y)) != "llanura":
				return false
			x += 1.0
		y += 1.0
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
	for b in _placed:
		if (b.pos - pos).length() < min_dist:
			return false
	return true
