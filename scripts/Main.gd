extends Node3D
# Composition root de la escena principal.
# Resuelve todas las dependencias entre nodos en un solo sitio, con tipos
# fuertes, para que el resto de scripts no tenga que buscar por rutas
# absolutas (`/root/Main/...`) en runtime.
#
# Flujo:
#   1. El autoload Economy existe desde antes que esta escena; le inyectamos
#      DayNightCycle explicitamente (sin lookups lazy).
#   2. Buildings emite mensajes y peticiones de limpieza: los enrutamos por
#      senales a HUD, Vegetation y Rocks (sin acoplamiento directo).
#   3. Los nodos UI (HUD, BuildMenu, Minimap, DevTools) reciben el resto de
#      dependencias via NodePaths tipados en su `@export`.

@onready var day_night: DayNightCycle = $DayNightCycle
@onready var camera: CameraController3D = $CameraRig
@onready var buildings: Buildings = $Buildings
@onready var villagers: Villagers = $Villagers
@onready var vegetation: Vegetation = $Vegetation
@onready var rocks: Rocks = $Rocks
@onready var hud: HUD = $HUD
@onready var build_menu: BuildMenu = $BuildMenu
@onready var minimap: Minimap = $MinimapLayer/Minimap
@onready var dev_tools: DevTools = $DevTools
@onready var info_menu: BuildingInfoMenu = $InfoLayer/BuildingInfoMenu
@onready var crop_menu: CropSelectMenu = $CropSelectMenu
@onready var game_over: GameOverOverlay = $GameOverOverlay
@onready var paths: Paths = $Paths
@onready var bridges: Bridges = $Bridges


func _ready() -> void:
	# Economy es un autoload y sobrevive al recargar Main.tscn. Cada nueva
	# partida debe empezar con el estado económico inicial.
	Economy.reset()
	Economy.bind_day_night(day_night)

	buildings.message_requested.connect(hud.show_message)
	buildings.building_built.connect(minimap._on_building)
	buildings.place_clear_requested.connect(vegetation.clear_near)
	buildings.place_clear_requested.connect(rocks.clear_near)
	paths.message_requested.connect(hud.show_message)
	paths.path_clear_requested.connect(vegetation.clear_near)
	paths.path_clear_requested.connect(rocks.clear_near)
	bridges.message_requested.connect(hud.show_message)
	info_menu.bind(buildings, villagers)
	info_menu.bind_camera(camera)
	crop_menu.bind_camera(camera)
	buildings.crop_select_requested.connect(crop_menu.open)
	crop_menu.crop_selected.connect(buildings.choose_field_crop)
	crop_menu.cancelled.connect(buildings.cancel_field_crop_selection)
	buildings.building_focus_changed.connect(_on_building_focus)
	buildings.building_demolished.connect(minimap._on_building_demolished)
	villagers.message_requested.connect(hud.show_message)
	villagers.workers_changed.connect(buildings.set_worker_count)
	villagers.worker_efficiency_changed.connect(buildings.set_worker_efficiency)
	villagers.workers_present_changed.connect(buildings.set_workers_present)
	buildings.work_area_changed.connect(villagers.set_work_area)
	villagers.population_changed.connect(hud.update_population)
	villagers.homeless_changed.connect(hud.update_homeless)
	villagers.defeat_requested.connect(_on_defeat_requested)
	villagers.refresh_population()


func _on_building_focus(rec: BuildingRecord, screen_pos: Vector2) -> void:
	if rec == null:
		info_menu.hide_menu()
	else:
		info_menu.show_for(rec, screen_pos)


func _on_defeat_requested(reason: String) -> void:
	game_over.show_defeat(reason)
	get_tree().paused = true
