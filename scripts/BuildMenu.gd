extends CanvasLayer
# Menu de construccion en la parte inferior de la pantalla: un boton por tipo
# de edificio (nombre, produccion y coste). Se elige con clic o con las teclas
# 1-4; la colocacion (fantasma, rotacion y validacion) la gestiona Buildings.

const TYPE_KEYS := ["granero", "granja", "aserradero", "cantera"]

var _buttons := {}
var _group := ButtonGroup.new()
var _buildings: Node
var _hint: Label
var _syncing := false


func _ready() -> void:
	_buildings = get_node("/root/Main/Buildings")
	layer = 10
	_buildings.selection_changed.connect(_on_selection_changed)

	var fill := VBoxContainer.new()
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.alignment = BoxContainer.ALIGNMENT_END
	fill.add_theme_constant_override("separation", 0)
	add_child(fill)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	fill.add_child(panel)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	fill.add_child(spacer)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	for i in TYPE_KEYS.size():
		var t: String = TYPE_KEYS[i]
		var d: Dictionary = _buildings.TYPES[t]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _group
		b.custom_minimum_size = Vector2(170, 74)
		b.text = "%s\n%s\n%s" % [d["name"], d["hint"], _cost_text(d["cost"])]
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_on_pressed.bind(t))
		row.add_child(b)
		_buttons[t] = b

	_hint = Label.new()
	_hint.text = "1-4: elegir edificio   |   clic: colocar   |   mantener R: rotar   |   Esc o clic der.: cancelar"
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_hint)

	Economy.changed.connect(_refresh)
	_refresh()


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _on_pressed(type: String) -> void:
	if _syncing:
		return
	_buildings.select(type)


func _on_selection_changed(type: String) -> void:
	_syncing = true
	for t in TYPE_KEYS:
		(_buttons[t] as Button).button_pressed = (t == type)
	_syncing = false


func _refresh() -> void:
	for t in TYPE_KEYS:
		var d: Dictionary = _buildings.TYPES[t]
		var b: Button = _buttons[t]
		if Economy.can_afford(d["cost"]):
			b.add_theme_color_override("font_color", Color(1, 1, 1))
		else:
			b.add_theme_color_override("font_color", Color(1, 0.55, 0.45))


func _unhandled_input(event: InputEvent) -> void:
	if _buildings.is_placing():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var idx := -1
		match event.keycode:
			KEY_1:
				idx = 0
			KEY_2:
				idx = 1
			KEY_3:
				idx = 2
			KEY_4:
				idx = 3
		if idx >= 0:
			_buildings.select(TYPE_KEYS[idx])
			get_viewport().set_input_as_handled()


func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), k])
	return "costo: " + ", ".join(parts)
