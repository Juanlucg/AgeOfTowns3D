extends Node3D
## Aldeano basico: vive en una casa y se mueve por sus alrededores.

const WALK_SPEED := 0.7
const WANDER_RADIUS := 3.0
const ARRIVAL_DISTANCE := 0.18
const VISUAL_SCALE := Vector3(0.35, 0.35, 0.35)
## Penalizacion de felicidad por dia sin vivienda (moderada). No toca la salud.
const HOMELESS_HAPPINESS_PENALTY := 6.0
## Color de camiseta que marca a un aldeano sin hogar.
const HOMELESS_SHIRT_COLOR := Color(0.52, 0.45, 0.38)
## Tolerancia al pisar un puente: el NavigationAgent puede devolver un punto un
## poco fuera del ancho visual del tablero.
const BRIDGE_TOL := 0.8
## Radio desde el que se busca un camino para seguirlo (m).
const PATH_SEEK_RADIUS := 6.0
## Avance por el camino entre dos objetivos intermedios (m).
const PATH_LOOKAHEAD := 3.0
## Distancia para dar por alcanzado un objetivo intermedio del camino.
const PATH_WAYPOINT_DISTANCE := 0.5
## Tope de objetivos intermedios seguidos sin llegar al destino (evita bucles).
const MAX_PATH_HOPS := 40
## Si un paso cae en agua, se replanifica el destino. Sin este enfriamiento se
## hacia en cada frame mientras el aldeano seguia bloqueado, disparando 8
## muestras de terreno + un plan de camino por frame y aldeano.
const BLOCKED_RETRY := 0.25
## Radio (m) al que hay que llegar al puesto para contar como presente. El
## aldeano deambula en 0.5-1.0 m alrededor de work_position.
const WORK_ARRIVAL := 1.6
## Comida que puede acarrear un granjero en cada viaje al almacen.
const CARRY_CAPACITY := 5.0

var home_position := Vector2.ZERO
var home_door_position := Vector2.ZERO
var home_exit_direction := Vector2(0.0, -1.0)
## Estado explicito de vivienda. No se deduce de home_position: lo marcan
## assign_home()/clear_home() (e initialize() para los recien llegados).
var has_home := false
## Punto de reunion (plaza) si existe: los aldeanos sin trabajo se juntan ahi.
var gathering_position := Vector2.ZERO
var has_gathering := false
## Refugio (hoguera inicial) donde duerme si no tiene casa.
var shelter_position := Vector2.ZERO
var has_shelter := false
var work_position := Vector2.ZERO
## Posicion del EDIFICIO donde trabaja (clave del grupo). No cambia aunque el
## punto de deambulacion (work_position) sea el campo de una granja.
var work_key := Vector2.ZERO
## Carril fijo del aldeano en el campo (0..4095): reparte a los granjeros en
## columnas estables para que avancen recto al cosechar/sembrar.
var work_lane := 0
var work_name := ""
var display_name := "Aldeano"
var hunger := 0.0
var health := 100.0
var happiness := 100.0
var _at_work := false
## De noche descansa en casa: no elige destinos nuevos de deambulacion.
var _resting := false
## A la hora de comer vuelve a casa; mientras dura no trabaja ni deambula.
var _at_meal := false
var _target := Vector2.ZERO
## Destino final del trayecto actual. `_target` puede ser un punto intermedio
## del camino que acerca a el, no necesariamente el destino.
var _destination := Vector2.ZERO
## Camino que se esta siguiendo ({} = navegacion directa por el terreno).
var _follow_stroke: Dictionary = {}
## Objetivos intermedios seguidos en el trayecto actual (tope de seguridad).
var _path_hops := 0
## Puntos de paso pendientes (hueco de la valla de un campo).
var _queue: Array[Vector2] = []
var _wait_time := 0.0
var _blocked_cooldown := 0.0
var _visual: Node3D
var _shirt_material: StandardMaterial3D
var _walk_phase := 0.0
var _pick_phase := 0.0
var _navigation_agent: NavigationAgent3D
## Acarreo: cuando un granjero recoge comida en el campo la lleva al almacen.
## Mientras lleva carga, su destino es el almacen y entrega al llegar.
var _carrying := false
var carry_amount := 0.0
var carry_resource := "comida"
var _carry_visual: Node3D = null


func initialize(home: Vector2, spawn_offset: Vector2, door_offset := Vector2.ZERO, housed := false) -> void:
	work_lane = randi() % 4096
	home_position = home
	home_door_position = home + door_offset
	if door_offset.length_squared() > 0.001:
		home_exit_direction = door_offset.normalized()
	has_home = housed
	_target = home + spawn_offset
	position = Vector3(_target.x, Terrain.height_at(_target), _target.y)
	_wait_time = randf_range(0.2, 1.5)
	_update_visual_state()


## Reasigna el hogar de un aldeano ya existente (los iniciales nacen sin casa y
## los que se quedan sin vivienda al demolerla). No mueve al aldeano: solo fija
## a donde vuelve al acabar la jornada. Si esta en casa, reorienta el objetivo.
func assign_home(home: Vector2, door_offset: Vector2) -> void:
	home_position = home
	home_door_position = home + door_offset
	if door_offset.length_squared() > 0.001:
		home_exit_direction = door_offset.normalized()
	has_home = true
	if not _at_work:
		_destination = home_door_position
		_follow_stroke = {}
		_path_hops = 0
		_route_or_direct()
	_update_visual_state()


## Se queda sin hogar (casa demolida y ninguna otra con hueco): deambula
## alrededor de donde esta ahora hasta que una casa nueva lo aloje. Antes el
## aldeano seguia creyendo que vivia en la casa demolida y volvia alli de noche.
func clear_home() -> void:
	var gp: Vector3 = global_position if is_inside_tree() else position
	var p := Vector2(gp.x, gp.z)
	home_position = p
	home_door_position = p
	home_exit_direction = Vector2(0.0, -1.0)
	has_home = false
	if not _at_work:
		_destination = home_door_position
		_follow_stroke = {}
		_path_hops = 0
		_route_or_direct()
	_update_visual_state()


## Fija (o quita, con Vector2.INF) el punto de reunion del pueblo.
func set_gathering_point(p: Vector2) -> void:
	has_gathering = p != Vector2.INF
	gathering_position = p if has_gathering else Vector2.ZERO


## Fija (o quita, con Vector2.INF) el refugio (hoguera) para los sin casa.
func set_shelter_point(p: Vector2) -> void:
	has_shelter = p != Vector2.INF
	shelter_position = p if has_shelter else Vector2.ZERO


# Donde descansa de noche: su casa si tiene, si no la hoguera.
func _rest_target() -> Vector2:
	if has_home:
		return home_door_position
	if has_shelter:
		return shelter_position
	return home_door_position


## Bonus de felicidad (plaza).
func add_happiness(amount: float) -> void:
	if amount <= 0.0:
		return
	happiness = clampf(happiness + amount, 0.0, 100.0)
	_update_visual_state()


## `work` es el punto donde deambula (para las granjas, un punto del campo) y
## `key` la posicion del edificio al que pertenece (por defecto, la misma).
func assign_work(work: Vector2, display_name: String, key: Vector2 = Vector2.INF) -> void:
	work_position = work
	work_key = work if key == Vector2.INF else key
	work_name = display_name
	_choose_target()


func clear_work() -> void:
	work_position = Vector2.ZERO
	work_key = Vector2.ZERO
	work_name = ""
	_at_work = false
	_choose_target()


## Cambia el punto de trabajo sin cambiar de oficio (una granja pasa a trabajar
## en el centro del campo). Si esta en jornada, se redirige ya.
func set_work_spot(spot: Vector2) -> void:
	work_position = spot
	# No se cambia el destino si va cargando: sigue hacia el almacen.
	if _at_work and not _carrying:
		_choose_target()


func is_carrying() -> bool:
	return _carrying


## Cuanto puede llevar de una vez (lo consulta Villagers al darle una carga).
func carry_capacity() -> float:
	return CARRY_CAPACITY


## Recoge una carga ya cosechada y va a dejarla al almacen (`target`). Mientras
## la lleva, se le ve un cajon y no cuenta como presente en el puesto.
func start_carry(target: Vector2, amount: float, resource: String) -> void:
	if _carrying or amount <= 0.0:
		return
	_carrying = true
	carry_amount = amount
	carry_resource = resource
	if _carry_visual != null:
		_carry_visual.visible = true
	# Sale hacia el almacen sin esperar a terminar la pausa actual.
	_wait_time = 0.0
	_destination = target
	_follow_stroke = {}
	_path_hops = 0
	_route_or_direct()


# Entrega la carga en el almacen y vuelve al puesto de trabajo.
func _deliver() -> void:
	Economy.add(carry_resource, carry_amount)
	carry_amount = 0.0
	_carrying = false
	if _carry_visual != null:
		_carry_visual.visible = false
	_wait_time = randf_range(0.3, 0.8)
	_choose_target()


func set_work_schedule(at_work: bool) -> void:
	_at_work = at_work and is_working()
	# Fuera de la jornada (noche) descansa en casa en vez de deambular.
	_resting = not at_work
	if _at_work:
		_choose_target()
	else:
		_destination = _rest_target()
		_follow_stroke = {}
		_path_hops = 0
		_route_or_direct()
	_update_visual_state()


## Entra o sale de la comida del mediodia. Mientras come vuelve a casa (igual
## que de noche); al acabar retoma el trabajo o el paseo.
func set_meal(eating: bool) -> void:
	if eating == _at_meal:
		return
	_at_meal = eating
	if _stay_home():
		_destination = _rest_target()
		_follow_stroke = {}
		_path_hops = 0
		_route_or_direct()
	else:
		_choose_target()
	_update_visual_state()


# True si toca estar en casa (de noche o comiendo).
func _stay_home() -> bool:
	return _resting or _at_meal


## [param fed_ratio] es 1.0 si comio todo lo que le tocaba, 0.0 si nada y un
## valor intermedio cuando el granero solo alcanzo para una parte. El dano
## escala con lo que le falto, en vez de tratarlo como hambruna total.
func daily_needs(fed_ratio: float) -> void:
	var fed := clampf(fed_ratio, 0.0, 1.0)
	if fed >= 1.0:
		hunger = maxf(0.0, hunger - 1.0)
		happiness = minf(100.0, happiness + 1.0)
	else:
		var lack := 1.0 - fed
		hunger = minf(100.0, hunger + 25.0 * lack)
		health = maxf(0.0, health - 5.0 * lack)
		happiness = maxf(0.0, happiness - 12.0 * lack)
	# Sin vivienda: penalizacion diaria de felicidad (no de salud).
	if not has_home:
		happiness = maxf(0.0, happiness - HOMELESS_HAPPINESS_PENALTY)
	_update_visual_state()


func is_working() -> bool:
	return work_name != ""


## True si esta en la jornada de trabajo Y ha llegado ya al puesto (esta a
## WORK_ARRIVAL o menos de el). Es lo que usa Villagers para no dar por
## trabajando a quien aun va de camino.
func is_at_work() -> bool:
	if not _at_work:
		return false
	var p := Vector2(global_position.x, global_position.z)
	return p.distance_to(work_position) <= WORK_ARRIVAL


func efficiency() -> float:
	return clampf((health / 100.0) * (happiness / 100.0), 0.0, 1.0)


## Estado legible del aldeano para el menu de la casa.
func mood_text() -> String:
	if _at_meal:
		return "Comiendo"
	if hunger > 10.0:
		return "Hambriento"
	if happiness < 40.0:
		return "Descontento"
	if health < 60.0:
		return "Enfermo"
	if _at_work:
		return "Trabajando"
	return "Descansando"


## Color que acompana a mood_text() (avatar y etiqueta).
func mood_color() -> Color:
	if _at_meal:
		return Color(0.96, 0.82, 0.34)
	if hunger > 10.0:
		return Color(0.85, 0.32, 0.24)
	if happiness < 40.0:
		return Color(0.92, 0.62, 0.25)
	if health < 60.0:
		return Color(0.85, 0.45, 0.55)
	if _at_work:
		return Color(0.42, 0.66, 0.95)
	return Color(0.45, 0.85, 0.5)


func _ready() -> void:
	_navigation_agent = NavigationAgent3D.new()
	_navigation_agent.path_desired_distance = ARRIVAL_DISTANCE
	_navigation_agent.target_desired_distance = ARRIVAL_DISTANCE
	_navigation_agent.avoidance_enabled = true
	add_child(_navigation_agent)
	_set_navigation_target()
	_build_visual()


func _process(delta: float) -> void:
	if _blocked_cooldown > 0.0:
		_blocked_cooldown -= delta
	var current := Vector2(global_position.x, global_position.z)
	# De noche, al llegar a casa el aldeano "entra" a dormir: se oculta el
	# modelo para que no se quede de pie en la puerta.
	if _visual != null:
		# Solo se oculta quien duerme DENTRO de una casa. En la hoguera los
		# aldeanos siguen a la vista, alrededor del fuego.
		_visual.visible = not (_resting and has_home \
			and current.distance_to(home_door_position) <= ARRIVAL_DISTANCE)

	if _wait_time > 0.0:
		_wait_time -= delta
		# Quieto en el puesto: gesto de agacharse a recoger (sembrar/cosechar).
		if _visual != null:
			if _at_work and not _stay_home():
				_pick_phase += delta * 7.0
				_visual.rotation.x = deg_to_rad(30.0) * maxf(0.0, sin(_pick_phase))
			else:
				_visual.rotation.x = 0.0
		return
	if _visual != null and _visual.rotation.x != 0.0:
		_visual.rotation.x = 0.0

	var arrive := ARRIVAL_DISTANCE if _follow_stroke.is_empty() else PATH_WAYPOINT_DISTANCE
	var distance := current.distance_to(_target)
	if distance <= arrive:
		_on_target_reached()
		return

	var navigation_target := _target
	if _navigation_agent != null and not _navigation_agent.is_navigation_finished():
		var next := _navigation_agent.get_next_path_position()
		var next_2d := Vector2(next.x, next.z)
		if next != Vector3.ZERO \
				and next_2d.distance_to(current) > ARRIVAL_DISTANCE \
				and next_2d.distance_to(_target) < current.distance_to(_target):
			navigation_target = next_2d
	var direction := current.direction_to(navigation_target)
	var speed := WALK_SPEED
	if Paths.instance != null:
		speed *= Paths.instance.speed_multiplier_at(current)
	# Puentes: sobre el agua se avanza a lo largo del eje del tablero (no en
	# diagonal, que sacaba al aldeano del ancho del puente y lo dejaba tirado en
	# la orilla). Si el paso recto cae al agua y hay un puente cerca, se va
	# hacia el eje del puente para subir a el por su extremo. Los aldeanos que
	# pasan cerca de un puente por tierra no se desvian.
	var bridge_now := {}
	if Bridges.instance != null:
		bridge_now = Bridges.instance.nearest_bridge(current, BRIDGE_TOL)
	var on_bridge_now := not bridge_now.is_empty()
	if on_bridge_now:
		speed = maxf(speed, WALK_SPEED * Bridges.SPEED_MULT)
	var step_ahead := current + direction * speed * delta
	if on_bridge_now and (Terrain.is_water(current) or Terrain.is_water(step_ahead)):
		var ba: Vector2 = bridge_now["a"]
		var bb: Vector2 = bridge_now["b"]
		var axis := (bb - ba).normalized()
		# Sentido: hacia el extremo del puente mas cercano al destino.
		if _target.distance_squared_to(ba) < _target.distance_squared_to(bb):
			axis = -axis
		direction = axis
	elif not on_bridge_now and Bridges.instance != null and Terrain.is_water(step_ahead):
		var near := Bridges.instance.nearest_bridge(current, PATH_SEEK_RADIUS)
		if not near.is_empty():
			var entry := Bridges.closest_point_on_bridge(near, current)
			if current.distance_squared_to(entry) > 0.0001:
				direction = current.direction_to(entry)
	var next := current + direction * speed * delta
	# Las vallas del campo no se atraviesan: si el paso cruza una, se desliza a
	# lo largo de ella (el hueco de la casa si deja pasar).
	next = _avoid_fences(current, next, direction, speed * delta)
	if next.distance_squared_to(current) < 0.000001:
		return
	direction = current.direction_to(next)
	var on_bridge_next := Bridges.instance != null and Bridges.instance.is_bridge(next, BRIDGE_TOL)
	# La guarda de agua no cancela un cruce valido por el puente (con tolerancia
	# para no atascarse si el punto de navegacion cae justo fuera del tablero).
	if Terrain.is_water(next) and not on_bridge_next and not on_bridge_now:
		# El navmesh no cubre el agua; sin esta guarda el aldeano puede meterse
		# en el mar o en un lago en linea recta cuando no hay ruta valida.
		# Con enfriamiento: si no, un aldeano atascado contra la orilla
		# replanificaba el destino en cada frame.
		if _blocked_cooldown <= 0.0:
			_blocked_cooldown = BLOCKED_RETRY
			# Si venia siguiendo un camino, reintenta su plan (los puntos del
			# camino nunca pisan agua) antes que abandonarlo y deambular.
			if not _route_via_path():
				_choose_target()
		return
	var ground_h := Terrain.height_at(next)
	if on_bridge_next:
		ground_h = Bridges.instance.deck_height_at(next, BRIDGE_TOL)
	elif on_bridge_now:
		ground_h = Bridges.instance.deck_height_at(current, BRIDGE_TOL)
	global_position = Vector3(next.x, ground_h, next.y)
	rotation.y = atan2(direction.x, direction.y)
	_walk_phase += delta * 10.0
	_visual.position.y = 0.02 + sin(_walk_phase) * 0.015


# Si el paso `current`->`next` cruza una valla de campo, devuelve el punto
# deslizado a lo largo de la valla (o `current` si no hay salida).
func _avoid_fences(current: Vector2, next: Vector2, direction: Vector2, step: float) -> Vector2:
	var normal := Buildings.fence_block_normal(current, next)
	if normal == Vector2.ZERO:
		return next
	var slide := direction - normal * direction.dot(normal)
	if slide.length_squared() < 0.0001:
		# De frente contra la valla: se elige el tangente que mas acerque al
		# destino para ir bordeandola en vez de quedarse clavado.
		var tangent := Vector2(-normal.y, normal.x)
		if tangent.dot(current.direction_to(_destination)) < 0.0:
			tangent = -tangent
		slide = tangent
	slide = slide.normalized()
	var alt := current + slide * step
	if Buildings.fence_block_normal(current, alt) != Vector2.ZERO:
		return current
	return alt


func _choose_target() -> void:
	_destination = _next_destination()
	_follow_stroke = {}
	_path_hops = 0
	_route_or_direct()


# Ir al destino en directo si no hay un camino razonable que ayude.
func _route_or_direct() -> void:
	var current := Vector2(global_position.x, global_position.z)
	# Si hay que entrar o salir de un campo, manda el paso por el hueco de la
	# casa (no se sigue un camino que pueda cruzar la valla). Son dos puntos de
	# paso, por fuera y por dentro, para que el cruce caiga en el hueco.
	var route := Buildings.gap_route(current, _destination)
	if not route.is_empty():
		_follow_stroke = {}
		_path_hops = 0
		_queue.clear()
		for p: Vector2 in route:
			_queue.append(p)
		_target = _queue.pop_front()
		_set_navigation_target()
		return
	_queue.clear()
	# Trabajando: va directo al puesto. Sin esto se enganchaba a un camino
	# cercano y se daba un paseo por la carretera en vez de quedarse.
	if _at_work and not _carrying:
		_follow_stroke = {}
		_target = _destination
		_set_navigation_target()
		return
	if _route_via_path():
		return
	_target = _destination
	_set_navigation_target()


# Destino final del modo actual: trabajo, casa/hoguera o deambulacion.
func _next_destination() -> Vector2:
	if _at_work:
		# Sin deambular: se queda en su puesto y hace el gesto de trabajar.
		return work_position
	if _stay_home():
		# Descanso o comida: casa o hoguera.
		return _rest_target()
	# Punto base de deambulacion: la plaza si la hay (reunion), si no la casa.
	var base := gathering_position if has_gathering else home_door_position
	var ref_dir := Vector2(0.0, -1.0) if has_gathering else home_exit_direction
	var side := Vector2(-ref_dir.y, ref_dir.x)
	for _attempt in 8:
		var candidate := base + ref_dir * randf_range(0.8, WANDER_RADIUS) \
			+ side * randf_range(-1.0, 1.0)
		if not Terrain.is_water(candidate):
			return candidate
	return base


# Intenta llevar al aldeano por un camino hacia `_destination`. Devuelve true si
# fijo un objetivo intermedio sobre el camino; false para navegar en directo.
func _route_via_path() -> bool:
	if Paths.instance == null or _path_hops >= MAX_PATH_HOPS:
		_follow_stroke = {}
		return false
	var current := Vector2(global_position.x, global_position.z)
	# 1) Continuar el tramo en curso si sigue existiendo y acercando al destino.
	if not _follow_stroke.is_empty() \
			and Paths.instance.has_stroke(int(_follow_stroke["id"])):
		var plan := Paths.instance.plan_along_stroke(
			_follow_stroke, current, _destination, PATH_LOOKAHEAD)
		if bool(plan["use"]):
			_path_hops += 1
			_target = plan["point"]
			_set_navigation_target()
			return true
	_follow_stroke = {}
	# 2) Elegir el mejor tramo cercano (incluye el siguiente tramo de la cadena).
	var choice := Paths.instance.plan_via_nearest(
		current, _destination, PATH_SEEK_RADIUS, PATH_LOOKAHEAD)
	if not bool(choice["use"]):
		return false
	_follow_stroke = choice["stroke"]
	_path_hops += 1
	_target = choice["point"]
	_set_navigation_target()
	return true


# Al alcanzar el objetivo actual: si era un punto intermedio del camino y este
# sigue siendo util, avanza al siguiente; si es el destino, cierra el trayecto.
func _on_target_reached() -> void:
	# Acarreando: al llegar al almacen (destino final) se entrega la carga.
	if _carrying and _target.distance_squared_to(_destination) <= 0.0001:
		_deliver()
		return
	# Quedan puntos de paso (hueco de la valla): va al siguiente.
	if not _queue.is_empty():
		_target = _queue.pop_front()
		_set_navigation_target()
		return
	# Destino final: no seguir enganchando caminos (evita dar vueltas al llegar).
	if _target.distance_squared_to(_destination) <= 0.0001:
		_follow_stroke = {}
		if _stay_home():
			# Ya en casa (noche o comida): se queda (reafirma el objetivo por si
			# lo empujan) en vez de buscar un nuevo punto y dar vueltas.
			_wait_time = randf_range(2.0, 5.0)
			_set_navigation_target()
			return
		_wait_time = randf_range(0.8, 2.5)
		_choose_target()
		return
	# Objetivo intermedio: seguir el camino, o ir en directo si ya no ayuda.
	if not _follow_stroke.is_empty() and _route_via_path():
		return
	_follow_stroke = {}
	_target = _destination
	_set_navigation_target()


## Estado interno del movimiento respecto a los caminos (depuracion).
func path_state() -> String:
	if not _follow_stroke.is_empty():
		return "siguiendo_camino"
	if Paths.instance != null and Paths.instance.is_path(Vector2(global_position.x, global_position.z)):
		return "sobre_camino"
	return "fuera_de_camino"


func _set_navigation_target() -> void:
	if _navigation_agent == null:
		return
	var y := Terrain.height_at(_target)
	if Bridges.instance != null and Bridges.instance.is_bridge(_target, BRIDGE_TOL):
		y = Bridges.instance.deck_height_at(_target, BRIDGE_TOL)
	_navigation_agent.target_position = Vector3(_target.x, y, _target.y)


# Meshes y materiales compartidos entre aldeanos: antes cada uno creaba sus
# propias CapsuleMesh/SphereMesh/BoxMesh y 3 materiales. El de la camiseta si
# es por aldeano, porque su color cambia con el estado (hambre/trabajo).
static var _shared_ready := false
static var _mesh_body: CapsuleMesh
static var _mesh_head: SphereMesh
static var _mesh_hair: SphereMesh
static var _mesh_leg: BoxMesh
static var _mat_skin: StandardMaterial3D
static var _mat_trousers: StandardMaterial3D
static var _mat_hair: StandardMaterial3D

static func _ensure_shared() -> void:
	if _shared_ready:
		return
	_mesh_body = CapsuleMesh.new()
	_mesh_body.radius = 0.13
	_mesh_body.height = 0.42
	_mesh_head = SphereMesh.new()
	_mesh_head.radius = 0.12
	_mesh_head.height = 0.24
	_mesh_hair = SphereMesh.new()
	_mesh_hair.radius = 0.125
	_mesh_hair.height = 0.13
	_mesh_leg = BoxMesh.new()
	_mesh_leg.size = Vector3(0.09, 0.25, 0.09)
	_mat_skin = _make_material(Color(0.82, 0.58, 0.42))
	_mat_trousers = _make_material(Color(0.16, 0.19, 0.25))
	_mat_hair = _make_material(Color(0.18, 0.10, 0.06))
	_shared_ready = true


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.position.y = 0.02
	_visual.scale = VISUAL_SCALE
	add_child(_visual)

	_ensure_shared()
	_shirt_material = _make_material(Color(0.25, 0.42, 0.62))

	_add_part(_mesh_body, _shirt_material, Vector3(0, 0.32, 0))
	_add_part(_mesh_head, _mat_skin, Vector3(0, 0.66, 0))
	_add_part(_mesh_hair, _mat_hair, Vector3(0, 0.73, 0))
	_add_part(_mesh_leg, _mat_trousers, Vector3(-0.07, 0.08, 0))
	_add_part(_mesh_leg, _mat_trousers, Vector3(0.07, 0.08, 0))

	# Cajon de acarreo: oculto hasta que el aldeano lleva una carga de comida.
	var crate := BoxMesh.new()
	crate.size = Vector3(0.30, 0.24, 0.30)
	var crate_mi := MeshInstance3D.new()
	crate_mi.mesh = crate
	crate_mi.material_override = _make_material(Color(0.72, 0.52, 0.28))
	_carry_visual = Node3D.new()
	_carry_visual.add_child(crate_mi)
	_carry_visual.position = Vector3(0.0, 0.50, 0.16)
	_carry_visual.visible = false
	_visual.add_child(_carry_visual)

	_update_visual_state()


func _update_visual_state() -> void:
	if _shirt_material == null:
		return
	if _at_meal:
		_shirt_material.albedo_color = Color(0.95, 0.80, 0.35)
	elif hunger > 10.0:
		_shirt_material.albedo_color = Color(0.65, 0.20, 0.16)
	elif not has_home:
		_shirt_material.albedo_color = HOMELESS_SHIRT_COLOR
	elif _at_work:
		_shirt_material.albedo_color = Color(0.25, 0.42, 0.62)
	else:
		_shirt_material.albedo_color = Color(0.30, 0.55, 0.32)


func _add_part(mesh: Mesh, material: Material, local_position: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = local_position
	_visual.add_child(instance)


static func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material
