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
@onready var vegetation: Vegetation = $Vegetation
@onready var rocks: Rocks = $Rocks
@onready var hud: HUD = $HUD
@onready var build_menu: BuildMenu = $BuildMenu
@onready var minimap: Minimap = $MinimapLayer/Minimap
@onready var dev_tools: DevTools = $DevTools


func _ready() -> void:
	Economy.bind_day_night(day_night)

	buildings.message_requested.connect(hud.show_message)
	buildings.building_built.connect(minimap._on_building)
	buildings.place_clear_requested.connect(vegetation.clear_near)
	buildings.place_clear_requested.connect(rocks.clear_near)
