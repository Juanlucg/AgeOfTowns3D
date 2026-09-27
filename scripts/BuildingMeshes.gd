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


## Reconstruye el castillete de una cantera ya creada con la planta y altura de su
## roca. `body` es el nodo del modelo (el que lleva el yaw del edificio): vacia
## sus hijos y mete un castillete nuevo, conservando el material y el giro.
## `ground_local` es el Callable de apoyo del terreno (ver [method quarry]).
static func rebuild_quarry(body: Node3D, rock_radius: float, rock_yaw: float,
		ground_local: Callable = Callable(), rock_top_y := 1.1) -> void:
	if body == null:
		return
	# Solo se conserva un material comun (el del fantasma). Si cada pieza tiene
	# el suyo (cantera real: madera, viga, piedra), se deja null para que el
	# castillete nuevo vuelva a usar su paleta.
	var mat := _shared_override(body)
	var rot := body.rotation.y
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var fresh := quarry(mat, rock_radius, rock_yaw, ground_local, rock_top_y)
	fresh.rotation.y = rot
	body.add_child(fresh)


# Material_override comun a todas las piezas del arbol, o null si no lo hay o
# cada pieza tiene el suyo. Sirve para reconstruir un edificio sin perder el
# material del fantasma.
static func _shared_override(root: Node) -> Material:
	var found: Material = null
	var mixed := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n != root and n is MeshInstance3D:
			var o: Material = (n as MeshInstance3D).material_override
			if o == null:
				mixed = true
			elif found == null:
				found = o
			elif found != o:
				mixed = true
		for c in n.get_children():
			stack.append(c)
	return null if mixed else found


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


# Cantera: castillete de madera arriostrado alrededor de la roca. Los postes
# coinciden con las uniones del marco; las vigas laterales terminan contra ellos
# en vez de quedar cortas o cruzarse fuera de las esquinas.
#
# `rock_radius` es el radio en planta de la roca (m). El castillete se dimensiona
# para horquillarla: las patas se abren por fuera de ella y el marco superior
# queda por encima, de modo que la roca queda encajada dentro del armazon y no
# atravesada por las patas. `rock_yaw` gira la planta para que los cuatro postes
# caigan por las esquinas de la roca (que es un icosaedro achatado) en vez de
# sobre dos de sus caras.
#
# `rock_radius` es el radio en planta real de la roca (m): fija la planta del
# castillete (patas por fuera de la piedra) y una altura suficiente para que el
# marco la libre por encima. Los grosores (vigas, patas, escalera) NO escalan
# con la roca: asi una piedra grande no genera una torre desproporcionada.
#
# `ground_local` es un Callable opcional `(local_x, local_z) -> float`: devuelve
# la altura del suelo EN COORDENADAS LOCALES del modelo bajo un punto XZ dado.
# Con el, las patas y la escalera se alargan hacia abajo hasta clavar su pie en
# el terreno (en una ladera el lado de abajo quedaria colgando). Sin el, todo
# acaba en y=0.
static func quarry(mat: Material, rock_radius := 0.58, rock_yaw := 0.0,
		ground_local: Callable = Callable(), rock_top_y := 1.1) -> Node3D:
	var n := Node3D.new()
	var wood := mat if mat != null else _mat(WOOD_COLOR)
	var beam := mat if mat != null else _mat(TIMBER_COLOR)
	var stone := mat if mat != null else _mat(STONE_COLOR)
	var rope := mat if mat != null else _mat(ROPE_COLOR)
	var ground_y := func(lx: float, lz: float) -> float:
		if ground_local.is_valid():
			return float(ground_local.call(lx, lz))
		return 0.0

	# Planta del castillete en XZ: pivote base + rotacion propia (independiente
	# del yaw del edificio, que va en la raiz del cuerpo). gira la planta para
	# que los cuatro postes caigan por las esquinas de la roca (icosaedro
	# achatado) y no sobre dos de sus caras.
	var base := Node3D.new()
	base.rotation.y = rock_yaw
	n.add_child(base)

	# Planta: el lado del marco deja holgura alrededor de la piedra. Los postes
	# verticales van exactamente en los vertices y continuan unos centimetros por
	# encima de las vigas para que la union se lea claramente.
	var frame := maxf(0.58, rock_radius * 1.12)
	# La viga queda apenas por encima de la cima medida de esta roca, en vez de
	# escalar la altura con el radio y dejar un castillete desproporcionado.
	var h := maxf(1.1, rock_top_y + 0.12)
	var post_size := 0.14
	var beam_size := 0.12
	var post_half := post_size * 0.5
	# Los extremos entran un poco en los postes: solapan la madera y no dejan
	# juntas abiertas por tolerancias de coma flotante.
	var beam_span := frame * 2.0
	var lower_y := minf(0.72, h * 0.42)
	var top_beam_y := h - 0.04
	var lashing := _box(Vector3(post_size + 0.025, 0.045, post_size + 0.025))

	# Postes principales. Cada uno apoya bajo el mismo punto donde se encuentran
	# las dos vigas del marco; las longitudes siguen el desnivel del terreno.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var foot_y := minf(0.0, ground_y.call(sx * frame, sz * frame))
			if ground_local.is_valid():
				# Entierra la zapata un poco en el terreno para que las variaciones
				# de muestreo no dejen una rendija visible bajo el apoyo.
				foot_y -= 0.08
			# Zapata de piedra en cada apoyo. El poste se solapa con ella y su base
			# queda ligeramente enterrada cuando se conoce la altura del terreno.
			base.add_child(_part(_box(Vector3(0.22, 0.12, 0.22)), stone,
				Vector3(sx * frame, foot_y + 0.06, sz * frame)))
			var foot_pos := Vector3(sx * frame, foot_y + 0.08, sz * frame)
			var top_pos := Vector3(sx * frame, h + 0.06, sz * frame)
			base.add_child(_beam_between(foot_pos, top_pos, post_size, wood))
			# Atadura justo bajo cada nudo para que se lea la union entre poste y
			# marco, en vez de parecer cuatro piezas que solo se rozan.
			base.add_child(_part(lashing, rope,
				Vector3(sx * frame, top_beam_y - 0.095, sz * frame)))

	# Marco superior e intermedio. Las piezas terminan en la cara interior de los
	# postes, sin atravesar sus centros ni dejar huecos en los extremos.
	for sz in [-1.0, 1.0]:
		var top_x := _box(Vector3(beam_span, beam_size, beam_size))
		base.add_child(_part(top_x, beam, Vector3(0.0, top_beam_y, sz * frame)))
		var tie_x := _box(Vector3(beam_span, 0.10, 0.10))
		base.add_child(_part(tie_x, wood, Vector3(0.0, lower_y, sz * frame)))
	for sx in [-1.0, 1.0]:
		var top_z := _box(Vector3(beam_size, beam_size, beam_span))
		base.add_child(_part(top_z, beam, Vector3(sx * frame, top_beam_y, 0.0)))
		var tie_z := _box(Vector3(0.10, 0.10, beam_span))
		base.add_child(_part(tie_z, wood, Vector3(sx * frame, lower_y, 0.0)))

	# Riostras de esquina: forman triangulos entre los montantes y los dos
	# cinturones, y evitan el aspecto de cuatro patas sueltas.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner_x: float = sx * (frame - post_half)
			var corner_z: float = sz * (frame - post_half)
			var brace_low := lower_y + 0.08
			var brace_high := h - 0.16
			base.add_child(_beam_between(
				Vector3(corner_x, brace_low, sz * frame),
				Vector3(sx * (frame - 0.42), brace_high, sz * frame), 0.075, wood))
			base.add_child(_beam_between(
				Vector3(sx * frame, brace_low, corner_z),
				Vector3(sx * frame, brace_high, sz * (frame - 0.42)), 0.075, wood))

	# Pequeña grua apoyada en el larguero trasero del marco. El mastil y sus
	# diagonales nacen sobre esa viga (no en el hueco central), y triangulan el
	# brazo antes de que este vuele sobre la piedra.
	var hoist_y := h + 0.42
	var mast_z := minf(0.22, frame * 0.3)
	for sz in [-1.0, 1.0]:
		base.add_child(_beam_between(Vector3(-frame, top_beam_y, sz * mast_z),
			Vector3(-frame, hoist_y, sz * mast_z), 0.09, wood))
	base.add_child(_part(_box(Vector3(0.10, 0.09, mast_z * 2.0 + 0.06)), beam,
		Vector3(-frame, hoist_y, 0.0)))
	var tip_x := frame + 0.58
	base.add_child(_beam_between(Vector3(-frame - 0.10, hoist_y + 0.06, 0.0),
		Vector3(tip_x + 0.10, hoist_y + 0.06, 0.0), 0.10, beam))
	for sz in [-1.0, 1.0]:
		base.add_child(_beam_between(Vector3(-frame, top_beam_y, sz * mast_z),
			Vector3(0.18, hoist_y + 0.06, sz * mast_z), 0.075, wood))
	var wheel_y := hoist_y - 0.08
	var wheel := _part(_cylinder(0.10, 0.10, 0.07, 12), stone,
		Vector3(tip_x, wheel_y, 0.0))
	wheel.rotate_x(PI * 0.5)
	base.add_child(wheel)
	var load_y := maxf(0.24, h * 0.42)
	base.add_child(_beam_between(Vector3(tip_x, wheel_y - 0.06, 0.0),
		Vector3(tip_x, load_y + 0.10, 0.0), 0.025, rope))
	base.add_child(_part(_box(Vector3(0.22, 0.20, 0.22)), stone,
		Vector3(tip_x, load_y, 0.0)))

	# Escalera inclinada en el lateral delantero. Se definen los extremos de cada
	# larguero directamente para que ambos pies apoyen en el terreno y la cabeza
	# llegue al marco, sin depender de una rotacion que los separe de las vigas.
	var ladder_bottom := Vector3(0.0,
		minf(0.0, ground_y.call(0.0, frame + 0.28)), frame + 0.28)
	var ladder_top := Vector3(0.0, h + 0.03, frame - 0.07)
	for x_offset in [-0.19, 0.19]:
		base.add_child(_beam_between(
			ladder_bottom + Vector3(x_offset, 0.0, 0.0),
			ladder_top + Vector3(x_offset, 0.0, 0.0), 0.055, wood))
	var ladder_len := ladder_bottom.distance_to(ladder_top)
	var rung_count := maxi(3, int(ladder_len / 0.24))
	for i in range(1, rung_count):
		var t := float(i) / float(rung_count)
		var center := ladder_bottom.lerp(ladder_top, t)
		base.add_child(_beam_between(center + Vector3(-0.19, 0.0, 0.0),
			center + Vector3(0.19, 0.0, 0.0), 0.045, wood))

	# Unos bloques cortados descansan sobre el terreno junto a la escalera.
	var block := _box(Vector3(0.24, 0.16, 0.20))
	var bx := -frame - 0.22
	var bz := frame + 0.22
	var block_ground := minf(0.0, ground_y.call(bx, bz))
	base.add_child(_part(block, stone, Vector3(bx, block_ground + 0.08, bz)))
	base.add_child(_part(block, stone, Vector3(bx, block_ground + 0.24, bz)))
	var bx2 := bx + 0.25
	var bz2 := bz + 0.04
	var block_ground2 := minf(0.0, ground_y.call(bx2, bz2))
	base.add_child(_part(block, stone, Vector3(bx2, block_ground2 + 0.08, bz2)))
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

# Base ortonormal cuyo eje Y local apunta en `dir`: sirve para orientar una caja
# (poste, riostra, larguero) a lo largo de una direccion cualquiera.
static func _basis_from_dir(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := Vector3.UP.cross(y)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func _beam_between(a: Vector3, b: Vector3, thickness: float, mat: Material) -> MeshInstance3D:
	var delta := b - a
	var length := maxf(delta.length(), 0.001)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, length, thickness)
	var beam := _part(mesh, mat, (a + b) * 0.5)
	beam.transform = Transform3D(_basis_from_dir(delta), (a + b) * 0.5)
	return beam


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
