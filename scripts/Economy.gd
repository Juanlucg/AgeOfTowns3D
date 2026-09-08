extends Node
# Economia y almacenamiento del pueblo: cantidades de recursos, capacidad de
# almacenaje (base + graneros) y definiciones de costes de construccion.
# Emite "changed" cada vez que cambia algo para que el HUD se refresque.
#
# Antes buscaba DayNightCycle cada frame por ruta absoluta. Ahora recibe la
# dependencia via bind() desde Main.gd y reacciona a la senal `day_changed`.
#
# Nota: este script se monta como autoload con el nombre "Economy" en
# project.godot. No se anade `class_name Economy` porque colisionaria con el
# singleton del autoload (el autoload ya provee `Economy` como global).

signal changed

const RESOURCE_NAMES := ["madera", "piedra", "comida"]
const RESOURCE_COLORS := {
	"madera": Color(0.62, 0.42, 0.22),
	"piedra": Color(0.55, 0.55, 0.58),
	"comida": Color(0.55, 0.72, 0.30),
}
const BASE_STORAGE := 200.0
const GRANARY_STORAGE := 50.0
const DAILY_FOOD := 3.0

var amounts := {"madera": 40.0, "piedra": 25.0, "comida": 20.0}
var granary_count := 0

var _day_night: DayNightCycle = null


func bind_day_night(dn: DayNightCycle) -> void:
	if _day_night != null:
		_day_night.day_changed.disconnect(_on_day_changed)
	_day_night = dn
	if _day_night != null:
		_day_night.day_changed.connect(_on_day_changed)


func storage_capacity() -> float:
	return BASE_STORAGE + granary_count * GRANARY_STORAGE


func storage_used() -> float:
	var total := 0.0
	for k in amounts:
		total += amounts[k]
	return total


# Suma recursos respetando la capacidad de almacenaje. Devuelve lo realmente
# anadido (puede ser menos que `amount` si el almacen esta lleno).
func add(type: String, amount: float) -> float:
	if not amounts.has(type) or amount <= 0.0:
		return 0.0
	var room := maxf(0.0, storage_capacity() - storage_used())
	var added := minf(amount, room)
	amounts[type] += added
	if added > 0.0:
		changed.emit()
	return added


func spend(type: String, amount: float) -> bool:
	if amounts.get(type, 0.0) < amount:
		return false
	amounts[type] -= amount
	changed.emit()
	return true


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if amounts.get(k, 0.0) < cost[k]:
			return false
	return true


# Devuelve un coste ya cobrado (p.ej. cancelar una construccion a medias).
# Pasa por add(), asi que respeta la capacidad de almacenaje: si el almacen se
# lleno mientras tanto, se devuelve lo que quepa y no mas. Antes los sitios de
# llamada tocaban `amounts` a mano y podian dejar el almacen por encima de su
# capacidad.
func refund(cost: Dictionary) -> void:
	for k in cost:
		add(k, cost[k])


func spend_all(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		amounts[k] -= cost[k]
	changed.emit()
	return true


func _on_day_changed(day: int) -> void:
	if day > 0:
		add("comida", DAILY_FOOD)
