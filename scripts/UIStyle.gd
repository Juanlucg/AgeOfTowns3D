extends RefCounted
class_name UIStyle
# Estilos UI compartidos. Antes cada CanvasLayer (HUD, BuildMenu, DevTools)
# tenia su propia copia de _panel_style() con pequenas variaciones. Aqui se
# centralizan para que un cambio de tema se haga en un solo sitio.

const PANEL_BG := Color(0, 0, 0, 0.45)
const PANEL_BORDER := Color(1, 1, 1, 0.25)
const PANEL_RADIUS := 6
const PANEL_MARGIN_X := 14
const PANEL_MARGIN_Y := 10

const DEV_PANEL_BG := Color(0, 0, 0, 0.48)
const DEV_PANEL_BORDER := Color(1, 1, 1, 0.22)
const DEV_PANEL_RADIUS := 8
const DEV_PANEL_MARGIN_X := 12
const DEV_PANEL_MARGIN_Y := 10


static func panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(PANEL_RADIUS)
	sb.content_margin_left = PANEL_MARGIN_X
	sb.content_margin_right = PANEL_MARGIN_X
	sb.content_margin_top = PANEL_MARGIN_Y
	sb.content_margin_bottom = PANEL_MARGIN_Y
	return sb


static func dev_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = DEV_PANEL_BG
	sb.border_color = DEV_PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(DEV_PANEL_RADIUS)
	sb.content_margin_left = DEV_PANEL_MARGIN_X
	sb.content_margin_right = DEV_PANEL_MARGIN_X
	sb.content_margin_top = DEV_PANEL_MARGIN_Y
	sb.content_margin_bottom = DEV_PANEL_MARGIN_Y
	return sb
