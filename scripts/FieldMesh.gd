extends RefCounted
class_name FieldMesh
# Genera la geometria del campo de cultivo (suelo adaptado al relieve, valla,
# postes y plantas en grid). Antes era un metodo privado de 200 lineas
# dentro de Buildings.gd. Se extrae para:
#   - Aislar la complejidad geometrica del flujo de colocacion.
#   - Permitir regenerar campos sin recrear Buildings.
#   - Testear la generacion sin escena.
#
# Todas las variables locales usan `:= float / Variant` explicito para evitar
# errores de inferencia en GDScript 4.7 con Callable (get_height.call()).

const FIELD_SPACING := 0.55
const SOIL_COLOR := Color(0.40, 0.28, 0.14)
const FENCE_COLOR := Color(0.50, 0.35, 0.18)


# `crop_color` es el color de los cultivos actuales del campo (trigo/zanahoria/bayas).
# `ghost` controla si el material es translucido (vista previa).
# `get_height` recibe una posicion del mundo y devuelve la altura local del
# terreno; por defecto usa el autoload Terrain.
static func build(
	rmin: Vector2,
	rmax: Vector2,
	crop_color: Color,
	ghost: bool,
	get_height: Callable = Callable()
) -> Node3D:
	if not get_height.is_valid():
		get_height = func(p: Vector2) -> float: return Terrain.height_at(p)
	var node := Node3D.new()
	var cell := 0.5
	var soil_h := 0.5
	var soil_raise := 0.01
	var margin := 0.5
	var rm := Vector2(rmin.x - margin, rmin.y - margin)
	var rx := Vector2(rmax.x + margin, rmax.y + margin)
	var soil_mat := _ghost_mat(Color(0.3, 0.25, 0.15, 0.5)) if ghost else _mat(SOIL_COLOR)
	var cx: float = floori(rm.x / cell) * cell
	var cz: float = floori(rm.y / cell) * cell
	var ex: float = ceili(rx.x / cell) * cell
	var ez: float = ceili(rx.y / cell) * cell
	# --- Suelo: triangulos adaptandose al terreno, con paredes laterales ---
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gz: float = cz
	while gz < ez:
		var gx: float = cx
		while gx < ex:
			var x0: float = gx
			var z0: float = gz
			var x1: float = gx + cell
			var z1: float = gz + cell
			var y00: float = get_height.call(Vector2(x0, z0)) + soil_raise
			var y10: float = get_height.call(Vector2(x1, z0)) + soil_raise
			var y01: float = get_height.call(Vector2(x0, z1)) + soil_raise
			var y11: float = get_height.call(Vector2(x1, z1)) + soil_raise
			st.add_vertex(Vector3(x0, y00, z0))
			st.add_vertex(Vector3(x1, y10, z0))
			st.add_vertex(Vector3(x0, y01, z1))
			st.add_vertex(Vector3(x1, y10, z0))
			st.add_vertex(Vector3(x1, y11, z1))
			st.add_vertex(Vector3(x0, y01, z1))
			gx += cell
		gz += cell
	# Muro inferior (donde el terreno cae por debajo del nivel del campo)
	var wall_min_h: float = 1e9
	gz = cz
	while gz <= ez:
		var gx: float = cx
		while gx <= ex:
			wall_min_h = minf(wall_min_h, get_height.call(Vector2(gx, gz)) + soil_raise)
			gx += cell
		gz += cell
	var wall_bot: float = wall_min_h - soil_h
	var gx: float = cx
	while gx < ex:
		var ty0: float = get_height.call(Vector2(gx, cz)) + soil_raise
		var ty1: float = get_height.call(Vector2(gx + cell, cz)) + soil_raise
		st.add_vertex(Vector3(gx, ty0, cz))
		st.add_vertex(Vector3(gx + cell, ty1, cz))
		st.add_vertex(Vector3(gx, wall_bot, cz))
		st.add_vertex(Vector3(gx + cell, ty1, cz))
		st.add_vertex(Vector3(gx + cell, wall_bot, cz))
		st.add_vertex(Vector3(gx, wall_bot, cz))
		ty0 = get_height.call(Vector2(gx, ez)) + soil_raise
		ty1 = get_height.call(Vector2(gx + cell, ez)) + soil_raise
		st.add_vertex(Vector3(gx + cell, ty1, ez))
		st.add_vertex(Vector3(gx, ty0, ez))
		st.add_vertex(Vector3(gx, wall_bot, ez))
		st.add_vertex(Vector3(gx + cell, ty1, ez))
		st.add_vertex(Vector3(gx, wall_bot, ez))
		st.add_vertex(Vector3(gx + cell, wall_bot, ez))
		gx += cell
	gz = cz
	while gz < ez:
		var ty0: float = get_height.call(Vector2(cx, gz)) + soil_raise
		var ty1: float = get_height.call(Vector2(cx, gz + cell)) + soil_raise
		st.add_vertex(Vector3(cx, ty1, gz + cell))
		st.add_vertex(Vector3(cx, ty0, gz))
		st.add_vertex(Vector3(cx, wall_bot, gz))
		st.add_vertex(Vector3(cx, ty0, gz))
		st.add_vertex(Vector3(cx, wall_bot, gz + cell))
		st.add_vertex(Vector3(cx, wall_bot, gz))
		ty0 = get_height.call(Vector2(ex, gz)) + soil_raise
		ty1 = get_height.call(Vector2(ex, gz + cell)) + soil_raise
		st.add_vertex(Vector3(ex, ty0, gz))
		st.add_vertex(Vector3(ex, ty1, gz + cell))
		st.add_vertex(Vector3(ex, wall_bot, gz))
		st.add_vertex(Vector3(ex, ty1, gz + cell))
		st.add_vertex(Vector3(ex, wall_bot, gz + cell))
		st.add_vertex(Vector3(ex, wall_bot, gz))
		gz += cell
	st.generate_normals()
	var soil_mi := MeshInstance3D.new()
	soil_mi.mesh = st.commit()
	soil_mi.material_override = soil_mat
	node.add_child(soil_mi)
	if not ghost:
		_add_fence(node, cx, cz, ex, ez, get_height)
	_add_crops(node, rmin, rmax, crop_color, ghost, get_height)
	return node


# Valla perimetral con postes cada metro y dos railes horizontales.
static func _add_fence(node: Node3D, fx0: float, fz0: float, fx1: float, fz1: float, get_height: Callable) -> void:
	var fence_mat := _mat(FENCE_COLOR)
	var post := BoxMesh.new()
	post.size = Vector3(0.03, 0.2, 0.03)
	var spacing := 1.0
	var px: float = fx0
	while px <= fx1 + 0.01:
		var ph: float = get_height.call(Vector2(px, fz0))
		node.add_child(_part(post, fence_mat, Vector3(px, ph + 0.10, fz0)))
		ph = get_height.call(Vector2(px, fz1))
		node.add_child(_part(post, fence_mat, Vector3(px, ph + 0.10, fz1)))
		px += spacing
	var pz: float = fz0
	while pz <= fz1 + 0.01:
		var ph: float = get_height.call(Vector2(fx0, pz))
		node.add_child(_part(post, fence_mat, Vector3(fx0, ph + 0.10, pz)))
		ph = get_height.call(Vector2(fx1, pz))
		node.add_child(_part(post, fence_mat, Vector3(fx1, ph + 0.10, pz)))
		pz += spacing
	var rail := BoxMesh.new()
	rail.size = Vector3(0.02, 0.02, 1.0)
	pz = fz0
	while pz < fz1 - 0.01:
		var nz: float = minf(pz + spacing, fz1)
		var seg_len: float = nz - pz
		var h0: float = get_height.call(Vector2(fx0, pz))
		var h1: float = get_height.call(Vector2(fx0, nz))
		var mid_h: float = (h0 + h1) * 0.5
		var r1: MeshInstance3D = _part(rail, fence_mat, Vector3(fx0, mid_h + 0.15, pz + seg_len * 0.5))
		r1.scale.z = seg_len
		node.add_child(r1)
		r1 = _part(rail, fence_mat, Vector3(fx0, mid_h + 0.06, pz + seg_len * 0.5))
		r1.scale.z = seg_len
		node.add_child(r1)
		h0 = get_height.call(Vector2(fx1, pz))
		h1 = get_height.call(Vector2(fx1, nz))
		mid_h = (h0 + h1) * 0.5
		r1 = _part(rail, fence_mat, Vector3(fx1, mid_h + 0.15, pz + seg_len * 0.5))
		r1.scale.z = seg_len
		node.add_child(r1)
		r1 = _part(rail, fence_mat, Vector3(fx1, mid_h + 0.06, pz + seg_len * 0.5))
		r1.scale.z = seg_len
		node.add_child(r1)
		pz = nz
	px = fx0
	while px < fx1 - 0.01:
		var nx: float = minf(px + spacing, fx1)
		var seg_len: float = nx - px
		var h0: float = get_height.call(Vector2(px, fz0))
		var h1: float = get_height.call(Vector2(nx, fz0))
		var mid_h: float = (h0 + h1) * 0.5
		var r1: MeshInstance3D = _part(rail, fence_mat, Vector3(px + seg_len * 0.5, mid_h + 0.15, fz0))
		r1.rotation.y = PI * 0.5
		r1.scale.z = seg_len
		node.add_child(r1)
		r1 = _part(rail, fence_mat, Vector3(px + seg_len * 0.5, mid_h + 0.06, fz0))
		r1.rotation.y = PI * 0.5
		r1.scale.z = seg_len
		node.add_child(r1)
		h0 = get_height.call(Vector2(px, fz1))
		h1 = get_height.call(Vector2(nx, fz1))
		mid_h = (h0 + h1) * 0.5
		r1 = _part(rail, fence_mat, Vector3(px + seg_len * 0.5, mid_h + 0.15, fz1))
		r1.rotation.y = PI * 0.5
		r1.scale.z = seg_len
		node.add_child(r1)
		r1 = _part(rail, fence_mat, Vector3(px + seg_len * 0.5, mid_h + 0.06, fz1))
		r1.rotation.y = PI * 0.5
		r1.scale.z = seg_len
		node.add_child(r1)
		px = nx


# Plantas en grid via MultiMesh (una sola draw call para todo el campo).
static func _add_crops(node: Node3D, rmin: Vector2, rmax: Vector2, crop_color: Color, ghost: bool, get_height: Callable) -> void:
	var plant := BoxMesh.new()
	plant.size = Vector3(0.12, 0.24, 0.12)
	var transforms := PackedFloat32Array()
	var spacing := FIELD_SPACING
	var py: float = rmin.y + spacing * 0.5
	while py <= rmax.y:
		var px: float = rmin.x + spacing * 0.5
		while px <= rmax.x:
			var ph: float = get_height.call(Vector2(px, py))
			transforms.append_array([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, px, ph + 0.12, py])
			px += spacing
		py += spacing
	if transforms.size() == 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plant
	mm.instance_count = transforms.size() / 12
	mm.buffer = transforms
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
