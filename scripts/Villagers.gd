extends Node3D
class_name Villagers
## Gestiona los aldeanos asociados a las casas construidas.

const VILLAGER_SCRIPT := preload("res://scripts/Villager.gd")
const CAMPFIRE_SCRIPT := preload("res://scripts/Campfire.gd")
const INITIAL_VILLAGERS := 10
const FOOD_PER_VILLAGER_PER_DAY := 1.0
const STARVATION_DAYS_TO_DEFEAT := 3
## A esta hora del dia los aldeanos vuelven a casa a comer (y es cuando se
## consume la comida diaria de cada uno).
const MEAL_HOUR := 13.0
const MEAL_DURATION_HOURS := 1.0

@export var buildings_path: NodePath
@export var day_night_path: NodePath

signal population_changed(population: int, housing: int, workers: int)
signal message_requested(text: String)
signal defeat_requested(reason: String)
signal workers_changed(position: Vector2, count: int)
signal worker_efficiency_changed(position: Vector2, efficiency: float)
## Emitida solo cuando cambia el numero de aldeanos sin vivienda (0 = todos
## alojados). El HUD la usa para el aviso persistente.
signal homeless_changed(count: int)

var _buildings: Buildings
var _day_night: DayNightCycle
var _villagers: Array = []
var _manual_free: Array = []
var _house_groups: Dictionary = {}
var _work_groups: Dictionary = {}
var _daytime := true
var _starvation_days := 0
var _defeat_requested := false
var _homeless_count := 0
var _next_name_id := 0
var _meal_time := false
## Hoguera inicial donde duermen los aldeanos sin casa.
var _shelter_pos := Vector2.INF
## Resultado de la ultima comida (true = todos comieron). Se evalua al
## amanecer para la inanicion en vez de consumir la comida a medianoche.
var _last_meal_fed := true


func _ready() -> void:
	_buildings = get_node_or_null(buildings_path) as Buildings
	if _buildings == null:
		push_error("Villagers: buildings_path no apunta a un Buildings")
		return
	_buildings.building_built.connect(_on_building_built)
	_buildings.building_demolished.connect(_on_building_demolished)
	_day_night = get_node_or_null(day_night_path) as DayNightCycle
	if _day_night != null:
		_day_night.day_changed.connect(_on_day_changed)
		_day_night.time_changed.connect(_on_time_changed)
	_spawn_initial_population()


func _on_building_built(type: StringName, pos: Vector2) -> void:
	var def := _buildings.get_def(type)
	if def == null:
		return
	if type == &"casa":
		_house_new_residents(pos, def.housing_capacity)
	elif def.worker_count > 0:
		_work_groups[pos] = {
			"position": pos,
			"type": type,
			"capacity": def.worker_count,
			"name": def.display_name,
			"workers": [],
		}
	_refresh_gathering()
	_reassign_workers()


func _on_building_demolished(type: StringName, pos: Vector2) -> void:
	if type == &"casa":
		# Los habitantes no desaparecen: se realojan en otra casa con hueco o,
		# si no la hay, se les quita el hogar. Hay que limpiar los datos internos
		# de cada Villager, no solo el registro _house_groups: si no, siguen
		# volviendo de noche a la casa demolida.
		var evicted: Array = _house_groups.get(pos, [])
		_house_groups.erase(pos)
		_rehouse_villagers(evicted)
	elif _work_groups.has(pos):
		_work_groups.erase(pos)
	_refresh_gathering()
	_reassign_workers()


func _house_new_residents(home: Vector2, capacity: int) -> void:
	var household: Array = []
	for villager in _villagers:
		if household.size() >= capacity:
			break
		if is_instance_valid(villager) and not _is_housed(villager):
			household.append(villager)
	_house_groups[home] = household
	# Los aldeanos que ya existian (los iniciales) tienen su hogar en el punto
	# de aparicion, no en la casa: hay que reasignarselo para que vuelvan a ella
	# al acabar la jornada en vez de al centro del mapa.
	var door_offset := _house_door_offset(home)
	for villager in household:
		villager.assign_home(home, door_offset)


## Un aldeano tiene vivienda si el propio aldeano lo dice (estado explicito),
## no por deducir la posicion ni por pertenecer a _house_groups.
func _is_housed(villager) -> bool:
	return villager.has_home


func _spawn_initial_population() -> void:
	var start := _find_initial_position()
	# Hoguera inicial: refugio de los aldeanos sin casa.
	_shelter_pos = start
	var campfire := CAMPFIRE_SCRIPT.new()
	campfire.position = Vector3(start.x, Terrain.height_at(start), start.y)
	add_child(campfire)
	for index in INITIAL_VILLAGERS:
		var offset := Vector2((index % 2) * 0.35 - 0.18, (index / 2) * 0.35)
		_create_villager(start, offset, Vector2.ZERO, false)
	message_requested.emit("La partida comienza con %d aldeanos" % INITIAL_VILLAGERS)


# Crea un aldeano, le asigna un nombre estable y lo registra. Devuelve el nodo.
func _create_villager(home: Vector2, spawn_offset: Vector2, door_offset: Vector2, housed: bool) -> Node3D:
	var villager := VILLAGER_SCRIPT.new()
	villager.display_name = "Aldeano %d" % (_next_name_id + 1)
	_next_name_id += 1
	villager.initialize(home, spawn_offset, door_offset, housed)
	villager.set_gathering_point(_buildings.get_gathering_point())
	villager.set_shelter_point(_shelter_pos)
	add_child(villager)
	_villagers.append(villager)
	return villager


# Reparte el punto de reunion (plaza) a todos los aldeanos.
func _refresh_gathering() -> void:
	var point := _buildings.get_gathering_point()
	for villager in _villagers:
		if is_instance_valid(villager):
			villager.set_gathering_point(point)
			villager.set_shelter_point(_shelter_pos)


func _find_initial_position() -> Vector2:
	var center := Vector2(Terrain.WORLD_SIZE * 0.5, Terrain.WORLD_SIZE * 0.5)
	for radius in range(0, 40, 2):
		for angle_index in 16:
			var angle := TAU * float(angle_index) / 16.0
			var candidate := center + Vector2(cos(angle), sin(angle)) * float(radius)
			if Terrain.terrain_type(candidate) == "llanura":
				return candidate
	return center


func _on_day_changed(_day: int) -> void:
	# La comida ya se consumio en la comida del mediodia (_serve_meal).
	var fed := _last_meal_fed
	if _villagers.is_empty():
		_starvation_days = 0
	elif fed:
		_starvation_days = 0
	else:
		_starvation_days += 1
		if _starvation_days >= STARVATION_DAYS_TO_DEFEAT and not _defeat_requested:
			_defeat_requested = true
			defeat_requested.emit("El pueblo no puede sobrevivir sin comida")
	if fed:
		_try_new_arrival()
	_reassign_workers()


func _on_time_changed(_day: int, _season: int, hour: float, _weather: String) -> void:
	var daytime := hour >= 7.0 and hour < 19.0
	var meal := daytime and hour >= MEAL_HOUR and hour < MEAL_HOUR + MEAL_DURATION_HOURS
	if daytime == _daytime and meal == _meal_time:
		return
	_daytime = daytime
	_meal_time = meal
	# Los edificios solo producen durante el turno de trabajo; en la comida los
	# aldeanos estan en casa, asi que el turno se pausa.
	if _buildings != null:
		_buildings.set_shift_active(_daytime and not _meal_time)
	for villager in _villagers:
		if is_instance_valid(villager):
			villager.set_work_schedule(_daytime)
			villager.set_meal(_meal_time)
	if meal:
		_serve_meal()


## Comida del mediodia: consume la racion diaria y actualiza a cada aldeano. Se
## llama una vez al dia, al empezar la hora de comer.
func _serve_meal() -> void:
	var required := _villagers.size() * FOOD_PER_VILLAGER_PER_DAY
	if required <= 0.0:
		_last_meal_fed = true
		return
	# Reparto proporcional: si solo hay parte de la comida, cada aldeano come
	# una fraccion y sufre en proporcion, en vez de que todos pasen hambre
	# completa aunque parte de la comida se haya consumido.
	var available: float = Economy.amounts.get(Economy.FOOD_RESOURCE, 0.0)
	var fed_ratio := clampf(available / required, 0.0, 1.0)
	Economy.consume_food(required)
	for villager in _villagers:
		if is_instance_valid(villager):
			villager.daily_needs(fed_ratio)
	# La plaza da felicidad a todos los aldeanos.
	var bonus := _buildings.total_happiness_bonus()
	if bonus > 0.0:
		for villager in _villagers:
			if is_instance_valid(villager):
				villager.add_happiness(bonus)
	_last_meal_fed = fed_ratio >= 1.0
	if fed_ratio < 1.0:
		message_requested.emit("Falta comida: los aldeanos pasan hambre")


func _try_new_arrival() -> void:
	# Los aldeanos sin hogar tienen prioridad: mientras queden, no se crean
	# nuevos llegados. Asi una casa nueva los aloja antes que a un recien
	# llegado (el alojamiento lo hace _house_new_residents al construirla).
	if _count_homeless() > 0:
		return
	# El crecimiento lo impulsa la plaza: sin ella el pueblo no atrae a nadie.
	if not _buildings.has_plaza():
		return
	var available_house := _find_available_house()
	if available_house == Vector2.INF:
		# Sin sitio, la poblacion no crece (no se crean aldeanos sin vivienda).
		message_requested.emit("No hay viviendas disponibles para nuevos aldeanos")
		return
	var door_offset := _house_door_offset(available_house)
	var villager := _create_villager(available_house, door_offset, door_offset, true)
	(_house_groups[available_house] as Array).append(villager)
	message_requested.emit("Ha llegado un nuevo aldeano")


## Aldeanos que viven en la casa situada en `home` (vacio si no hay ninguna).
func residents_of(home: Vector2) -> Array:
	return _house_groups.get(home, [])


## Primera casa con hueco (capacidad = housing_capacity), o Vector2.INF.
func _find_available_house() -> Vector2:
	var def := _buildings.get_def(&"casa")
	if def == null:
		return Vector2.INF
	for home in _house_groups:
		if (_house_groups[home] as Array).size() < def.housing_capacity:
			return home
	return Vector2.INF


## Aloja a los aldeanos que se han quedado sin casa: primero intenta meterlos en
## otra vivienda con hueco; los que no quepan se quedan sin hogar (clear_home).
func _rehouse_villagers(villagers: Array) -> void:
	var homeless := 0
	for villager in villagers:
		if not is_instance_valid(villager):
			continue
		var home := _find_available_house()
		if home == Vector2.INF:
			villager.clear_home()
			homeless += 1
			continue
		(_house_groups[home] as Array).append(villager)
		villager.assign_home(home, _house_door_offset(home))
	if homeless > 0:
		message_requested.emit("%d aldeanos se han quedado sin hogar" % homeless)


func _house_door_offset(home: Vector2) -> Vector2:
	var record := _buildings.building_at(home)
	if record == null:
		return Vector2(0.0, -0.7)
	var yaw := deg_to_rad(record.yaw)
	# La puerta de la casa importada mira hacia su -Z local.
	return Vector2(-sin(yaw), -cos(yaw)) * 0.7


func _reassign_workers() -> void:
	for group in _work_groups.values():
		group["workers"] = []
	for villager in _villagers:
		if not is_instance_valid(villager) or not villager.is_working():
			continue
		var group: Variant = _group_at(villager.work_position)
		if group == null:
			villager.clear_work()
		else:
			(group["workers"] as Array).append(villager)
	for group in _work_groups.values():
		while (group["workers"] as Array).size() < group["capacity"]:
			var villager: Variant = _find_free_villager()
			if villager == null:
				break
			villager.assign_work(group["position"], group["name"])
			villager.set_work_schedule(_daytime)
			(group["workers"] as Array).append(villager)
		_emit_group_workers(group)
	_emit_population()


func assign_free_worker(position: Vector2) -> bool:
	var group: Variant = _group_at(position)
	if group == null or (group["workers"] as Array).size() >= group["capacity"]:
		return false
	var villager: Variant = _find_free_villager(true)
	if villager == null:
		return false
	_manual_free.erase(villager)
	villager.assign_work(position, group["name"])
	villager.set_work_schedule(_daytime)
	(group["workers"] as Array).append(villager)
	_emit_group_workers(group)
	_emit_population()
	return true


func release_worker(position: Vector2) -> bool:
	var group: Variant = _group_at(position)
	if group == null or (group["workers"] as Array).is_empty():
		return false
	var villager = (group["workers"] as Array).pop_back()
	villager.clear_work()
	if not _manual_free.has(villager):
		_manual_free.append(villager)
	_emit_group_workers(group)
	_emit_population()
	return true


func _find_free_villager(include_manual := false) -> Variant:
	for villager in _villagers:
		if is_instance_valid(villager) and not villager.is_working() \
				and (include_manual or not _manual_free.has(villager)):
			return villager
	return null


func _group_at(position: Vector2) -> Variant:
	for key in _work_groups:
		if key.is_equal_approx(position):
			return _work_groups[key]
	return null


func _emit_group_workers(group: Dictionary) -> void:
	var workers: Array = group["workers"]
	workers_changed.emit(group["position"], workers.size())
	var efficiency := 0.0
	for villager in workers:
		efficiency += villager.efficiency()
	if not workers.is_empty():
		efficiency /= workers.size()
	worker_efficiency_changed.emit(group["position"], efficiency)


func _count_homeless() -> int:
	var n := 0
	for villager in _villagers:
		if is_instance_valid(villager) and not villager.has_home:
			n += 1
	return n


func _emit_population() -> void:
	var housing := 0
	for _home in _house_groups:
		var def := _buildings.get_def(&"casa")
		if def != null:
			housing += def.housing_capacity
	var workers := 0
	for group in _work_groups.values():
		workers += (group["workers"] as Array).size()
	population_changed.emit(_villagers.size(), housing, workers)
	# Aviso persistente: solo cuando cambia el numero de aldeanos sin hogar.
	var homeless := _count_homeless()
	if homeless != _homeless_count:
		_homeless_count = homeless
		homeless_changed.emit(homeless)


func refresh_population() -> void:
	_emit_population()
