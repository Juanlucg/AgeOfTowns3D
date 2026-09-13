extends Node3D
## Aldeano basico: vive en una casa y se mueve por sus alrededores.

const WALK_SPEED := 0.7
const WANDER_RADIUS := 3.0
const ARRIVAL_DISTANCE := 0.18
const VISUAL_SCALE := Vector3(0.35, 0.35, 0.35)

var home_position := Vector2.ZERO
var work_position := Vector2.ZERO
var work_name := ""
var _target := Vector2.ZERO
var _wait_time := 0.0
var _visual: Node3D


func initialize(home: Vector2, spawn_offset: Vector2) -> void:
	home_position = home
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
	_choose_target()


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
	var angle := randf_range(0.0, TAU)
	var center := work_position if is_working() else home_position
	var radius := randf_range(0.5, 1.0) if is_working() else randf_range(0.8, WANDER_RADIUS)
	_target = center + Vector2(cos(angle), sin(angle)) * radius


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
