extends CanvasLayer
class_name HUD
## Interfaz de estado global (esquina superior izquierda): estacion, dia,
## hora, fase del dia, clima y panel de economia.
##
## Se actualiza con la senal [signal DayNightCycle.time_changed] (~10 Hz)
## en vez de polleo por frame.

@export var day_night_path: NodePath

# Carga explicita (no depende de la resolucion de class_name por el indice).
const UIStyle := preload("res://scripts/UIStyle.gd")

const SEASON_COLORS := [
	Color(0.45, 0.78, 0.35),  # primavera: verde
	Color(0.95, 0.78, 0.25),  # verano: dorado
	Color(0.88, 0.48, 0.15),  # otono: naranja
	Color(0.62, 0.78, 0.92),  # invierno: azul claro
]
const MSG_TIME_MS := 2800

var _day: DayNightCycle
var _season_color: ColorRect
var _season_label: Label
var _day_label: Label
var _time_label: Label
var _phase_label: Label
var _weather_label: Label
var _last_key := ""
var _res_labels := {}
var _storage_bar: ProgressBar
var _storage_label: Label
var _msg_label: Label
var _msg_timer: Timer


func _ready() -> void:
	_day = get_node_or_null(day_night_path) as DayNightCycle
	assert(_day != null, "HUD: day_night_path no asignado en el .tscn")
	_day.time_changed.connect(_on_time_changed)
	layer = 10

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var season_row := HBoxContainer.new()
	season_row.add_theme_constant_override("separation", 8)
	vbox.add_child(season_row)
	_season_color = ColorRect.new()
	_season_color.custom_minimum_size = Vector2(14, 14)
	season_row.add_child(_season_color)
	_season_label = _label(18)
	season_row.add_child(_season_label)

	_day_label = _label(14)
	vbox.add_child(_day_label)
	_time_label = _label(22, true)
	vbox.add_child(_time_label)
	_phase_label = _label(14)
	vbox.add_child(_phase_label)
	_weather_label = _label(14)
	vbox.add_child(_weather_label)

	vbox.add_child(HSeparator.new())

	for k in Economy.RESOURCE_NAMES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.color = Economy.RESOURCE_COLORS[k]
		row.add_child(dot)
		var l := _label(14)
		row.add_child(l)
		_res_labels[k] = l

	var store_row := HBoxContainer.new()
	store_row.add_theme_constant_override("separation", 8)
	vbox.add_child(store_row)
	_storage_label = _label(14)
	store_row.add_child(_storage_label)
	_storage_bar = ProgressBar.new()
	_storage_bar.custom_minimum_size = Vector2(150, 14)
	_storage_bar.show_percentage = false
	store_row.add_child(_storage_bar)

	var hint := _label(12)
	hint.text = "1-4: elegir edificio (menu inferior)"
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	vbox.add_child(hint)

	_msg_label = _label(14)
	_msg_label.visible = false
	_msg_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	vbox.add_child(_msg_label)

	_msg_timer = Timer.new()
	_msg_timer.one_shot = true
	_msg_timer.wait_time = MSG_TIME_MS / 1000.0
	_msg_timer.timeout.connect(func(): _msg_label.visible = false)
	add_child(_msg_timer)

	Economy.changed.connect(_update_resources)
	_update()
	_update_resources()


func show_message(text: String) -> void:
	_msg_label.text = text
	_msg_label.visible = true
	_msg_timer.start()


func _panel_style() -> StyleBoxFlat:
	return UIStyle.panel()


func _label(font_size: int, bold := false) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	if bold:
		l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	return l


func _on_time_changed(day: int, season: int, hour: float, weather_name: String) -> void:
	_season_color.color = SEASON_COLORS[season]
	_season_label.text = _day.get_season_name()
	_day_label.text = "Día %d" % day
	_time_label.text = _fmt_hour(hour)
	_phase_label.text = _phase(hour)
	_weather_label.text = weather_name


func _update() -> void:
	_on_time_changed(_day.get_day(), _day.get_season(), _day.get_hour(), _day.get_weather_name())


func _update_resources() -> void:
	for k in Economy.RESOURCE_NAMES:
		(_res_labels[k] as Label).text = "%s  %d" % [k.capitalize(), int(Economy.amounts[k])]
	var used := int(Economy.storage_used())
	var cap := int(Economy.storage_capacity())
	_storage_bar.max_value = cap
	_storage_bar.value = used
	_storage_label.text = "Almacen %d/%d" % [used, cap]


func _fmt_hour(h: float) -> String:
	var hh := int(floor(h))
	var mm := int(floor((h - hh) * 60.0))
	return "%02d:%02d" % [hh, mm]


func _phase(h: float) -> String:
	if h < 5.0 or h >= 20.0:
		return "Noche"
	if h < 7.0:
		return "Amanecer"
	if h < 12.0:
		return "Mañana"
	if h < 14.0:
		return "Mediodía"
	if h < 18.0:
		return "Tarde"
	return "Anochecer"
