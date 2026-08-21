extends Node
# Economia y almacenamiento del pueblo: cantidades de recursos, capacidad de
# almacenaje (base + graneros) y definiciones de costes de construccion.
# Emite "changed" cada vez que cambia algo para que el HUD se refresque.

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
var _last_day := -1
var _day_node: Node = null


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


func spend_all(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		amounts[k] -= cost[k]
	changed.emit()
	return true


func _process(_delta: float) -> void:
	if _day_node == null:
		_day_node = get_node_or_null("/root/Main/DayNightCycle")
		if _day_node == null:
			return
	var day: int = _day_node.get_day()
	if day != _last_day:
		_last_day = day
		if day > 0:
			add("comida", DAILY_FOOD)