extends PanelContainer
class_name BuildingTooltip
## Popup que muestra el detalle de un [BuildingDef]: nombre, coste,
## produccion, biomas validos. Se posiciona cerca del raton al hover.

const _BIOME_NAMES := {0: "llanura", 1: "bosque", 2: "montaña"}


func show_for(def: BuildingDef, at: Vector2) -> void:
	_clear()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)
	var title := Label.new()
	title.text = def.display_name
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", def.color)
	vbox.add_child(title)
	_add_row(vbox, "Coste", def.cost_text())
	if def.can_produce():
		var amt := _format_amount(def.prod_amount)
		_add_row(vbox, "Produce", "+%s %s cada %ss" % [amt, String(def.prod_resource), _format_amount(def.prod_interval)])
	if def.hint != "":
		_add_row(vbox, "", def.hint)
	var biomes_str := ", ".join([_BIOME_NAMES.get(b, str(b)) for b in def.biomes])
	_add_row(vbox, "Biomas", biomes_str)
	position = at
	visible = true


func hide_tooltip() -> void:
	visible = false


func _add_row(parent: Container, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	if label != "":
		var l := Label.new()
		l.text = label + ":"
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
		l.custom_minimum_size = Vector2(70, 0)
		row.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 12)
	row.add_child(v)


func _format_amount(n: float) -> String:
	if n == int(n):
		return str(int(n))
	return "%.1f" % n


func _clear() -> void:
	for c in get_children():
		c.queue_free()
