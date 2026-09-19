extends MultiMeshInstance3D
class_name CropField
## Los cultivos de un huerto, con crecimiento: se plantan como brotes bajos y
## verdes y acaban como espigas altas del color del cultivo (trigo dorado,
## zanahoria naranja, bayas rojas).
##
## El MultiMesh no se rehace nunca: solo se reescriben los transforms de las
## instancias (altura, anchura y giro) y el color del material. Y no en cada
## frame: solo cuando el crecimiento avanza [constant GROWTH_STEP], que en un
## ciclo completo son unas 50 actualizaciones. Cuando el cultivo esta maduro el
## nodo se quita del bucle de proceso; al cosecharlo, [method replant] lo vuelve
## a sembrar y a poner en proceso.

## Segundos que tarda un cultivo en madurar del todo si no se indica otro.
const DEFAULT_GROW_SECONDS := 150.0
## Cuanto tiene que avanzar el crecimiento para volver a escribir los transforms.
const GROWTH_STEP := 0.02
## Color del brote recien plantado. El maduro lo pone quien lo siembra.
const SPROUT_COLOR := Color(0.42, 0.66, 0.27)
## Altura y anchura del brote, como fraccion de la planta madura.
const SPROUT_HEIGHT := 0.20
const SPROUT_WIDTH := 0.60

var ripe_color := Color.WHITE

var _plant_height := 0.34
var _base := PackedVector3Array()      # (x, suelo, z) de cada planta, en local
var _height_var := PackedFloat32Array()
var _yaw := PackedFloat32Array()
# Posicion de cada planta en el orden de recogida: de la mas cercana al centro
# del campo (donde estan los aldeanos) hacia fuera.
var _rank := PackedInt32Array()
var _age := 0.0
var _applied := -1.0
var _grow_seconds := DEFAULT_GROW_SECONDS
## Plantas ya recogidas (no se dibujan). Lo lleva Buildings mientras los
## aldeanos cosechan; en vez del progreso, se guarda el numero entero para
## reescribir los transforms solo cuando cambia.
var _harvested := 0
var _mat: StandardMaterial3D


## `bases` lleva la posicion de cada planta en coordenadas del campo, con la Y
## a ras de suelo: la planta se apoya encima, no se centra ahi.
## `grow_seconds` es el tiempo que tarda este cultivo en madurar; cada cultivo
## (trigo, zanahoria, bayas) tiene el suyo.
func setup(
	plant_height: float,
	bases: PackedVector3Array,
	height_var: PackedFloat32Array,
	yaws: PackedFloat32Array,
	color: Color,
	grow_seconds: float = DEFAULT_GROW_SECONDS
) -> void:
	_plant_height = plant_height
	_base = bases
	_height_var = height_var
	_yaw = yaws
	ripe_color = color
	_grow_seconds = maxf(0.1, grow_seconds)
	_build_harvest_rank()
	_mat = StandardMaterial3D.new()
	_mat.roughness = 1.0
	# Permite que el color por instancia del MultiMesh (textura de tonos) module
	# el color del cultivo. Los MultiMesh sin colores usan blanco y no cambian.
	_mat.vertex_color_use_as_albedo = true
	material_override = _mat
	_apply(0.0)


## True cuando el cultivo ha crecido del todo. A partir de ahi la granja puede
## cosecharlo (ver Buildings._update_farms) y volver a sembrarlo con replant().
func is_mature() -> bool:
	return _age >= _grow_seconds


# Ordena las plantas por profundidad (eje z local): la cosecha empieza por la
# franja pegada a la casa (-z) y avanza hacia el fondo (+z), como si los
# aldeanos entraran por el hueco de la casa y fueran limpiando el campo.
func _build_harvest_rank() -> void:
	var order: Array[int] = []
	for i in _base.size():
		order.append(i)
	var bases := _base
	order.sort_custom(func(a: int, b: int) -> bool:
		return bases[a].z < bases[b].z)
	_rank.resize(_base.size())
	for k in order.size():
		_rank[order[k]] = k


## Progreso de cosecha 0..1: oculta las plantas ya recogidas (por filas, que es
## el orden en que se sembraron). No toca el crecimiento. Se sale sin trabajo
## si el numero entero de plantas recogidas no cambio.
func set_harvest(t: float) -> void:
	var count := int(round(clampf(t, 0.0, 1.0) * float(_base.size())))
	if count == _harvested:
		return
	_harvested = count
	_apply(maxf(_applied, 0.0))


## Deja el campo pelado tras cosechar: todos los brotes ocultos y sin crecer.
## Los va mostrando Buildings mientras los granjeros siembran (set_harvest de 1
## a 0, que revela del fondo hacia la casa).
func replant() -> void:
	_age = 0.0
	_applied = -1.0
	_harvested = _base.size()
	_apply(0.0)
	set_process(false)


## Reanuda el crecimiento una vez terminada la siembra.
func begin_growth() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _applied >= 1.0:
		set_process(false)
		return
	_age += delta
	var g: float = clampf(_age / _grow_seconds, 0.0, 1.0)
	if g < 1.0 and g - _applied < GROWTH_STEP:
		return
	_apply(g)


func _apply(g: float) -> void:
	_applied = g
	# El verdor aguanta un poco antes de empezar a dorarse.
	_mat.albedo_color = SPROUT_COLOR.lerp(ripe_color, smoothstep(0.2, 1.0, g))
	var sy: float = lerpf(SPROUT_HEIGHT, 1.0, g)
	var sxz: float = lerpf(SPROUT_WIDTH, 1.0, g)
	var mm := multimesh
	# Se ocultan con escala cero las plantas ya recogidas (las mas cercanas al
	# centro primero, segun _rank).
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in _base.size():
		var b: Vector3 = _base[i]
		if i < _rank.size() and _rank[i] < _harvested:
			mm.set_instance_transform(i, hidden)
			continue
		var hs: float = sy * _height_var[i]
		var basis := Basis(Vector3.UP, _yaw[i]).scaled(Vector3(sxz, hs, sxz))
		# La malla de la planta esta centrada en su origen, asi que hay que
		# subirla media altura para que se apoye en el suelo en vez de quedar
		# medio enterrada.
		mm.set_instance_transform(i, Transform3D(
			basis, Vector3(b.x, b.y + _plant_height * hs * 0.5, b.z)))
