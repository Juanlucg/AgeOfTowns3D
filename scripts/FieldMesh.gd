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
## Franja de tierra desnuda alrededor de los cultivos.
const MARGIN := 0.5
const FIELD_SPACING := 0.55
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
## [param crop_color] es el color del cultivo (trigo/zanahoria/bayas) y
## [param ghost] hace el material translucido para la vista previa.
static func build(
	center: Vector2,
	size: Vector2,
	yaw: float,
	crop_color: Color,
	ghost: bool,
	get_height: Callable = Callable()
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

	if not ghost:
		_add_fence(node, hx, hz, h)
	_add_crops(node, size, crop_color, ghost, h)
	return node


# Valla perimetral con postes cada metro y dos railes horizontales.
# `h` da la altura del terreno para un punto en coordenadas del campo.
static func _add_fence(node: Node3D, hx: float, hz: float, h: Callable) -> void:
	var fence_mat := _mat(FENCE_COLOR)
	var post := BoxMesh.new()
	post.size = Vector3(0.03, 0.2, 0.03)
	var px: float = -hx
	while px <= hx + 0.01:
		node.add_child(_part(post, fence_mat, Vector3(px, h.call(px, -hz) + 0.10, -hz)))
		node.add_child(_part(post, fence_mat, Vector3(px, h.call(px, hz) + 0.10, hz)))
		px += FENCE_SPACING
	var pz: float = -hz
	while pz <= hz + 0.01:
		node.add_child(_part(post, fence_mat, Vector3(-hx, h.call(-hx, pz) + 0.10, pz)))
		node.add_child(_part(post, fence_mat, Vector3(hx, h.call(hx, pz) + 0.10, pz)))
		pz += FENCE_SPACING

	var rail := BoxMesh.new()
	rail.size = Vector3(0.02, 0.02, 1.0)
	# Lados largos (paralelos a z)
	pz = -hz
	while pz < hz - 0.01:
		var nz: float = minf(pz + FENCE_SPACING, hz)
		var seg: float = nz - pz
		for edge: float in [-hx, hx]:
			var mid_h: float = (h.call(edge, pz) + h.call(edge, nz)) * 0.5
			for dy: float in [0.15, 0.06]:
				var r := _part(rail, fence_mat, Vector3(edge, mid_h + dy, pz + seg * 0.5))
				r.scale.z = seg
				node.add_child(r)
		pz = nz
	# Lados cortos (paralelos a x)
	px = -hx
	while px < hx - 0.01:
		var nx: float = minf(px + FENCE_SPACING, hx)
		var seg: float = nx - px
		for edge: float in [-hz, hz]:
			var mid_h: float = (h.call(px, edge) + h.call(nx, edge)) * 0.5
			for dy: float in [0.15, 0.06]:
				var r := _part(rail, fence_mat, Vector3(px + seg * 0.5, mid_h + dy, edge))
				r.rotation.y = PI * 0.5
				r.scale.z = seg
				node.add_child(r)
		px = nx


# Plantas en grid via MultiMesh (una sola draw call para todo el campo).
#
# Los transforms se ponen con set_instance_transform, no rellenando
# MultiMesh.buffer a mano. Antes se hacia a mano con doce floats por planta en
# orden [3x3 identidad, x, y, z], que no es el formato que espera Godot: las
# plantas acababan todas amontonadas en el mismo punto y al nivel del mar, o
# sea enterradas bajo el terreno. Por eso los huertos salian pelados.
#
# Es una llamada por planta en vez de una sola asignacion, pero un huerto son
# como mucho un par de cientos (FIELD_MAX_AREA / FIELD_SPACING^2) y asi el
# formato lo pone Godot, no nosotros. Es lo que ya hacen Vegetation y Rocks.
static func _add_crops(node: Node3D, size: Vector2, crop_color: Color, ghost: bool, h: Callable) -> void:
	var plant := BoxMesh.new()
	plant.size = Vector3(0.12, 0.24, 0.12)
	var spots: Array[Transform3D] = []
	var hx: float = size.x * 0.5
	var hz: float = size.y * 0.5
	var pz: float = -hz + FIELD_SPACING * 0.5
	while pz <= hz:
		var px: float = -hx + FIELD_SPACING * 0.5
		while px <= hx:
			spots.append(Transform3D(Basis.IDENTITY, Vector3(px, h.call(px, pz) + 0.12, pz)))
			px += FIELD_SPACING
		pz += FIELD_SPACING
	if spots.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plant
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, spots[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _ghost_mat(crop_color) if ghost else _mat(crop_color)
	node.add_child(mmi)


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
