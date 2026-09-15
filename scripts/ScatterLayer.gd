extends Node3D
class_name ScatterLayer
## Base comun de las capas de objetos dispersos por el mapa con [MultiMesh]:
## [Vegetation] (arboles y arbustos) y [Rocks] (cantos).
##
## Las dos hacian exactamente lo mismo, con el codigo duplicado caracter por
## caracter en los dos ficheros: crear una MultiMeshInstance3D vacia por
## variante, recorrer el mapa en un hilo para decidir donde va cada instancia,
## volcar los transforms en el hilo principal y poder retirar los que estorban
## cuando se construye encima.
##
## La subclase pone lo que cambia: las mallas, las probabilidades por bioma y
## el criterio de colocacion.

## MultiMeshInstance3D por variante, en el mismo orden que las mallas.
var _mmis: Array = []

## Tamano de celda del indice espacial de instancias. Con 8 m, un radio de
## limpieza tipico (~5 m) toca como mucho 4 celdas.
const CLEAR_CELL := 8.0

## Indice por capa: MultiMeshInstance3D -> Dictionary[Vector2i, Array[int]].
## La AABB de la MultiMesh abarca el mapa entero, asi que el prefiltro por AABB
## no descartaba nada y cada limpieza recorria todas las instancias de la capa
## (decenas de miles). Con el indice solo se visitan las celdas cercanas.
var _spatial: Dictionary = {}

## Id de la tarea del WorkerThreadPool que puebla la capa. Se guarda para
## esperarla en _exit_tree: si no, salir del juego durante la generacion deja
## un hilo tocando un nodo que Godot esta destruyendo.
var _task_id := -1

## Llimpiezas pendientes durante el primer segundo, cuando la MultiMesh
## todavia no tiene instancias (el populate corre en hilo). Se aplican
## en _apply_populated para que no aparezcan arbustos/rocas dentro de un
## edificio recien puesto durante ese intervalo.
var _pending_clears: Array = []  # entradas: { pos: Vector2, radius: float }
var _populated := false


func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


## Crea una MultiMeshInstance3D vacia por malla y lanza [method _populate] en
## un hilo. La subclase llama a esto al final de su `_ready()`.
##
## El bucle de colocacion recorre el mapa entero (231x231 celdas) consultando
## bioma y altura: en el hilo principal era un paron de varios segundos al
## arrancar. MultiMesh no es thread-safe, asi que el hilo solo calcula
## transforms y el volcado se hace con call_deferred.
func _start_scatter(meshes: Array) -> void:
	_mmis.resize(meshes.size())
	for i in meshes.size():
		_mmis[i] = _create_empty_mmi(meshes[i])
	_task_id = WorkerThreadPool.add_task(_populate)


## Corre en un hilo. La subclase la implementa: solo debe leer datos ya
## generados (el autoload Terrain) y terminar con
## `call_deferred("_apply_populated")`.
func _populate() -> void:
	pass


func _create_empty_mmi(mesh: ArrayMesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mmi


func _assign_transforms(mmi: MultiMeshInstance3D, transforms: Array[Transform3D]) -> void:
	if mmi == null or transforms.is_empty():
		return
	var mm := mmi.multimesh
	mm.instance_count = transforms.size()
	# Se vuelca en una sola pasada y de paso se construye el indice espacial por
	# celdas, mientras ya se tienen los transforms a mano. Las celdas se guardan
	# como Array (tipo referencia) para poder añadir sin recopiar el bucket.
	var grid: Dictionary = {}
	for i in transforms.size():
		var t: Transform3D = transforms[i]
		mm.set_instance_transform(i, t)
		var origin := t.origin
		var cell := Vector2i(int(floor(origin.x / CLEAR_CELL)), int(floor(origin.z / CLEAR_CELL)))
		var bucket: Array
		if grid.has(cell):
			bucket = grid[cell]
		else:
			bucket = []
			grid[cell] = bucket
		bucket.append(i)
	_spatial[mmi] = grid


## Hunde bajo tierra las instancias a menos de `radius` de `world_pos`, para
## dejar sitio a un edificio o a un campo de cultivo.
func clear_near(world_pos: Vector2, radius: float) -> void:
	# Si la capa todavia no esta poblada, encolamos para aplicarlo al
	# terminar el populate (sino el efecto se pierde y aparecen arbustos
	# dentro del edificio que acabamos de poner).
	if not _populated:
		_pending_clears.append({"pos": world_pos, "radius": radius})
		return
	_clear_region(world_pos, radius)


# Llamado por la subclase al final de _apply_populated: vacia la cola
# de limpiezas que llegaron durante el populate.
func _flush_pending_clears() -> void:
	for entry in _pending_clears:
		_clear_region(entry["pos"], entry["radius"])
	_pending_clears.clear()


## Retira la vegetacion/rocas de la zona. Usa el indice por celdas: solo recorre
## los buckets que solapan el cuadrado [world_pos ± radius], no toda la capa.
func _clear_region(world_pos: Vector2, radius: float) -> void:
	var r2 := radius * radius
	var c0 := Vector2i(
		int(floor((world_pos.x - radius) / CLEAR_CELL)),
		int(floor((world_pos.y - radius) / CLEAR_CELL)))
	var c1 := Vector2i(
		int(floor((world_pos.x + radius) / CLEAR_CELL)),
		int(floor((world_pos.y + radius) / CLEAR_CELL)))
	for c in get_children():
		if not (c is MultiMeshInstance3D):
			continue
		var mmi := c as MultiMeshInstance3D
		var mm: MultiMesh = mmi.multimesh
		if mm == null or mm.instance_count == 0:
			continue
		var grid: Dictionary = _spatial.get(mmi, {})
		if grid.is_empty():
			# Capa sin indice (p.ej. aun no volcada): recorrido completo.
			_clear_bruteforce(mm, world_pos, r2)
			continue
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var cell := Vector2i(cx, cz)
				if not grid.has(cell):
					continue
				for i in grid[cell]:
					_sink_if_near(mm, i, world_pos, r2)


func _clear_bruteforce(mm: MultiMesh, world_pos: Vector2, r2: float) -> void:
	for i in mm.instance_count:
		_sink_if_near(mm, i, world_pos, r2)


func _sink_if_near(mm: MultiMesh, i: int, world_pos: Vector2, r2: float) -> void:
	var t: Transform3D = mm.get_instance_transform(i)
	var dx: float = t.origin.x - world_pos.x
	var dz: float = t.origin.z - world_pos.y
	if dx * dx + dz * dz < r2:
		mm.set_instance_transform(i, t.translated(Vector3(0, -50, 0)))
