extends PanelContainer
class_name BuildingInfoMenu
## Popup contextual que aparece al hacer clic en un edificio colocado.
## Muestra nombre, coste, produccion y un boton para demoler con reembolso.

const _BIOME_NAMES := {0: "llanura", 1: "bosque", 2: "montaña"}


var _record: BuildingRecord = null
var _buildings: Buildings = null
var _on_demolished_cb: Callable = Callable()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 100


func bind(buildings: Buildings) -> void:
	_buildings = buildings


func show_for(record: BuildingRecord, at: Vector2) -> void:
	_record = record
	_clear()
	var def := _buildings.get_def(record.type)
	if def == null:
		hide_menu()
		return
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var title := Label.new()
	title.text = def.display_name
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", def.color)
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_add_row(vbox, "Coste", def.cost_text())
	if def.can_produce():
		_add_row(vbox, "Produce", "+%s %s cada %ss" % [_fmt(def.prod_amount), String(def.prod_resource), _fmt(def.prod_interval)])
	if record.crop != "":
		_add_row(vbox, "Cultivo", record.crop.capitalize())
	var biomes_parts: Array = []
	for b in def.biomes:
		biomes_parts.append(_BIOME_NAMES.get(b, str(b)))
	_add_row(vbox, "Biomas", ", ".join(biomes_parts))

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 6)
	vbox.add_child(button_row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_child(spacer)

	var demolish := Button.new()
	demolish.text = "Demoler (50%% reembolso)"
	demolish.add_theme_font_size_override("font_size", 12)
	demolish.pressed.connect(_on_demolish_pressed)
	button_row.add_child(demolish)

	# Posicion: arriba a la izquierda del edificio, dentro de la pantalla.
	var vp := get_viewport_rect().size
	var pos := at + Vector2(20, -size.y - 10)
	pos.x = clampf(pos.x, 8, vp.x - size.x - 8)
	pos.y = clampf(pos.y, 8, vp.y - size.y - 8)
	position = pos
	visible = true


func hide_menu() -> void:
	_record = null
	visible = false


func has_record() -> bool:
	return _record != null


func _on_demolish_pressed() -> void:
	if _record == null or _buildings == null:
		return
	var rec := _record
	hide_menu()
	_buildings.demolish(rec)


func _add_row(parent: Container, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	if label != "":
		var l := Label.new()
		l.text = label + ":"
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
		l.custom_minimum_size = Vector2(80, 0)
		row.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 12)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(v)


func _fmt(n: float) -> String:
	if n == int(n):
		return str(int(n))
	return "%.1f" % n


func _clear() -> void:
	for c in get_children():
		c.queue_free()
