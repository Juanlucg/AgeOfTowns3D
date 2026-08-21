extends Node3D
# Construcciones del pueblo. Se eligen desde el menu inferior (o teclas 1-4):
# granero (almacen), granja (casita + campo de cultivo elegido), aserradero
# (cabaña abierta con mesa de corte) y cantera (piedra).
# Mientras un tipo esta seleccionado se muestra un fantasma translucido que
# sigue al raton sobre el terreno; R lo rota y el clic lo coloca si el terreno
# y los recursos lo permiten. La base se apoya en el punto mas alto del solar
# y, donde el terreno baja, se genera una pared de piedras para que el edificio
# nunca quede flotando.
# La granja tiene un segundo paso: tras colocar la casita se delimita una zona
# (rectangulo desde la casita hasta el raton) y se elige el cultivo con 1/2/3.

signal building_built(type: String, pos: Vector2)
signal selection_changed(type: String)

const TYPES := {
	"granero": {
		"name": "Granero",
		"cost": {"madera": 25.0, "piedra": 15.0},
		"prod": "",
		"amount": 0.0,
		"interval": 0.0,
		"footprint": 1.0,
		"terrains": ["llanura"],
		"hint": "+50 almacen",
		"color": Color(0.95, 0.65, 0.2),
	},
	"granja": {
		"name": "Granja",
		"cost": {"madera": 25.0},
		"prod": "comida",
		"amount": 2.0,
		"interval": 5.0,
		"footprint": 1.0,
		"terrains": ["llanura"],
		"hint": "casita + campo a elegir",
		"color": Color(0.55, 0.72, 0.3),
	},
	"aserradero": {
		"name": "Aserradero",
		"cost": {"madera": 30.0},
		"prod": "madera",
		"amount": 2.0,
		"interval": 5.0,
		"footprint": 1.1,
		"terrains": ["bosque"],
		"hint": "+2 madera / 5s",
		"color": Color(0.62, 0.42, 0.22),
	},
	"cantera": {
		"name": "Cantera",
		"cost": {"madera": 20.0, "piedra": 10.0},
		"prod": "piedra",
		"amount": 2.0,
		"interval": 5.0,
		"footprint": 1.1,
		"terrains": ["montaña"],
		"hint": "+2 piedra / 5s",
		"color": Color(0.55, 0.55, 0.58),
	},
}

const WOOD_COLOR := Color(0.55, 0.38, 0.20)
const ROOF_COLOR := Color(0.42, 0.26, 0.13)
const STONE_COLOR := Color(0.50, 0.50, 0.52)
const STEEL_COLOR := Color(0.72, 0.72, 0.78)
const SOIL_COLOR := Color(0.40, 0.28, 0.14)
const GHOST_OK := Color(0.30, 1.0, 0.45, 0.45)
const GHOST_BAD := Color(1.0, 0.30, 0.30, 0.45)
const FOUNDATION_STEP := 1.0
const ROTATE_SPEED := 120.0   # grados por segundo manteniendo R

const CROP_COLORS := {
	"trigo": Color(0.85, 0.70, 0.25),
	"zanahoria": Color(0.90, 0.50, 0.20),
	"bayas": Color(0.72, 0.16, 0.18),
}
const CROP_NAMES := {
	"trigo": "Trigo",
	"zanahoria": "Zanahorias",
	"bayas": "Bayas",
}
const FIELD_SPACING := 0.55
const FIELD_MIN := 1.2
const FIELD_MAX_AREA := 60.0
const FIELD_RATE := 0.4     # comida por segundo por m2 de campo

var _pending := ""
var _yaw := 0.0
var _ghost: Node3D = null
var _ghost_building: Node3D = null
var _ghost_foundation: Node3D = null
var _placed: Array = []
var _cam_rig: Node3D
var _field_mode := false
var _field_start := Vector2.ZERO
var _field_crop := "trigo"
var _field_ghost: Node3D = null
var _field_farm: Dictionary = {}
var _field_yaw := 0.0


func _ready() -> void:
	_cam_rig = get_node("/root/Main/CameraRig")


func is_placing() -> bool:
	return _pending != "" or _field_mode


func select(type: String) -> void:
	if _field_mode:
		return
	if not TYPES.has(type):
		return
	if _pending == type:
		deselect()
		return
	deselect()
	_pending = type
	_yaw = 0.0
	_ghost = Node3D.new()
	_ghost_building = _build_mesh(type, _ghost_mat(GHOST_OK))
	_ghost.add_child(_ghost_building)
	_ghost_foundation = Node3D.new()
	_ghost.add_child(_ghost_foundation)
	add_child(_ghost)
	selection_changed.emit(type)


func deselect() -> void:
	_pending = ""
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
		_ghost_building = null
		_ghost_foundation = null
	selection_changed.emit("")


func _process(delta: float) -> void:
	_tick_production(delta)
	if _field_mode:
		_update_field_ghost()
		return
	if _pending == "" or _ghost == null:
		return
	if Input.is_key_pressed(KEY_R):
		_yaw = fmod(_yaw + ROTATE_SPEED * delta, 360.0)
	var ground: Vector2 = _cam_rig.screen_to_ground(get_viewport().get_mouse_position())
	var d: Dictionary = TYPES[_pending]
	var base_h := _base_height(ground, d["footprint"])
	_ghost.position = Vector3(ground.x, base_h, ground.y)
	_ghost.rotation = Vector3(0.0, deg_to_rad(_yaw), 0.0)
	for c in _ghost_foundation.get_children():
		_ghost_foundation.remove_child(c)
		c.queue_free()
	var valid := _is_valid(ground, _pending)
	_update_ghost_material(GHOST_OK if valid else GHOST_BAD)
	_ghost_foundation.add_child(_make_foundation(ground, d["footprint"], base_h, _ghost_mat(GHOST_OK if valid else GHOST_BAD)))


func _update_ghost_material(color: Color) -> void:
	var m := _ghost_mat(color)
	for c in _ghost_building.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = m


func _tick_production(delta: float) -> void:
	for b in _placed:
		var d: Dictionary = TYPES[b.type]
		if d["prod"] == "":
			continue
		b.timer += delta
		if b.timer >= d["interval"]:
			b.timer = 0.0
			var amt: float = b.get("amount", d["amount"])
			Economy.add(d["prod"], amt)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _field_mode:
			match event.keycode:
				KEY_1:
					_field_crop = "trigo"
				KEY_2:
					_field_crop = "zanahoria"
				KEY_3:
					_field_crop = "bayas"
				KEY_ESCAPE:
					_cancel_field()
			get_viewport().set_input_as_handled()
			return
		if _pending != "":
			if event.keycode == KEY_ESCAPE:
				deselect()
				get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var btn := event as InputEventMouseButton
		if _field_mode and btn.pressed:
			if btn.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_field()
			elif btn.button_index == MOUSE_BUTTON_LEFT:
				_confirm_field()
			get_viewport().set_input_as_handled()
			return
		if _pending != "" and btn.pressed:
			if btn.button_index == MOUSE_BUTTON_RIGHT:
				deselect()
				get_viewport().set_input_as_handled()
			elif btn.button_index == MOUSE_BUTTON_LEFT:
				_place()
				get_viewport().set_input_as_handled()


func _place() -> void:
	var hud := get_node_or_null("/root/Main/HUD")
	var ground: Vector2 = _cam_rig.screen_to_ground(get_viewport().get_mouse_position())
	var d: Dictionary = TYPES[_pending]
	if not _is_valid(ground, _pending):
		var reason := ""
		var cls := Terrain.terrain_type(ground)
		if not (d["terrains"] as Array).has(cls):
			reason = "Solo se puede construir en %s" % _terrains_text(d["terrains"])
		elif not Economy.can_afford(d["cost"]):
			reason = "Recursos insuficientes (%s)" % _cost_text(d["cost"])
		else:
			reason = "Demasiado cerca de otro edificio"
		if hud != null:
			hud.show_message(reason)
		return
	Economy.spend_all(d["cost"])
	if _pending == "granero":
		Economy.granary_count += 1
		Economy.changed.emit()
	var base_h := _base_height(ground, d["footprint"])
	var node := _build_mesh(_pending, null)
	node.rotation = Vector3(0.0, deg_to_rad(_yaw), 0.0)
	node.position = Vector3(ground.x, base_h, ground.y)
	node.add_child(_make_foundation(ground, d["footprint"], base_h, null))
	add_child(node)
	var rec := {"type": _pending, "pos": ground, "yaw": _yaw, "node": node, "timer": 0.0}
	_placed.append(rec)
	building_built.emit(_pending, ground)
	var veg := get_node_or_null("/root/Main/Vegetation")
	if veg != null:
		veg.clear_near(ground, d["footprint"] + 1.0)
	var rocks := get_node_or_null("/root/Main/Rocks")
	if rocks != null:
		rocks.clear_near(ground, d["footprint"] + 1.0)
	if hud != null:
		hud.show_message("%s construido" % d["name"])
	if _pending == "granja":
		# segundo paso: delimitar el campo de cultivo
		_field_mode = true
		var back_dir := Vector2(-sin(deg_to_rad(_yaw)), -cos(deg_to_rad(_yaw)))
		_field_start = ground + back_dir * (TYPES["granja"]["footprint"] * 0.5 + 0.6)
		_field_yaw = _yaw
		_field_crop = "trigo"
		_field_farm = rec
		_field_ghost = Node3D.new()
		add_child(_field_ghost)
		_ghost.visible = false
		if hud != null:
			hud.show_message("Elige la zona con el raton (clic) y el cultivo: 1 Trigo, 2 Zanahorias, 3 Bayas")
		return
	deselect()


func _confirm_field() -> void:
	var hud := get_node_or_null("/root/Main/HUD")
	var ground: Vector2 = _cam_rig.screen_to_ground(get_viewport().get_mouse_position())
	var back := Vector2(-sin(deg_to_rad(_field_yaw)), -cos(deg_to_rad(_field_yaw)))
	var side := Vector2(back.y, -back.x)
	var diff := ground - _field_start
	var depth := maxf(0.0, diff.dot(back))
	var spread := diff.dot(side)
	depth = maxf(depth, FIELD_MIN)
	var rmin := _field_start + back * 0.0 + side * minf(spread, 0.0)
	var rmax := _field_start + back * depth + side * maxf(spread, 0.0)
	if rmin.x > rmax.x:
		var tmp := rmin.x
		rmin.x = rmax.x
		rmax.x = tmp
	if rmin.y > rmax.y:
		var tmp := rmin.y
		rmin.y = rmax.y
		rmax.y = tmp
	var w := rmax.x - rmin.x
	var d := rmax.y - rmin.y
	if w < FIELD_MIN or d < FIELD_MIN:
		if hud != null:
			hud.show_message("Zona demasiado pequena (min %0.0fx%0.0f m)" % [FIELD_MIN, FIELD_MIN])
		return
	if w * d > FIELD_MAX_AREA:
		if hud != null:
			hud.show_message("Zona demasiado grande (max %0.0f m2)" % FIELD_MAX_AREA)
		return
	if not _field_terrain_ok(rmin, rmax):
		if hud != null:
			hud.show_message("Los cultivos necesitan llanura")
		return
	var field := _make_field_mesh(rmin, rmax, SOIL_COLOR, CROP_COLORS[_field_crop], false)
	add_child(field)
	var center := Vector2((rmin.x + rmax.x) * 0.5, (rmin.y + rmax.y) * 0.5)
	var field_radius := maxf(w, d) + 1.5
	var veg := get_node_or_null("/root/Main/Vegetation")
	if veg != null:
		veg.clear_near(center, field_radius)
	var rocks := get_node_or_null("/root/Main/Rocks")
	if rocks != null:
		rocks.clear_near(center, field_radius)
	_field_farm["amount"] = clampf(w * d * FIELD_RATE, 1.0, 25.0)
	_field_farm["crop"] = _field_crop
	Economy.changed.emit()
	var area := int(round(w * d))
	var crop_name: String = CROP_NAMES[_field_crop]
	if hud != null:
		hud.show_message("Campo de %d m2 sembrado de %s" % [area, crop_name])
	_end_field_mode()


func _cancel_field() -> void:
	var hud := get_node_or_null("/root/Main/HUD")
	_placed.erase(_field_farm)
	if _field_farm.has("node") and _field_farm["node"] != null:
		(_field_farm["node"] as Node).queue_free()
	var cost: Dictionary = TYPES["granja"]["cost"]
	for k in cost:
		Economy.amounts[k] = Economy.amounts[k] + cost[k]
	Economy.changed.emit()
	if hud != null:
		hud.show_message("Granja cancelada (recursos devueltos)")
	_end_field_mode()


func _end_field_mode() -> void:
	_field_mode = false
	if _field_ghost != null:
		_field_ghost.queue_free()
		_field_ghost = null
	_field_farm = {}
	deselect()


func _update_field_ghost() -> void:
	if _field_ghost == null:
		return
	var ground: Vector2 = _cam_rig.screen_to_ground(get_viewport().get_mouse_position())
	var back := Vector2(-sin(deg_to_rad(_field_yaw)), -cos(deg_to_rad(_field_yaw)))
	var side := Vector2(back.y, -back.x)
	var diff := ground - _field_start
	var depth := maxf(0.0, diff.dot(back))
	var spread := diff.dot(side)
	depth = maxf(depth, FIELD_MIN)
	var rmin := _field_start + back * 0.0 + side * minf(spread, 0.0)
	var rmax := _field_start + back * depth + side * maxf(spread, 0.0)
	if rmin.x > rmax.x:
		var tmp := rmin.x
		rmin.x = rmax.x
		rmax.x = tmp
	if rmin.y > rmax.y:
		var tmp := rmin.y
		rmin.y = rmax.y
		rmax.y = tmp
	for c in _field_ghost.get_children():
		_field_ghost.remove_child(c)
		c.queue_free()
	var valid := _field_valid(rmin, rmax)
	var soil_color := Color(0.3, 0.25, 0.15, 0.5) if valid else Color(1.0, 0.3, 0.3, 0.4)
	var crop_color: Color = CROP_COLORS[_field_crop]
	crop_color.a = 0.55 if valid else 0.35
	if not valid:
		crop_color = Color(1.0, 0.3, 0.3, 0.4)
	_field_ghost.add_child(_make_field_mesh(rmin, rmax, soil_color, crop_color, true))


func _field_valid(rmin: Vector2, rmax: Vector2) -> bool:
	var w := rmax.x - rmin.x
	var d := rmax.y - rmin.y
	if w < FIELD_MIN or d < FIELD_MIN or w * d > FIELD_MAX_AREA:
		return false
	return _field_terrain_ok(rmin, rmax)


func _field_terrain_ok(rmin: Vector2, rmax: Vector2) -> bool:
	var y := rmin.y
	while y <= rmax.y:
		var x := rmin.x
		while x <= rmax.x:
			if Terrain.terrain_type(Vector2(x, y)) != "llanura":
				return false
			x += 1.0
		y += 1.0
	return true


func _make_field_mesh(rmin: Vector2, rmax: Vector2, soil_color: Color, crop_color: Color, ghost: bool) -> Node3D:
	var node := Node3D.new()
	var cell := 0.5
	var soil_h := 0.5
	var soil_raise := 0.01
	var margin := 0.5
	var rm := Vector2(rmin.x - margin, rmin.y - margin)
	var rx := Vector2(rmax.x + margin, rmax.y + margin)
	var soil_mat := _ghost_mat(soil_color) if ghost else _material(soil_color)
	var cx := float(floori(rm.x / cell) * cell)
	var cz := float(floori(rm.y / cell) * cell)
	var ex := float(ceili(rx.x / cell) * cell)
	var ez := float(ceili(rx.y / cell) * cell)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gx := 0.0
	var gz := 0.0
	var px := 0.0
	gz = cz
	while gz < ez:
		gx = cx
		while gx < ex:
			var x0 := gx
			var z0 := gz
			var x1 := gx + cell
			var z1 := gz + cell
			var y00 := Terrain.height_at(Vector2(x0, z0)) + soil_raise
			var y10 := Terrain.height_at(Vector2(x1, z0)) + soil_raise
			var y01 := Terrain.height_at(Vector2(x0, z1)) + soil_raise
			var y11 := Terrain.height_at(Vector2(x1, z1)) + soil_raise
			st.add_vertex(Vector3(x0, y00, z0))
			st.add_vertex(Vector3(x1, y10, z0))
			st.add_vertex(Vector3(x0, y01, z1))
			st.add_vertex(Vector3(x1, y10, z0))
			st.add_vertex(Vector3(x1, y11, z1))
			st.add_vertex(Vector3(x0, y01, z1))
			gx += cell
		gz += cell
	var wall_min_h := 1e9
	gz = cz
	while gz <= ez:
		gx = cx
		while gx <= ex:
			var ty := Terrain.height_at(Vector2(gx, gz)) + soil_raise
			if ty < wall_min_h:
				wall_min_h = ty
			gx += cell
		gz += cell
	var wall_bot := wall_min_h - soil_h
	gx = cx
	while gx < ex:
		var ty0 := Terrain.height_at(Vector2(gx, cz)) + soil_raise
		var ty1 := Terrain.height_at(Vector2(gx + cell, cz)) + soil_raise
		st.add_vertex(Vector3(gx, ty0, cz))
		st.add_vertex(Vector3(gx + cell, ty1, cz))
		st.add_vertex(Vector3(gx, wall_bot, cz))
		st.add_vertex(Vector3(gx + cell, ty1, cz))
		st.add_vertex(Vector3(gx + cell, wall_bot, cz))
		st.add_vertex(Vector3(gx, wall_bot, cz))
		ty0 = Terrain.height_at(Vector2(gx, ez)) + soil_raise
		ty1 = Terrain.height_at(Vector2(gx + cell, ez)) + soil_raise
		st.add_vertex(Vector3(gx + cell, ty1, ez))
		st.add_vertex(Vector3(gx, ty0, ez))
		st.add_vertex(Vector3(gx, wall_bot, ez))
		st.add_vertex(Vector3(gx + cell, ty1, ez))
		st.add_vertex(Vector3(gx, wall_bot, ez))
		st.add_vertex(Vector3(gx + cell, wall_bot, ez))
		gx += cell
	gz = cz
	while gz < ez:
		var ty0 := Terrain.height_at(Vector2(cx, gz)) + soil_raise
		var ty1 := Terrain.height_at(Vector2(cx, gz + cell)) + soil_raise
		st.add_vertex(Vector3(cx, ty1, gz + cell))
		st.add_vertex(Vector3(cx, ty0, gz))
		st.add_vertex(Vector3(cx, wall_bot, gz))
		st.add_vertex(Vector3(cx, ty0, gz))
		st.add_vertex(Vector3(cx, wall_bot, gz + cell))
		st.add_vertex(Vector3(cx, wall_bot, gz))
		ty0 = Terrain.height_at(Vector2(ex, gz)) + soil_raise
		ty1 = Terrain.height_at(Vector2(ex, gz + cell)) + soil_raise
		st.add_vertex(Vector3(ex, ty0, gz))
		st.add_vertex(Vector3(ex, ty1, gz + cell))
		st.add_vertex(Vector3(ex, wall_bot, gz))
		st.add_vertex(Vector3(ex, ty1, gz + cell))
		st.add_vertex(Vector3(ex, wall_bot, gz + cell))
		st.add_vertex(Vector3(ex, wall_bot, gz))
		gz += cell
	st.generate_normals()
	var mesh := st.commit()
	var soil_mi := MeshInstance3D.new()
	soil_mi.mesh = mesh
	soil_mi.material_override = soil_mat
	node.add_child(soil_mi)
	if not ghost:
		var fence_post := BoxMesh.new()
		fence_post.size = Vector3(0.03, 0.2, 0.03)
		var fence_mat := _material(Color(0.50, 0.35, 0.18))
		var post_spacing := 1.0
		var fx0 := cx
		var fx1 := ex
		var fz0 := cz
		var fz1 := ez
		px = fx0
		while px <= fx1 + 0.01:
			var ph := Terrain.height_at(Vector2(px, fz0))
			node.add_child(_part(fence_post, fence_mat, Vector3(px, ph + 0.10, fz0)))
			ph = Terrain.height_at(Vector2(px, fz1))
			node.add_child(_part(fence_post, fence_mat, Vector3(px, ph + 0.10, fz1)))
			px += post_spacing
		var pz := fz0
		while pz <= fz1 + 0.01:
			var ph := Terrain.height_at(Vector2(fx0, pz))
			node.add_child(_part(fence_post, fence_mat, Vector3(fx0, ph + 0.10, pz)))
			ph = Terrain.height_at(Vector2(fx1, pz))
			node.add_child(_part(fence_post, fence_mat, Vector3(fx1, ph + 0.10, pz)))
			pz += post_spacing
		var rail_seg := BoxMesh.new()
		rail_seg.size = Vector3(0.02, 0.02, 1.0)
		pz = fz0
		while pz < fz1 - 0.01:
			var nz := minf(pz + post_spacing, fz1)
			var seg_len := nz - pz
			var h0 := Terrain.height_at(Vector2(fx0, pz))
			var h1 := Terrain.height_at(Vector2(fx0, nz))
			var mid_h := (h0 + h1) * 0.5
			var r1 := _part(rail_seg, fence_mat, Vector3(fx0, mid_h + 0.15, pz + seg_len * 0.5))
			r1.scale.z = seg_len
			node.add_child(r1)
			r1 = _part(rail_seg, fence_mat, Vector3(fx0, mid_h + 0.06, pz + seg_len * 0.5))
			r1.scale.z = seg_len
			node.add_child(r1)
			h0 = Terrain.height_at(Vector2(fx1, pz))
			h1 = Terrain.height_at(Vector2(fx1, nz))
			mid_h = (h0 + h1) * 0.5
			r1 = _part(rail_seg, fence_mat, Vector3(fx1, mid_h + 0.15, pz + seg_len * 0.5))
			r1.scale.z = seg_len
			node.add_child(r1)
			r1 = _part(rail_seg, fence_mat, Vector3(fx1, mid_h + 0.06, pz + seg_len * 0.5))
			r1.scale.z = seg_len
			node.add_child(r1)
			pz = nz
		px = fx0
		while px < fx1 - 0.01:
			var nx := minf(px + post_spacing, fx1)
			var seg_len := nx - px
			var h0 := Terrain.height_at(Vector2(px, fz0))
			var h1 := Terrain.height_at(Vector2(nx, fz0))
			var mid_h := (h0 + h1) * 0.5
			var r1 := _part(rail_seg, fence_mat, Vector3(px + seg_len * 0.5, mid_h + 0.15, fz0))
			r1.rotation.y = PI * 0.5
			r1.scale.z = seg_len
			node.add_child(r1)
			r1 = _part(rail_seg, fence_mat, Vector3(px + seg_len * 0.5, mid_h + 0.06, fz0))
			r1.rotation.y = PI * 0.5
			r1.scale.z = seg_len
			node.add_child(r1)
			h0 = Terrain.height_at(Vector2(px, fz1))
			h1 = Terrain.height_at(Vector2(nx, fz1))
			mid_h = (h0 + h1) * 0.5
			r1 = _part(rail_seg, fence_mat, Vector3(px + seg_len * 0.5, mid_h + 0.15, fz1))
			r1.rotation.y = PI * 0.5
			r1.scale.z = seg_len
			node.add_child(r1)
			r1 = _part(rail_seg, fence_mat, Vector3(px + seg_len * 0.5, mid_h + 0.06, fz1))
			r1.rotation.y = PI * 0.5
			r1.scale.z = seg_len
			node.add_child(r1)
			px = nx
	var plant := BoxMesh.new()
	plant.size = Vector3(0.12, 0.24, 0.12)
	var transforms := PackedFloat32Array()
	var spacing := FIELD_SPACING
	var py := rmin.y + spacing * 0.5
	while py <= rmax.y:
		px = rmin.x + spacing * 0.5
		while px <= rmax.x:
			var ph := Terrain.height_at(Vector2(px, py))
			transforms.append_array([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, px, ph + 0.12, py])
			px += spacing
		py += spacing
	if transforms.size() > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = plant
		mm.instance_count = transforms.size() / 12
		mm.buffer = transforms
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _ghost_mat(crop_color) if ghost else _material(crop_color)
		node.add_child(mmi)
	return node


func _is_valid(pos: Vector2, type: String) -> bool:
	var d: Dictionary = TYPES[type]
	if not (d["terrains"] as Array).has(Terrain.terrain_type(pos)):
		return false
	if not Economy.can_afford(d["cost"]):
		return false
	var min_dist: float = d["footprint"] + 1.5
	for b in _placed:
		if (b.pos - pos).length() < min_dist:
			return false
	return true


func _build_mesh(type: String, mat: Material) -> Node3D:
	match type:
		"granero":
			return _mesh_granary(mat)
		"granja":
			return _mesh_farm(mat)
		"aserradero":
			return _mesh_sawmill(mat)
		"cantera":
			return _mesh_quarry(mat)
	return Node3D.new()


func _mesh_granary(mat: Material) -> Node3D:
	var n := Node3D.new()
	var wood := mat if mat != null else _material(WOOD_COLOR)
	var roof_mat := mat if mat != null else _material(ROOF_COLOR)
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


func _mesh_farm(mat: Material) -> Node3D:
	var n := Node3D.new()
	var wood := mat if mat != null else _material(WOOD_COLOR)
	var roof_mat := mat if mat != null else _material(ROOF_COLOR)
	var base := BoxMesh.new()
	base.size = Vector3(0.75, 0.5, 0.75)
	n.add_child(_part(base, wood, Vector3(0, 0.25, 0)))
	var door := BoxMesh.new()
	door.size = Vector3(0.12, 0.22, 0.03)
	n.add_child(_part(door, roof_mat, Vector3(0, 0.11, 0.38)))
	n.add_child(_part(_roof_plane(-0.38, 0.50, 0.0, 0.72, 0.86, wood), wood, Vector3.ZERO))
	n.add_child(_part(_roof_plane(0.0, 0.72, 0.38, 0.50, 0.86, wood), wood, Vector3.ZERO))
	n.add_child(_part(_make_gable_wall(-0.38, 0.50, 0.38, 0.72), wood, Vector3(0, 0, -0.42)))
	n.add_child(_part(_make_gable_wall(-0.38, 0.50, 0.38, 0.72), wood, Vector3(0, 0, 0.42)))
	var chimney := BoxMesh.new()
	chimney.size = Vector3(0.08, 0.14, 0.08)
	n.add_child(_part(chimney, roof_mat, Vector3(0.15, 0.72, -0.2)))
	return n


func _roof_plane(x0: float, y0: float, x1: float, y1: float, depth: float, _mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0 := -depth * 0.5
	var z1 := depth * 0.5
	var p0 := Vector3(x0, y0, z0)
	var p1 := Vector3(x1, y1, z0)
	var p2 := Vector3(x0, y0, z1)
	var p3 := Vector3(x1, y1, z1)
	st.add_vertex(p0)
	st.add_vertex(p1)
	st.add_vertex(p2)
	st.add_vertex(p1)
	st.add_vertex(p3)
	st.add_vertex(p2)
	st.add_vertex(p2)
	st.add_vertex(p1)
	st.add_vertex(p0)
	st.add_vertex(p2)
	st.add_vertex(p3)
	st.add_vertex(p1)
	st.generate_normals()
	var mesh := st.commit()
	return mesh


func _make_gable_wall(x_left: float, y_bot: float, x_right: float, ridge_y: float) -> ArrayMesh:
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


func _mesh_sawmill(mat: Material) -> Node3D:
	var n := Node3D.new()
	var wood := mat if mat != null else _material(WOOD_COLOR)
	var roof_mat := mat if mat != null else _material(ROOF_COLOR)
	var steel := mat if mat != null else _material(STEEL_COLOR)
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


func _mesh_quarry(mat: Material) -> Node3D:
	var n := Node3D.new()
	var stone := mat if mat != null else _material(STONE_COLOR)
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


# Altura de apoyo del edificio: el punto mas alto del solar para que nunca se
# entierre en la ladera.
func _base_height(pos: Vector2, footprint: float) -> float:
	var half := footprint * 0.5
	var h := -1e9
	var y := -half
	while y <= half:
		var x := -half
		while x <= half:
			h = maxf(h, Terrain.height_at(pos + Vector2(x, y)))
			x += FOUNDATION_STEP
		y += FOUNDATION_STEP
	return h


# Losa de piedra bajo el edificio y, donde el terreno baja, pilares/pared de
# piedras que rellenan hasta el suelo real. Si `mat` es null usa piedra real.
func _make_foundation(pos: Vector2, footprint: float, base_h: float, mat: Material) -> Node3D:
	var n := Node3D.new()
	var stone := mat if mat != null else _material(STONE_COLOR)
	var slab := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(footprint + 0.5, 0.3, footprint + 0.5)
	slab.mesh = sm
	slab.material_override = stone
	slab.position = Vector3(pos.x, base_h - 0.15, pos.y)
	n.add_child(slab)
	var step := 0.5
	var half := footprint * 0.5 + 0.25
	var y := -half
	while y <= half:
		var x := -half
		while x <= half:
			var h := Terrain.height_at(pos + Vector2(x, y))
			var dh := base_h - h - 0.15
			if dh > 0.08:
				var col := MeshInstance3D.new()
				var cm := BoxMesh.new()
				cm.size = Vector3(step * 1.05, dh, step * 1.05)
				col.mesh = cm
				col.material_override = stone
				col.position = Vector3(pos.x + x, h + dh * 0.5 + 0.05, pos.y + y)
				n.add_child(col)
			x += step
		y += step
	return n


func _part(m: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	return mi


func _ghost_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), k])
	return ", ".join(parts)


func _terrains_text(terrains: Array) -> String:
	var names := {"llanura": "llanura", "bosque": "bosque", "montaña": "montaña"}
	var out := []
	for t in terrains:
		out.append(names.get(t, str(t)))
	return ", ".join(out)
