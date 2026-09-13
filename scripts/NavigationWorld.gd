extends NavigationRegion3D
## Superficie navegable base del mapa. Los edificios añaden obstaculos dinamicos.


func _ready() -> void:
	var size := Terrain.WORLD_SIZE
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(size, 0.0, 0.0),
		Vector3(size, 0.0, size),
		Vector3(0.0, 0.0, size),
	])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation_mesh = mesh
