extends NavigationRegion3D
## Superficie navegable base del mapa. Los edificios añaden obstaculos dinamicos.


func _ready() -> void:
	var size := Terrain.WORLD_SIZE
	var cell_size := 3.0
	var mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	var polygons: Array[PackedInt32Array] = []
	var cells := int(ceil(size / cell_size))
	for ix in cells:
		for iz in cells:
			var x0 := float(ix) * cell_size
			var z0 := float(iz) * cell_size
			var x1 := minf(size, x0 + cell_size)
			var z1 := minf(size, z0 + cell_size)
			var center := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
			if Terrain.is_water(center):
				continue
			var base := vertices.size()
			vertices.append(Vector3(x0, Terrain.height_at(Vector2(x0, z0)), z0))
			vertices.append(Vector3(x1, Terrain.height_at(Vector2(x1, z0)), z0))
			vertices.append(Vector3(x1, Terrain.height_at(Vector2(x1, z1)), z1))
			vertices.append(Vector3(x0, Terrain.height_at(Vector2(x0, z1)), z1))
			polygons.append(PackedInt32Array([base, base + 1, base + 2, base + 3]))
	mesh.vertices = vertices
	for polygon in polygons:
		mesh.add_polygon(polygon)
	navigation_mesh = mesh
