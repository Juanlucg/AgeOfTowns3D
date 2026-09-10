extends Node
# Economia y almacenamiento del pueblo: cantidades de recursos, capacidad
# de almacenaje y registro de produccion por recurso.
# Emite "changed" cada vez que cambia algo para que el HUD se refresque.
#
# Almacenaje POR RECURSO, con dos almacenes fisicos:
#   - Comida: capacidad = BASE_STORAGE + granary_count * GRANARY_STORAGE
#     (los graneros amplian la capacidad SOLO de comida).
#   - Resto (madera, piedra, futuros como herramientas): capacidad =
#     BASE_STORAGE + warehouse_count * WAREHOUSE_STORAGE (los almacenes
#     tradicionales amplian el resto). Los graneros NO afectan al resto.
# Asi puedes acumular madera aunque la comida este al tope.
#
# Ritmo de produccion por recurso (unidades/segundo) lo mantienen los
# Buildings via add_production / remove_production al colocar/demoler.
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
const BASE_STORAGE := 200.0          # base comun para comida y resto
const GRANARY_STORAGE := 50.0       # +50 comida por granero
const WAREHOUSE_STORAGE := 200.0    # +200 al resto por almacen
const DAILY_FOOD := 3.0
# Comida va al granero; el resto al almacen tradicional. Si anades un
# recurso nuevo (herramientas, etc.) que no sea "comida", va al almacen
# tradicional sin bonificacion.
const FOOD_RESOURCE := "comida"

var amounts := {"madera": 40.0, "piedra": 25.0, "comida": 20.0}
var granary_count := 0
var warehouse_count := 0
# Produccion neta por recurso en unidades/segundo. La mantienen los
# Buildings al colocar/demoler; el HUD la lee para mostrar "+X.X/s".
var _production_rates: Dictionary = {}

var _day_night: DayNightCycle = null


func bind_day_night(dn: DayNightCycle) -> void:
	if _day_night != null:
		_day_night.day_changed.disconnect(_on_day_changed)
	_day_night = dn
	if _day_night != null:
		_day_night.day_changed.connect(_on_day_changed)


# Capacidad POR RECURSO. La comida crece con graneros; el resto con almacenes.
func storage_capacity_for(resource: StringName) -> float:
	if resource == FOOD_RESOURCE:
		return BASE_STORAGE + granary_count * GRANARY_STORAGE
	return BASE_STORAGE + warehouse_count * WAREHOUSE_STORAGE


# Capacidad total (suma de todas las caps por recurso). Lo que ve la
# barra de storage del HUD y el tooltip con el desglose.
func storage_capacity() -> float:
	var total := 0.0
	for k in RESOURCE_NAMES:
		total += storage_capacity_for(k)
	return total


func storage_used_for(resource: StringName) -> float:
	return amounts.get(resource, 0.0)


func storage_used() -> float:
	var total := 0.0
	for k in amounts:
		total += amounts[k]
	return total


# Suma recursos respetando la capacidad POR RECURSO. Devuelve lo realmente
# anadido (puede ser menos que `amount` si el almacen de ese recurso esta
# lleno). Asi, un granero lleno de comida no bloquea la entrada de madera.
func add(type: String, amount: float) -> float:
	if not amounts.has(type) or amount <= 0.0:
		return 0.0
	var room := maxf(0.0, storage_capacity_for(type) - storage_used_for(type))
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
# Pasa por add(), asi que respeta la capacidad POR RECURSO.
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


# Produccion neta (unidades/segundo) por recurso. La gestionan los Buildings
# al colocar/demoler; el HUD solo la lee.
func add_production(resource: StringName, rate: float) -> void:
	if rate <= 0.0:
		return
	_production_rates[resource] = _production_rates.get(resource, 0.0) + rate


func remove_production(resource: StringName, rate: float) -> void:
	if rate <= 0.0:
		return
	_production_rates[resource] = _production_rates.get(resource, 0.0) - rate


func production_rate(resource: StringName) -> float:
	return _production_rates.get(resource, 0.0)


func _on_day_changed(day: int) -> void:
	if day > 0:
		add(FOOD_RESOURCE, DAILY_FOOD)
