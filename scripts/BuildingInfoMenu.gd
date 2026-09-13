extends PanelContainer
class_name BuildingInfoMenu
## Popup contextual al hacer clic en un edificio colocado.
##
## Estructura: CanvasLayer -> [click-catcher fullscreen, este panel].
## El click-catcher captura todos los clics cuando el menu esta visible y
## cierra el menu si caen fuera del panel. Asi evitamos que el clic pase
## al mundo y deseleccione (lo que parecia 'el menu se cierra pero no
## demole').
##
## Layout: header (icono + nombre), descripcion, capacidad, trabajadores,
## storage global y boton Demoler full-width abajo.

const _BIOME_NAMES := {0: "llanura", 1: "bosque", 2: "montaña"}

var _content: VBoxContainer = null
var _catcher: ColorRect = null
var _record: BuildingRecord = null
var _buildings: Buildings = null
var _villagers: Villagers = null
var _last_screen_pos := Vector2.ZERO
var _demolish_button: Button = null
var _assign_button: Button = null
var _release_button: Button = null
var _worker_status_labels: Array[Label] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 100
	custom_minimum_size = Vector2(260, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.14, 0.95)
	sb.border_color = Color(0.4, 0.4, 0.45, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)


func bind(buildings: Buildings, villagers: Villagers = null) -> void:
	_buildings = buildings
	_villagers = villagers
	if _villagers != null:
		_villagers.workers_changed.connect(_on_workers_changed)


func show_for(record: BuildingRecord, at: Vector2) -> void:
	_record = record
	_last_screen_pos = at
	_worker_status_labels.clear()
	# Click-catcher fullscreen para absorber clics fuera del menu.
	if _catcher == null:
		_catcher = ColorRect.new()
		_catcher.color = Color(0, 0, 0, 0.001)   # casi invisible
		_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
		_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
		# Anadimos al padre (InfoLayer) detras del menu.
		get_parent().add_child(_catcher)
		get_parent().move_child(_catcher, get_index())
		_catcher.gui_input.connect(_on_catcher_input)
	_catcher.visible = true

	# Reemplazo atomico del contenido (queue_free es diferido: si no,
	# los hijos viejos y nuevos se solapan).
	if _content != null and is_instance_valid(_content):
		_content.queue_free()
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	# Expandir el VBox para que llene todo el PanelContainer. Sin esto, el
	# VBox se queda en su tamano minimo y queda un hueco entre el final del
	# contenido y el borde inferior del panel (donde caian los clics).
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content)

	var def := _buildings.get_def(record.type)
	if def == null:
		hide_menu()
		return

	_build_header(_content, def)
	if def.description != "":
		_content.add_child(HSeparator.new())
		_build_description(_content, def.description)
	if def.capacity > 0:
		_content.add_child(HSeparator.new())
		_build_capacity(_content, def.capacity, def.capacity_resource)
	if def.worker_count > 0:
		_content.add_child(HSeparator.new())
		_build_workers(_content, def, record.workers, record.pos)
	_content.add_child(HSeparator.new())
	_build_action_bar(_content)

	visible = true
	await get_tree().process_frame
	# Posicion: a la derecha del edificio, dentro del viewport.
	var vp := get_viewport_rect().size
	var pos := at + Vector2(-size.x * 0.5, -size.y - 16)
	pos.x = clampf(pos.x, 8, maxf(8.0, vp.x - size.x - 8.0))
	pos.y = clampf(pos.y, 8, maxf(8.0, vp.y - size.y - 8.0))
	position = pos


func hide_menu() -> void:
	_record = null
	visible = false
	if _catcher != null and is_instance_valid(_catcher):
		_catcher.visible = false


# Captura el clic directamente sobre el rect del boton. Esto evita depender
# de la propagacion de eventos de Button dentro del PanelContainer/CanvasLayer.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		hide_menu()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _assign_button != null and _button_rect(_assign_button).has_point(event.position):
			if _villagers != null:
				_villagers.assign_free_worker(_record.pos)
			get_viewport().set_input_as_handled()
			return
		if _release_button != null and _button_rect(_release_button).has_point(event.position):
			if _villagers != null:
				_villagers.release_worker(_record.pos)
			get_viewport().set_input_as_handled()
			return
		if _demolish_button != null and is_instance_valid(_demolish_button):
			if _button_rect(_demolish_button).has_point(event.position):
				_on_demolish_pressed()
				get_viewport().set_input_as_handled()
				return


func _button_rect(button: Button) -> Rect2:
	return Rect2(button.global_position, button.size)


func has_record() -> bool:
	return _record != null


func _on_catcher_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		hide_menu()
		get_viewport().set_input_as_handled()


# --- builders internos ---

func _build_header(parent: VBoxContainer, def: BuildingDef) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.color = def.color
	row.add_child(icon)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_box)
	var title := Label.new()
	title.text = def.display_name
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", def.color)
	title_box.add_child(title)
	if def.can_produce():
		var sub := Label.new()
		sub.text = "+%s %s / %ss" % [_fmt(def.prod_amount), String(def.prod_resource), _fmt(def.prod_interval)]
		sub.add_theme_font_size_override("font_size", 11)
		sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
		title_box.add_child(sub)


func _build_description(parent: VBoxContainer, text: String) -> void:
	var desc := Label.new()
	desc.text = text
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(230, 0)
	parent.add_child(desc)


func _build_capacity(parent: VBoxContainer, max: int, resource: StringName) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var label := Label.new()
	label.text = "%s:" % String(resource).capitalize()
	label.add_theme_font_size_override("font_size", 12)
	label.custom_minimum_size = Vector2(80, 0)
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = max
	bar.value = 0
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, 14)
	row.add_child(bar)
	var value_label := Label.new()
	value_label.text = "0/%d" % max
	value_label.add_theme_font_size_override("font_size", 12)
	row.add_child(value_label)


func _build_workers(parent: VBoxContainer, def: BuildingDef, assigned: int, position: Vector2) -> void:
	var title := Label.new()
	title.text = "Trabajadores"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	parent.add_child(title)
	for i in def.worker_count:
		var slot := HBoxContainer.new()
		slot.add_theme_constant_override("separation", 6)
		parent.add_child(slot)
		var avatar := ColorRect.new()
		avatar.custom_minimum_size = Vector2(20, 20)
		avatar.color = def.color
		slot.add_child(avatar)
		var name := ""
		if i < def.worker_names.size():
			name = def.worker_names[i]
		else:
			name = "Trabajador %d" % (i + 1)
		var lbl := Label.new()
		lbl.text = name
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.add_child(lbl)
		var mood := Label.new()
		mood.text = "Asignado" if i < assigned else "Libre"
		mood.add_theme_color_override(
			"font_color", Color(0.45, 1.0, 0.55) if i < assigned else Color(1.0, 0.75, 0.4))
		mood.add_theme_font_size_override("font_size", 12)
		slot.add_child(mood)
		_worker_status_labels.append(mood)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	parent.add_child(actions)
	var assign := Button.new()
	_assign_button = assign
	assign.text = "+ Asignar"
	assign.mouse_filter = Control.MOUSE_FILTER_STOP
	assign.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(assign)
	var release := Button.new()
	_release_button = release
	release.text = "- Liberar"
	release.mouse_filter = Control.MOUSE_FILTER_STOP
	release.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(release)


func _on_workers_changed(position: Vector2, count: int) -> void:
	if _record == null or not _record.pos.is_equal_approx(position):
		return
	_record.workers = count
	for i in _worker_status_labels.size():
		var assigned := i < count
		var label := _worker_status_labels[i]
		label.text = "Asignado" if assigned else "Libre"
		label.add_theme_color_override(
			"font_color", Color(0.45, 1.0, 0.55) if assigned else Color(1.0, 0.75, 0.4))


func _build_action_bar(parent: VBoxContainer) -> void:
	# Boton compacto, fijo (no se estira). SIZE_SHRINK_CENTER hace que el
	# VBoxContainer no le fuerce a llenar el ancho: se queda en su minimo.
	var demolish := Button.new()
	_demolish_button = demolish
	demolish.text = "X  Demoler"
	demolish.add_theme_font_size_override("font_size", 12)
	demolish.custom_minimum_size = Vector2(110, 28)
	demolish.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var red := StyleBoxFlat.new()
	red.bg_color = Color(0.7, 0.15, 0.15, 1.0)
	red.set_corner_radius_all(4)
	red.content_margin_left = 8
	red.content_margin_right = 8
	red.content_margin_top = 4
	red.content_margin_bottom = 4
	demolish.add_theme_stylebox_override("normal", red)
	var red_hover := red.duplicate()
	red_hover.bg_color = Color(0.85, 0.2, 0.2, 1.0)
	demolish.add_theme_stylebox_override("hover", red_hover)
	parent.add_child(demolish)
func _on_demolish_pressed() -> void:
	if _record == null or _buildings == null:
		return
	var rec := _record
	hide_menu()
	_buildings.demolish(rec)


func _fmt(n: float) -> String:
	if n == int(n):
		return str(int(n))
	return "%.1f" % n
