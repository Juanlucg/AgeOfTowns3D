extends CanvasLayer
# Interfaz de estado global (esquina superior izquierda). Muestra la hora del
# dia, el dia del calendario y la estacion. Se ampliara con mas informacion
# en el futuro (recursos, poblacion, etc.).

const SEASON_COLORS := [
	Color(0.45, 0.78, 0.35),  # primavera: verde
	Color(0.95, 0.78, 0.25),  # verano: dorado
	Color(0.88, 0.48, 0.15),  # otono: naranja
	Color(0.62, 0.78, 0.92),  # invierno: azul claro
]

var _day: Node
var _season_color: ColorRect
var _season_label: Label
var _day_label: Label
var _time_label: Label
var _phase_label: Label
var _weather_label: Label
var _last_key := ""


func _ready() -> void:
	_day = get_node("/root/Main/DayNightCycle")
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

	_update()


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _label(font_size: int, bold := false) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	if bold:
		l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	return l


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var season: int = _day.get_season()
	var key := "%d|%d|%.4f" % [season, _day.get_day(), _day.get_hour()]
	if key == _last_key:
		return
	_last_key = key
	_season_color.color = SEASON_COLORS[season]
	_season_label.text = _day.get_season_name()
	_day_label.text = "Día %d" % _day.get_day()
	_time_label.text = _fmt_hour(_day.get_hour())
	_phase_label.text = _phase(_day.get_hour())
	_weather_label.text = _day.get_weather_name()


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