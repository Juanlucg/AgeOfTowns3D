extends RefCounted
class_name BuildingMeshes
## Constructores puros de geometria para los edificios del juego
## (casa, granero, granja, aserradero, cantera). Extraidos de [Buildings]
## para ser testables y reutilizables (fantasmas, catalogo).

const WOOD_COLOR := Color(0.55, 0.38, 0.20)
const ROOF_COLOR := Color(0.42, 0.26, 0.13)
const STONE_COLOR := Color(0.50, 0.50, 0.52)
const STEEL_COLOR := Color(0.72, 0.72, 0.78)
const SOIL_COLOR := Color(0.40, 0.28, 0.14)
const WATER_COLOR := Color(0.22, 0.46, 0.62)
const ROPE_COLOR := Color(0.72, 0.64, 0.42)

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
const COTTAGE_SCENE := preload("res://assets/buildings/cottage/cottage.fbx")
const COTTAGE_SCALE := Vector3(1.5, 1.5, 1.5)
const SAWMILL_SCENE := preload("res://assets/buildings/aserradero/aserradero.fbx")
const SAWMILL_SCALE := Vector3(1.45, 1.45, 1.45)


# `mat` es el material a aplicar; si es null, se usa el color solido del tipo.
# El tipo es el mismo StringName que usa [BuildingDef.id] (antes esta funcion
# recibia String y los dos llamantes pasaban tipos distintos).
static func build(type: StringName, mat: Material) -> Node3D:
	match type:
		&"casa": return house(mat)
		&"granero": return granary(mat)
		&"granja": return farm(mat)
		&"aserradero": return sawmill(mat)
		&"cantera": return quarry(mat)
		&"almacen": return warehouse(mat)
		&"plaza": return plaza(mat)
	push_warning("BuildingMeshes.build: tipo desconocido '%s'" % type)
	return Node3D.new()


static func house(mat: Material) -> Node3D:
	var instance := COTTAGE_SCENE.instantiate() as Node3D
	if instance == null:
		push_error("BuildingMeshes.house: el modelo de la casa no es un Node3D")
		return Node3D.new()
	instance.scale = COTTAGE_SCALE
	if mat != null:
		_apply_material_recursive(instance, mat)
	return instance


static func apply_material_recursive(root: Node, mat: Material) -> void:
	_apply_material_recursive(root, mat)


static func _apply_material_recursive(root: Node, mat: Material) -> void:
	if root is MeshInstance3D:
		(root as MeshInstance3D).material_override = mat
	for child in root.get_children():
		_apply_material_recursive(child, mat)


static func granary(mat: Material) -> Node3D:
	var n := Node3D.new()
	var wood := mat if mat != null else _mat(WOOD_COLOR)
	var roof_mat := mat if mat != null else _mat(ROOF_COLOR)
	var base := _box(Vector3(0.85, 0.5, 0.85))
	n.add_child(_part(base, wood, Vector3(0, 0.25, 0)))
	var door := _box(Vector3(0.26, 0.38, 0.06))
	n.add_child(_part(door, roof_mat, Vector3(0, 0.22, 0.43)))
	var roof := _cylinder(0.03, 0.62, 0.38, 4)
	n.add_child(_part(roof, roof_mat, Vector3(0, 0.5 + 0.19, 0)))
	return n


const FARM_WALL_HX := 0.34    # medio ancho del muro (X)
const FARM_WALL_HZ := 0.40    # medio largo del muro (Z); el caballete va en Z
const FARM_PLINTH_H := 0.12
const FARM_WALL_H := 0.56
# Media huella VISUAL de la casa de labranza (el tejado vuela por fuera del
# muro). Se usa para pegar el campo a la casa y abrir la valla justo donde la
# toca. BACK es hacia el huerto (eje Z local, el lado largo del tejado); SIDE es
# el ancho (eje X local). No coincide con el footprint (redondeado a 1.0).
const FARM_HALF_BACK := 0.60
const FARM_HALF_SIDE := 0.50


# Casa de labranza con techo de paja. Lo que manda es el tejado: grueso,
# redondeado, a cuatro aguas y volando muy por fuera de los muros. Debajo,
# yeso claro con entramado de madera sobre un zocalo de piedra.
#
# Todo cabe en +-0.75 en X y Z, que es lo que ocupa el solar
# (footprint 1.0 + margen). Si el tejado se saliera de ahi se comeria la
# separacion con el huerto (ver Buildings._field_offset).
static func farm(mat: Material) -> Node3D:
	var n := Node3D.new()
	var plaster := mat if mat != null else _mat(PLASTER_COLOR)
	var timber := mat if mat != null else _mat(TIMBER_COLOR)
	var stone := mat if mat != null else _mat(STONE_COLOR)
	var door_mat := mat if mat != null else _mat(DOOR_COLOR)
	var wall_top: float = FARM_PLINTH_H + FARM_WALL_H

	# Zocalo de piedra: levanta el yeso del barro.
	var plinth := _box(Vector3(FARM_WALL_HX * 2.0 + 0.10, FARM_PLINTH_H, FARM_WALL_HZ * 2.0 + 0.10))
	n.add_child(_part(plinth, stone, Vector3(0, FARM_PLINTH_H * 0.5, 0)))

	# Muros
	var walls := _box(Vector3(FARM_WALL_HX * 2.0, FARM_WALL_H, FARM_WALL_HZ * 2.0))
	n.add_child(_part(walls, plaster, Vector3(0, FARM_PLINTH_H + FARM_WALL_H * 0.5, 0)))

	# Entramado: postes en las cuatro esquinas y durmiente arriba.
	var post := _box(Vector3(0.07, FARM_WALL_H, 0.07))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			n.add_child(_part(post, timber, Vector3(
				sx * FARM_WALL_HX, FARM_PLINTH_H + FARM_WALL_H * 0.5, sz * FARM_WALL_HZ)))
	var plate_z := _box(Vector3(0.06, 0.07, FARM_WALL_HZ * 2.0 + 0.02))
	for sx in [-1.0, 1.0]:
		n.add_child(_part(plate_z, timber, Vector3(sx * FARM_WALL_HX, wall_top - 0.04, 0)))
	var plate_x := _box(Vector3(FARM_WALL_HX * 2.0 + 0.02, 0.07, 0.06))
	for sz in [-1.0, 1.0]:
		n.add_child(_part(plate_x, timber, Vector3(0, wall_top - 0.04, sz * FARM_WALL_HZ)))

	# Tornapuntas: es lo que hace que se lea como entramado y no como una caja
	# con las esquinas pintadas.
	var brace := _box(Vector3(0.05, 0.36, 0.05))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var b := _part(brace, timber, Vector3(
				sx * FARM_WALL_HX, FARM_PLINTH_H + FARM_WALL_H * 0.60, sz * FARM_WALL_HZ * 0.5))
			b.rotate_x(sz * 0.6)
			n.add_child(b)

	# Puerta en el hastial que da la espalda al huerto.
	var frame := _box(Vector3(0.30, 0.38, 0.04))
	n.add_child(_part(frame, timber, Vector3(0, FARM_PLINTH_H + 0.19, FARM_WALL_HZ + 0.01)))
	var door := _box(Vector3(0.22, 0.32, 0.05))
	n.add_child(_part(door, door_mat, Vector3(0, FARM_PLINTH_H + 0.16, FARM_WALL_HZ + 0.02)))

	# Puerta trasera, hacia el huerto (el campo queda en -Z): es por donde los
	# aldeanos salen al campo desde la casa.
	var back_frame := _box(Vector3(0.30, 0.38, 0.04))
	n.add_child(_part(back_frame, timber, Vector3(0, FARM_PLINTH_H + 0.19, -(FARM_WALL_HZ + 0.01))))
	var back_door := _box(Vector3(0.22, 0.32, 0.05))
	n.add_child(_part(back_door, door_mat, Vector3(0, FARM_PLINTH_H + 0.16, -(FARM_WALL_HZ + 0.02))))

	# Ventanita en un costado.
	var win := _box(Vector3(0.04, 0.16, 0.18))
	n.add_child(_part(win, timber, Vector3(FARM_WALL_HX + 0.01, FARM_PLINTH_H + 0.27, -0.10)))

	# Techo. Arranca por debajo del durmiente para tapar la junta.
	var roof := _thatch_roof(0.48, 0.58, wall_top - 0.04, 0.40, 0.10)
	n.add_child(_part(roof, mat if mat != null else _vertex_color_mat(), Vector3.ZERO))

	# Chimenea de piedra saliendo por el faldon.
	var chimney := _box(Vector3(0.13, 0.55, 0.13))
	n.add_child(_part(chimney, stone, Vector3(0.20, wall_top + 0.30, -0.26)))
	var cap := _box(Vector3(0.17, 0.05, 0.17))
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


# Triangulo con el giro corregido para que mire hacia `outward`.
static func _tri_facing(st: SurfaceTool, col: Color, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	if (a - c).cross(a - b).dot(outward) < 0.0:
		var t := b
		b = c
		c = t
	_tri(st, col, a, b, c)


# Tejado a dos aguas (cumbrera a lo largo de X, faldones hacia +-Z) con color de
# vertice. Alternativa recta al _thatch_roof del granjero, para que el almacen
# se lea distinto.
static func _gable_roof(half_w: float, half_l: float, base_y: float, ridge_h: float, eave: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y_ridge := base_y + ridge_h
	var r0 := Vector3(-half_w, y_ridge, 0.0)
	var r1 := Vector3(half_w, y_ridge, 0.0)
	var f00 := Vector3(-half_w, base_y, -half_l)
	var f10 := Vector3(half_w, base_y, -half_l)
	var f01 := Vector3(-half_w, base_y, half_l)
	var f11 := Vector3(half_w, base_y, half_l)
	# Faldones. _quad_facing espera a-b como un borde y c-d como el borde
	# opuesto (a sobre c, b sobre d); si se pasan en diagonal, el segundo
	# triangulo queda invertido y el tejado sale retorcido con huecos.
	_quad_facing(st, ROOF_COLOR, r0, r1, f01, f11, Vector3(0.0, half_l, ridge_h))
	_quad_facing(st, ROOF_COLOR, r0, r1, f00, f10, Vector3(0.0, half_l, -ridge_h))
	# Hastiales (triangulos de los extremos), en color de madera para que se
	# lean como el remate del muro y no como tejado.
	_tri_facing(st, WOOD_COLOR.darkened(0.15), r0, f01, f00, Vector3(-1.0, 0.0, 0.0))
	_tri_facing(st, WOOD_COLOR.darkened(0.15), r1, f10, f11, Vector3(1.0, 0.0, 0.0))
	# Alero: banda vertical alrededor de la base del tejado.
	var edge := ROOF_COLOR.darkened(0.35)
	var y_bot := base_y - eave
	_quad_facing(st, edge, f10, f11, Vector3(f10.x, y_bot, f10.z), Vector3(f11.x, y_bot, f11.z), Vector3(1.0, 0.0, 0.0))
	_quad_facing(st, edge, f01, f00, Vector3(f01.x, y_bot, f01.z), Vector3(f00.x, y_bot, f00.z), Vector3(-1.0, 0.0, 0.0))
	_quad_facing(st, edge, f00, f10, Vector3(f00.x, y_bot, f00.z), Vector3(f10.x, y_bot, f10.z), Vector3(0.0, 0.0, -1.0))
	_quad_facing(st, edge, f11, f01, Vector3(f11.x, y_bot, f11.z), Vector3(f01.x, y_bot, f01.z), Vector3(0.0, 0.0, 1.0))
	st.generate_normals()
	return st.commit()


# Material que pinta con el color de vertice, como el de las rocas.
static var _vertex_mat: StandardMaterial3D = null

static func _vertex_color_mat() -> StandardMaterial3D:
	if _vertex_mat == null:
		_vertex_mat = StandardMaterial3D.new()
		_vertex_mat.vertex_color_use_as_albedo = true
		_vertex_mat.roughness = 1.0
	return _vertex_mat


# Modelo importado del aserradero (FBX). Ya viene a escala (~1 m de huella y la
# base apoyada en y=0), igual que la casa importada.
static func sawmill(mat: Material) -> Node3D:
	var instance := SAWMILL_SCENE.instantiate() as Node3D
	if instance == null:
		push_error("BuildingMeshes.sawmill: el modelo importado no es un Node3D")
		return Node3D.new()
	instance.scale = SAWMILL_SCALE
	if mat != null:
		_apply_material_recursive(instance, mat)
	return instance


# Cantera: castillete de vigas de madera con escalera, montado ENCIMA de una
# roca (el yacimiento). El armazon queda abierto en el centro para dejar ver la
# piedra de la que extraen los aldeanos: jib con roldana y cuerda para subir los
# bloques, escalera de mano y riostras en las esquinas.
static func quarry(mat: Material) -> Node3D:
	var n := Node3D.new()
	var wood := mat if mat != null else _mat(WOOD_COLOR)
	var beam := mat if mat != null else _mat(TIMBER_COLOR)
	var stone := mat if mat != null else _mat(STONE_COLOR)
	var rope := mat if mat != null else _mat(ROPE_COLOR)

	# Cuatro patas en ligera piramide: dejan hueco en el centro para la roca.
	var h := 1.45
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := _part(_box(Vector3(0.09, h, 0.09)), wood,
				Vector3(sx * 0.52, h * 0.5, sz * 0.52))
			leg.rotate_x(-sz * 0.10)
			leg.rotate_z(sx * 0.10)
			n.add_child(leg)

	# Marco superior (cuatro vigas).
	var beam_z := _box(Vector3(0.08, 0.08, 1.0))
	n.add_child(_part(beam_z, beam, Vector3(-0.46, h, 0)))
	n.add_child(_part(beam_z, beam, Vector3(0.46, h, 0)))
	var beam_x := _box(Vector3(1.0, 0.08, 0.08))
	n.add_child(_part(beam_x, beam, Vector3(0, h, -0.46)))
	n.add_child(_part(beam_x, beam, Vector3(0, h, 0.46)))

	# Tornapuntas cruzadas en las dos caras laterales.
	for sx in [-1.0, 1.0]:
		var brace := _part(_box(Vector3(0.06, 1.25, 0.06)), wood,
			Vector3(sx * 0.50, 0.72, -0.50))
		brace.rotate_z(sx * 0.55)
		n.add_child(brace)

	# Viga voladiza (jib) con roldana y cuerda: sube los bloques de piedra.
	var jib := _part(_box(Vector3(1.15, 0.09, 0.09)), beam, Vector3(0.18, h + 0.12, 0.0))
	jib.rotate_z(0.14)
	n.add_child(jib)
	var wheel := _part(_cylinder(0.09, 0.09, 0.05, 10), stone, Vector3(0.72, h + 0.20, 0))
	wheel.rotate_z(PI * 0.5)
	n.add_child(wheel)
	n.add_child(_part(_box(Vector3(0.025, 0.85, 0.025)), rope, Vector3(0.72, h - 0.24, 0)))
	n.add_child(_part(_box(Vector3(0.22, 0.18, 0.22)), stone, Vector3(0.72, h - 0.72, 0)))

	# Escalera de mano apoyada en el castillete.
	var ladder := Node3D.new()
	var rail := _box(Vector3(0.05, 1.5, 0.05))
	ladder.add_child(_part(rail, wood, Vector3(-0.17, 0.75, 0)))
	ladder.add_child(_part(rail, wood, Vector3(0.17, 0.75, 0)))
	var rung := _box(Vector3(0.38, 0.05, 0.05))
	for i in 6:
		ladder.add_child(_part(rung, wood, Vector3(0, 0.18 + float(i) * 0.24, 0)))
	ladder.position = Vector3(0.52, 0.0, 0.62)
	ladder.rotate_x(-0.18)
	n.add_child(ladder)

	# Bloques de piedra ya cortados al pie.
	var block := _box(Vector3(0.24, 0.16, 0.20))
	n.add_child(_part(block, stone, Vector3(-0.55, 0.08, 0.52)))
	n.add_child(_part(block, stone, Vector3(-0.55, 0.24, 0.52)))
	n.add_child(_part(block, stone, Vector3(-0.30, 0.08, 0.56)))
	return n


# Almacen: nave de madera sobre zocalo de piedra, mas ancha que el granero y
# con tejado a dos aguas y porton doble. Cajas y un barril junto a la entrada
# para que se lea como deposito. La puerta da a +Z (como el granero).
static func warehouse(mat: Material) -> Node3D:
	var n := Node3D.new()
	var wood := mat if mat != null else _mat(WOOD_COLOR)
	var roof_mat := mat if mat != null else _mat(ROOF_COLOR)
	var stone := mat if mat != null else _mat(STONE_COLOR)
	var door_mat := mat if mat != null else _mat(DOOR_COLOR)
	var timber := mat if mat != null else _mat(TIMBER_COLOR)

	# Zocalo de piedra.
	var base := _box(Vector3(1.06, 0.10, 0.78))
	n.add_child(_part(base, stone, Vector3(0, 0.05, 0)))

	# Muros.
	var walls := _box(Vector3(0.98, 0.48, 0.70))
	n.add_child(_part(walls, wood, Vector3(0, 0.10 + 0.24, 0)))

	# Postes en las cuatro esquinas y viga superior.
	var post := _box(Vector3(0.07, 0.48, 0.07))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			n.add_child(_part(post, timber, Vector3(sx * 0.47, 0.10 + 0.24, sz * 0.33)))
	var beam := _box(Vector3(1.0, 0.06, 0.06))
	n.add_child(_part(beam, timber, Vector3(0, 0.55, 0.33)))
	n.add_child(_part(beam, timber, Vector3(0, 0.55, -0.33)))

	# Porton doble en el frontal (+Z).
	var frame := _box(Vector3(0.60, 0.42, 0.04))
	n.add_child(_part(frame, timber, Vector3(0, 0.31, 0.355)))
	var door := _box(Vector3(0.50, 0.36, 0.05))
	n.add_child(_part(door, door_mat, Vector3(0, 0.28, 0.37)))
	var divider := _box(Vector3(0.02, 0.36, 0.05))
	n.add_child(_part(divider, timber, Vector3(0, 0.28, 0.375)))

	# Ventanuco en un costado.
	var win := _box(Vector3(0.04, 0.14, 0.16))
	n.add_child(_part(win, timber, Vector3(0.50, 0.40, -0.10)))

	# Tejado a dos aguas + caballete.
	var roof := _gable_roof(0.55, 0.41, 0.58, 0.25, 0.11)
	n.add_child(_part(roof, mat if mat != null else _vertex_color_mat(), Vector3.ZERO))
	var ridge := _box(Vector3(1.16, 0.06, 0.10))
	n.add_child(_part(ridge, roof_mat, Vector3(0, 0.83, 0)))

	# Cajas apiladas y un barril junto a la entrada.
	var crate := _box(Vector3(0.18, 0.18, 0.18))
	n.add_child(_part(crate, wood, Vector3(-0.52, 0.09, 0.30)))
	n.add_child(_part(crate, wood, Vector3(-0.52, 0.27, 0.30)))
	n.add_child(_part(crate, wood, Vector3(-0.68, 0.09, 0.22)))
	var barrel := _cylinder(0.10, 0.10, 0.24, 10)
	n.add_child(_part(barrel, roof_mat, Vector3(0.55, 0.12, 0.28)))
	return n


# Plaza: explanada empedrada con fuente central y bancos. Es el punto de
# reunion del pueblo; queda plana para que los aldeanos anden por ella.
static func plaza(mat: Material) -> Node3D:
	var n := Node3D.new()
	var stone := mat if mat != null else _mat(STONE_COLOR)
	var wood := mat if mat != null else _mat(WOOD_COLOR)
	var water := mat if mat != null else _mat(WATER_COLOR)

	# Explanada (octogono bajo).
	var ground := _cylinder(1.15, 1.20, 0.08, 8)
	n.add_child(_part(ground, stone, Vector3(0, 0.04, 0)))

	# Fuente: pila, agua, pilar y tazon superior.
	var basin := _cylinder(0.40, 0.46, 0.16, 14)
	n.add_child(_part(basin, stone, Vector3(0, 0.08, 0)))
	var pool := _cylinder(0.34, 0.34, 0.05, 14)
	n.add_child(_part(pool, water, Vector3(0, 0.15, 0)))
	var pillar := _cylinder(0.07, 0.09, 0.22, 10)
	n.add_child(_part(pillar, stone, Vector3(0, 0.28, 0)))
	var bowl := _cylinder(0.20, 0.10, 0.10, 12)
	n.add_child(_part(bowl, stone, Vector3(0, 0.44, 0)))

	# Cuatro bancos de madera mirando a la fuente.
	var bench := _box(Vector3(0.12, 0.06, 0.42))
	var leg := _box(Vector3(0.10, 0.14, 0.10))
	for i in range(4):
		var ang := TAU * float(i) / 4.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var seat := _part(bench, wood, dir * 0.85 + Vector3(0.0, 0.17, 0.0))
		seat.rotate_y(-ang)
		n.add_child(seat)
		n.add_child(_part(leg, stone, dir * 0.85 + Vector3(0.0, 0.07, 0.0)))
	return n


# --- Piezas de la cuadrilla del aserradero (mula, tronco y brote) ---
# No proyectan sombra: son props cosmeticos pequenos y su sombra provocaba
# artefactos (manchas/bordes duros) segun el angulo del sol. Ver _no_shadow.

static func _no_shadow(root: Node) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in root.get_children():
		_no_shadow(c)


# Mula de carga: animal pequeno (a escala de los aldeanos) que acompana al
# lenador y tira del tronco hasta el aserradero.
static func mule() -> Node3D:
	var n := Node3D.new()
	var brown := _mat(Color(0.42, 0.30, 0.20))
	var dark := _mat(Color(0.26, 0.19, 0.13))
	n.add_child(_part(_box(Vector3(0.14, 0.14, 0.30)), brown, Vector3(0, 0.25, 0)))
	var neck := _part(_box(Vector3(0.07, 0.14, 0.07)), dark, Vector3(0, 0.33, -0.14))
	neck.rotate_x(-0.4)
	n.add_child(neck)
	n.add_child(_part(_box(Vector3(0.06, 0.06, 0.13)), brown, Vector3(0, 0.41, -0.20)))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			n.add_child(_part(_box(Vector3(0.04, 0.19, 0.04)), dark,
				Vector3(sx * 0.045, 0.095, sz * 0.11)))
	var tail := _part(_box(Vector3(0.02, 0.12, 0.02)), dark, Vector3(0, 0.29, 0.15))
	tail.rotate_x(0.5)
	n.add_child(tail)
	_no_shadow(n)
	return n


# Tronco recien derribado, pequeno. El origen del nodo esta en la base (el mesh
# sube), de modo que al girarlo cae pivoteando sobre el suelo.
static func log_piece() -> Node3D:
	var n := Node3D.new()
	n.add_child(_part(_cylinder(0.055, 0.06, 0.55, 8), _mat(WOOD_COLOR), Vector3(0, 0.275, 0)))
	_no_shadow(n)
	return n


# Brote joven que crece hasta ser un arbol de la capa de vegetacion.
static func sapling() -> Node3D:
	var n := Node3D.new()
	var leaf := _mat(Color(0.16, 0.32, 0.14))
	n.add_child(_part(_cylinder(0.04, 0.06, 0.5, 5), _mat(WOOD_COLOR), Vector3(0, 0.25, 0)))
	n.add_child(_part(_cylinder(0.0, 0.30, 0.55, 6), leaf, Vector3(0, 0.62, 0)))
	n.add_child(_part(_cylinder(0.0, 0.22, 0.48, 6), leaf, Vector3(0, 0.98, 0)))
	_no_shadow(n)
	return n


# Disco translucido para marcar la zona de actuacion de un edificio.
static func zone_disc(radius: float, color: Color) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = 0.02
	m.radial_segments = 48
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi


# --- helpers internos (no son parte de la API publica) ---

static func _part(m: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	return mi


# Cache de materiales por color: antes cada parte de cada edificio colocado
# creaba su propio StandardMaterial3D. Nunca se mutan, asi que se comparten.
static var _mat_cache: Dictionary = {}

static func _mat(c: Color) -> StandardMaterial3D:
	if _mat_cache.has(c):
		return _mat_cache[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	_mat_cache[c] = m
	return m


# Cache de mallas: muchas partes repiten la misma caja o cilindro en cada
# edificio colocado (postes, patas, bloques de cantera...). Se comparten.
static var _box_cache: Dictionary = {}
static var _cyl_cache: Dictionary = {}

static func _box(size: Vector3) -> BoxMesh:
	if _box_cache.has(size):
		return _box_cache[size]
	var m := BoxMesh.new()
	m.size = size
	_box_cache[size] = m
	return m


static func _cylinder(top_r: float, bottom_r: float, height: float, segments: int) -> CylinderMesh:
	var key := Vector4(top_r, bottom_r, height, float(segments))
	if _cyl_cache.has(key):
		return _cyl_cache[key]
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = segments
	_cyl_cache[key] = m
	return m


# Material translucido no sombreado para el fantasma de colocacion.
static func ghost_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
