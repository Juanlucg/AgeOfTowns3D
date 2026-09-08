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
var field: Node3D = null         # granjas: mesh del campo de cultivo (hijo de Buildings, no del edificio)
var timer: float = 0.0          # segundos desde la ultima produccion
var amount: float = 0.0         # override de BuildingDef.prod_amount (granjas con campo)
var crop: String = ""           # tipo de cultivo en granjas (trigo/zanahoria/bayas), "" si no aplica
var dev: bool = false            # modo dev: gratis y sin produccion


func _init(p_type: StringName = &"", p_pos: Vector2 = Vector2.ZERO, p_yaw: float = 0.0, p_node: Node3D = null, p_dev: bool = false) -> void:
	type = p_type
	pos = p_pos
	yaw = p_yaw
	node = p_node
	dev = p_dev
