extends CanvasLayer
class_name CropSelectMenu
## Popup para elegir el cultivo de un campo recien delimitado.
##
## Buildings no conoce la UI: emite [signal Buildings.crop_select_requested] con
## las opciones ([{ "id": String, "name": String, "color": Color }, ...]) y este
## menu responde por [signal crop_selected] o [signal cancelled].
##
## Estilo y comportamiento como el menu de edificio (BuildingInfoMenu): un panel
## compacto, sin atenuar la pantalla. Un Control a pantalla completa y
## transparente absorbe los clics: uno fuera del panel cancela.
##
## El panel queda anclado a la posicion 3D de la granja: cada frame se reproyecta
## a pantalla, asi que sigue al edificio cuando se mueve la camara.

signal crop_selected(id: String)
signal cancelled

const PANEL_MIN_WIDTH := 180.0

var _root: Control = null
var _panel: PanelContainer = null
var _options_box: VBoxContainer = null
var _option_ids: Array[String] = []
var _open := false
# Camara para proyectar el ancla; la inyecta Main. Sin ella el panel se coloca
# una sola vez junto al raton.
var _cam: CameraController3D = null
var _anchor := Vector3.INF


## Camara con la que reproyectar el ancla del menu cada frame.
func bind_camera(cam: CameraController3D) -> void:
	_cam = cam


func _ready() -> void:
	layer = 20
	_build()


func _build() -> void:
	# El nodo raiz del CanvasLayer no se dibuja: hace falta un Control hijo.
	# Transparente (sin atenuar) y STOP para que los clics no lleguen al mundo.
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	_root.gui_input.connect(_on_root_input)
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_MIN_WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_root.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "¿Qué plantar?"
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 4)
	box.add_child(_options_box)

	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.add_theme_font_size_override("font_size", 12)
	cancel.pressed.connect(_on_cancel)
	box.add_child(cancel)


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.14, 0.95)
	sb.border_color = Color(0.4, 0.4, 0.45, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


## Muestra el menu con las opciones que manda Buildings, anclado a la granja
## (`anchor` es su posicion de mundo). Si no hay ancla o camara, cae junto al
## raton.
func open(options: Array, anchor: Vector3 = Vector3.INF) -> void:
	for c in _options_box.get_children():
		_options_box.remove_child(c)
		c.queue_free()
	_option_ids.clear()
	for opt in options:
		var id := String(opt["id"])
		var button := Button.new()
		button.text = String(opt["name"])
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_color_override("font_color", opt["color"])
		button.pressed.connect(_on_crop.bind(id))
		_options_box.add_child(button)
		_option_ids.append(id)
	_anchor = anchor
	_root.visible = true
	_open = true
	# La posicion necesita el tamano ya calculado del panel.
	await get_tree().process_frame
	if not is_instance_valid(_panel):
		return
	if _anchor != Vector3.INF and _cam != null:
		_place_at(_cam.world_to_screen(_anchor))
	else:
		_place_at(get_viewport().get_mouse_position())


# El ancla es un punto del mundo: se reproyecta cada frame para que el panel
# siga pegado a la granja si el jugador mueve la camara.
func _process(_delta: float) -> void:
	if _open and _anchor != Vector3.INF and _cam != null and is_instance_valid(_panel):
		_place_at(_cam.world_to_screen(_anchor))


func _place_at(at: Vector2) -> void:
	# Encima del punto (la granja), como el menu de edificio.
	var vp := get_viewport().get_visible_rect().size
	var pos := at + Vector2(-_panel.size.x * 0.5, -_panel.size.y - 14.0)
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - _panel.size.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vp.y - _panel.size.y - 8.0))
	_panel.position = pos


func close() -> void:
	_root.visible = false
	_open = false


func _on_crop(id: String) -> void:
	close()
	crop_selected.emit(id)


func _on_cancel() -> void:
	close()
	cancelled.emit()


# Clic fuera del panel (el panel y sus botones consumen el suyo): cancela. Solo
# con botones reales: la rueda tambien llega como InputEventMouseButton pulsado
# y cerraba el menu al hacer scroll.
func _on_root_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton and event.pressed \
			and (event.button_index == MOUSE_BUTTON_LEFT \
			or event.button_index == MOUSE_BUTTON_RIGHT):
		_on_cancel()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()
		return
	# Atajos 1-4 equivalentes a los botones del menu.
	if event is InputEventKey and event.pressed and not event.echo:
		var index := -1
		match event.keycode:
			KEY_1: index = 0
			KEY_2: index = 1
			KEY_3: index = 2
			KEY_4: index = 3
		if index >= 0 and index < _option_ids.size():
			_on_crop(_option_ids[index])
			get_viewport().set_input_as_handled()
