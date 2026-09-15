extends ScatterLayer
class_name Rocks
# Rocas: cantos de bajo poligono instanciados con MultiMesh. Forma de boulder
# (icosaedro subdividido, con los vertices desplazados radialmente y aplastado
# en Y): anchas y bajas, medio hundidas en el suelo. Frecuentes en montaña y
# cumbres nevadas, raras en bosques y llanuras.

const STEP := 1.3
const JITTER := 0.5
const FOOTHILL_PROB := 0.03
const FOREST_PROB := 0.015
const PLAINS_PROB := 0.01
const FOOTHILL_HEIGHT := 2.6
const SCALE_MIN := 0.2
const SCALE_MAX := 0.45

const ROCK_COLOR := Color(0.52, 0.50, 0.47)
const ROCK_COLOR_CRAG := Color(0.47, 0.45, 0.43)
const ROCK_COLOR_SLAB := Color(0.55, 0.53, 0.49)


# Resultados que calcula el hilo, por variante. El resto de la maquinaria
# (MultiMeshInstance3D, hilo, clear_near) vive en ScatterLayer.
var _boulder_result: Array[Transform3D] = []
var _crag_result: Array[Transform3D] = []
var _slab_result: Array[Transform3D] = []


func _ready() -> void:
	_start_scatter([
		_build_rock(_mesh_rng(201), 0.7, ROCK_COLOR),
		_build_rock(_mesh_rng(202), 1.0, ROCK_COLOR_CRAG),
		_build_rock(_mesh_rng(203), 0.45, ROCK_COLOR_SLAB),
	])


func _populate() -> void:
	var sy := [0.7, 1.0, 0.45]
	var boulder: Array[Transform3D] = []
	var crag: Array[Transform3D] = []
	var slab: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = Terrain.SEED + 20
	var x := 0.0
	while x < Terrain.WORLD_SIZE:
		var y := 0.0
		while y < Terrain.WORLD_SIZE:
			var p := Vector2(x, y)
			var pos := p + Vector2(rng.randf_range(-JITTER, JITTER), rng.randf_range(-JITTER, JITTER))
			if Terrain.distance_to_water(pos) < 0.5:
				y += STEP
				continue
			# La altura se consulta como maximo una vez por celda y se reutiliza
			# para decidir la probabilidad, la escala y el apoyo de la roca. En
			# monte/playa/nieve no se calcula: prob es 0 y no hace falta.
			var cls := Terrain.class_at(pos)
			var prob := 0.0
			var h := 0.0
			match cls:
				Terrain.CLASS_FOREST:
					prob = FOREST_PROB
				Terrain.CLASS_PLAINS:
					h = Terrain.height_at(pos)
					prob = FOOTHILL_PROB if h > FOOTHILL_HEIGHT else PLAINS_PROB
			if prob > 0.0 and rng.randf() < prob:
				if cls == Terrain.CLASS_FOREST:
					h = Terrain.height_at(pos)
				var hgt := clampf((h - 3.0) / 4.0, 0.0, 1.0)
				var s := lerpf(SCALE_MIN, SCALE_MAX, hgt) * rng.randf_range(0.8, 1.25)
				var variant := rng.randi_range(0, 2)
				var yaw := rng.randf_range(0.0, TAU)
				var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
				var t := Transform3D(basis, Vector3(pos.x, h + sy[variant] * s * 1.0, pos.y))
				match variant:
					0:
						boulder.append(t)
					1:
						crag.append(t)
					_:
						slab.append(t)
			y += STEP
		x += STEP
	_boulder_result = boulder
	_crag_result = crag
	_slab_result = slab
	call_deferred("_apply_populated")


func _apply_populated() -> void:
	_assign_transforms(_mmis[0], _boulder_result)
	_assign_transforms(_mmis[1], _crag_result)
	_assign_transforms(_mmis[2], _slab_result)
	_populated = true
	_flush_pending_clears()


func _mesh_rng(rng_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	return rng


func _material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _icosa_verts() -> Array[Vector3]:
	var t := (1.0 + sqrt(5.0)) * 0.5
	return [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]


func _icosa_faces() -> Array:
	return [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]


# Boulder: icosaedro subdividido una vez (80 caras), vertices desplazados
# radialmente y aplastado en Y -> canto anguloso pero redondeado, ancho y bajo.
func _build_rock(rng: RandomNumberGenerator, sy: float, col: Color) -> ArrayMesh:
	var verts := _icosa_verts()
	var faces := _icosa_faces()
	var cache := {}
	var mid := func(a: int, b: int) -> int:
		var key := mini(a, b) * 1000 + maxi(a, b)
		if cache.has(key):
			return cache[key]
		verts.append((verts[a] + verts[b]) * 0.5)
		var idx := verts.size() - 1
		cache[key] = idx
		return idx

	var new_faces: Array = []
	for f in faces:
		var a: int = f[0]
		var b: int = f[1]
		var c: int = f[2]
		var ab: int = mid.call(a, b)
		var bc: int = mid.call(b, c)
		var ca: int = mid.call(c, a)
		new_faces.append([a, ab, ca])
		new_faces.append([ab, b, bc])
		new_faces.append([ca, bc, c])
		new_faces.append([ab, bc, ca])
	faces = new_faces

	for i in range(verts.size()):
		verts[i] = verts[i].normalized()
	for i in range(verts.size()):
		var d := rng.randf_range(1.0, 1.35)
		var v := verts[i] * d
		verts[i] = Vector3(v.x, v.y * sy, v.z)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		st.set_color(col)
		st.add_vertex(verts[f[0]])
		st.set_color(col)
		st.add_vertex(verts[f[1]])
		st.set_color(col)
		st.add_vertex(verts[f[2]])
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _material())
	return mesh
