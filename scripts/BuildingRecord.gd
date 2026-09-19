extends RefCounted
class_name BuildingRecord
## Registro inmutable de un edificio colocado: tipo, posicion, yaw, nodo,
## estado de produccion, cultivo (granjas) y flag dev.
##
## Antes [member Buildings._placed] era Array de Dictionary sin tipos.
## Ahora es Array[BuildingRecord]: autocompletado, tipos en compile-time,
## facil de serializar para save/load futuro.

var type: StringName = &""
var pos: Vector2 = Vector2.ZERO
var yaw: float = 0.0
var node: Node3D = null
var field: Node3D = null         # granjas: mesh del campo de cultivo (hijo de Buildings)
var crops: CropField = null      # granjas: cultivos del campo (hijo de field), para saber si maduran
var field_min: Vector2 = Vector2.ZERO  # esquina inferior-izda del campo en mundo
var field_max: Vector2 = Vector2.ZERO  # esquina superior-dcha del campo en mundo
var field_area: float = 0.0     # granjas: m2 sembrados (para recalcular al cambiar de cultivo)
var field_center: Vector2 = Vector2.ZERO  # granjas: centro del campo (para reconstruirlo)
var field_size: Vector2 = Vector2.ZERO    # granjas: tamano sembrado (ancho x fondo)
var timer: float = 0.0          # segundos desde la ultima produccion
var amount: float = 0.0         # override de BuildingDef.prod_amount (granjas con campo)
var crop: String = ""           # tipo de cultivo en granjas (trigo/zanahoria/bayas), "" si no aplica
var harvest: float = 0.0         # granjas: trigo ya quitado 0..1 (limitado a los granjeros)
var harvest_time: float = 0.0    # granjas: avance deseado 0..1 (por tiempo)
var worker_positions := PackedVector2Array()  # granjas: posicion de los granjeros presentes
var pending: float = 0.0         # granjas: comida cosechada esperando a que un aldeano la acarree
var planting: float = 1.0        # granjas: progreso de siembra 0..1 (1 = no hay siembra pendiente)
var spread_harvest: float = -1.0  # granjas: frente (m) en que se repartio a los granjeros; -1 = en la casa
var dev: bool = false            # modo dev: gratis y sin produccion
var workers: int = 0             # aldeanos asignados al edificio
var workers_present: int = 0     # de los asignados, cuantos han llegado al puesto
var worker_efficiency: float = 1.0


func _init(p_type: StringName = &"", p_pos: Vector2 = Vector2.ZERO, p_yaw: float = 0.0, p_node: Node3D = null, p_dev: bool = false) -> void:
	type = p_type
	pos = p_pos
	yaw = p_yaw
	node = p_node
	dev = p_dev
