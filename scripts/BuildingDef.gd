extends Resource
class_name BuildingDef
## Definicion inmutable de un tipo de edificio: coste, produccion, huella,
## biomas validos y pista visual.
##
## Reemplaza el antiguo Dictionary en [Buildings]. Como Resource, se puede
## guardar como [code].tres[/code] y editar desde el inspector.

enum Biome { LLANURA = 0, BOSQUE = 1, MONTANA = 2 }

@export var id: StringName = &""
@export var display_name: String = ""
@export var cost: Dictionary = {}              # {"madera": 25.0, ...}
@export var prod_resource: StringName = &""     # "" = no produce
@export var prod_amount: float = 0.0
@export var prod_interval: float = 0.0          # segundos entre producciones
@export var footprint: float = 1.0              # tamano del solar (m)
@export var biomes: Array[Biome] = []
@export var hint: String = ""
@export var color: Color = Color.WHITE


# Helpers que Buildings.gd usaba implicitamente.
func can_produce() -> bool:
	return prod_resource != &"" and prod_interval > 0.0


func cost_text() -> String:
	var parts := []
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), k])
	return ", ".join(parts)


func biomes_text(biome_names: Dictionary) -> String:
	var out := []
	for b in biomes:
		out.append(biome_names.get(b, str(b)))
	return ", ".join(out)
