extends CanvasLayer
class_name DevTools
# Panel de herramientas de desarrollador arriba a la derecha:
# - Hora (slider 0..24h + pausa)
# - Estacion (selector)
# - Tiempo/clima (Despejado/Lluvia/Nieve + Auto)
# - Edificios dev (gratis y sin produccion, solo para probar implantacion)

@export var day_night_path: NodePath
@export var buildings_path: NodePath

# Carga explicita (no depende de la resolucion de class_name por el indice).
const UIStyle := preload("res://scripts/UIStyle.gd")

var _day: DayNightCycle
var _buildings: Buildings
var _hour_slider: HSlider
var _hour_label: Label
var _pause_btn: Button
var _season_opt: OptionButton
var _weather_opt: OptionButton
var _dev_check: CheckBox
var _updating := false


func _ready() -> void:
	layer = 11
	_day = get_node_or_null(day_night_path) as DayNightCycle
	_buildings = get_node_or_null(buildings_path) as Buildings
	if _day != null:
		_day.time_changed.connect(_on_time_changed)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.position = Vector2(-340, 16)
	panel.custom_minimum_size = Vector2(320, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Contenido plegable. Se declara antes que el boton porque el lambda de
	# plegado lo captura. El boton vive en title_row (fuera de `body`):
	# antes ocultaba el VBox que lo contenia a el mismo, asi que una vez
	# plegado no habia forma de volver a desplegarlo.
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)

	# Titulo
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	vbox.add_child(title_row)
	var title := Label.new()
	title.text = "Herramientas Dev"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var collapse := Button.new()
	collapse.text = "—"
	collapse.custom_minimum_size = Vector2(24, 24)
	collapse.add_theme_font_size_override("font_size", 12)
	collapse.pressed.connect(func() -> void:
		body.visible = not body.visible
		collapse.text = "—" if body.visible else "+")
	title_row.add_child(collapse)
	vbox.add_child(body)

	body.add_child(HSeparator.new())

	# --- Hora ---
	var h_label := Label.new()
	h_label.text = "Hora del dia"
	h_label.add_theme_font_size_override("font_size", 12)
	h_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	body.add_child(h_label)

	var hour_row := HBoxContainer.new()
	hour_row.add_theme_constant_override("separation", 8)
	body.add_child(hour_row)

	_hour_slider = HSlider.new()
	_hour_slider.min_value = 0.0
	_hour_slider.max_value = 24.0
	_hour_slider.step = 0.05
	_hour_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hour_slider.value_changed.connect(_on_hour_changed)
	hour_row.add_child(_hour_slider)

	_hour_label = Label.new()
	_hour_label.custom_minimum_size = Vector2(52, 0)
	_hour_label.add_theme_font_size_override("font_size", 13)
	_hour_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hour_row.add_child(_hour_label)

	_pause_btn = Button.new()
	_pause_btn.text = "Pausar"
	_pause_btn.toggle_mode = true
	_pause_btn.custom_minimum_size = Vector2(76, 26)
	_pause_btn.add_theme_font_size_override("font_size", 12)
	_pause_btn.toggled.connect(_on_pause_toggled)
	body.add_child(_pause_btn)

	body.add_child(HSeparator.new())

	# --- Estacion ---
	var s_label := Label.new()
	s_label.text = "Estacion"
	s_label.add_theme_font_size_override("font_size", 12)
	s_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	body.add_child(s_label)

	_season_opt = OptionButton.new()
	_season_opt.add_theme_font_size_override("font_size", 13)
	for i in _day.SEASONS.size():
		_season_opt.add_item(_day.SEASONS[i], i)
	_season_opt.item_selected.connect(_on_season_selected)
	body.add_child(_season_opt)

	# --- Tiempo / Clima ---
	var w_label := Label.new()
	w_label.text = "Tiempo (clima)"
	w_label.add_theme_font_size_override("font_size", 12)
	w_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	body.add_child(w_label)

	_weather_opt = OptionButton.new()
	_weather_opt.add_theme_font_size_override("font_size", 13)
	_weather_opt.add_item("Auto (por estacion)", 0)
	_weather_opt.add_item("Despejado", 1)
	_weather_opt.add_item("Lluvia", 2)
	_weather_opt.add_item("Nieve", 3)
	_weather_opt.item_selected.connect(_on_weather_selected)
	body.add_child(_weather_opt)

	body.add_child(HSeparator.new())

	# --- Edificios dev ---
	var b_label := Label.new()
	b_label.text = "Edificios (prueba)"
	b_label.add_theme_font_size_override("font_size", 12)
	b_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	body.add_child(b_label)

	_dev_check = CheckBox.new()
	_dev_check.text = "Colocacion libre (sin coste, sin produccion)"
	_dev_check.add_theme_font_size_override("font_size", 12)
	_dev_check.toggled.connect(_on_dev_toggled)
	body.add_child(_dev_check)

	var hint := Label.new()
	hint.text = "Solo para probar implantacion en el terreno."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(280, 0)
	body.add_child(hint)

	_sync_from_state()
	# Sin _process: el slider sigue a DayNightCycle via la misma senal
	# time_changed que usa HUD (10 Hz en vez de 60 Hz).


func _on_time_changed(day_value: int, _season: int, hour: float, _weather: String) -> void:
	if _updating:
		return
	# _day es la referencia al DayNightCycle de instancia; los parametros
	# del callback usan nombres distintos para no sombrearlo.
	if not _hour_slider.has_focus() and not _day.dev_paused:
		_updating = true
		_hour_slider.value = hour
		_hour_label.text = _fmt_hour(hour)
		_updating = false


func _sync_from_state() -> void:
	if _day == null:
		return
	_updating = true
	_hour_slider.value = _day.get_hour()
	_hour_label.text = _fmt_hour(_day.get_hour())
	_pause_btn.button_pressed = _day.dev_paused
	_pause_btn.text = "Reanudar" if _day.dev_paused else "Pausar"
	_season_opt.selected = _day.get_season()
	if _day._dev_weather_override == "":
		_weather_opt.selected = 0
	elif _day._dev_weather_override == "despejado":
		_weather_opt.selected = 1
	elif _day._dev_weather_override == "lluvia":
		_weather_opt.selected = 2
	else:
		_weather_opt.selected = 3
	if _buildings != null:
		_dev_check.button_pressed = _buildings.dev_free_build
	_updating = false


func _on_hour_changed(v: float) -> void:
	if _updating or _day == null:
		return
	_day.dev_set_hour(v)
	_hour_label.text = _fmt_hour(v)


func _on_pause_toggled(pressed: bool) -> void:
	if _day == null:
		return
	_day.dev_set_paused(pressed)
	_pause_btn.text = "Reanudar" if pressed else "Pausar"


func _on_season_selected(idx: int) -> void:
	if _updating or _day == null:
		return
	_day.dev_set_season(idx)


func _on_weather_selected(idx: int) -> void:
	if _updating or _day == null:
		return
	match idx:
		0:
			_day.dev_set_weather_override("")
		1:
			_day.dev_set_weather_override("despejado")
		2:
			_day.dev_set_weather_override("lluvia")
		3:
			_day.dev_set_weather_override("nieve")


func _on_dev_toggled(pressed: bool) -> void:
	if _buildings != null:
		_buildings.dev_free_build = pressed


func _fmt_hour(h: float) -> String:
	var hh := int(floor(h)) % 24
	var mm := int(floor((h - hh) * 60.0))
	return "%02d:%02d" % [hh, mm]


func _panel_style() -> StyleBoxFlat:
	return UIStyle.dev_panel()
