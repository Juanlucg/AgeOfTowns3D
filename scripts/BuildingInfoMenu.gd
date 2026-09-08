extends PanelContainer
class_name BuildingInfoMenu
## Popup contextual que aparece al hacer clic en un edificio colocado.
## Inspirado en menus de city-builders (Garrison, Banished...):
## header con icono + nombre + descripcion, barra de capacidad,
## lista de trabajadores con mood, y barra de acciones inferior.

const _BIOME_NAMES := {0: "llanura", 1: "bosque", 2: "montaña"}
const _RESOURCE_COLORS := {
	"madera": Color(0.62, 0.42, 0.22),
	"piedra": Color(0.55, 0.55, 0.58),
	"comida": Color(0.55, 0.72, 0.30),
}


var _record: BuildingRecord = null
var _buildings: Buildings = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 100
	custom_minimum_size = Vector2(280, 0)


func bind(buildings: Buildings) -> void:
	_buildings = buildings


func show_for(record: BuildingRecord, at: Vector2) -> void:
	_record = record
	_clear()
	var def := _buildings.get_def(record.type)
	if def == null:
		hide_menu()
		return

	# --- Header: icono + nombre + cerrar ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	add_child(header)
	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(56, 56)
	icon.color = def.color
	header.add_child(icon)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
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
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(hide_menu)
	header.add_child(close_btn)

	# --- Descripcion ---
	if def.description != "":
		var sep := HSeparator.new()
		add_child(sep)
		var desc := Label.new()
		desc.text = def.description
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(260, 0)
		add_child(desc)

	# --- Capacidad (e.g. granero 300/300 de comida) ---
	if def.capacity > 0:
		add_child(HSeparator.new())
		_add_capacity(def.capacity, def.capacity_resource)

	# --- Trabajadores ---
	if def.worker_count > 0:
		add_child(HSeparator.new())
		_add_workers(def)

	# --- Storage global (resumen rapido) ---
	add_child(HSeparator.new())
	_add_storage_row()

	# --- Barra de acciones inferior ---
	add_child(HSeparator.new())
	_add_action_bar()

	# Posicion: a la derecha del edificio, dentro del viewport.
	var vp := get_viewport_rect().size
	await get_tree().process_frame  # dejar que el layout calcule size
	var pos := at + Vector2(20, -size.y * 0.5)
	pos.x = clampf(pos.x, 8, vp.x - size.x - 8)
	pos.y = clampf(pos.y, 8, vp.y - size.y - 8)
	position = pos
	visible = true


func hide_menu() -> void:
	_record = null
	visible = false


func has_record() -> bool:
	return _record != null


# --- builders internos ---

func _add_capacity(max: int, resource: StringName) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
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


func _add_workers(def: BuildingDef) -> void:
	var title := Label.new()
	title.text = "Trabajadores"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	add_child(title)
	for i in def.worker_count:
		var slot := HBoxContainer.new()
		slot.add_theme_constant_override("separation", 6)
		add_child(slot)
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
		mood.text = "😊"
		mood.add_theme_font_size_override("font_size", 12)
		slot.add_child(mood)


func _add_storage_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	for k in Economy.RESOURCE_NAMES:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		row.add_child(cell)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.color = Economy.RESOURCE_COLORS.get(k, Color.WHITE)
		cell.add_child(dot)
		var amount: int = int(Economy.amounts.get(k, 0.0))
		var cap: int = int(Economy.storage_capacity())
		var lbl := Label.new()
		lbl.text = "%s %d/%d" % [k, amount, cap]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		cell.add_child(lbl)


func _add_action_bar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(bar)

	var spacer_l := Control.new()
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer_l)

	# Demoler (boton principal, color rojo)
	var demolish := Button.new()
	demolish.text = "✕ Demoler (50% reembolso)"
	demolish.add_theme_font_size_override("font_size", 12)
	var red := StyleBoxFlat.new()
	red.bg_color = Color(0.55, 0.18, 0.18, 0.85)
	red.set_corner_radius_all(4)
	red.content_margin_left = 10
	red.content_margin_right = 10
	red.content_margin_top = 4
	red.content_margin_bottom = 4
	demolish.add_theme_stylebox_override("normal", red)
	demolish.pressed.connect(_on_demolish_pressed)
	bar.add_child(demolish)

	var spacer_r := Control.new()
	spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer_r)


# --- handlers ---

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


func _clear() -> void:
	for c in get_children():
		c.queue_free()
