extends Node3D
## Aldeano basico: vive en una casa y se mueve por sus alrededores.

const WALK_SPEED := 0.7
const WANDER_RADIUS := 3.0
const ARRIVAL_DISTANCE := 0.18
const VISUAL_SCALE := Vector3(0.35, 0.35, 0.35)

var home_position := Vector2.ZERO
var home_door_position := Vector2.ZERO
var home_exit_direction := Vector2(0.0, -1.0)
var work_position := Vector2.ZERO
var work_name := ""
var hunger := 0.0
var health := 100.0
var happiness := 100.0
var _at_work := false
var _target := Vector2.ZERO
var _wait_time := 0.0
var _visual: Node3D


func initialize(home: Vector2, spawn_offset: Vector2, door_offset := Vector2.ZERO) -> void:
	home_position = home
	home_door_position = home + door_offset
	if door_offset.length_squared() > 0.001:
		home_exit_direction = door_offset.normalized()
	_target = home + spawn_offset
	position = Vector3(_target.x, Terrain.height_at(_target), _target.y)
	_wait_time = randf_range(0.2, 1.5)


func assign_work(work: Vector2, display_name: String) -> void:
	work_position = work
	work_name = display_name
	_choose_target()


func clear_work() -> void:
	work_position = Vector2.ZERO
	work_name = ""
	_at_work = false
	_choose_target()


func set_work_schedule(at_work: bool) -> void:
	_at_work = at_work and is_working()
	if _at_work:
		_choose_target()
	else:
		_target = home_door_position


func daily_needs(was_fed: bool) -> void:
	if was_fed:
		hunger = maxf(0.0, hunger - 1.0)
		happiness = minf(100.0, happiness + 1.0)
	else:
		hunger = minf(100.0, hunger + 25.0)
		health = maxf(0.0, health - 5.0)
		happiness = maxf(0.0, happiness - 12.0)


func is_working() -> bool:
	return work_name != ""


func _ready() -> void:
	_build_visual()


func _process(delta: float) -> void:
	if _wait_time > 0.0:
		_wait_time -= delta
		return

	var current := Vector2(global_position.x, global_position.z)
	var distance := current.distance_to(_target)
	if distance <= ARRIVAL_DISTANCE:
		_wait_time = randf_range(0.8, 2.5)
		_choose_target()
		return

	var direction := current.direction_to(_target)
	var next := current + direction * WALK_SPEED * delta
	global_position = Vector3(next.x, Terrain.height_at(next), next.y)
	rotation.y = atan2(direction.x, direction.y)


func _choose_target() -> void:
	if _at_work:
		var angle := randf_range(0.0, TAU)
		_target = work_position + Vector2(cos(angle), sin(angle)) * randf_range(0.5, 1.0)
		return
	var side := Vector2(-home_exit_direction.y, home_exit_direction.x)
	_target = home_door_position + home_exit_direction * randf_range(0.8, WANDER_RADIUS) \
		+ side * randf_range(-1.0, 1.0)


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.position.y = 0.02
	_visual.scale = VISUAL_SCALE
	add_child(_visual)

	var skin := _material(Color(0.82, 0.58, 0.42))
	var shirt := _material(Color(0.25, 0.42, 0.62))
	var trousers := _material(Color(0.16, 0.19, 0.25))
	var hair := _material(Color(0.18, 0.10, 0.06))

	var body := CapsuleMesh.new()
	body.radius = 0.13
	body.height = 0.42
	_add_part(body, shirt, Vector3(0, 0.32, 0))

	var head := SphereMesh.new()
	head.radius = 0.12
	head.height = 0.24
	_add_part(head, skin, Vector3(0, 0.66, 0))

	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.125
	hair_mesh.height = 0.13
	_add_part(hair_mesh, hair, Vector3(0, 0.73, 0))

	var leg := BoxMesh.new()
	leg.size = Vector3(0.09, 0.25, 0.09)
	_add_part(leg, trousers, Vector3(-0.07, 0.08, 0))
	_add_part(leg, trousers, Vector3(0.07, 0.08, 0))


func _add_part(mesh: Mesh, material: Material, local_position: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = local_position
	_visual.add_child(instance)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material
