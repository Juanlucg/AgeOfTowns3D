extends RefCounted
class_name BuildingMeshes
# Constructores puros de geometria para los edificios del juego.
# Antes vivian como metodos privados (_mesh_granary, _mesh_farm, ...) dentro
# de Buildings.gd. Se extraen aqui como funciones estaticas para:
#   - Testearlos sin instanciar Buildings (que requiere una escena).
#   - Reutilizarlos (vista previa del fantasma, render de catalogo, etc.).
#   - Reducir Buildings.gd a solo la logica de colocacion y produccion.

const WOOD_COLOR := Color(0.55, 0.38, 0.20)
const ROOF_COLOR := Color(0.42, 0.26, 0.13)
const STONE_COLOR := Color(0.50, 0.50, 0.52)
const STEEL_COLOR := Color(0.72, 0.72, 0.78)
const SOIL_COLOR := Color(0.40, 0.28, 0.14)


# `mat` es el material a aplicar; si es null, se usa el color solido del tipo.
static func build(type: String, mat: Material) -> Node3D:
	match type:
		"granero": return granary(mat)
		"granja": return farm(mat)
		"aserradero": return sawmill(mat)
		"cantera": return quarry(mat)
	return Node3D.new()


static func granary(mat: Material) -> Node3D:
	var n := Node3D.new()
	var wood := mat if mat != null else _mat(WOOD_COLOR)
	var roof_mat := mat if mat != null else _mat(ROOF_COLOR)
	var base := BoxMesh.new()
	base.size = Vector3(0.85, 0.5, 0.85)
	n.add_child(_part(base, wood, Vector3(0, 0.25, 0)))
	var door := BoxMesh.new()
	door.size = Vector3(0.26, 0.38, 0.06)
	n.add_child(_part(door, roof_mat, Vector3(0, 0.22, 0.43)))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.03
	roof.bottom_radius = 0.62
	roof.height = 0.38
	roof.radial_segments = 4
	n.add_child(_part(roof, roof_mat, Vector3(0, 0.5 + 0.19, 0)))
	return n


static func farm(mat: Material) -> Node3D:
	var n := Node3D.new()
	var wood := mat if mat != null else _mat(WOOD_COLOR)
	var roof_mat := mat if mat != null else _mat(ROOF_COLOR)
	var base := BoxMesh.new()
	base.size = Vector3(0.75, 0.5, 0.75)
	n.add_child(_part(base, wood, Vector3(0, 0.25, 0)))
	var door := BoxMesh.new()
	door.size = Vector3(0.12, 0.22, 0.03)
	n.add_child(_part(door, roof_mat, Vector3(0, 0.11, 0.38)))
	n.add_child(_part(_roof_plane(-0.38, 0.50, 0.0, 0.72, 0.86, wood), wood, Vector3.ZERO))
	n.add_child(_part(_roof_plane(0.0, 0.72, 0.38, 0.50, 0.86, wood), wood, Vector3.ZERO))
	n.add_child(_part(_gable_wall(-0.38, 0.50, 0.38, 0.72), wood, Vector3(0, 0, -0.42)))
	n.add_child(_part(_gable_wall(-0.38, 0.50, 0.38, 0.72), wood, Vector3(0, 0, 0.42)))
	var chimney := BoxMesh.new()
	chimney.size = Vector3(0.08, 0.14, 0.08)
	n.add_child(_part(chimney, roof_mat, Vector3(0.15, 0.72, -0.2)))
	return n


static func sawmill(mat: Material) -> Node3D:
	var n := Node3D.new()
	var wood := mat if mat != null else _mat(WOOD_COLOR)
	var roof_mat := mat if mat != null else _mat(ROOF_COLOR)
	var steel := mat if mat != null else _mat(STEEL_COLOR)
	var slab := BoxMesh.new()
	slab.size = Vector3(1.0, 0.08, 1.0)
	n.add_child(_part(slab, wood, Vector3(0, 0.04, 0)))
	for corner in [Vector2(-0.44, -0.44), Vector2(0.44, -0.44), Vector2(-0.44, 0.44), Vector2(0.44, 0.44)]:
		var post := BoxMesh.new()
		post.size = Vector3(0.06, 0.75, 0.06)
		n.add_child(_part(post, wood, Vector3(corner.x, 0.42, corner.y)))
	var lr := BoxMesh.new()
	lr.size = Vector3(0.55, 0.06, 1.0)
	var left := _part(lr, wood, Vector3(-0.22, 0.86, 0))
	left.rotate_z(0.55)
	n.add_child(left)
	var rr := BoxMesh.new()
	rr.size = Vector3(0.55, 0.06, 1.0)
	var right := _part(rr, wood, Vector3(0.22, 0.86, 0))
	right.rotate_z(-0.55)
	n.add_child(right)
	var ridge := BoxMesh.new()
	ridge.size = Vector3(0.1, 0.05, 1.02)
	n.add_child(_part(ridge, wood, Vector3(0, 0.98, 0)))
	var top := BoxMesh.new()
	top.size = Vector3(0.75, 0.12, 0.45)
	n.add_child(_part(top, wood, Vector3(0, 0.5, 0)))
	for leg in [Vector2(-0.32, -0.16), Vector2(0.32, -0.16), Vector2(-0.32, 0.16), Vector2(0.32, 0.16)]:
		var leg_box := BoxMesh.new()
		leg_box.size = Vector3(0.04, 0.45, 0.04)
		n.add_child(_part(leg_box, wood, Vector3(leg.x, 0.25, leg.y)))
	for side in [-1.0, 1.0]:
		var log := CylinderMesh.new()
		log.top_radius = 0.06
		log.bottom_radius = 0.06
		log.height = 0.3
		log.radial_segments = 8
		var log_mi := _part(log, roof_mat, Vector3(0.16 * side, 0.66, 0))
		log_mi.rotate_x(PI * 0.5)
		n.add_child(log_mi)
	var blade := CylinderMesh.new()
	blade.top_radius = 0.09
	blade.bottom_radius = 0.09
	blade.height = 0.03
	blade.radial_segments = 12
	var blade_mi := _part(blade, steel, Vector3(0, 0.68, 0))
	blade_mi.rotate_z(PI * 0.5)
	n.add_child(blade_mi)
	return n


static func quarry(mat: Material) -> Node3D:
	var n := Node3D.new()
	var stone := mat if mat != null else _mat(STONE_COLOR)
	var base := BoxMesh.new()
	base.size = Vector3(1.05, 0.15, 1.05)
	n.add_child(_part(base, stone, Vector3(0, 0.075, 0)))
	for r in [
		[Vector3(-0.35, 0.32, -0.32), Vector3(0.4, 0.32, 0.35)],
		[Vector3(0.38, 0.35, 0.28), Vector3(0.45, 0.4, 0.4)],
		[Vector3(0.0, 0.3, -0.1), Vector3(0.3, 0.28, 0.3)],
		[Vector3(-0.1, 0.35, 0.4), Vector3(0.28, 0.3, 0.28)],
	]:
		var rock := BoxMesh.new()
		rock.size = r[1]
		n.add_child(_part(rock, stone, r[0]))
	return n


# --- helpers internos (no son parte de la API publica) ---

static func _part(m: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	return mi


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


static func _roof_plane(x0: float, y0: float, x1: float, y1: float, depth: float, _mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0 := -depth * 0.5
	var z1 := depth * 0.5
	var p0 := Vector3(x0, y0, z0)
	var p1 := Vector3(x1, y1, z0)
	var p2 := Vector3(x0, y0, z1)
	var p3 := Vector3(x1, y1, z1)
	st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
	st.add_vertex(p1); st.add_vertex(p3); st.add_vertex(p2)
	st.add_vertex(p2); st.add_vertex(p1); st.add_vertex(p0)
	st.add_vertex(p2); st.add_vertex(p3); st.add_vertex(p1)
	st.generate_normals()
	return st.commit()


static func _gable_wall(x_left: float, y_bot: float, x_right: float, ridge_y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	st.set_normal(Vector3(0, 0, 1))
	st.add_vertex(Vector3(x_left, y_bot, 0.0))
	st.add_vertex(Vector3(0.0, ridge_y, 0.0))
	st.add_vertex(Vector3(x_right, y_bot, 0.0))
	st.set_normal(Vector3(0, 0, -1))
	st.add_vertex(Vector3(x_right, y_bot, 0.0))
	st.add_vertex(Vector3(0.0, ridge_y, 0.0))
	st.add_vertex(Vector3(x_left, y_bot, 0.0))
	return st.commit()


# Material translucido no sombreado para el fantasma de colocacion.
static func ghost_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
