extends Node3D
## Hoguera inicial del pueblo. Es el punto donde duermen los aldeanos que aun
## no tienen casa (y su punto de referencia de dia hasta que haya plaza).
## El jugador les construira casas mas adelante.

const STONE_COLOR := Color(0.45, 0.44, 0.42)
const LOG_COLOR := Color(0.35, 0.22, 0.12)
const FIRE_COLOR := Color(1.0, 0.55, 0.15)

var _light: OmniLight3D
var _base_energy := 1.4
var _t := 0.0


func _ready() -> void:
	# Anillo de piedras.
	var stone_mesh := CylinderMesh.new()
	stone_mesh.top_radius = 0.09
	stone_mesh.bottom_radius = 0.09
	stone_mesh.height = 0.12
	stone_mesh.radial_segments = 6
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = STONE_COLOR
	stone_mat.roughness = 1.0
	for i in range(8):
		var ang := TAU * float(i) / 8.0
		var mi := MeshInstance3D.new()
		mi.mesh = stone_mesh
		mi.material_override = stone_mat
		mi.position = Vector3(cos(ang) * 0.45, 0.06, sin(ang) * 0.45)
		add_child(mi)

	# Leños cruzados.
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = 0.05
	log_mesh.bottom_radius = 0.05
	log_mesh.height = 0.7
	log_mesh.radial_segments = 6
	var log_mat := StandardMaterial3D.new()
	log_mat.albedo_color = LOG_COLOR
	log_mat.roughness = 1.0
	for i in range(3):
		var ang := TAU * float(i) / 3.0
		var mi := MeshInstance3D.new()
		mi.mesh = log_mesh
		mi.material_override = log_mat
		mi.position = Vector3(0.0, 0.15, 0.0)
		mi.rotation = Vector3(deg_to_rad(70.0), ang, 0.0)
		add_child(mi)

	# Llama.
	var flame_mesh := CylinderMesh.new()
	flame_mesh.top_radius = 0.02
	flame_mesh.bottom_radius = 0.18
	flame_mesh.height = 0.5
	flame_mesh.radial_segments = 8
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = FIRE_COLOR
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.emission_enabled = true
	flame_mat.emission = FIRE_COLOR
	flame_mat.emission_energy_multiplier = 2.0
	var flame := MeshInstance3D.new()
	flame.mesh = flame_mesh
	flame.material_override = flame_mat
	flame.position = Vector3(0.0, 0.38, 0.0)
	add_child(flame)

	# Luz parpadeante.
	_light = OmniLight3D.new()
	_light.light_color = FIRE_COLOR
	_light.omni_range = 6.0
	_light.light_energy = _base_energy
	_light.position = Vector3(0.0, 0.8, 0.0)
	add_child(_light)


func _process(delta: float) -> void:
	if _light == null:
		return
	_t += delta
	_light.light_energy = _base_energy + sin(_t * 7.0) * 0.15 + sin(_t * 13.0) * 0.08
