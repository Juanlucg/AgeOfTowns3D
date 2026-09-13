extends Node3D
class_name Villagers
## Gestiona los aldeanos asociados a las casas construidas.

const VILLAGER_SCRIPT := preload("res://scripts/Villager.gd")
const VILLAGERS_PER_HOUSE := 2
const FOOD_PER_VILLAGER_PER_DAY := 1.0

@export var buildings_path: NodePath
@export var day_night_path: NodePath

signal population_changed(population: int, housing: int, workers: int)
signal message_requested(text: String)
signal workers_changed(position: Vector2, count: int)
signal worker_efficiency_changed(position: Vector2, efficiency: float)

var _buildings: Buildings
var _day_night: DayNightCycle
var _villagers: Array = []
var _manual_free: Array = []
var _house_groups: Dictionary = {}
var _work_groups: Dictionary = {}
var _daytime := true


func _ready() -> void:
	_buildings = get_node_or_null(buildings_path) as Buildings
	if _buildings == null:
		push_error("Villagers: buildings_path no apunta a un Buildings")
		return
	_buildings.building_built.connect(_on_building_built)
	_buildings.building_demolished.connect(_on_building_demolished)
	_day_night = get_node_or_null(day_night_path) as DayNightCycle
	if _day_night != null:
		_day_night.day_changed.connect(_on_day_changed)
		_day_night.time_changed.connect(_on_time_changed)


func _on_building_built(type: StringName, pos: Vector2) -> void:
	var def := _buildings.get_def(type)
	if def == null:
		return
	if type == &"casa":
		_spawn_household(pos)
	elif def.worker_count > 0:
		_work_groups[pos] = {
			"position": pos,
			"type": type,
			"capacity": def.worker_count,
			"name": def.display_name,
			"workers": [],
		}
	_reassign_workers()


func _on_building_demolished(type: StringName, pos: Vector2) -> void:
	if type == &"casa":
		var household: Array = _house_groups.get(pos, [])
		for villager in household:
			if is_instance_valid(villager):
				_villagers.erase(villager)
				_manual_free.erase(villager)
				villager.queue_free()
		_house_groups.erase(pos)
	elif _work_groups.has(pos):
		_work_groups.erase(pos)
	_reassign_workers()


func _spawn_household(home: Vector2) -> void:
	var household: Array = []
	var door_offset := _house_door_offset(home)
	for index in VILLAGERS_PER_HOUSE:
		var villager := VILLAGER_SCRIPT.new()
		var side := _house_side_offset(home, -0.18 if index == 0 else 0.18)
		var offset := door_offset + side
		villager.initialize(home, offset, door_offset)
		add_child(villager)
		household.append(villager)
		_villagers.append(villager)
	_house_groups[home] = household


func _on_day_changed(_day: int) -> void:
	var fed := _consume_daily_food()
	if fed:
		_try_new_arrival()
	_reassign_workers()


func _on_time_changed(_day: int, _season: int, hour: float, _weather: String) -> void:
	var daytime := hour >= 7.0 and hour < 19.0
	if daytime == _daytime:
		return
	_daytime = daytime
	for villager in _villagers:
		if is_instance_valid(villager):
			villager.set_work_schedule(_daytime)


func _consume_daily_food() -> bool:
	var required := _villagers.size() * FOOD_PER_VILLAGER_PER_DAY
	var fed := Economy.consume_food(required)
	for villager in _villagers:
		if is_instance_valid(villager):
			villager.daily_needs(fed)
	if not fed and required > 0.0:
		message_requested.emit("Falta comida: los aldeanos pasan hambre")
	return fed


func _try_new_arrival() -> void:
	var available_house := Vector2.INF
	for home in _house_groups:
		var def := _buildings.get_def(&"casa")
		if def != null and (_house_groups[home] as Array).size() < def.housing_capacity:
			available_house = home
			break
	if available_house == Vector2.INF:
		return
	var villager := VILLAGER_SCRIPT.new()
	var door_offset := _house_door_offset(available_house)
	villager.initialize(available_house, door_offset, door_offset)
	add_child(villager)
	(_house_groups[available_house] as Array).append(villager)
	_villagers.append(villager)
	message_requested.emit("Ha llegado un nuevo aldeano")


func _house_door_offset(home: Vector2) -> Vector2:
	var record := _buildings.building_at(home)
	if record == null:
		return Vector2(0.0, -0.7)
	var yaw := deg_to_rad(record.yaw)
	# La puerta de la casa importada mira hacia su -Z local.
	return Vector2(-sin(yaw), -cos(yaw)) * 0.7


func _house_side_offset(home: Vector2, amount: float) -> Vector2:
	var record := _buildings.building_at(home)
	if record == null:
		return Vector2(amount, 0.0)
	var yaw := deg_to_rad(record.yaw)
	return Vector2(cos(yaw), -sin(yaw)) * amount


func _reassign_workers() -> void:
	for group in _work_groups.values():
		group["workers"] = []
	for villager in _villagers:
		if not is_instance_valid(villager) or not villager.is_working():
			continue
		var group: Variant = _group_at(villager.work_position)
		if group == null:
			villager.clear_work()
		else:
			(group["workers"] as Array).append(villager)
	for group in _work_groups.values():
		while (group["workers"] as Array).size() < group["capacity"]:
			var villager: Variant = _find_free_villager()
			if villager == null:
				break
			villager.assign_work(group["position"], group["name"])
			villager.set_work_schedule(_daytime)
			(group["workers"] as Array).append(villager)
		_emit_group_workers(group)
	_emit_population()


func assign_free_worker(position: Vector2) -> bool:
	var group: Variant = _group_at(position)
	if group == null or (group["workers"] as Array).size() >= group["capacity"]:
		return false
	var villager: Variant = _find_free_villager(true)
	if villager == null:
		return false
	_manual_free.erase(villager)
	villager.assign_work(position, group["name"])
	villager.set_work_schedule(_daytime)
	(group["workers"] as Array).append(villager)
	_emit_group_workers(group)
	_emit_population()
	return true


func release_worker(position: Vector2) -> bool:
	var group: Variant = _group_at(position)
	if group == null or (group["workers"] as Array).is_empty():
		return false
	var villager = (group["workers"] as Array).pop_back()
	villager.clear_work()
	if not _manual_free.has(villager):
		_manual_free.append(villager)
	_emit_group_workers(group)
	_emit_population()
	return true


func _find_free_villager(include_manual := false) -> Variant:
	for villager in _villagers:
		if is_instance_valid(villager) and not villager.is_working() \
				and (include_manual or not _manual_free.has(villager)):
			return villager
	return null


func _group_at(position: Vector2) -> Variant:
	for key in _work_groups:
		if key.is_equal_approx(position):
			return _work_groups[key]
	return null


func _emit_group_workers(group: Dictionary) -> void:
	var workers: Array = group["workers"]
	workers_changed.emit(group["position"], workers.size())
	var efficiency := 0.0
	for villager in workers:
		efficiency += villager.efficiency()
	if not workers.is_empty():
		efficiency /= workers.size()
	worker_efficiency_changed.emit(group["position"], efficiency)


func _emit_population() -> void:
	var housing := 0
	for _home in _house_groups:
		var def := _buildings.get_def(&"casa")
		if def != null:
			housing += def.housing_capacity
	var workers := 0
	for group in _work_groups.values():
		workers += (group["workers"] as Array).size()
	population_changed.emit(_villagers.size(), housing, workers)


func refresh_population() -> void:
	_emit_population()
