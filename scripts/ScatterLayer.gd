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

## Instancias retiradas de la capa: MultiMeshInstance3D -> Dictionary[int, bool].
## Incluye tanto las hundidas por construir encima ([method clear_near]) como las
## consumidas por la produccion ([method consume_resource]). Sirve para no
## contarlas como recurso disponible y para poder restaurar (rebrote).
var _consumed: Dictionary = {}

## Posicion XZ de cada instancia: MultiMeshInstance3D -> PackedVector2Array.
## Se guarda aparte de la MultiMesh porque leer de ella cruza al servidor de
## render y no es fiable en headless; ademas evita decenas de miles de
## get_instance_transform por consulta de radio.
var _positions: Dictionary = {}

## Capas de yacimiento (rocas): extracciones que rinde cada instancia antes de
## agotarse. 0 = uso unico (comportamiento de la vegetacion). Lo fija la
## subclase con [method set_deposit_amount].
var deposit_amount := 0.0
## Reserva restante por instancia: MultiMeshInstance3D -> Array[float]. Se crea
## de forma perezosa la primera vez que se consulta la capa.
var _reserves: Dictionary = {}

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
	var positions := PackedVector2Array()
	positions.resize(transforms.size())
	for i in transforms.size():
		var t: Transform3D = transforms[i]
		mm.set_instance_transform(i, t)
		var origin := t.origin
		positions[i] = Vector2(origin.x, origin.z)
		var cell := Vector2i(int(floor(origin.x / CLEAR_CELL)), int(floor(origin.z / CLEAR_CELL)))
		var bucket: Array
		if grid.has(cell):
			bucket = grid[cell]
		else:
			bucket = []
			grid[cell] = bucket
		bucket.append(i)
	_spatial[mmi] = grid
	_positions[mmi] = positions


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
	for c in get_children():
		if not (c is MultiMeshInstance3D):
			continue
		var mmi := c as MultiMeshInstance3D
		var positions: PackedVector2Array = _positions.get(mmi, PackedVector2Array())
		if positions.is_empty():
			continue
		var grid: Dictionary = _spatial.get(mmi, {})
		if grid.is_empty():
			# Capa sin indice (p.ej. aun no volcada): recorrido completo.
			for i in positions.size():
				_sink_if_near(mmi, i, world_pos, r2)
			continue
		for cell in _cells_in_radius(world_pos, radius):
			if not grid.has(cell):
				continue
			for i in grid[cell]:
				_sink_if_near(mmi, i, world_pos, r2)


# Celdas del indice espacial que solapan el cuadrado [world_pos ± radius].
func _cells_in_radius(world_pos: Vector2, radius: float) -> Array[Vector2i]:
	var c0 := Vector2i(
		int(floor((world_pos.x - radius) / CLEAR_CELL)),
		int(floor((world_pos.y - radius) / CLEAR_CELL)))
	var c1 := Vector2i(
		int(floor((world_pos.x + radius) / CLEAR_CELL)),
		int(floor((world_pos.y + radius) / CLEAR_CELL)))
	var out: Array[Vector2i] = []
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			out.append(Vector2i(cx, cz))
	return out


## True si la capa ya tiene sus instancias volcadas. Antes de eso no se puede
## contar ni consumir recurso (el populate corre en un hilo).
func is_populated() -> bool:
	return _populated


## Cuantas instancias NO consumidas hay dentro del radio. `variants` vacio =
## todas las variantes de la capa (arboles: [0, 1]; rocas: [0, 1, 2]).
func count_resource(world_pos: Vector2, radius: float, variants: Array[int] = []) -> int:
	if not _populated:
		return 0
	var r2 := radius * radius
	var total := 0
	for vi in _variant_indices(variants):
		if vi < 0 or vi >= _mmis.size():
			continue
		var mmi := _mmis[vi] as MultiMeshInstance3D
		if mmi == null:
			continue
		var positions: PackedVector2Array = _positions.get(mmi, PackedVector2Array())
		if positions.is_empty():
			continue
		var consumed: Dictionary = _consumed.get(mmi, {})
		var grid: Dictionary = _spatial.get(mmi, {})
		if grid.is_empty():
			for i in positions.size():
				if not consumed.has(i) and _near(positions, i, world_pos, r2):
					total += 1
			continue
		for cell in _cells_in_radius(world_pos, radius):
			if not grid.has(cell):
				continue
			for i in grid[cell]:
				if not consumed.has(i) and _near(positions, i, world_pos, r2):
					total += 1
	return total


## Hunde y marca hasta `max_count` instancias cercanas. Devuelve cuantas
## consume de verdad. Las ya consumidas no se vuelven a contar.
func consume_resource(world_pos: Vector2, radius: float, max_count: int, variants: Array[int] = []) -> int:
	if not _populated or max_count <= 0:
		return 0
	var r2 := radius * radius
	var taken := 0
	for vi in _variant_indices(variants):
		if vi < 0 or vi >= _mmis.size():
			continue
		var mmi := _mmis[vi] as MultiMeshInstance3D
		if mmi == null:
			continue
		var positions: PackedVector2Array = _positions.get(mmi, PackedVector2Array())
		if positions.is_empty():
			continue
		var consumed: Dictionary = _consumed.get(mmi, {})
		var grid: Dictionary = _spatial.get(mmi, {})
		if grid.is_empty():
			for i in positions.size():
				if taken >= max_count:
					return taken
				if not consumed.has(i) and _consume_instance(mmi, positions, i, world_pos, r2):
					taken += 1
			continue
		for cell in _cells_in_radius(world_pos, radius):
			if taken >= max_count:
				return taken
			if not grid.has(cell):
				continue
			for i in grid[cell]:
				if taken >= max_count:
					return taken
				if not consumed.has(i) and _consume_instance(mmi, positions, i, world_pos, r2):
					taken += 1
	return taken


## "Deshunde" la instancia consumida mas cercana dentro del radio (rebrote).
## `filter` opcional recibe la posicion original (Vector2) y devuelve true si
## alli se puede restaurar (p.ej. no esta bajo un edificio). Devuelve si pudo.
func restore_resource(world_pos: Vector2, radius: float, variants: Array[int] = [],
		filter: Callable = Callable()) -> bool:
	if not _populated:
		return false
	var r2 := radius * radius
	for vi in _variant_indices(variants):
		if vi < 0 or vi >= _mmis.size():
			continue
		var mmi := _mmis[vi] as MultiMeshInstance3D
		if mmi == null:
			continue
		var consumed: Dictionary = _consumed.get(mmi, {})
		if consumed.is_empty():
			continue
		var positions: PackedVector2Array = _positions.get(mmi, PackedVector2Array())
		if positions.is_empty():
			continue
		var grid: Dictionary = _spatial.get(mmi, {})
		if grid.is_empty():
			for i in positions.size():
				if _restore_instance(mmi, positions, i, world_pos, r2, filter):
					return true
			continue
		for cell in _cells_in_radius(world_pos, radius):
			if not grid.has(cell):
				continue
			for i in grid[cell]:
				if _restore_instance(mmi, positions, i, world_pos, r2, filter):
					return true
	return false


## Define cuantas extracciones rinde cada instancia de esta capa (yacimientos).
## 0 = uso unico (vegetacion).
func set_deposit_amount(amount: float) -> void:
	deposit_amount = maxf(0.0, amount)


## True si la capa usa yacimientos con reserva (rocas).
func uses_deposits() -> bool:
	return deposit_amount > 0.0


## Yacimiento (roca) con reserva mas cercano dentro del radio, o {} si no hay.
## El diccionario devuelto es un handle para [method extract_deposit]:
## {mmi: MultiMeshInstance3D, index: int, pos: Vector2, amount: float}.
func find_deposit(world_pos: Vector2, radius: float, variants: Array[int] = []) -> Dictionary:
	if not _populated or deposit_amount <= 0.0:
		return {}
	var r2 := radius * radius
	var best: Dictionary = {}
	var best_d := INF
	for vi in _variant_indices(variants):
		if vi < 0 or vi >= _mmis.size():
			continue
		var mmi := _mmis[vi] as MultiMeshInstance3D
		if mmi == null:
			continue
		var positions: PackedVector2Array = _positions.get(mmi, PackedVector2Array())
		if positions.is_empty():
			continue
		var consumed: Dictionary = _consumed.get(mmi, {})
		var reserves := _reserve_array(mmi)
		var grid: Dictionary = _spatial.get(mmi, {})
		for i in _candidate_indices(positions, grid, world_pos, radius):
			if consumed.has(i) or reserves[i] <= 0.0:
				continue
			var p := positions[i]
			var dx := p.x - world_pos.x
			var dz := p.y - world_pos.y
			var d2 := dx * dx + dz * dz
			if d2 > r2:
				continue
			if d2 < best_d:
				best_d = d2
				best = {"mmi": mmi, "index": i, "pos": p, "amount": reserves[i]}
	return best


## True si el yacimiento sigue teniendo reserva y no esta agotado/retirado.
func deposit_is_active(deposit: Dictionary) -> bool:
	if deposit.is_empty():
		return false
	var mmi = deposit.get("mmi")
	if mmi == null or not is_instance_valid(mmi):
		return false
	var i: int = deposit.get("index", -1)
	var positions: PackedVector2Array = _positions.get(mmi, PackedVector2Array())
	if i < 0 or i >= positions.size():
		return false
	if (_consumed.get(mmi, {}) as Dictionary).has(i):
		return false
	return deposit_remaining(deposit) > 0.0


## Reserva restante del yacimiento.
func deposit_remaining(deposit: Dictionary) -> float:
	var mmi = deposit.get("mmi")
	if mmi == null:
		return 0.0
	var i: int = deposit.get("index", -1)
	var reserves := _reserve_array(mmi)
	if i < 0 or i >= reserves.size():
		return 0.0
	return maxf(0.0, reserves[i])


## Extrae hasta `amount` de un yacimiento. Si se agota, se hunde y se marca
## como consumido. Devuelve lo extraido de verdad (puede ser menos si la roca
## se queda sin reserva a mitad).
func extract_deposit(deposit: Dictionary, amount: float) -> float:
	if amount <= 0.0 or not deposit_is_active(deposit):
		return 0.0
	var mmi: MultiMeshInstance3D = deposit["mmi"]
	var i: int = deposit["index"]
	var reserves := _reserve_array(mmi)
	var take := minf(amount, reserves[i])
	if take <= 0.0:
		return 0.0
	reserves[i] = reserves[i] - take
	if reserves[i] <= 0.0001:
		_move_instance(mmi, i, -50.0)
		_mark_consumed(mmi, i)
	deposit["amount"] = reserves[i]
	return take


# Reserva por instancia de una capa (creada de forma perezosa). Es un Array
# (tipo referencia) para que las mutaciones persistan en _reserves.
func _reserve_array(mmi: MultiMeshInstance3D) -> Array:
	if not _reserves.has(mmi):
		var positions: PackedVector2Array = _positions.get(mmi, PackedVector2Array())
		var arr := []
		arr.resize(positions.size())
		arr.fill(deposit_amount if deposit_amount > 0.0 else 1.0)
		_reserves[mmi] = arr
	return _reserves[mmi]


# Indices de instancia dentro del cuadrado [world_pos ± radius], reutilizando
# el indice por celdas si existe.
func _candidate_indices(positions: PackedVector2Array, grid: Dictionary,
		world_pos: Vector2, radius: float) -> Array:
	var out: Array = []
	if grid.is_empty():
		for i in positions.size():
			out.append(i)
		return out
	for cell in _cells_in_radius(world_pos, radius):
		if not grid.has(cell):
			continue
		for i in grid[cell]:
			out.append(i)
	return out


## Instancia NO consumida mas cercana dentro del radio, o {} si no hay.
## Devuelve {mmi, index, pos} (sin reservas: vale para vegetacion y yacimientos).
## `exclude` es una lista de Vector2: se saltan las instancias a menos de
## `min_sep` de ellas (para que dos lenadores no elijan el mismo arbol).
func find_nearest(world_pos: Vector2, radius: float, variants: Array[int] = [],
		exclude: Array = [], min_sep := 0.0) -> Dictionary:
	if not _populated:
		return {}
	var r2 := radius * radius
	var best: Dictionary = {}
	var best_d := INF
	for vi in _variant_indices(variants):
		if vi < 0 or vi >= _mmis.size():
			continue
		var mmi := _mmis[vi] as MultiMeshInstance3D
		if mmi == null:
			continue
		var positions: PackedVector2Array = _positions.get(mmi, PackedVector2Array())
		if positions.is_empty():
			continue
		var consumed: Dictionary = _consumed.get(mmi, {})
		var grid: Dictionary = _spatial.get(mmi, {})
		for i in _candidate_indices(positions, grid, world_pos, radius):
			if consumed.has(i):
				continue
			var p := positions[i]
			if not exclude.is_empty() and _excluded(p, exclude, min_sep):
				continue
			var dx := p.x - world_pos.x
			var dz := p.y - world_pos.y
			var d2 := dx * dx + dz * dz
			if d2 > r2:
				continue
			if d2 < best_d:
				best_d = d2
				best = {"mmi": mmi, "index": i, "pos": p, "variant": vi}
	return best


func _excluded(p: Vector2, exclude: Array, min_sep: float) -> bool:
	if min_sep <= 0.0:
		return false
	for ex in exclude:
		if p.distance_to(ex) < min_sep:
			return true
	return false


## Retira una instancia concreta (por handle de [method find_nearest] o
## [method find_deposit]). Devuelve false si ya estaba consumida.
func consume_instance(mmi: MultiMeshInstance3D, index: int) -> bool:
	if mmi == null:
		return false
	var positions: PackedVector2Array = _positions.get(mmi, PackedVector2Array())
	if index < 0 or index >= positions.size():
		return false
	var consumed: Dictionary = _consumed.get(mmi, {})
	if consumed.has(index):
		return false
	_move_instance(mmi, index, -50.0)
	_mark_consumed(mmi, index)
	return true


## "Revive" una instancia consumida en su sitio (replantado del aserradero),
## poniendole el transform nuevo. Evita agrandar el MultiMesh en runtime, que
## podia corromper el buffer y hacer desaparecer instancias. Devuelve si pudo.
func revive_instance(mmi: MultiMeshInstance3D, index: int, xform: Transform3D) -> bool:
	if mmi == null or not is_instance_valid(mmi):
		return false
	var positions: PackedVector2Array = _positions.get(mmi, PackedVector2Array())
	if index < 0 or index >= positions.size():
		return false
	var consumed: Dictionary = _consumed.get(mmi, {})
	if not consumed.has(index):
		return false
	var mm := mmi.multimesh
	if mm == null:
		return false
	mm.set_instance_transform(index, xform)
	positions[index] = Vector2(xform.origin.x, xform.origin.z)
	_positions[mmi] = positions
	consumed.erase(index)
	return true


## Anade una instancia nueva (p.ej. un arbol replantado) y devuelve su indice,
## o -1 si el tipo/variante no existe. Mantiene el indice espacial y las
## posiciones para que cuente como recurso.
func spawn_instance(xform: Transform3D, variant: int) -> int:
	if not _populated or variant < 0 or variant >= _mmis.size():
		return -1
	var mmi := _mmis[variant] as MultiMeshInstance3D
	if mmi == null:
		return -1
	var mm := mmi.multimesh
	if mm == null:
		return -1
	var idx := mm.instance_count
	mm.instance_count = idx + 1
	mm.set_instance_transform(idx, xform)
	var positions: PackedVector2Array = _positions.get(mmi, PackedVector2Array())
	positions.append(Vector2(xform.origin.x, xform.origin.z))
	_positions[mmi] = positions
	var cell := Vector2i(int(floor(xform.origin.x / CLEAR_CELL)),
		int(floor(xform.origin.z / CLEAR_CELL)))
	var grid: Dictionary = _spatial.get(mmi, {})
	if not grid.has(cell):
		grid[cell] = []
	(grid[cell] as Array).append(idx)
	_spatial[mmi] = grid
	(_consumed.get(mmi, {}) as Dictionary).erase(idx)
	return idx


# Variantes a visitar: todas si `variants` viene vacio.
func _variant_indices(variants: Array[int]) -> Array[int]:
	if not variants.is_empty():
		return variants
	var all: Array[int] = []
	for i in _mmis.size():
		all.append(i)
	return all


func _near(positions: PackedVector2Array, i: int, world_pos: Vector2, r2: float) -> bool:
	var p := positions[i]
	var dx := p.x - world_pos.x
	var dz := p.y - world_pos.y
	return dx * dx + dz * dz < r2


func _consume_instance(mmi: MultiMeshInstance3D, positions: PackedVector2Array, i: int,
		world_pos: Vector2, r2: float) -> bool:
	if not _near(positions, i, world_pos, r2):
		return false
	_move_instance(mmi, i, -50.0)
	_mark_consumed(mmi, i)
	return true


func _restore_instance(mmi: MultiMeshInstance3D, positions: PackedVector2Array, i: int,
		world_pos: Vector2, r2: float, filter: Callable) -> bool:
	var consumed: Dictionary = _consumed.get(mmi, {})
	if not consumed.has(i):
		return false
	if not _near(positions, i, world_pos, r2):
		return false
	if filter.is_valid() and not bool(filter.call(positions[i])):
		return false
	_move_instance(mmi, i, 50.0)
	consumed.erase(i)
	# Rebrota con la reserva llena (las rocas vuelven a ser un yacimiento).
	if deposit_amount > 0.0:
		var reserves := _reserve_array(mmi)
		reserves[i] = deposit_amount
	return true


# Mueve la instancia en Y (visual). En headless MultiMesh no guarda transforms,
# pero el estado logico (posiciones/consumidas) no depende de ello.
func _move_instance(mmi: MultiMeshInstance3D, i: int, dy: float) -> void:
	var mm := mmi.multimesh
	if mm == null:
		return
	var t := mm.get_instance_transform(i)
	mm.set_instance_transform(i, t.translated(Vector3(0, dy, 0)))


func _mark_consumed(mmi: MultiMeshInstance3D, i: int) -> void:
	var set: Dictionary = _consumed.get(mmi, {})
	if not _consumed.has(mmi):
		_consumed[mmi] = set
	set[i] = true


func _sink_if_near(mmi: MultiMeshInstance3D, i: int, world_pos: Vector2, r2: float) -> void:
	var consumed: Dictionary = _consumed.get(mmi, {})
	if consumed.has(i):
		return
	var positions: PackedVector2Array = _positions.get(mmi, PackedVector2Array())
	if positions.is_empty() or not _near(positions, i, world_pos, r2):
		return
	_move_instance(mmi, i, -50.0)
	_mark_consumed(mmi, i)
