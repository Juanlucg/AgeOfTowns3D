extends Node3D
class_name Vegetation
# Vegetacion: arboles 3D de bajo poligono instanciados con MultiMesh sobre los
# biomas del terreno (bosque denso, llanura escasa) y arbustos de matorral en
# las llanuras. La colocacion usa la semilla del terreno para que sea estable
# entre ejecuciones.

const STEP := 1.3
const JITTER := 0.5
const SCALE_MIN := 0.6
const SCALE_MAX := 1.0
const FOREST_PROB := 0.85
const PLAINS_PROB := 0.03
const FOREST_BUSH_PROB := 0.05
const PLAINS_BUSH_PROB := 0.18
const PINE_RATIO := 0.6

const TRUNK_COLOR := Color(0.42, 0.28, 0.15)
const PINE_COLOR := Color(0.16, 0.32, 0.14)
const ROUND_COLOR := Color(0.26, 0.43, 0.19)
const BUSH_COLOR := Color(0.30, 0.46, 0.20)

# Tinte del follaje por estacion (Primavera, Verano, Otono, Invierno)
const LEAF_TINT_PINE := [
	Color(0.95, 1.05, 0.95),
	Color(1.0, 1.0, 1.0),
	Color(0.85, 0.72, 0.50),
	Color(0.55, 0.68, 0.55),
]
const LEAF_TINT_ROUND := [
	Color(0.95, 1.05, 0.95),
	Color(1.0, 1.0, 1.0),
	Color(1.15, 0.60, 0.28),
	Color(0.55, 0.42, 0.34),
]
const LEAF_TINT_BUSH := [
	Color(0.95, 1.05, 0.95),
	Color(1.0, 1.0, 1.0),
	Color(1.05, 0.65, 0.30),
	Color(0.60, 0.52, 0.38),
]

var _pine_mat: ShaderMaterial
var _round_mat: ShaderMaterial
var _bush_mat: ShaderMaterial


func _ready() -> void:
	var pine := _build_pine()
	var round := _build_round()
	var bush := _build_bush()
	var pine_transforms: Array[Transform3D] = []
	var round_transforms: Array[Transform3D] = []
	var bush_transforms: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = Terrain.SEED + 10

	var x := 0.0
	while x < Terrain.WORLD_SIZE:
		var y := 0.0
		while y < Terrain.WORLD_SIZE:
			var p := Vector2(x, y)
			var cls := Terrain.terrain_type(p)
			var tree_prob := 0.0
			var bush_prob := 0.0
			var round_only := false
			match cls:
				"bosque":
					tree_prob = FOREST_PROB
					bush_prob = FOREST_BUSH_PROB
				"llanura":
					tree_prob = PLAINS_PROB
					bush_prob = PLAINS_BUSH_PROB
					round_only = true
				_:
					tree_prob = 0.0
			var pos := p + Vector2(rng.randf_range(-JITTER, JITTER), rng.randf_range(-JITTER, JITTER))
			if _plantable_at(pos):
				if bush_prob > 0.0 and rng.randf() < bush_prob:
					bush_transforms.append(_make_transform(pos, rng, 0.7, 1.4))
				elif tree_prob > 0.0 and rng.randf() < tree_prob:
					var is_pine := (not round_only) and rng.randf() < PINE_RATIO
					var t := _make_transform(pos, rng, SCALE_MIN, SCALE_MAX)
					if is_pine:
						pine_transforms.append(t)
					else:
						round_transforms.append(t)
			y += STEP
		x += STEP

	_add_multimesh(pine, pine_transforms)
	_add_multimesh(round, round_transforms)
	_add_multimesh(bush, bush_transforms)


# True si la posicion final es valida para plantar: bosque o llanura, con una
# separacion minima de la costa para que troncos y arbustos no queden en el
# agua, la arena ni la montaña (el jitter puede sacarlos de su celda original).
func _plantable_at(pos: Vector2) -> bool:
	var cls := Terrain.terrain_type(pos)
	if cls != "bosque" and cls != "llanura":
		return false
	return Terrain.distance_to_water(pos) >= 0.6


func _make_transform(pos: Vector2, rng: RandomNumberGenerator, s_min: float, s_max: float) -> Transform3D:
	var h := Terrain.height_at(pos)
	var s := rng.randf_range(s_min, s_max)
	var yaw := rng.randf_range(0.0, TAU)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
	return Transform3D(basis, Vector3(pos.x, h, pos.y))


func _add_multimesh(mesh: ArrayMesh, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)


func _material(foliage_y: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
		shader_type spatial;
		uniform vec3 u_tint : source_color = vec3(1.0, 1.0, 1.0);
		uniform float u_foliage_y = 0.3;
		varying vec3 vcol;
		varying float vy;
		void vertex() {
			vcol = COLOR.rgb;
			vy = VERTEX.y;
		}
		void fragment() {
			float f = smoothstep(u_foliage_y - 0.1, u_foliage_y + 0.1, vy);
			ALBEDO = vcol * mix(vec3(1.0), u_tint, f);
			ROUGHNESS = 1.0;
		}
	"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("u_foliage_y", foliage_y)
	return mat


func apply_season(season: int, k: float) -> void:
	_pine_mat.set_shader_parameter("u_tint", _tint(LEAF_TINT_PINE, season, k))
	_round_mat.set_shader_parameter("u_tint", _tint(LEAF_TINT_ROUND, season, k))
	_bush_mat.set_shader_parameter("u_tint", _tint(LEAF_TINT_BUSH, season, k))


func clear_near(world_pos: Vector2, radius: float) -> void:
	for c in get_children():
		if c is MultiMeshInstance3D:
			var mm: MultiMesh = c.multimesh
			for i in mm.instance_count:
				var t: Transform3D = mm.get_instance_transform(i)
				var dx: float = t.origin.x - world_pos.x
				var dz: float = t.origin.z - world_pos.y
				if sqrt(dx * dx + dz * dz) < radius:
					mm.set_instance_transform(i, t.translated(Vector3(0, -50, 0)))


func _tint(values: Array, season: int, k: float) -> Vector3:
	var s: Color = values[season] as Color
	var n: Color = values[(season + 1) % values.size()] as Color
	var c: Color = s.lerp(n, k)
	return Vector3(c.r, c.g, c.b)


func _build_pine() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_frustum(st, 0.0, 0.9, 0.06, 0.03, 5, TRUNK_COLOR)
	_add_frustum(st, 0.5, 1.4, 0.44, 0.02, 6, PINE_COLOR)
	_add_frustum(st, 0.9, 1.85, 0.36, 0.02, 6, PINE_COLOR)
	_add_frustum(st, 1.25, 2.25, 0.26, 0.02, 6, PINE_COLOR)
	st.generate_normals()
	var mesh := st.commit()
	_pine_mat = _material(0.42)
	mesh.surface_set_material(0, _pine_mat)
	return mesh


func _build_round() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_frustum(st, 0.0, 0.8, 0.07, 0.045, 5, TRUNK_COLOR)
	_add_frustum(st, 0.55, 1.35, 0.36, 0.05, 7, ROUND_COLOR)
	_add_frustum(st, 0.85, 1.85, 0.28, 0.02, 7, ROUND_COLOR)
	st.generate_normals()
	var mesh := st.commit()
	_round_mat = _material(0.42)
	mesh.surface_set_material(0, _round_mat)
	return mesh


func _build_bush() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_dome(st, 0.4, 0.8, BUSH_COLOR, 4, 7)
	st.generate_normals()
	var mesh := st.commit()
	_bush_mat = _material(0.0)
	mesh.surface_set_material(0, _bush_mat)
	return mesh


func _add_dome(st: SurfaceTool, radius: float, flat: float, col: Color, bands: int, segs: int) -> void:
	for b in range(bands):
		var a0 := (PI * 0.5) * (b / float(bands))
		var a1 := (PI * 0.5) * ((b + 1) / float(bands))
		for s in range(segs):
			var b0 := TAU * s / segs
			var b1 := TAU * (s + 1) / segs
			var p00 := _dome_pt(a0, b0, radius, flat)
			var p01 := _dome_pt(a0, b1, radius, flat)
			var p10 := _dome_pt(a1, b0, radius, flat)
			var p11 := _dome_pt(a1, b1, radius, flat)
			st.set_color(col)
			st.add_vertex(p00)
			st.set_color(col)
			st.add_vertex(p01)
			st.set_color(col)
			st.add_vertex(p10)
			st.set_color(col)
			st.add_vertex(p01)
			st.set_color(col)
			st.add_vertex(p11)
			st.set_color(col)
			st.add_vertex(p10)


func _dome_pt(lat: float, lon: float, radius: float, flat: float) -> Vector3:
	var cl := cos(lat)
	return Vector3(cl * cos(lon) * radius, sin(lat) * radius * flat, cl * sin(lon) * radius)


func _add_frustum(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, sides: int, col: Color) -> void:
	for s in range(sides):
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var p01 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		st.set_color(col)
		st.add_vertex(p00)
		st.set_color(col)
		st.add_vertex(p01)
		st.set_color(col)
		st.add_vertex(p10)
		st.set_color(col)
		st.add_vertex(p01)
		st.set_color(col)
		st.add_vertex(p11)
		st.set_color(col)
		st.add_vertex(p10)
	if r1 > 0.001:
		var top := Vector3(0.0, y1, 0.0)
		for s in range(sides):
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var q0 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var q1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			st.set_color(col)
			st.add_vertex(top)
			st.set_color(col)
			st.add_vertex(q0)
			st.set_color(col)
			st.add_vertex(q1)