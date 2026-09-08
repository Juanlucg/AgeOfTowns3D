extends Node3D
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


func _ready() -> void:
	# Misma estrategia que Vegetation: el bucle 230x230 con lookups de bioma
	# se ejecuta en un hilo y los transforms se aplican al MultiMesh en el
	# hilo principal via call_deferred (MultiMesh no es thread-safe).
	_meshes[0] = _build_rock(_mesh_rng(201), 0.7, ROCK_COLOR)
	_meshes[1] = _build_rock(_mesh_rng(202), 1.0, ROCK_COLOR_CRAG)
	_meshes[2] = _build_rock(_mesh_rng(203), 0.45, ROCK_COLOR_SLAB)
	_mmis[0] = _create_empty_mmi(_meshes[0])
	_mmis[1] = _create_empty_mmi(_meshes[1])
	_mmis[2] = _create_empty_mmi(_meshes[2])
	_task_id = WorkerThreadPool.add_task(_populate)


# Id de la tarea del WorkerThreadPool. Antes no se guardaba y nadie la
# esperaba: si se salia del juego mientras generaba, el hilo seguia
# tocando este nodo mientras Godot lo destruia.
var _task_id := -1


func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


var _meshes: Array = [null, null, null]
var _mmis: Array = [null, null, null]
var _boulder_result: Array[Transform3D] = []
var _crag_result: Array[Transform3D] = []
var _slab_result: Array[Transform3D] = []


func _create_empty_mmi(mesh: ArrayMesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mmi


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
			var cls: String = Terrain.terrain_type(pos)
			var prob := 0.0
			match cls:
				"bosque":
					prob = FOREST_PROB
				"llanura":
					prob = PLAINS_PROB
					if Terrain.height_at(pos) > FOOTHILL_HEIGHT:
						prob = FOOTHILL_PROB
				_:
					prob = 0.0
			if prob > 0.0 and rng.randf() < prob:
				var hgt := clampf((Terrain.height_at(pos) - 3.0) / 4.0, 0.0, 1.0)
				var s := lerpf(SCALE_MIN, SCALE_MAX, hgt) * rng.randf_range(0.8, 1.25)
				var variant := rng.randi_range(0, 2)
				var yaw := rng.randf_range(0.0, TAU)
				var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
				var h: float = Terrain.height_at(pos)
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


func _assign_transforms(mmi: MultiMeshInstance3D, transforms: Array[Transform3D]) -> void:
	if mmi == null or transforms.is_empty():
		return
	var mm := mmi.multimesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])


func _mesh_rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


func clear_near(world_pos: Vector2, radius: float) -> void:
	# AABB pre-filtro: si la MultiMesh no toca la caja del radio, nada que limpiar.
	var query_box := AABB(
		Vector3(world_pos.x - radius, -1000.0, world_pos.y - radius),
		Vector3(radius * 2.0, 2000.0, radius * 2.0),
	)
	for c in get_children():
		if c is MultiMeshInstance3D:
			var mm: MultiMesh = c.multimesh
			if not mm.get_aabb().intersects(query_box):
				continue
			for i in mm.instance_count:
				var t: Transform3D = mm.get_instance_transform(i)
				var dx: float = t.origin.x - world_pos.x
				var dz: float = t.origin.z - world_pos.y
				if dx * dx + dz * dz < radius * radius:
					mm.set_instance_transform(i, t.translated(Vector3(0, -50, 0)))


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