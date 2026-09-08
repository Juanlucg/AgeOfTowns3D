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

## Id de la tarea del WorkerThreadPool que puebla la capa. Se guarda para
## esperarla en _exit_tree: si no, salir del juego durante la generacion deja
## un hilo tocando un nodo que Godot esta destruyendo.
var _task_id := -1


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
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])


## Hunde bajo tierra las instancias a menos de `radius` de `world_pos`, para
## dejar sitio a un edificio o a un campo de cultivo.
##
## El pre-filtro por AABB evita recorrer las decenas de miles de instancias de
## una capa que ni siquiera toca la zona (el mundo mide 300x300 y cada limpieza
## son unos 5 m).
func clear_near(world_pos: Vector2, radius: float) -> void:
	var query_box := AABB(
		Vector3(world_pos.x - radius, -1000.0, world_pos.y - radius),
		Vector3(radius * 2.0, 2000.0, radius * 2.0),
	)
	var r2 := radius * radius
	for c in get_children():
		if c is MultiMeshInstance3D:
			var mm: MultiMesh = (c as MultiMeshInstance3D).multimesh
			if not mm.get_aabb().intersects(query_box):
				continue
			for i in mm.instance_count:
				var t: Transform3D = mm.get_instance_transform(i)
				var dx: float = t.origin.x - world_pos.x
				var dz: float = t.origin.z - world_pos.y
				if dx * dx + dz * dz < r2:
					mm.set_instance_transform(i, t.translated(Vector3(0, -50, 0)))
