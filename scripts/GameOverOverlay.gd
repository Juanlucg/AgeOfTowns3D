extends CanvasLayer
class_name GameOverOverlay
## Pantalla de derrota reutilizable para hambre, ataques y futuras condiciones.

const UIStyle := preload("res://scripts/UIStyle.gd")

var _panel: PanelContainer
var _title: Label
var _reason: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	visible = false

	var background := ColorRect.new()
	background.color = Color(0.02, 0.025, 0.04, 0.72)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(380, 210)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(_panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(content)

	_title = Label.new()
	_title.text = "Partida terminada"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	content.add_child(_title)

	_reason = Label.new()
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.custom_minimum_size = Vector2(330, 48)
	_reason.add_theme_font_size_override("font_size", 16)
	content.add_child(_reason)

	var restart := Button.new()
	restart.text = "Reiniciar partida"
	restart.custom_minimum_size = Vector2(0, 38)
	restart.pressed.connect(_on_restart_pressed)
	content.add_child(restart)


func show_defeat(reason: String) -> void:
	_reason.text = reason
	visible = true


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _panel_style() -> StyleBoxFlat:
	var style := UIStyle.panel()
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	return style
