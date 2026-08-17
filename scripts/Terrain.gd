extends Node
# Autoload de geografia. Genera el terreno del mundo 100% por procedimiento
# (ruido fractal) a partir de una semilla, sin ninguna imagen.
#
# Modelo de relieve:
#   - Una mascara continua define tierra/mar (ruido + caida hacia los bordes,
#     suavizada para evitar pozas pequenas).
#   - La altura de la tierra sube con la distancia a la costa (playa estrecha
#     cerca del agua, llanuras en el interior, montañas lejos), mas ruido de
#     colinas y crestas montañosas en las zonas altas.
#   - Rios: trazado downhill desde las alturas hasta el mar y excavado del
#     cauce por debajo del nivel del agua.
#   - Biomas: agua, playa, llanura, bosque, montaña y nieve.
#
# Al ser matematico, la resolucion es infinita: hacer zoom nunca da pixelado.

const WORLD_SIZE := 200.0
const WORLD_SCALE := WORLD_SIZE / 100.0
const WORK_RES := 512
const SEED := 424242

# Nivel del mar y bandas de bioma
const SEA_LEVEL := 0.0
const BEACH_TOP := 0.28
const ROCK_LEVEL := 3.0
const SNOW_LEVEL := 4.2

# Mascara tierra/mar (continente + océano alrededor)
const CONTINENT_FREQ := 1.8
const CONTINENT_GAIN := 0.7
const CONTINENT_SHORE := 0.45
const EDGE_FALLOFF := 0.9
const FALLOFF_START := 0.55
const FALLOFF_END := 1.2
const MASK_SMOOTH := 4            # blur de la mascara: elimina pozas pequenas

# Relieve
const WATER_DEPTH := 1.5          # profundidad del mar
const WATER_RAMP_U := 4.0 * WORLD_SCALE  # u.m. desde la costa hasta la profundidad normal
const RAMP_MAX := 2.2             # altura de la meseta interior (llanura alta)
const RAMP_DIST := 22.0 * WORLD_SCALE    # u.m. desde la costa hasta la meseta interior

# Colinas
const HILL_FREQ := 6.0
const HILL_AMP := 0.4
const HILL_FADE_U := 3.0 * WORLD_SCALE   # u.m. para que las colinas aparezcan desde la costa

# Montañas (crestas), solo en el interior profundo
const MOUNT_FREQ := 3.5
const MOUNT_AMP := 2.2
const MOUNT_RAMP_START := 2.0

# Bosque (ruido de humedad)
const FOREST_FREQ := 7.0
const FOREST_THRESHOLD := 0.08

# Rios
const RIVER_COUNT := 14
const RIVER_START_MIN := 0.8
const RIVER_START_MAX := 4.2
const RIVER_HALF_WIDTH_U := 1.5 * WORLD_SCALE  # media anchura del cauce, en u.m.
const RIVER_CARVE := 0.9          # profundidad del cauce
const RIVER_MAX_STEPS := 600

# Suavizado final del relieve
const SMOOTH_RADIUS := 4

# Clases de terreno (para consumo externo)
const CLASS_WATER := 0
const CLASS_SAND := 1
const CLASS_PLAINS := 2
const CLASS_FOREST := 3
const CLASS_ROCK := 4
const CLASS_SNOW := 5

# Paleta de colores por bioma
const COLOR_WATER_SHALLOW := Color(0.20, 0.50, 0.72)
const COLOR_WATER_DEEP := Color(0.07, 0.22, 0.42)
const COLOR_BEACH := Color(0.85, 0.78, 0.55)
const COLOR_PLAINS := Color(0.42, 0.60, 0.30)
const COLOR_FOREST := Color(0.20, 0.38, 0.16)
const COLOR_ROCK := Color(0.48, 0.46, 0.42)
const COLOR_SNOW := Color(0.94, 0.95, 0.97)

var _class_px := PackedByteArray()      # clase por pixel (W*H)
var _height_px := PackedFloat32Array()  # altura por pixel (W*H)
var _forest_px := PackedFloat32Array()  # ruido de bosque por pixel (W*H)
var _water_dist_px := PackedFloat32Array()
var _width := 0
var _height := 0
var _px_per_unit := 0.0


func _ready() -> void:
	_generate()


func _generate() -> void:
	_width = WORK_RES
	_height = WORK_RES
	_px_per_unit = float(_width) / WORLD_SIZE
	var n := _width * _height

	var base_noise := FastNoiseLite.new()
	base_noise.seed = SEED + 1
	base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base_noise.frequency = CONTINENT_FREQ
	base_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	base_noise.fractal_octaves = 4
	base_noise.fractal_gain = 0.5
	base_noise.fractal_lacunarity = 2.0

	var hill_noise := FastNoiseLite.new()
	hill_noise.seed = SEED + 2
	hill_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hill_noise.frequency = HILL_FREQ
	hill_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	hill_noise.fractal_octaves = 3
	hill_noise.fractal_gain = 0.5

	var mount_noise := FastNoiseLite.new()
	mount_noise.seed = SEED + 3
	mount_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mount_noise.frequency = MOUNT_FREQ

	var forest_noise := FastNoiseLite.new()
	forest_noise.seed = SEED + 4
	forest_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest_noise.frequency = FOREST_FREQ

	# --- Mascara tierra/mar ---
	var cont := PackedFloat32Array()
	cont.resize(n)
	for j in range(_height):
		for i in range(_width):
			var nx := float(i) / float(_width)
			var ny := float(j) / float(_height)
			var cx := nx - 0.5
			var cy := ny - 0.5
			var d := sqrt(cx * cx + cy * cy) * 2.0
			var falloff := _smoothstep(clampf((d - FALLOFF_START) / (FALLOFF_END - FALLOFF_START), 0.0, 1.0))
			cont[j * _width + i] = base_noise.get_noise_2d(nx, ny) * CONTINENT_GAIN - falloff * EDGE_FALLOFF + CONTINENT_SHORE

	# Suaviza la mascara para eliminar pozas/islotes de ruido diminutos
	cont = _blur_y(_blur_x(cont, MASK_SMOOTH), MASK_SMOOTH)
	var sea_mask := PackedByteArray()
	sea_mask.resize(n)
	sea_mask.fill(0)
	for i in range(n):
		if cont[i] < 0.0:
			sea_mask[i] = 1

	var land_mask := PackedByteArray()
	land_mask.resize(n)
	for i in range(n):
		land_mask[i] = 1 - sea_mask[i]
	var coast_dist := _distance_field(sea_mask)   # tierra -> costa
	var land_dist := _distance_field(land_mask)   # mar -> costa

	# --- Alturas ---
	var heights := PackedFloat32Array()
	heights.resize(n)
	for idx in range(n):
		var i := idx % _width
		var j := idx / _width
		if sea_mask[idx] == 1:
			var d_land_u: float = land_dist[idx] / _px_per_unit
			var t := _smoothstep(clampf(d_land_u / WATER_RAMP_U, 0.0, 1.0))
			heights[idx] = lerpf(0.0, -WATER_DEPTH, t)
			continue
		var d_u: float = coast_dist[idx] / _px_per_unit
		var ramp := RAMP_MAX * clampf(d_u / RAMP_DIST, 0.0, 1.0)
		var hills_w := _smoothstep(clampf(d_u / HILL_FADE_U, 0.0, 1.0))
		var hills: float = hill_noise.get_noise_2d(float(i) / float(_width), float(j) / float(_height)) * HILL_AMP * hills_w
		var m_mask := _smoothstep(clampf((ramp - MOUNT_RAMP_START) / (RAMP_MAX - MOUNT_RAMP_START), 0.0, 1.0))
		var mr: float = mount_noise.get_noise_2d(float(i) / float(_width), float(j) / float(_height))
		var ridge: float = 1.0 - absf(mr)
		ridge *= ridge
		var mtn: float = ridge * MOUNT_AMP * m_mask
		heights[idx] = ramp + hills + mtn

	# --- Rios: trazado downhill y excavado del cauce ---
	var river_mask := PackedByteArray()
	river_mask.resize(n)
	river_mask.fill(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 5
	for r in range(RIVER_COUNT):
		_trace_river(heights, river_mask, rng)

	var river_dist := _distance_field(river_mask)
	var half_px := RIVER_HALF_WIDTH_U * _px_per_unit
	for idx in range(n):
		var rd: float = river_dist[idx]
		if rd < half_px:
			heights[idx] -= RIVER_CARVE * _smoothstep(1.0 - rd / half_px)

	# --- Suavizado final del relieve ---
	heights = _blur_y(_blur_x(heights, SMOOTH_RADIUS), SMOOTH_RADIUS)
	_height_px = heights

	# --- Biomas ---
	var water_mask := PackedByteArray()
	water_mask.resize(n)
	var forest_arr := PackedFloat32Array()
	forest_arr.resize(n)
	for idx in range(n):
		var fx := float(idx % _width) / float(_width)
		var fy := float(idx / _width) / float(_height)
		forest_arr[idx] = forest_noise.get_noise_2d(fx, fy)
	_forest_px = forest_arr
	var cls := PackedByteArray()
	cls.resize(n)
	for idx in range(n):
		var h: float = heights[idx]
		var is_water := h < SEA_LEVEL
		water_mask[idx] = 1 if is_water else 0
		if is_water:
			cls[idx] = CLASS_WATER
		elif h < BEACH_TOP:
			cls[idx] = CLASS_SAND
		elif h > SNOW_LEVEL:
			cls[idx] = CLASS_SNOW
		elif h > ROCK_LEVEL:
			cls[idx] = CLASS_ROCK
		else:
			cls[idx] = CLASS_FOREST if forest_arr[idx] > FOREST_THRESHOLD else CLASS_PLAINS
	_class_px = cls
	_water_dist_px = _distance_field(water_mask)

	var counts := [0, 0, 0, 0, 0, 0]
	for i in range(n):
		counts[_class_px[i]] += 1
	print("[Terrain] %dx%d px/unidad=%.2f | agua=%d playa=%d llanura=%d bosque=%d montaña=%d nieve=%d"
		% [_width, _height, _px_per_unit, counts[0], counts[1], counts[2], counts[3], counts[4], counts[5]])


# ---------------------------------------------------------------------------
# Rios
# ---------------------------------------------------------------------------
func _trace_river(heights: PackedFloat32Array, river_mask: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var w := _width
	var h := _height

	var start := -1
	for attempt in range(300):
		var idx := rng.randi_range(0, w * h - 1)
		var hv: float = heights[idx]
		if hv >= RIVER_START_MIN and hv <= RIVER_START_MAX:
			start = idx
			break
	if start == -1:
		return

	var cur := start
	var steps := 0
	while steps < RIVER_MAX_STEPS:
		if heights[cur] < SEA_LEVEL:
			break
		river_mask[cur] = 1
		var i := cur % w
		var j := cur / w
		var best := -1
		var best_h: float = heights[cur]
		for dj in range(-1, 2):
			for di in range(-1, 2):
				if di == 0 and dj == 0:
					continue
				var ni := i + di
				var nj := j + dj
				if ni < 0 or ni >= w or nj < 0 or nj >= h:
					continue
				var nidx := nj * w + ni
				var nh: float = heights[nidx]
				if nh < best_h:
					best_h = nh
					best = nidx
		if best == -1:
			break
		if river_mask[best] == 1:
			break
		cur = best
		steps += 1


# ---------------------------------------------------------------------------
# Herramientas de imagen / campo de distancias
# ---------------------------------------------------------------------------
func _smoothstep(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _distance_field(inside: PackedByteArray) -> PackedFloat32Array:
	var w := _width
	var h := _height
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	dist.fill(1.0e9)
	for i in range(w * h):
		if inside[i] == 1:
			dist[i] = 0.0

	for j in range(h):
		var row := j * w
		for i in range(w):
			var idx := row + i
			var d := dist[idx]
			if i > 0:
				d = minf(d, dist[idx - 1] + 1.0)
			if j > 0:
				d = minf(d, dist[idx - w] + 1.0)
			if i > 0 and j > 0:
				d = minf(d, dist[idx - w - 1] + 1.41421)
			if i < w - 1 and j > 0:
				d = minf(d, dist[idx - w + 1] + 1.41421)
			dist[idx] = d

	for j in range(h - 1, -1, -1):
		var row := j * w
		for i in range(w - 1, -1, -1):
			var idx := row + i
			var d := dist[idx]
			if i < w - 1:
				d = minf(d, dist[idx + 1] + 1.0)
			if j < h - 1:
				d = minf(d, dist[idx + w] + 1.0)
			if i < w - 1 and j < h - 1:
				d = minf(d, dist[idx + w + 1] + 1.41421)
			if i > 0 and j < h - 1:
				d = minf(d, dist[idx + w - 1] + 1.41421)
			dist[idx] = d
	return dist


func _blur_x(src: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var w := _width
	var h := _height
	var out := src.duplicate()
	var pref := PackedFloat32Array()
	pref.resize(w + 1)
	for j in range(h):
		var row := j * w
		pref[0] = 0.0
		for i in range(w):
			pref[i + 1] = pref[i] + src[row + i]
		for i in range(w):
			var lo := maxi(0, i - radius)
			var hi := mini(w - 1, i + radius)
			out[row + i] = (pref[hi + 1] - pref[lo]) / float(hi - lo + 1)
	return out


func _blur_y(src: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var w := _width
	var h := _height
	var out := src.duplicate()
	var pref := PackedFloat32Array()
	pref.resize(h + 1)
	for i in range(w):
		pref[0] = 0.0
		for j in range(h):
			pref[j + 1] = pref[j] + src[j * w + i]
		for j in range(h):
			var lo := maxi(0, j - radius)
			var hi := mini(h - 1, j + radius)
			out[j * w + i] = (pref[hi + 1] - pref[lo]) / float(hi - lo + 1)
	return out


# ---------------------------------------------------------------------------
# API de consulta
# ---------------------------------------------------------------------------
func _pixel(p: Vector2) -> Vector2i:
	var px := int(clampf(p.x / WORLD_SIZE, 0.0, 1.0) * float(_width - 1))
	var py := int(clampf(p.y / WORLD_SIZE, 0.0, 1.0) * float(_height - 1))
	return Vector2i(px, py)


func height_at(p: Vector2) -> float:
	if _width == 0:
		return 0.0
	var fx: float = clampf(p.x / WORLD_SIZE, 0.0, 1.0) * float(_width - 1)
	var fy: float = clampf(p.y / WORLD_SIZE, 0.0, 1.0) * float(_height - 1)
	var x0 := int(fx)
	var y0 := int(fy)
	var x1 := mini(x0 + 1, _width - 1)
	var y1 := mini(y0 + 1, _height - 1)
	var tx := fx - x0
	var ty := fy - y0
	var v00: float = _height_px[y0 * _width + x0]
	var v10: float = _height_px[y0 * _width + x1]
	var v01: float = _height_px[y1 * _width + x0]
	var v11: float = _height_px[y1 * _width + x1]
	return lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), ty)


func forest_at(p: Vector2) -> float:
	if _width == 0:
		return 0.0
	var fx: float = clampf(p.x / WORLD_SIZE, 0.0, 1.0) * float(_width - 1)
	var fy: float = clampf(p.y / WORLD_SIZE, 0.0, 1.0) * float(_height - 1)
	var x0 := int(fx)
	var y0 := int(fy)
	var x1 := mini(x0 + 1, _width - 1)
	var y1 := mini(y0 + 1, _height - 1)
	var tx := fx - x0
	var ty := fy - y0
	var v00: float = _forest_px[y0 * _width + x0]
	var v10: float = _forest_px[y0 * _width + x1]
	var v01: float = _forest_px[y1 * _width + x0]
	var v11: float = _forest_px[y1 * _width + x1]
	return lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), ty)


func terrain_type(p: Vector2) -> String:
	if _width == 0:
		return "llanura"
	var pi := _pixel(p)
	var c := _class_px[pi.y * _width + pi.x]
	match c:
		CLASS_WATER:
			return "agua"
		CLASS_SAND:
			return "playa"
		CLASS_FOREST:
			return "bosque"
		CLASS_ROCK:
			return "montaña"
		CLASS_SNOW:
			return "nieve"
		_:
			return "llanura"


func is_water(p: Vector2) -> bool:
	if _width == 0:
		return false
	var pi := _pixel(p)
	return _class_px[pi.y * _width + pi.x] == CLASS_WATER


func biome_color(c: int, h: float) -> Color:
	match c:
		CLASS_WATER:
			var depth := clampf(-h / WATER_DEPTH, 0.0, 1.0)
			return COLOR_WATER_SHALLOW.lerp(COLOR_WATER_DEEP, depth)
		CLASS_SAND:
			return COLOR_BEACH
		CLASS_FOREST:
			return COLOR_FOREST
		CLASS_ROCK:
			return COLOR_ROCK
		CLASS_SNOW:
			return COLOR_SNOW
		_:
			return COLOR_PLAINS


func distance_to_water(p: Vector2) -> float:
	if _width == 0:
		return 0.0
	if is_water(p):
		return -0.1
	var pi := _pixel(p)
	return _water_dist_px[pi.y * _width + pi.x] / _px_per_unit