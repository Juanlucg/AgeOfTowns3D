extends CanvasLayer
class_name BuildMenu
## Menu de construccion en la parte inferior: boton por tipo de edificio
## (nombre, hint, coste) + tooltip al hover con detalle.

@export var buildings_path: NodePath

# Carga explicita (no depende de la resolucion de class_name por el indice).
const UIStyle := preload("res://scripts/UIStyle.gd")
const BuildingTooltip := preload("res://scripts/BuildingTooltip.gd")

const TYPE_KEYS: Array[StringName] = [&"granero", &"granja", &"aserradero", &"cantera"]

var _buttons := {}
var _group := ButtonGroup.new()
var _buildings: Buildings
var _hint: Label
var _syncing := false
var _tooltip: BuildingTooltip


func _ready() -> void:
	_buildings = get_node_or_null(buildings_path) as Buildings
	assert(_buildings != null, "BuildMenu: buildings_path no asignado en el .tscn")
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
		b.custom_minimum_size = Vector2(170, 74)
		b.text = "%s\n%s\n%s" % [d.display_name, d.hint, _cost_text(d.cost)]
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_on_pressed.bind(id))
		b.mouse_entered.connect(_on_button_hover.bind(id))
		b.mouse_exited.connect(_on_button_unhover)
		row.add_child(b)
		_buttons[id] = b

	_hint = Label.new()
	_hint.text = "1-4: elegir edificio   |   clic: colocar   |   mantener R: rotar   |   Esc o clic der.: cancelar   |   Delete: demoler seleccionado"
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
	_buildings.select(String(type))


func _on_selection_changed(type: StringName) -> void:
	_syncing = true
	for t in TYPE_KEYS:
		(_buttons[t] as Button).button_pressed = (t == type)
	_syncing = false


func _on_button_hover(id: StringName) -> void:
	var d := _buildings.get_def(id)
	if d == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_tooltip.show_for(d, Vector2(vp.x - _tooltip.size.x - 20, 20))


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
			_buildings.select(String(TYPE_KEYS[i]))
			get_viewport().set_input_as_handled()
			return


func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), k])
	return "costo: " + ", ".join(parts)
