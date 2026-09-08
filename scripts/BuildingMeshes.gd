extends RefCounted
class_name BuildingMeshes
## Constructores puros de geometria para los edificios del juego
## (granero, granja, aserradero, cantera). Extraidos de [Buildings]
## para ser testables y reutilizables (fantasmas, catalogo).

const WOOD_COLOR := Color(0.55, 0.38, 0.20)
const ROOF_COLOR := Color(0.42, 0.26, 0.13)
const STONE_COLOR := Color(0.50, 0.50, 0.52)
const STEEL_COLOR := Color(0.72, 0.72, 0.78)
const SOIL_COLOR := Color(0.40, 0.28, 0.14)

# --- Paleta de la granja: paja calida, yeso crema, viga oscura ---
const THATCH_COLOR := Color(0.82, 0.68, 0.41)    # paja al sol
const THATCH_RIDGE := Color(0.70, 0.56, 0.32)    # caballete, mas apagado
const THATCH_SHADE := Color(0.58, 0.45, 0.24)    # canto del alero, en sombra
const PLASTER_COLOR := Color(0.97, 0.88, 0.68)   # muro encalado, tirando a
                                                 # calido: la luz ambiental de
                                                 # primavera es muy azul y lo
                                                 # dejaba gris
const TIMBER_COLOR := Color(0.30, 0.19, 0.11)    # entramado de madera
const DOOR_COLOR := Color(0.45, 0.29, 0.15)


# `mat` es el material a aplicar; si es null, se usa el color solido del tipo.
# El tipo es el mismo StringName que usa [BuildingDef.id] (antes esta funcion
# recibia String y los dos llamantes pasaban tipos distintos).
static func build(type: StringName, mat: Material) -> Node3D:
	match type:
		&"granero": return granary(mat)
		&"granja": return farm(mat)
		&"aserradero": return sawmill(mat)
		&"cantera": return quarry(mat)
	push_warning("BuildingMeshes.build: tipo desconocido '%s'" % type)
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


const FARM_WALL_HX := 0.34    # medio ancho del muro (X)
const FARM_WALL_HZ := 0.40    # medio largo del muro (Z); el caballete va en Z
const FARM_PLINTH_H := 0.12
const FARM_WALL_H := 0.56


# Casa de labranza con techo de paja. Lo que manda es el tejado: grueso,
# redondeado, a cuatro aguas y volando muy por fuera de los muros. Debajo,
# yeso claro con entramado de madera sobre un zocalo de piedra.
#
# Todo cabe en +-0.75 en X y Z, que es lo que ocupa la losa de cimentacion
# (footprint 1.0 + 0.5). Si el tejado se saliera de ahi se comeria la
# separacion con el huerto (ver Buildings._field_offset).
static func farm(mat: Material) -> Node3D:
	var n := Node3D.new()
	var plaster := mat if mat != null else _mat(PLASTER_COLOR)
	var timber := mat if mat != null else _mat(TIMBER_COLOR)
	var stone := mat if mat != null else _mat(STONE_COLOR)
	var door_mat := mat if mat != null else _mat(DOOR_COLOR)
	var wall_top: float = FARM_PLINTH_H + FARM_WALL_H

	# Zocalo de piedra: levanta el yeso del barro.
	var plinth := BoxMesh.new()
	plinth.size = Vector3(FARM_WALL_HX * 2.0 + 0.10, FARM_PLINTH_H, FARM_WALL_HZ * 2.0 + 0.10)
	n.add_child(_part(plinth, stone, Vector3(0, FARM_PLINTH_H * 0.5, 0)))

	# Muros
	var walls := BoxMesh.new()
	walls.size = Vector3(FARM_WALL_HX * 2.0, FARM_WALL_H, FARM_WALL_HZ * 2.0)
	n.add_child(_part(walls, plaster, Vector3(0, FARM_PLINTH_H + FARM_WALL_H * 0.5, 0)))

	# Entramado: postes en las cuatro esquinas y durmiente arriba.
	var post := BoxMesh.new()
	post.size = Vector3(0.07, FARM_WALL_H, 0.07)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			n.add_child(_part(post, timber, Vector3(
				sx * FARM_WALL_HX, FARM_PLINTH_H + FARM_WALL_H * 0.5, sz * FARM_WALL_HZ)))
	var plate_z := BoxMesh.new()
	plate_z.size = Vector3(0.06, 0.07, FARM_WALL_HZ * 2.0 + 0.02)
	for sx in [-1.0, 1.0]:
		n.add_child(_part(plate_z, timber, Vector3(sx * FARM_WALL_HX, wall_top - 0.04, 0)))
	var plate_x := BoxMesh.new()
	plate_x.size = Vector3(FARM_WALL_HX * 2.0 + 0.02, 0.07, 0.06)
	for sz in [-1.0, 1.0]:
		n.add_child(_part(plate_x, timber, Vector3(0, wall_top - 0.04, sz * FARM_WALL_HZ)))

	# Tornapuntas: es lo que hace que se lea como entramado y no como una caja
	# con las esquinas pintadas.
	var brace := BoxMesh.new()
	brace.size = Vector3(0.05, 0.36, 0.05)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var b := _part(brace, timber, Vector3(
				sx * FARM_WALL_HX, FARM_PLINTH_H + FARM_WALL_H * 0.60, sz * FARM_WALL_HZ * 0.5))
			b.rotate_x(sz * 0.6)
			n.add_child(b)

	# Puerta en el hastial que da la espalda al huerto.
	var frame := BoxMesh.new()
	frame.size = Vector3(0.30, 0.38, 0.04)
	n.add_child(_part(frame, timber, Vector3(0, FARM_PLINTH_H + 0.19, FARM_WALL_HZ + 0.01)))
	var door := BoxMesh.new()
	door.size = Vector3(0.22, 0.32, 0.05)
	n.add_child(_part(door, door_mat, Vector3(0, FARM_PLINTH_H + 0.16, FARM_WALL_HZ + 0.02)))

	# Ventanita en un costado.
	var win := BoxMesh.new()
	win.size = Vector3(0.04, 0.16, 0.18)
	n.add_child(_part(win, timber, Vector3(FARM_WALL_HX + 0.01, FARM_PLINTH_H + 0.27, -0.10)))

	# Techo. Arranca por debajo del durmiente para tapar la junta.
	var roof := _thatch_roof(0.48, 0.58, wall_top - 0.04, 0.40, 0.10)
	n.add_child(_part(roof, mat if mat != null else _vertex_color_mat(), Vector3.ZERO))

	# Chimenea de piedra saliendo por el faldon.
	var chimney := BoxMesh.new()
	chimney.size = Vector3(0.13, 0.55, 0.13)
	n.add_child(_part(chimney, stone, Vector3(0.20, wall_top + 0.30, -0.26)))
	var cap := BoxMesh.new()
	cap.size = Vector3(0.17, 0.05, 0.17)
	n.add_child(_part(cap, timber, Vector3(0.20, wall_top + 0.59, -0.26)))
	return n


# Cubierta de paja: rejilla curvada a cuatro aguas mas el canto grueso del
# alero, que es lo que hace que la paja parezca paja y no una chapa.
#
# La forma sale de dos perfiles:
#   - a lo ancho, la altura cae como 1-|v|^1.15: caballete apenas redondeado y
#     faldones casi rectos, como un techo de paja de verdad;
#   - a lo largo, la cumbrera muere en los dos extremos, y eso genera las
#     cuatro aguas.
static func _thatch_roof(half_w: float, half_l: float, base_y: float, ridge_h: float, eave: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 14   # divisiones a lo largo
	var nv := 12   # divisiones a lo ancho
	var grid: Array[PackedVector3Array] = []
	for i in nu + 1:
		var u := -1.0 + 2.0 * float(i) / float(nu)
		var hip: float = smoothstep(0.0, 0.20, 1.0 - absf(u))
		var row := PackedVector3Array()
		for j in nv + 1:
			var v := -1.0 + 2.0 * float(j) / float(nv)
			var prof: float = 1.0 - pow(absf(v), 1.15)
			row.append(Vector3(v * half_w, base_y + ridge_h * hip * prof, u * half_l))
		grid.append(row)

	for i in nu:
		var r0 := grid[i]
		var r1 := grid[i + 1]
		for j in nv:
			# Este giro es el que Godot toma como cara frontal mirando hacia
			# arriba (el mismo que usa el suelo de FieldMesh).
			var v := -1.0 + 2.0 * float(j) / float(nv)
			var col := THATCH_COLOR.lerp(THATCH_RIDGE, clampf(1.0 - absf(v) * 2.2, 0.0, 1.0))
			_tri(st, col, r0[j], r0[j + 1], r1[j])
			_tri(st, col, r0[j + 1], r1[j + 1], r1[j])

	# Canto del alero. Todo el borde de la cubierta esta a base_y, asi que es
	# una banda vertical alrededor del rectangulo.
	var c00 := Vector3(-half_w, base_y, -half_l)
	var c10 := Vector3(half_w, base_y, -half_l)
	var c01 := Vector3(-half_w, base_y, half_l)
	var c11 := Vector3(half_w, base_y, half_l)
	var y_bot := base_y - eave
	_skirt(st, c10, c11, Vector3.RIGHT, y_bot)
	_skirt(st, c01, c00, Vector3.LEFT, y_bot)
	_skirt(st, c11, c01, Vector3.BACK, y_bot)
	_skirt(st, c00, c10, Vector3.FORWARD, y_bot)
	st.generate_normals()
	return st.commit()


# Banda vertical del alero entre dos esquinas, mirando hacia `outward`.
static func _skirt(st: SurfaceTool, a: Vector3, b: Vector3, outward: Vector3, y_bot: float) -> void:
	_quad_facing(st, THATCH_SHADE, a, b,
		Vector3(a.x, y_bot, a.z), Vector3(b.x, y_bot, b.z), outward)


# Cuadrilatero a-b-d-c, con el giro corregido para que mire hacia `outward`.
static func _quad_facing(st: SurfaceTool, col: Color, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	# Godot saca la normal de un triangulo como (p1-p3) x (p1-p2).
	if (a - c).cross(a - b).dot(outward) < 0.0:
		var t := b
		b = c
		c = t
	_tri(st, col, a, b, c)
	_tri(st, col, b, d, c)


static func _tri(st: SurfaceTool, col: Color, p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	st.set_color(col)
	st.add_vertex(p0)
	st.set_color(col)
	st.add_vertex(p1)
	st.set_color(col)
	st.add_vertex(p2)


# Material que pinta con el color de vertice, como el de las rocas.
static func _vertex_color_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	return m


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
