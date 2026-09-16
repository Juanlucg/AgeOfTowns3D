extends Resource
class_name BuildingDef
## Definicion inmutable de un tipo de edificio: coste, produccion, huella,
## biomas validos y pista visual.
##
## Reemplaza el antiguo Dictionary en [Buildings]. Como Resource, se puede
## guardar como [code].tres[/code] y editar desde el inspector.

enum Biome { LLANURA = 0, BOSQUE = 1, MONTANA = 2 }

## Fuente unica de los nombres de bioma (antes estaba duplicado en Buildings,
## BuildingTooltip y BuildingInfoMenu).
const BIOME_NAMES := {
	0: "llanura",
	1: "bosque",
	2: "montaña",
}
const BIOME_BY_NAME := {
	"llanura": 0,
	"bosque": 1,
	"montaña": 2,
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""              # texto largo en el menu contextual
@export var cost: Dictionary = {}              # {"madera": 25.0, ...}
@export var prod_resource: StringName = &""     # "" = no produce
@export var prod_amount: float = 0.0
@export var prod_interval: float = 0.0          # segundos entre producciones
@export var footprint: float = 1.0              # tamano del solar (m)
@export var biomes: Array[Biome] = []
@export var hint: String = ""
@export var color: Color = Color.WHITE
# Capacidad mostrada en el menu (granero = 300 de comida, etc.). 0 = oculta.
@export var capacity: int = 0
@export var capacity_resource: StringName = &"" # recurso que llena la capacidad
# Numero de trabajadores mostrados en el menu. 0 = sin panel de trabajadores.
@export var worker_count: int = 0
@export var worker_names: PackedStringArray = PackedStringArray()
@export var housing_capacity: int = 0
# Felicidad diaria que aporta a cada aldeano (plaza).
@export var happiness_bonus: float = 0.0
# Necesaria para que lleguen aldeanos nuevos (crecimiento).
@export var attracts_growth: bool = false
# Punto de reunion: los aldeanos sin trabajo se juntan aqui de dia.
@export var gathering_point: bool = false
# Radio de la zona de actuacion (aserradero). 0 = sin zona. Dos edificios con
# zona no pueden solaparla.
@export var work_radius: float = 0.0
# Orden en el menu de construccion (menor primero). Determina tambien que
# atajo 1-7 le corresponde.
@export var order: int = 0
# Desfase en grados de la fachada segun el modelo. Los procedurales tienen la
# puerta en -Z (0); la casa importada al contrario (180).
@export var facade_offset: float = 0.0
# Almacen que amplia al construirse: "" (ninguno), "granary" (comida) o
# "warehouse" (resto). Antes se decidia con if type == &"granero"/&"almacen".
@export var storage_kind: StringName = &""
# Edificio de dos pasos: tras colocarlo se delimita un campo de cultivo.
@export var has_field: bool = false


# Helpers que Buildings.gd usaba implicitamente.
func can_produce() -> bool:
	return prod_resource != &"" and prod_interval > 0.0


func cost_text() -> String:
	var parts := []
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), k])
	return ", ".join(parts)


func biomes_text() -> String:
	var out := []
	for b in biomes:
		out.append(BIOME_NAMES.get(b, str(b)))
	return ", ".join(out)
