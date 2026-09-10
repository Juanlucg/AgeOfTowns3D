extends Node
# Economia y almacenamiento del pueblo: cantidades de recursos, capacidad de
# almacenaje y definiciones de costes de construccion.
# Emite "changed" cada vez que cambia algo para que el HUD se refresque.
#
# Almacenaje por RECURSO, no por total:
#   - Comida: capacidad = BASE_STORAGE + granary_count * GRANARY_STORAGE
#     (los graneros amplian la capacidad SOLO de comida).
#   - Otros recursos (madera, piedra, futuros como herramientas): capacidad
#     = BASE_STORAGE, sin bonificacion de graneros.
# Asi puedes acumular madera aunque la comida este al tope (antes la
# capacidad era global y un solo recurso al tope bloqueaba los demas).
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
# Comida va al granero; el resto al almacen tradicional. Si anades un
# recurso nuevo (herramientas, etc.) que no sea "comida", va al almacen
# tradicional sin bonificacion.
const FOOD_RESOURCE := "comida"

var amounts := {"madera": 40.0, "piedra": 25.0, "comida": 20.0}
var granary_count := 0

var _day_night: DayNightCycle = null


func bind_day_night(dn: DayNightCycle) -> void:
	if _day_night != null:
		_day_night.day_changed.disconnect(_on_day_changed)
	_day_night = dn
	if _day_night != null:
		_day_night.day_changed.connect(_on_day_changed)


# Capacidad y uso POR RECURSO. La comida crece con los graneros; el resto no.
func storage_capacity_for(resource: StringName) -> float:
	if resource == FOOD_RESOURCE:
		return BASE_STORAGE + granary_count * GRANARY_STORAGE
	return BASE_STORAGE


func storage_used_for(resource: StringName) -> float:
	return amounts.get(resource, 0.0)


# Compatibilidad: el HUD antiguo y el tooltip de edificios usan estas para
# mostrar "X/Y". Como ahora la capacidad es por recurso, devolvemos
# comida (el unico recurso donde la capacidad cambia con edificios).
func storage_capacity() -> float:
	return storage_capacity_for(FOOD_RESOURCE)


func storage_used() -> float:
	return storage_used_for(FOOD_RESOURCE)


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
# Pasa por add(), asi que respeta la capacidad POR RECURSO: si la comida
# se lleno mientras tanto, se devuelve lo que quepa de comida y el resto
# del reembolso se pierde. Antes los sitios de llamada tocaban `amounts`
# a mano y podian dejar el almacen por encima de su capacidad.
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
		add(FOOD_RESOURCE, DAILY_FOOD)
