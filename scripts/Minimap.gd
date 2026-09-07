extends Control
class_name Minimap
# Minimapa de vision general en la esquina inferior derecha: textura del mapa
# completo generada del terreno, rectangulo del area visible de la camara y
# clic para mover la camara al punto elegido.

@export var camera_path: NodePath
@export var buildings_path: NodePath

const SIZE := 220
const MARGIN := 14
const TEX_SIZE := 256
const BORDER_COLOR := Color(0.95, 0.95, 0.92, 0.9)
const VIEW_RECT_COLOR := Color(1.0, 1.0, 1.0, 0.35)

var _tex: ImageTexture
var _cam_rig: CameraController3D
var _buildings: Buildings
var _buildings_on_map: Array = []


func _ready() -> void:
	_tex = Terrain.make_minimap_texture(TEX_SIZE)
	_cam_rig = get_node_or_null(camera_path) as CameraController3D
	_buildings = get_node_or_null(buildings_path) as Buildings
	mouse_filter = Control.MOUSE_FILTER_PASS


func _process(_delta: float) -> void:
	queue_redraw()


func _minimap_rect() -> Rect2:
	return Rect2(Vector2(size.x - SIZE - MARGIN, size.y - SIZE - MARGIN), Vector2(SIZE, SIZE))


func _to_minimap(world: Vector2) -> Vector2:
	var r := _minimap_rect()
	return r.position + Vector2(world.x / Terrain.WORLD_SIZE * SIZE, world.y / Terrain.WORLD_SIZE * SIZE)


func _draw() -> void:
	var r := _minimap_rect()
	draw_rect(Rect2(r.position - Vector2(3, 3), r.size + Vector2(6, 6)), Color(0, 0, 0, 0.45))
	if _tex != null:
		draw_texture_rect(_tex, r, false)
	draw_rect(r, BORDER_COLOR, false, 2.0)
	if _cam_rig == null:
		return
	var vs := get_viewport_rect().size
	var pts := PackedVector2Array([
		_to_minimap(_cam_rig.screen_to_ground(Vector2(0, 0))),
		_to_minimap(_cam_rig.screen_to_ground(Vector2(vs.x, 0))),
		_to_minimap(_cam_rig.screen_to_ground(Vector2(vs.x, vs.y))),
		_to_minimap(_cam_rig.screen_to_ground(Vector2(0, vs.y))),
	])
	draw_polygon(pts, PackedColorArray([VIEW_RECT_COLOR]))
	var c := _cam_rig.global_position
	draw_circle(_to_minimap(Vector2(c.x, c.z)), 3.0, Color(1, 1, 1, 0.9))
	for b in _buildings_on_map:
		draw_circle(_to_minimap(b.pos), 3.0, b.color)


func _on_building(type: StringName, pos: Vector2) -> void:
	var d := _buildings.get_def(type)
	_buildings_on_map.append({"pos": pos, "color": d.color})


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var btn := event as InputEventMouseButton
		if btn.pressed and btn.button_index == MOUSE_BUTTON_LEFT and _minimap_rect().has_point(btn.position):
			var p := btn.position - _minimap_rect().position
			var world := Vector2(p.x / SIZE * Terrain.WORLD_SIZE, p.y / SIZE * Terrain.WORLD_SIZE)
			_cam_rig.move_to(world)
			accept_event()
