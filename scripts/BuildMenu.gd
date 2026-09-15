extends CanvasLayer
class_name BuildMenu
## Menu de construccion en la parte inferior: boton por tipo de edificio
## (nombre, hint, coste) + tooltip al hover con detalle.

@export var buildings_path: NodePath
@export var paths_path: NodePath

# Carga explicita (no depende de la resolucion de class_name por el indice).
const UIStyle := preload("res://scripts/UIStyle.gd")
const BuildingTooltip := preload("res://scripts/BuildingTooltip.gd")

const TYPE_KEYS: Array[StringName] = [&"granero", &"granja", &"casa", &"aserradero", &"cantera", &"almacen", &"plaza"]

var _buttons := {}
var _group := ButtonGroup.new()
var _buildings: Buildings
var _paths: Paths
var _hint: Label
var _syncing := false
var _tooltip: BuildingTooltip


func _ready() -> void:
	_buildings = get_node_or_null(buildings_path) as Buildings
	if _buildings == null:
		push_error("BuildMenu: buildings_path no apunta a un Buildings en el .tscn")
		return
	_paths = get_node_or_null(paths_path) as Paths
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

	for id in TYPE_KEYS:
		var d := _buildings.get_def(id)
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _group
		b.custom_minimum_size = Vector2(145, 64)
		b.text = "%s\n%s\ncosto: %s" % [d.display_name, d.hint, d.cost_text()]
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_on_pressed.bind(id))
		b.mouse_entered.connect(_on_button_hover.bind(id))
		b.mouse_exited.connect(_on_button_unhover)
		row.add_child(b)
		_buttons[id] = b

	# Boton de caminos (no es un edificio).
	var path_row := HBoxContainer.new()
	path_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(path_row)
	var path_btn := Button.new()
	path_btn.text = "Camino (P)"
	path_btn.custom_minimum_size = Vector2(0, 30)
	path_btn.add_theme_font_size_override("font_size", 12)
	path_btn.pressed.connect(_on_path_pressed)
	path_row.add_child(path_btn)

	_hint = Label.new()
	_hint.text = "1-7: edificio   |   P: camino   |   clic: colocar   |   R: rotar   |   Esc/der.: cancelar   |   Delete: demoler"
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_hint)

	_tooltip = BuildingTooltip.new()
	_tooltip.visible = false
	add_child(_tooltip)

	Economy.changed.connect(_refresh)
	_refresh()


func _panel_style() -> StyleBoxFlat:
	return UIStyle.panel()


func _on_pressed(type: StringName) -> void:
	if _syncing:
		return
	if _paths != null:
		_paths.stop_build()
	_buildings.select(String(type))


func _on_path_pressed() -> void:
	if _paths == null:
		return
	# Camino y edificios son excluyentes: cancelar la colocacion pendiente.
	_buildings.cancel_placement()
	_paths.toggle_build()


func _on_selection_changed(type: StringName) -> void:
	_syncing = true
	for t in TYPE_KEYS:
		(_buttons[t] as Button).button_pressed = (t == type)
	_syncing = false


func _on_button_hover(id: StringName) -> void:
	var d := _buildings.get_def(id)
	if d == null:
		return
	var button := _buttons[id] as Button
	_tooltip.show_for(d, Vector2.ZERO)
	await get_tree().process_frame
	if not is_instance_valid(button) or not is_instance_valid(_tooltip):
		return
	var pos := button.global_position + Vector2(
		(button.size.x - _tooltip.size.x) * 0.5,
		-_tooltip.size.y - 8.0)
	var vp := get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - _tooltip.size.x - 8.0))
	pos.y = maxf(8.0, pos.y)
	_tooltip.position = pos


func _on_button_unhover() -> void:
	_tooltip.hide_tooltip()


func _refresh() -> void:
	for t in TYPE_KEYS:
		var d := _buildings.get_def(t)
		var b: Button = _buttons[t]
		if Economy.can_afford(d.cost):
			b.add_theme_color_override("font_color", Color(1, 1, 1))
		else:
			b.add_theme_color_override("font_color", Color(1, 0.55, 0.45))


func _unhandled_input(event: InputEvent) -> void:
	if _buildings.is_placing():
		return
	for i in TYPE_KEYS.size():
		if event.is_action_pressed("select_building_%d" % (i + 1)):
			if _paths != null:
				_paths.stop_build()
			_buildings.select(String(TYPE_KEYS[i]))
			get_viewport().set_input_as_handled()
			return
