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
## nodo se quita del bucle de proceso.

## Segundos que tarda un cultivo en madurar del todo.
const GROW_SECONDS := 150.0
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
var _age := 0.0
var _applied := -1.0
var _mat: StandardMaterial3D


## `bases` lleva la posicion de cada planta en coordenadas del campo, con la Y
## a ras de suelo: la planta se apoya encima, no se centra ahi.
func setup(
	plant_height: float,
	bases: PackedVector3Array,
	height_var: PackedFloat32Array,
	yaws: PackedFloat32Array,
	color: Color
) -> void:
	_plant_height = plant_height
	_base = bases
	_height_var = height_var
	_yaw = yaws
	ripe_color = color
	_mat = StandardMaterial3D.new()
	_mat.roughness = 1.0
	material_override = _mat
	_apply(0.0)


func _process(delta: float) -> void:
	if _applied >= 1.0:
		set_process(false)
		return
	_age += delta
	var g: float = clampf(_age / GROW_SECONDS, 0.0, 1.0)
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
	for i in _base.size():
		var b: Vector3 = _base[i]
		var hs: float = sy * _height_var[i]
		var basis := Basis(Vector3.UP, _yaw[i]).scaled(Vector3(sxz, hs, sxz))
		# La malla de la planta esta centrada en su origen, asi que hay que
		# subirla media altura para que se apoye en el suelo en vez de quedar
		# medio enterrada.
		mm.set_instance_transform(i, Transform3D(
			basis, Vector3(b.x, b.y + _plant_height * hs * 0.5, b.z)))
