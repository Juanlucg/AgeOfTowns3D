extends RefCounted
class_name FieldMesh
## Geometria del campo de cultivo: suelo adaptado al relieve, valla perimetral
## y plantas en grid via MultiMesh.
##
## Extraido de [Buildings] para aislar la complejidad geometrica.
## Acepta un [Callable] opcional [param get_height] para tests con altura
## sintetica (por defecto usa [Terrain].height_at).
##
## El campo se construye en su PROPIO sistema de coordenadas (x a lo ancho, z
## a lo largo, origen en el centro) y se orienta con la rotacion del nodo. Antes
## se construia directamente en coordenadas de mundo alineadas con los ejes:
## [Buildings] calculaba un rectangulo girado con la casa y luego lo aplastaba
## a su caja envolvente, asi que con la granja girada el campo no seguia la
## direccion del arrastre (a 30 grados, arrastrar 6x3 m daba un campo de 7x5,5)
## y ademas se comia la esquina de la casa.
##
## Girar solo alrededor de Y no cambia la altura de ningun punto, asi que las
## alturas se muestrean en la posicion de mundo real y se guardan tal cual como
## coordenada Y local.

const CELL := 0.5
## Franja de tierra desnuda alrededor de los cultivos. Con 0.5 sobraba casi un
## metro de tierra entre la ultima planta y la valla.
const MARGIN := 0.3
## Hueco entre la ultima planta y la valla. Los cultivos llenan el campo hasta
## casi la valla (antes solo cubrian la zona sembrada y quedaba un borde ancho).
const CROP_INSET := 0.06
## Semilla fija para la variacion de altura y giro de cada planta: si dependiera
## del azar, la vista previa cambiaria de aspecto en cada frame mientras
## arrastras el raton.
const CROP_SEED := 20260909
const SOIL_DEPTH := 0.5
const SOIL_RAISE := 0.01
const FENCE_SPACING := 1.0
const SOIL_COLOR := Color(0.40, 0.28, 0.14)
const FENCE_COLOR := Color(0.50, 0.35, 0.18)


## Lo que ocupa de verdad un campo con [param size] de cultivos: la zona
## sembrada mas el margen de tierra, redondeado a celdas enteras.
## [Buildings] la necesita para saber cuanto sitio dejarle a la casa.
static func outer_size(size: Vector2) -> Vector2:
	return Vector2(
		ceilf((size.x + MARGIN * 2.0) / CELL) * CELL,
		ceilf((size.y + MARGIN * 2.0) / CELL) * CELL,
	)


## [param center] es el centro del campo en el mundo, [param size] el tamano de
## la zona sembrada (sin margen) y [param yaw] su orientacion en radianes, la
## misma que la de la granja.
##
## [param crop_color] es el color del cultivo (trigo/zanahoria/bayas),
## [param grow_seconds] lo que tarda en madurar y [param ghost] hace el material
## translucido para la vista previa.
##
## [param house_local] es el centro de la casa en coordenadas del campo y
## [param house_half_side] su media anchura: la valla del lado cercano se corta
## ahi para que la casa quede encajada en el hueco. Con house_half_side <= 0 no
## se abre hueco.
static func build(
	center: Vector2,
	size: Vector2,
	yaw: float,
	crop_color: Color,
	grow_seconds: float,
	crop_id: String,
	ghost: bool,
	get_height: Callable = Callable(),
	house_local: Vector2 = Vector2.ZERO,
	house_half_side: float = -1.0
) -> Node3D:
	if not get_height.is_valid():
		get_height = func(p: Vector2) -> float: return Terrain.height_at(p)

	# Ejes del campo vistos desde el mundo: +z local hacia `back`, +x hacia `side`.
	var back := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(back.y, -back.x)
	# Altura del terreno bajo un punto dado en coordenadas del campo.
	var h := func(lx: float, lz: float) -> float:
		return get_height.call(center + side * lx + back * lz) as float

	var outer := outer_size(size)
	var hx: float = outer.x * 0.5
	var hz: float = outer.y * 0.5

	var node := Node3D.new()
	node.position = Vector3(center.x, 0.0, center.y)
	# Una rotacion en Y manda el punto local (x,z) a (x·cos + z·sin, -x·sin + z·cos).
	# Con yaw+PI, el eje local +z cae sobre `back` y el +x sobre `side`.
	node.rotation.y = yaw + PI

	var soil_mat := _ghost_mat(Color(0.3, 0.25, 0.15, 0.5)) if ghost else _mat(SOIL_COLOR)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# --- Suelo: triangulos adaptandose al terreno ---
	var gz: float = -hz
	while gz < hz - 0.001:
		var gx: float = -hx
		while gx < hx - 0.001:
			var x1: float = gx + CELL
			var z1: float = gz + CELL
			var y00: float = h.call(gx, gz) + SOIL_RAISE
			var y10: float = h.call(x1, gz) + SOIL_RAISE
			var y01: float = h.call(gx, z1) + SOIL_RAISE
			var y11: float = h.call(x1, z1) + SOIL_RAISE
			st.add_vertex(Vector3(gx, y00, gz))
			st.add_vertex(Vector3(x1, y10, gz))
			st.add_vertex(Vector3(gx, y01, z1))
			st.add_vertex(Vector3(x1, y10, gz))
			st.add_vertex(Vector3(x1, y11, z1))
			st.add_vertex(Vector3(gx, y01, z1))
			gx += CELL
		gz += CELL

	# --- Paredes laterales, hasta por debajo del punto mas bajo del terreno ---
	var wall_min_h: float = 1e9
	gz = -hz
	while gz <= hz + 0.001:
		var gx: float = -hx
		while gx <= hx + 0.001:
			wall_min_h = minf(wall_min_h, h.call(gx, gz) + SOIL_RAISE)
			gx += CELL
		gz += CELL
	var wall_bot: float = wall_min_h - SOIL_DEPTH

	var wx: float = -hx
	while wx < hx - 0.001:
		var nx: float = wx + CELL
		var ty0: float = h.call(wx, -hz) + SOIL_RAISE
		var ty1: float = h.call(nx, -hz) + SOIL_RAISE
		st.add_vertex(Vector3(wx, ty0, -hz))
		st.add_vertex(Vector3(nx, ty1, -hz))
		st.add_vertex(Vector3(wx, wall_bot, -hz))
		st.add_vertex(Vector3(nx, ty1, -hz))
		st.add_vertex(Vector3(nx, wall_bot, -hz))
		st.add_vertex(Vector3(wx, wall_bot, -hz))
		ty0 = h.call(wx, hz) + SOIL_RAISE
		ty1 = h.call(nx, hz) + SOIL_RAISE
		st.add_vertex(Vector3(nx, ty1, hz))
		st.add_vertex(Vector3(wx, ty0, hz))
		st.add_vertex(Vector3(wx, wall_bot, hz))
		st.add_vertex(Vector3(nx, ty1, hz))
		st.add_vertex(Vector3(wx, wall_bot, hz))
		st.add_vertex(Vector3(nx, wall_bot, hz))
		wx += CELL

	var wz: float = -hz
	while wz < hz - 0.001:
		var nz: float = wz + CELL
		var ty0: float = h.call(-hx, wz) + SOIL_RAISE
		var ty1: float = h.call(-hx, nz) + SOIL_RAISE
		st.add_vertex(Vector3(-hx, ty1, nz))
		st.add_vertex(Vector3(-hx, ty0, wz))
		st.add_vertex(Vector3(-hx, wall_bot, wz))
		st.add_vertex(Vector3(-hx, ty0, wz))
		st.add_vertex(Vector3(-hx, wall_bot, nz))
		st.add_vertex(Vector3(-hx, wall_bot, wz))
		ty0 = h.call(hx, wz) + SOIL_RAISE
		ty1 = h.call(hx, nz) + SOIL_RAISE
		st.add_vertex(Vector3(hx, ty0, wz))
		st.add_vertex(Vector3(hx, ty1, nz))
		st.add_vertex(Vector3(hx, wall_bot, wz))
		st.add_vertex(Vector3(hx, ty1, nz))
		st.add_vertex(Vector3(hx, wall_bot, nz))
		st.add_vertex(Vector3(hx, wall_bot, wz))
		wz += CELL

	st.generate_normals()
	var soil_mi := MeshInstance3D.new()
	soil_mi.mesh = st.commit()
	soil_mi.material_override = soil_mat
	node.add_child(soil_mi)

	# El fantasma enseña la valla (en translucido) para saber donde quedara el
	# campo, pero no los cultivos.
	_add_fence(node, hx, hz, h, house_local.x, house_half_side, ghost)
	if not ghost:
		_add_crops(node, outer, crop_color, grow_seconds, crop_id, h)
	return node


# Valla perimetral con postes cada metro y dos railes horizontales.
# `h` da la altura del terreno para un punto en coordenadas del campo.
#
# La casa se apoya sobre el lado cercano (z = -hz): ahi se abre un hueco del
# ancho de la casa (`house_x` +- `house_half`) y la valla termina/empieza en los
# dos postes que tocan sus esquinas.
static func _add_fence(
	node: Node3D, hx: float, hz: float, h: Callable,
	house_x: float = 0.0, house_half: float = -1.0, ghost: bool = false
) -> void:
	# En el fantasma la valla va translucida para leerse como vista previa.
	var fence_mat := _ghost_mat(Color(FENCE_COLOR.r, FENCE_COLOR.g, FENCE_COLOR.b, 0.55)) \
		if ghost else _mat(FENCE_COLOR)
	var post := BoxMesh.new()
	post.size = Vector3(0.03, 0.2, 0.03)
	var g0 := 0.0
	var g1 := 0.0
	var gap := false
	if house_half > 0.0:
		g0 = clampf(house_x - house_half, -hx, hx)
		g1 = clampf(house_x + house_half, -hx, hx)
		gap = g1 - g0 > 0.05

	# Postes de los lados cercano (z=-hz) y lejano (z=+hz), saltando las
	# esquinas (van aparte, siempre, para no perderlas ni duplicarlas).
	var px: float = -hx
	while px <= hx + 0.01:
		if px > -hx + 0.001 and px < hx - 0.001:
			if not (gap and px > g0 + 0.001 and px < g1 - 0.001):
				node.add_child(_part(post, fence_mat, Vector3(px, h.call(px, -hz) + 0.10, -hz)))
			node.add_child(_part(post, fence_mat, Vector3(px, h.call(px, hz) + 0.10, hz)))
		px += FENCE_SPACING
	# Postes laterales (x=-hx, x=+hx), saltando esquinas.
	var pz: float = -hz
	while pz <= hz + 0.01:
		if pz > -hz + 0.001 and pz < hz - 0.001:
			node.add_child(_part(post, fence_mat, Vector3(-hx, h.call(-hx, pz) + 0.10, pz)))
			node.add_child(_part(post, fence_mat, Vector3(hx, h.call(hx, pz) + 0.10, pz)))
		pz += FENCE_SPACING
	# Las cuatro esquinas, explícitas.
	for sx: float in [-hx, hx]:
		for sz: float in [-hz, hz]:
			node.add_child(_part(post, fence_mat, Vector3(sx, h.call(sx, sz) + 0.10, sz)))
	# Postes de arranque y final del hueco de la casa (solo interiores).
	if gap:
		for gx: float in [g0, g1]:
			if gx > -hx + 0.05 and gx < hx - 0.05:
				node.add_child(_part(post, fence_mat, Vector3(gx, h.call(gx, -hz) + 0.10, -hz)))

	var rail := BoxMesh.new()
	rail.size = Vector3(0.02, 0.02, 1.0)
	# Lados paralelos a z (x = +-hx). Cada tramo sigue la pendiente del terreno.
	pz = -hz
	while pz < hz - 0.01:
		var nz: float = minf(pz + FENCE_SPACING, hz)
		for edge: float in [-hx, hx]:
			for dy: float in [0.15, 0.06]:
				_rail_seg(node, fence_mat, rail, edge, pz, edge, nz, h, dy)
		pz = nz
	# Lado cercano (z=-hz): en dos tramos si la casa abre hueco.
	if gap:
		_add_rails_x(node, fence_mat, rail, h, -hx, g0, -hz)
		_add_rails_x(node, fence_mat, rail, h, g1, hx, -hz)
	else:
		_add_rails_x(node, fence_mat, rail, h, -hx, hx, -hz)
	# Lado lejano (z=+hz).
	_add_rails_x(node, fence_mat, rail, h, -hx, hx, hz)


# Raíles a lo largo de X entre `x0` y `x1`, troceados en tramos de
# FENCE_SPACING y adaptados a la pendiente.
static func _add_rails_x(
	node: Node3D, mat: Material, rail: Mesh, h: Callable,
	x0: float, x1: float, z: float
) -> void:
	if x1 - x0 < 0.05:
		return
	var x: float = x0
	while x < x1 - 0.01:
		var nx: float = minf(x + FENCE_SPACING, x1)
		for dy: float in [0.15, 0.06]:
			_rail_seg(node, mat, rail, x, z, nx, z, h, dy)
		x = nx


# Tramo de rail entre dos puntos del terreno, inclinado para seguirlo. Antes era
# una caja horizontal a la altura media, asi que en pendiente cada tramo quedaba
# a distinta altura y la valla parecia rota (escalones).
static func _rail_seg(
	node: Node3D, mat: Material, rail: Mesh,
	x0: float, z0: float, x1: float, z1: float, h: Callable, dy: float
) -> void:
	var p0 := Vector3(x0, h.call(x0, z0) + dy, z0)
	var p1 := Vector3(x1, h.call(x1, z1) + dy, z1)
	var delta := p1 - p0
	var length := delta.length()
	if length < 0.001:
		return
	var dir := delta / length
	var xc := Vector3.UP.cross(dir)
	if xc.length_squared() < 1e-6:
		xc = Vector3.RIGHT
	xc = xc.normalized()
	var yc := dir.cross(xc).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = rail
	mi.material_override = mat
	mi.transform = Transform3D(Basis(xc, yc, dir * length), (p0 + p1) * 0.5)
	node.add_child(mi)


# Plantas en grid via MultiMesh (una sola draw call para todo el campo).
#
# Los transforms se ponen con set_instance_transform, no rellenando
# MultiMesh.buffer a mano. Antes se hacia a mano con doce floats por planta en
# orden [3x3 identidad, x, y, z], que no es el formato que espera Godot: las
# plantas acababan todas amontonadas en el mismo punto y al nivel del mar, o
# sea enterradas bajo el terreno. Por eso los huertos salian pelados.
#
# Es una llamada por planta en vez de una sola asignacion, pero un huerto son
# como mucho unos cientos de plantas y asi el formato lo pone Godot, no
# nosotros. Es lo que ya hacen Vegetation y Rocks.
static func _add_crops(
	node: Node3D, outer: Vector2, crop_color: Color, grow_seconds: float,
	crop_id: String, h: Callable
) -> void:
	# Cada cultivo tiene su forma, altura, densidad y patron de siembra: no solo
	# cambia el color.
	var shape := _crop_shape(crop_id)
	var plant_height: float = shape["height"]
	var radius: float = shape["radius"]
	var row_spacing: float = shape["row"]
	var plant_spacing: float = shape["plant"]
	var stagger: float = shape["stagger"]
	var yaw_jitter: float = shape["yaw"]
	var h_lo: float = shape["h_lo"]
	var h_hi: float = shape["h_hi"]
	var tint_lo: float = shape["tint_lo"]
	var tint_hi: float = shape["tint_hi"]
	var plant := _plant_mesh(shape["kind"], plant_height, radius)
	var bases := PackedVector3Array()
	var height_var := PackedFloat32Array()
	var yaws := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = CROP_SEED
	# Los cultivos llenan el campo hasta CROP_INSET de la valla (no la tocan).
	# Se descuenta el radio de la planta para que ninguna asome por encima.
	var hx: float = maxf(0.0, outer.x * 0.5 - CROP_INSET - radius)
	var hz: float = maxf(0.0, outer.y * 0.5 - CROP_INSET - radius)
	var row := 0
	var pz: float = -hz + row_spacing * 0.5
	while pz <= hz:
		# Las filas impares pueden ir desplazadas media planta (a tresbolillo).
		var shift: float = plant_spacing * 0.5
		if stagger > 0.0 and row % 2 == 1:
			shift += plant_spacing * stagger
		var px: float = -hx + shift
		while px <= hx:
			bases.append(Vector3(px, h.call(px, pz) + SOIL_RAISE, pz))
			height_var.append(rng.randf_range(h_lo, h_hi))
			yaws.append(rng.randf_range(0.0, yaw_jitter))
			px += plant_spacing
		pz += row_spacing
		row += 1
	if bases.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# Color por instancia (multiplica al del material, ver CropField.setup): da
	# una textura de tonos que rompe el bloque de color plano.
	mm.use_colors = true
	mm.mesh = plant
	mm.instance_count = bases.size()
	for i in bases.size():
		var t := rng.randf_range(tint_lo, tint_hi)
		mm.set_instance_color(i, Color(t, t, t))

	var crops := CropField.new()
	crops.name = "CropField"
	crops.multimesh = mm
	node.add_child(crops)
	crops.setup(plant_height, bases, height_var, yaws, crop_color, grow_seconds)


# Aspecto y forma de cultivar de cada planta. No solo cambia el color: cambian
# la malla, la altura, el tamano, la separacion de los surcos y si van a
# tresbolillo.
#   - Trigo: cajas rectangulares muy juntas: forman una alfombra solida que
#     llena el campo.
#   - Zanahoria: cono invertido (la raiz), en filas mas separadas.
#   - Bayas: racimo de bolas (las frutas), en cuadricula amplia.
static func _crop_shape(crop_id: String) -> Dictionary:
	match crop_id:
		"zanahoria":
			return {"kind": "carrot", "height": 0.22, "radius": 0.10,
				"row": 0.30, "plant": 0.18, "stagger": 0.5,
				"yaw": TAU, "h_lo": 0.85, "h_hi": 1.15,
				"tint_lo": 0.90, "tint_hi": 1.10}
		"bayas":
			return {"kind": "berries", "height": 0.26, "radius": 0.18,
				"row": 0.52, "plant": 0.42, "stagger": 0.5,
				"yaw": TAU, "h_lo": 0.85, "h_hi": 1.15,
				"tint_lo": 0.88, "tint_hi": 1.12}
		_:
			# Trigo: sin giro aleatorio (uniforme), con variacion de altura y de
			# tono por planta para que no parezca una losa amarilla.
			return {"kind": "block", "height": 0.45, "radius": 0.09,
				"row": 0.16, "plant": 0.14, "stagger": 0.5,
				"yaw": 0.0, "h_lo": 0.88, "h_hi": 1.18,
				"tint_lo": 0.78, "tint_hi": 1.16}


static func _plant_mesh(kind: String, height: float, radius: float) -> Mesh:
	match kind:
		"carrot":
			# Cono invertido: ancho arriba, punta abajo.
			var cone := CylinderMesh.new()
			cone.top_radius = radius
			cone.bottom_radius = 0.0
			cone.height = height
			cone.radial_segments = 7
			return cone
		"berries":
			# Racimo de tres bolas, centrado en vertical (alto = height).
			var r := height / 3.0
			var berry := SphereMesh.new()
			berry.radius = r
			berry.height = r * 2.0
			berry.radial_segments = 8
			berry.rings = 4
			var st := SurfaceTool.new()
			st.append_from(berry, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, -r * 0.5, 0.0)))
			st.append_from(berry, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, r * 0.5, 0.0)))
			st.append_from(berry, 0, Transform3D(Basis.IDENTITY, Vector3(r * 0.9, 0.0, r * 0.5)))
			return st.commit()
		_:
			# Bloque de trigo: prisma rectangular.
			var block := BoxMesh.new()
			block.size = Vector3(radius * 2.0, height, radius * 2.0)
			return block


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


static func _ghost_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
