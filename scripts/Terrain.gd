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

const WORLD_SIZE := 300.0
const WORLD_SCALE := WORLD_SIZE / 100.0
const WORK_RES := 768
const SEED := 424242

# Nivel del mar y bandas de bioma
const SEA_LEVEL := 0.0
const BEACH_TOP := 0.28
const ROCK_LEVEL := 2.6
const SNOW_LEVEL := 7.0

# Mascara tierra/mar (continente + océano alrededor)
const CONTINENT_FREQ := 1.8
const CONTINENT_GAIN := 0.7
const CONTINENT_SHORE := 0.45
const EDGE_FALLOFF := 0.9
const FALLOFF_START := 0.55
const FALLOFF_END := 1.2
const MASK_SMOOTH := 4            # blur de la mascara: elimina pozas pequenas
const LAKE_MIN_DIST := 20.0       # u.m. minimas de un lago al mar (solo lagos de interior)

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
const MOUNT_BASE := 2.6
const MOUNT_AMP := 8.0
const MOUNT_RAMP_START := 2.0
const RANGE_FREQ := 1.1
const RANGE_SHARP := -0.1
const RUGGED_FREQ := 2.2

# Bosque (ruido de humedad)
const FOREST_FREQ := 7.0
const FOREST_THRESHOLD := 0.08

# Rio principal: un solo cauce fino que nace en un pequeno lago al pie de la
# sierra mas alta y desemboca en la costa opuesta, con meandros suaves
const RIVER_SOURCE_MAX_H := 1.9   # nacimiento mas abajo: el lago queda en la zona llana, separado de la sierra
const RIVER_SOURCE_LAKE_RADIUS_U := 5.0  # pequeno lago de nacimiento, en u.m.
const RIVER_SOURCE_LAKE_DEPTH := 0.5     # profundidad del lago de nacimiento (poco profundo)
const RIVER_HALF_WIDTH_U := 0.9 * WORLD_SCALE  # media anchura del cauce, en u.m.
const RIVER_CARVE := 1.6          # profundidad del cauce (sobrevive al suavizado)
const RIVER_WATER_MARGIN := 0.15  # nivel del agua del cauce bajo la orilla
const RIVER_TURN_PENALTY := 0.7   # suaviza los giros del trazado
const RIVER_NOISE := 0.10         # pequena aleatoriedad en el trazado
const RIVER_MOUTH_PULL := 0.6     # atraccion del cauce hacia la boca elegida
const RIVER_MEANDER_AMP_U := 1.5  # amplitud base de los meandros, en u.m.
const RIVER_MEANDER_LEN_U := 8.0  # longitud de onda base de los meandros, en u.m.
const RIVER_MOUTH_FADE_U := 12.0  # longitud del cauce en la que se funde con el mar, en u.m.
const RIVER_MOUTH_BED := -0.12    # profundidad del cauce justo en la desembocadura
const RIVER_MAX_STEPS := 3000

# Lago de montaña: un solo lago, medio, irregular y elevado entre las sierras
const MOUNTAIN_LAKE_WL := 1.9       # nivel del agua del lago (por encima del mar) — mas bajo para no flotar
const MOUNTAIN_LAKE_MIN_SEA := 25.0   # u.m. minimas del lago al mar
const MOUNTAIN_LAKE_H_MIN := 3.0      # altura del sitio (entre las sierras)
const MOUNTAIN_LAKE_H_MAX := 6.5
const MOUNTAIN_LAKE_NEAR := 14.0      # radio para buscar una montaña cercana
const MOUNTAIN_LAKE_NEAR_H := 4.0     # altura que cuenta como montaña cercana
const MOUNTAIN_LAKE_FOREST_H := 2.6   # altura del bosque: la abertura se orienta ahi
const MOUNTAIN_LAKE_GAP_ANGLE := 30.0 # medio angulo del cono de abertura (grados)
const MOUNTAIN_LAKE_WATER_FADE := 6.5 # longitud media de la bahia que sale del lago (u.m.)
const MOUNTAIN_LAKE_GAP_MAX_LEN := 48.0 # longitud maxima del valle (u.m.)

# Suavizado final del relieve
const SMOOTH_RADIUS := 2

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
var _wl_px := PackedFloat32Array()     # nivel de agua por pixel (mar=0, rios y lagos elevados)
var _lake_px := PackedByteArray()      # 1 = lago protegido (no se rellena)
var _width := 0
var _height := 0
var _px_per_unit := 0.0


# --- Cache en disco -------------------------------------------------------
# Generar el terreno cuesta ~3,4 s de hilo principal (medido con Godot 4.7.2
# en 768x768), y son 3,4 s de ventana congelada en CADA arranque. El resultado
# es determinista: solo depende de las constantes de este script. Asi que se
# vuelca a user:// y los arranques siguientes cuestan ~0,1 s.
#
# La clave de la cache incluye un hash de TODAS las constantes del script, de
# modo que tocar cualquier parametro de generacion (SEED, MOUNT_AMP, el radio
# de los lagos...) la invalida solo. Si cambias el ALGORITMO sin tocar ninguna
# constante, sube CACHE_VERSION a mano o borra el fichero.
const CACHE_VERSION := 1
const CACHE_PATH := "user://terrain_cache.bin"
const CACHE_MAGIC := 0x41335443  # "AOT3" (formato del volcado)


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	if _load_cache():
		print_verbose("[Terrain] cache cargada en %d ms" % (Time.get_ticks_msec() - t0))
		return
	_generate()
	print_verbose("[Terrain] generado en %d ms" % (Time.get_ticks_msec() - t0))
	_save_cache()


# Identifica de forma unica la configuracion de generacion actual.
func _cache_key() -> int:
	return hash([CACHE_MAGIC, CACHE_VERSION, get_script().get_script_constant_map()])


func _load_cache() -> bool:
	var f := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if f == null:
		return false
	if f.get_64() != _cache_key():
		return false   # cache de otra configuracion: se regenera y se pisa
	_width = f.get_32()
	_height = f.get_32()
	_px_per_unit = f.get_double()
	var n := _width * _height
	if n <= 0:
		return false
	_height_px = f.get_var()
	_wl_px = f.get_var()
	_forest_px = f.get_var()
	_water_dist_px = f.get_var()
	_class_px = f.get_var()
	# Un volcado truncado (disco lleno, cierre a lo bruto) no debe dejar el
	# juego con arrays a medias: mejor regenerar.
	if (_height_px.size() != n or _wl_px.size() != n or _forest_px.size() != n
			or _water_dist_px.size() != n or _class_px.size() != n):
		push_warning("[Terrain] cache corrupta o truncada, se regenera")
		_width = 0
		_height = 0
		return false
	return true


func _save_cache() -> void:
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[Terrain] no se pudo escribir la cache en %s" % CACHE_PATH)
		return
	f.store_64(_cache_key())
	f.store_32(_width)
	f.store_32(_height)
	f.store_double(_px_per_unit)
	f.store_var(_height_px)
	f.store_var(_wl_px)
	f.store_var(_forest_px)
	f.store_var(_water_dist_px)
	f.store_var(_class_px)


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

	var range_noise := FastNoiseLite.new()
	range_noise.seed = SEED + 6
	range_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	range_noise.frequency = RANGE_FREQ

	var rugged_noise := FastNoiseLite.new()
	rugged_noise.seed = SEED + 7
	rugged_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	rugged_noise.frequency = RUGGED_FREQ

	var forest_noise := FastNoiseLite.new()
	forest_noise.seed = SEED + 4
	forest_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest_noise.frequency = FOREST_FREQ

	# --- Mascara tierra/mar a baja resolucion (campo de baja frecuencia) ---
	var MASK_LOW := 192
	var ml := MASK_LOW
	var cont_low := PackedFloat32Array()
	cont_low.resize(ml * ml)
	for j in range(ml):
		for i in range(ml):
			var nx := float(i) / float(ml)
			var ny := float(j) / float(ml)
			var cx := nx - 0.5
			var cy := ny - 0.5
			var d := sqrt(cx * cx + cy * cy) * 2.0
			var falloff := TerrainUtils.smoothstep(clampf((d - FALLOFF_START) / (FALLOFF_END - FALLOFF_START), 0.0, 1.0))
			cont_low[j * ml + i] = base_noise.get_noise_2d(nx, ny) * CONTINENT_GAIN - falloff * EDGE_FALLOFF + CONTINENT_SHORE

	# Suaviza la mascara a baja resolucion (equivale al blur a res. completa)
	cont_low = TerrainUtils.blur_y(TerrainUtils.blur_x(cont_low, ml, ml, 1), ml, ml, 1)
	var sea_mask_low := PackedByteArray()
	sea_mask_low.resize(ml * ml)
	var land_mask_low := PackedByteArray()
	land_mask_low.resize(ml * ml)
	for i in range(ml * ml):
		if cont_low[i] < 0.0:
			sea_mask_low[i] = 1
		else:
			land_mask_low[i] = 1

	var coast_dist_low := TerrainUtils.distance_field(sea_mask_low, ml, ml)
	var land_dist_low := TerrainUtils.distance_field(land_mask_low, ml, ml)
	var _lr_scale := float(_width) / float(ml)
	var coast_dist := TerrainUtils.upsample_field(coast_dist_low, ml, ml, _width, _height, _lr_scale)
	var land_dist := TerrainUtils.upsample_field(land_dist_low, ml, ml, _width, _height, _lr_scale)

	var sea_mask := PackedByteArray()
	sea_mask.resize(n)
	sea_mask.fill(0)
	var cont_full := TerrainUtils.upsample_field(cont_low, ml, ml, _width, _height, 1.0)
	for i in range(n):
		if cont_full[i] < 0.0:
			sea_mask[i] = 1

	# --- Alturas ---
	var heights := PackedFloat32Array()
	heights.resize(n)
	_wl_px.resize(n)
	_wl_px.fill(0.0)
	_lake_px.resize(n)
	_lake_px.fill(0)
	for idx in range(n):
		var i := idx % _width
		var j := idx / _width
		if sea_mask[idx] == 1:
			var d_land_u: float = land_dist[idx] / _px_per_unit
			var t := TerrainUtils.smoothstep(clampf(d_land_u / WATER_RAMP_U, 0.0, 1.0))
			heights[idx] = lerpf(0.0, -WATER_DEPTH, t)
			continue
		var nx := float(i) / float(_width)
		var ny := float(j) / float(_height)
		var d_u: float = coast_dist[idx] / _px_per_unit
		var ramp := RAMP_MAX * clampf(d_u / RAMP_DIST, 0.0, 1.0)
		var hills_w := TerrainUtils.smoothstep(clampf(d_u / HILL_FADE_U, 0.0, 1.0))
		var hills: float = hill_noise.get_noise_2d(nx, ny) * HILL_AMP * hills_w
		var m_mask := TerrainUtils.smoothstep(clampf((ramp - MOUNT_RAMP_START) / (RAMP_MAX - MOUNT_RAMP_START), 0.0, 1.0))
		# Cadenas de montaña: solo donde el ruido de cadenas supera el umbral,
		# dejando valles y zonas llanas entre sierras.
		var range_m := TerrainUtils.smoothstep(clampf((range_noise.get_noise_2d(nx, ny) - RANGE_SHARP) / 0.5, 0.0, 1.0))
		# Aspereza por zona: solo algunas cadenas desarrollan picos afilados,
		# otras quedan como macizos suaves (variedad montañosa).
		var rugged := TerrainUtils.smoothstep(clampf((rugged_noise.get_noise_2d(nx, ny) + 0.1) / 0.5, 0.0, 1.0))
		var ridge_amp := lerpf(0.35, 1.0, rugged)
		# Cresta multifractal: varias octavas de (1-|noise|)^2 -> cumbres afiladas
		# con estribaciones mas suaves alrededor.
		var ridge_total := 0.0
		var amp := 1.0
		var freq := 1.0
		for o in range(3):
			var r := 1.0 - absf(mount_noise.get_noise_2d(nx * freq, ny * freq))
			ridge_total += r * r * amp
			amp *= 0.55
			freq *= 2.3
		var mtn: float = (MOUNT_BASE + ridge_total * MOUNT_AMP * ridge_amp) * range_m * m_mask
		heights[idx] = ramp + hills + mtn

	# --- Rio principal: nace en un pequeno lago al pie de la sierra mas alta,
	# baja con meandros suaves y desemboca en la costa opuesta ---
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 5
	var src := _highest_pixel(heights)
	for _s in range(300):
		if heights[src] <= RIVER_SOURCE_MAX_H:
			break
		var lo := _lowest_neighbor(heights, src)
		if lo == -1:
			break
		src = lo
	var mouth := _opposite_mouth(heights, src)
	var sl_center := Vector2(src % _width, src / _width)
	# Nivel de agua del lago de nacimiento: 0.2 bajo la orilla mas baja, asi el
	# lago queda hundido en el terreno (nunca flota por encima de el).
	var lake_wl := 1.0e9
	for k in range(16):
		var ang := TAU * k / 16.0
		var rim := sl_center + Vector2(cos(ang), sin(ang)) * (RIVER_SOURCE_LAKE_RADIUS_U * _px_per_unit * 0.9)
		var rim_i := clampi(int(round(rim.x)), 0, _width - 1)
		var rim_j := clampi(int(round(rim.y)), 0, _height - 1)
		lake_wl = minf(lake_wl, heights[rim_j * _width + rim_i])
	lake_wl -= 0.2
	var path := _trace_river(heights, rng, src, mouth)
	var meander := _meander_polyline(path)
	var meander_mask := _polyline_mask(meander.points)
	var half_px := RIVER_HALF_WIDTH_U * _px_per_unit
	# Campo de distancias del cauce solo dentro de su caja (no en todo el mapa)
	var pad := int(half_px * 2.5) + 2
	var rmin := Vector2(1.0e9, 1.0e9)
	var rmax := Vector2(-1.0e9, -1.0e9)
	for pt in meander.points:
		rmin.x = minf(rmin.x, pt.x)
		rmin.y = minf(rmin.y, pt.y)
		rmax.x = maxf(rmax.x, pt.x)
		rmax.y = maxf(rmax.y, pt.y)
	var rbox := Rect2i(int(rmin.x) - pad, int(rmin.y) - pad, int(rmax.x - rmin.x) + pad * 2 + 1, int(rmax.y - rmin.y) + pad * 2 + 1)
	var river_dist := TerrainUtils.distance_field_region(meander_mask, _width, _height, rbox)
	var rtotal: float = meander.cum[meander.cum.size() - 1]
	# Fraccion del cauce (al final) dedicada a fundir la desembocadura con el mar
	var mouth_frac := 1.0
	if rtotal > 0.0:
		mouth_frac = clampf(RIVER_MOUTH_FADE_U * _px_per_unit / rtotal, 0.0, 1.0)
	for idx in range(n):
		var rd: float = river_dist[idx]
		if rd >= half_px * 2.5:
			continue
		var p := Vector2(idx % _width, idx / _width)
		var s := _along_fraction(p, meander.points, meander.cum, rtotal)
		# Cerca de la desembocadura el cauce se ensancha, se hace poco profundo
		# y su nivel de agua baja hasta el nivel del mar: sin escalon submarino
		# ni "linea" entre el agua del rio y la del mar.
		var mf := TerrainUtils.smoothstep(clampf((s - (1.0 - mouth_frac)) / mouth_frac, 0.0, 1.0))
		var hp := half_px * (1.0 + 1.5 * mf)
		if rd < hp:
			var bank: float = heights[idx]
			var bed := bank - RIVER_CARVE * TerrainUtils.smoothstep(1.0 - rd / hp)
			bed = lerpf(bed, RIVER_MOUTH_BED, mf)
			heights[idx] = bed
			# El nivel de agua del cauce declina desde el lago (s=0) hasta el
			# mar (s=1), y nunca supera la orilla (sin inundar).
			var wl := minf(lerpf(lake_wl, SEA_LEVEL, s), bank - RIVER_WATER_MARGIN)
			wl = lerpf(wl, SEA_LEVEL, mf)
			_wl_px[idx] = wl

	# --- Lago de nacimiento: pequeno lago hundido al pie de la montaña, del
	# que nace el rio ---
	var sl_shape := FastNoiseLite.new()
	sl_shape.seed = SEED + 11
	sl_shape.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	sl_shape.frequency = 0.20
	var sl_radius := RIVER_SOURCE_LAKE_RADIUS_U
	var sl_bottom := lake_wl - RIVER_SOURCE_LAKE_DEPTH
	var sl_box := int(sl_radius * 1.5 * _px_per_unit) + 2
	for j in range(maxi(0, int(sl_center.y) - sl_box), mini(_height - 1, int(sl_center.y) + sl_box) + 1):
		for i in range(maxi(0, int(sl_center.x) - sl_box), mini(_width - 1, int(sl_center.x) + sl_box) + 1):
			var d_u: float = Vector2(i, j).distance_to(sl_center) / _px_per_unit
			var nv := sl_shape.get_noise_2d(float(i) / _px_per_unit, float(j) / _px_per_unit)
			var rr := sl_radius * (1.0 + 0.25 * nv)
			if d_u > rr:
				continue
			var idx := j * _width + i
			var orig: float = heights[idx]
			# El lago ya esta en zona llana: solo se evita excavar una ladera
			# realmente escarpada si el terreno llega muy alto dentro del circulo
			# (corte duro, sin fundidos, para no crear picos residuales).
			if orig - lake_wl > 2.0:
				continue
			var target: float
			if d_u <= rr * 0.4:
				# Fondo plano del lago (por debajo de su nivel de agua)
				target = sl_bottom
			else:
				var u := (d_u - rr * 0.4) / (rr - rr * 0.4)
				var t := TerrainUtils.smoothstep(clampf(u, 0.0, 1.0))
				target = lerpf(sl_bottom, orig, t)
			# El lago nunca rellena el cauce del rio ya excavado: se mantiene lo
			# mas profundo de los dos, asi el agua del lago conecta con el rio.
			heights[idx] = minf(target, orig)
			if heights[idx] < lake_wl:
				_wl_px[idx] = lake_wl
				_lake_px[idx] = 1
	print_verbose("[Terrain] rio: fuente=%s boca=%s (lado opuesto)" % [src, mouth])

	# --- Lago de montaña: un solo lago, de tamano medio, con orilla irregular
	# (ruido) y elevado entre las sierras, en correlacion con sus alturas ---
	var lake_rng := RandomNumberGenerator.new()
	lake_rng.seed = SEED + 8
	var lake_shape := FastNoiseLite.new()
	lake_shape.seed = SEED + 9
	lake_shape.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	lake_shape.frequency = 0.16
	var shore_shape := FastNoiseLite.new()
	shore_shape.seed = SEED + 12
	shore_shape.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	shore_shape.frequency = 0.25
	for attempt in range(400):
		var px := lake_rng.randi_range(20, _width - 21)
		var py := lake_rng.randi_range(20, _height - 21)
		var pidx := py * _width + px
		var h0: float = heights[pidx]
		if h0 < MOUNTAIN_LAKE_H_MIN or h0 > MOUNTAIN_LAKE_H_MAX:
			continue
		if coast_dist[pidx] / _px_per_unit < MOUNTAIN_LAKE_MIN_SEA:
			continue
		var near_mtn := false
		for k in range(8):
			var ang := TAU * k / 8.0
			var sx := clampi(px + int(cos(ang) * MOUNTAIN_LAKE_NEAR * _px_per_unit), 0, _width - 1)
			var sy := clampi(py + int(sin(ang) * MOUNTAIN_LAKE_NEAR * _px_per_unit), 0, _height - 1)
			if heights[sy * _width + sx] >= MOUNTAIN_LAKE_NEAR_H:
				near_mtn = true
				break
		if not near_mtn:
			continue
		var center := Vector2(px, py)
		var radius_u := lake_rng.randf_range(8.0, 11.0)
		var core_frac := 0.82
		var bottom := MOUNTAIN_LAKE_WL - 1.2
		var box := int(radius_u * 1.5 * _px_per_unit) + 2
		var x0 := maxi(0, px - box)
		var x1 := mini(_width - 1, px + box)
		var y0 := maxi(0, py - box)
		var y1 := mini(_height - 1, py + box)
		# Núcleo plano circular (sin ruido) para evitar islas: 75% del radio siempre es fondo
		var flat_r := radius_u * 0.75
		for j in range(y0, y1 + 1):
			for i in range(x0, x1 + 1):
				var d_u: float = Vector2(i, j).distance_to(center) / _px_per_unit
				var nv := lake_shape.get_noise_2d(float(i) / _px_per_unit * 1.3, float(j) / _px_per_unit * 0.8)
				var rr := radius_u * (1.0 + 0.5 * nv)
				if d_u > rr and d_u > flat_r:
					continue
				var orig: float = heights[j * _width + i]
				var target: float
				if d_u <= flat_r:
					target = bottom
				elif d_u <= rr:
					var u := (d_u - flat_r) / (rr - flat_r)
					var t := TerrainUtils.smoothstep(clampf(u, 0.0, 1.0))
					target = lerpf(bottom, orig, t)
				else:
					target = bottom
				heights[j * _width + i] = target
				_wl_px[j * _width + i] = MOUNTAIN_LAKE_WL
				_lake_px[j * _width + i] = 1
		# Borde del lago: eleva el anillo exterior para que el agua no flote sobre laderas bajas
		for j in range(y0, y1 + 1):
			for i in range(x0, x1 + 1):
				var d_u: float = Vector2(i, j).distance_to(center) / _px_per_unit
				var nv := lake_shape.get_noise_2d(float(i) / _px_per_unit * 1.3, float(j) / _px_per_unit * 0.8)
				var rr := radius_u * (1.0 + 0.5 * nv)
				if d_u <= maxf(rr, flat_r) or d_u > maxf(rr, flat_r) + 3.0:
					continue
				var idx := j * _width + i
				var wall_h := MOUNTAIN_LAKE_WL + 0.45
				if heights[idx] < wall_h:
					heights[idx] = lerpf(wall_h, heights[idx], clampf((d_u - maxf(rr, flat_r)) / 3.0, 0.0, 1.0))

		# --- Abertura hacia el bosque: se quita la sierra del lado que da al
		# terreno mas bajo (bosque/llanura) con un cono ancho, para que el lago
		# no quede encerrado del todo entre montañas. El cono baja la pared del
		# borde del lago en ese sector (desde la orilla hasta el bosque) y la
		# boca queda bajo el agua (pequeno vertido).
		var gap_dir := _lake_gap_direction(heights, center, radius_u)
		var gap_len := clampf(_lake_gap_length(heights, center, radius_u, gap_dir), 10.0, MOUNTAIN_LAKE_GAP_MAX_LEN)
		var gbox := int((radius_u + gap_len + 4.0) * 1.3 * _px_per_unit) + 2
		var gx0 := maxi(0, int(center.x) - gbox)
		var gx1 := mini(_width - 1, int(center.x) + gbox)
		var gy0 := maxi(0, int(center.y) - gbox)
		var gy1 := mini(_height - 1, int(center.y) + gbox)
		for j in range(gy0, gy1 + 1):
			for i in range(gx0, gx1 + 1):
				var p := Vector2(i, j)
				var d_u: float = p.distance_to(center) / _px_per_unit
				var nv := lake_shape.get_noise_2d(float(i) / _px_per_unit * 1.3, float(j) / _px_per_unit * 0.8)
				var rr := radius_u * (1.0 + 0.5 * nv)
				if d_u <= rr * 0.5:
					continue
				var off := p - center
				var along_u := off.dot(gap_dir) / _px_per_unit
				var ang_deg := rad_to_deg(acos(clampf(off.normalized().dot(gap_dir), -1.0, 1.0)))
				if ang_deg > MOUNTAIN_LAKE_GAP_ANGLE:
					continue
				if along_u > radius_u + gap_len:
					continue
				var idx := j * _width + i
				var orig: float = heights[idx]
				var sw := TerrainUtils.smoothstep(clampf(1.0 - ang_deg / MOUNTAIN_LAKE_GAP_ANGLE, 0.0, 1.0))
				# Borde exterior del agua: sigue el ruido de la orilla (curvas)
				# con amplitud suave, para que la bahia sea continua y sin islas.
				var shore := shore_shape.get_noise_2d(float(i) / _px_per_unit, float(j) / _px_per_unit)
				var bay_end := radius_u + MOUNTAIN_LAKE_WATER_FADE * clampf(1.0 + 0.5 * shore, 0.7, 1.5)
				if along_u < bay_end:
					# Dentro de la bahia: suelo plano bajo el agua (un solo
					# cuerpo de agua, sin trozos sueltos).
					var floor_h := minf(orig, MOUNTAIN_LAKE_WL - 0.2)
					heights[idx] = minf(orig, lerpf(orig, floor_h, sw))
					_wl_px[idx] = MOUNTAIN_LAKE_WL
					_lake_px[idx] = 1
				else:
					# Valle seco: del borde del agua hacia el bosque.
					var u := clampf((along_u - bay_end) / 4.0, 0.0, 1.0)
					var floor_h := lerpf(MOUNTAIN_LAKE_WL + 0.15, orig, TerrainUtils.smoothstep(u))
					heights[idx] = minf(orig, lerpf(orig, floor_h, sw))
		break

	# --- Nivel de agua suavizado: se difumina _wl_px para que el borde de
	# los lagos y el cauce del rio no tengan saltos de 1 px entre celdas ---
	_wl_px = TerrainUtils.blur_y(TerrainUtils.blur_x(_wl_px, _width, _height, 1), _width, _height, 1)

	# --- Suavizado final del relieve ---
	heights = TerrainUtils.blur_y(TerrainUtils.blur_x(heights, _width, _height, SMOOTH_RADIUS), _width, _height, SMOOTH_RADIUS)
	_height_px = heights

	# --- Lagos solo en el interior: se rellenan las masas de agua aisladas
	# (tramos de rio excavados que quedaron desconectados) pegadas a la costa.
	# Un lago permitido debe estar lejos del mar. ---
	var wmask := PackedByteArray()
	wmask.resize(n)
	for i in range(n):
		wmask[i] = 1 if heights[i] < _wl_px[i] else 0
	var wcomp := PackedInt32Array()
	wcomp.resize(n)
	wcomp.fill(-1)
	var wcomp_ocean: Array[bool] = []
	var wcomp_lake: Array[bool] = []
	var wstack: Array[int] = []
	var wcid := 0
	for idx in range(n):
		if wmask[idx] == 0 or wcomp[idx] != -1:
			continue
		var ocean := false
		var elevated := false
		wstack.append(idx)
		wcomp[idx] = wcid
		while wstack.size() > 0:
			var cur: int = wstack.pop_back()
			if _lake_px[cur] == 1:
				elevated = true
			var ci := cur % _width
			var cj := cur / _width
			if ci == 0 or cj == 0 or ci == _width - 1 or cj == _height - 1:
				ocean = true
			if ci > 0 and wmask[cur - 1] == 1 and wcomp[cur - 1] == -1:
				wcomp[cur - 1] = wcid
				wstack.append(cur - 1)
			if ci < _width - 1 and wmask[cur + 1] == 1 and wcomp[cur + 1] == -1:
				wcomp[cur + 1] = wcid
				wstack.append(cur + 1)
			if cj > 0 and wmask[cur - _width] == 1 and wcomp[cur - _width] == -1:
				wcomp[cur - _width] = wcid
				wstack.append(cur - _width)
			if cj < _height - 1 and wmask[cur + _width] == 1 and wcomp[cur + _width] == -1:
				wcomp[cur + _width] = wcid
				wstack.append(cur + _width)
		wcomp_ocean.append(ocean)
		wcomp_lake.append(elevated)
		wcid += 1

	var wocean := PackedByteArray()
	wocean.resize(n)
	wocean.fill(0)
	for i in range(n):
		if wmask[i] == 1 and wcomp_ocean[wcomp[i]]:
			wocean[i] = 1
	var wocean_dist := TerrainUtils.distance_field(wocean, _width, _height)
	var wlake_min := {}
	for i in range(n):
		if wmask[i] == 0:
			continue
		var c: int = wcomp[i]
		if wcomp_ocean[c]:
			continue
		var d: float = wocean_dist[i]
		if not wlake_min.has(c) or d < wlake_min[c]:
			wlake_min[c] = d
	var lake_min_px := LAKE_MIN_DIST * _px_per_unit
	var filled := 0
	for i in range(n):
		if wmask[i] == 0:
			continue
		var c: int = wcomp[i]
		if not wcomp_ocean[c] and wlake_min[c] < lake_min_px and not wcomp_lake[c]:
			heights[i] = 0.1
			_wl_px[i] = 0.0
			filled += 1
	_height_px = heights
	print_verbose("[Terrain] lagos_rellenados=%d" % filled)

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
		var is_water := h < _wl_px[idx]
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
	_water_dist_px = TerrainUtils.distance_field(water_mask, _width, _height)

	var counts := [0, 0, 0, 0, 0, 0]
	for i in range(n):
		counts[_class_px[i]] += 1
	print_verbose("[Terrain] %dx%d px/unidad=%.2f | agua=%d playa=%d llanura=%d bosque=%d montaña=%d nieve=%d"
		% [_width, _height, _px_per_unit, counts[0], counts[1], counts[2], counts[3], counts[4], counts[5]])


# ---------------------------------------------------------------------------
# Rios
# ---------------------------------------------------------------------------
func _lowest_neighbor(heights: PackedFloat32Array, cur: int) -> int:
	var i := cur % _width
	var j := cur / _width
	var best := -1
	var best_h: float = heights[cur]
	for dj in range(-1, 2):
		for di in range(-1, 2):
			if di == 0 and dj == 0:
				continue
			var ni := i + di
			var nj := j + dj
			if ni < 0 or ni >= _width or nj < 0 or nj >= _height:
				continue
			var nidx := nj * _width + ni
			if heights[nidx] < best_h:
				best_h = heights[nidx]
				best = nidx
	return best


func _trace_river(heights: PackedFloat32Array, rng: RandomNumberGenerator, start_idx: int, mouth: Vector2i) -> Array[int]:
	var w := _width
	var h := _height
	var path: Array[int] = []
	var visited := PackedByteArray()
	visited.resize(w * h)
	visited.fill(0)
	var cur := start_idx
	var prev_dir := Vector2i.ZERO
	var steps := 0
	while steps < RIVER_MAX_STEPS:
		if heights[cur] < SEA_LEVEL:
			break
		path.append(cur)
		visited[cur] = 1
		var i := cur % w
		var j := cur / w
		var best := -1
		var best_cost := 1.0e9
		var to_mouth := Vector2(mouth - Vector2i(i, j)).normalized()
		for dj in range(-1, 2):
			for di in range(-1, 2):
				if di == 0 and dj == 0:
					continue
				var ni := i + di
				var nj := j + dj
				if ni < 0 or ni >= w or nj < 0 or nj >= h:
					continue
				var nidx := nj * w + ni
				if visited[nidx] == 1:
					continue
				var nh: float = heights[nidx]
				# Coste = altura + penalizacion de giro + atraccion hacia la boca
				# + pequeno ruido: el rio desciende, conserva su direccion y se
				# orienta hacia la costa opuesta.
				var cost := nh
				if prev_dir != Vector2i.ZERO:
					var nd := Vector2i(di, dj)
					var turn := 1.0 - Vector2(prev_dir).normalized().dot(Vector2(nd).normalized())
					cost += turn * RIVER_TURN_PENALTY
				cost += (1.0 - to_mouth.dot(Vector2(di, dj).normalized())) * RIVER_MOUTH_PULL
				cost += rng.randf_range(-RIVER_NOISE, RIVER_NOISE)
				if cost < best_cost:
					best_cost = cost
					best = nidx
		if best == -1:
			break
		prev_dir = Vector2i(best % w - i, best / w - j)
		cur = best
		steps += 1
	return path


func _meander_polyline(path: Array[int]) -> Dictionary:
	var pts := PackedVector2Array()
	for idx in path:
		pts.append(Vector2(idx % _width, idx / _width))
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	cum[0] = 0.0
	for k in range(1, pts.size()):
		cum[k] = cum[k - 1] + pts[k].distance_to(pts[k - 1])
	var total: float = cum[pts.size() - 1]
	if pts.size() < 3 or total <= 0.0:
		return {"points": pts, "cum": cum}
	var amp_px := RIVER_MEANDER_AMP_U * _px_per_unit
	var len_px := RIVER_MEANDER_LEN_U * _px_per_unit
	# Meandros irregulares: amplitud y onda moduladas por senos lentos, con
	# tramos mas curvos y otros casi rectos (nada de curvas uniformes).
	var meandered := PackedVector2Array()
	meandered.resize(pts.size())
	for k in range(pts.size()):
		# Normal perpendicular al flujo
		var nrm: Vector2
		if k == 0:
			nrm = (pts[1] - pts[0]).orthogonal().normalized()
		elif k == pts.size() - 1:
			nrm = (pts[k] - pts[k - 1]).orthogonal().normalized()
		else:
			nrm = (pts[k + 1] - pts[k - 1]).orthogonal().normalized()
		var s: float = cum[k] / len_px * TAU
		var amp_mod: float = 0.35 + 0.65 * (0.5 + 0.5 * sin(cum[k] * 0.05 + 1.3))
		var gate: float = 0.30 + 0.70 * (0.5 + 0.5 * sin(cum[k] * 0.028 + 4.7))
		var phase: float = sin(cum[k] * 0.041 + 2.2) * 1.8
		# Los meandros se atenuan en el nacimiento y la desembocadura
		var fade := clampf(minf(cum[k], total - cum[k]) / 10.0, 0.2, 1.0)
		meandered[k] = pts[k] + nrm * (amp_px * amp_mod * gate * fade * sin(s + phase))
	# Suavizado (media movil) para eliminar el aspecto pixelado
	var smooth := PackedVector2Array()
	smooth.resize(pts.size())
	for k in range(pts.size()):
		var acc := Vector2.ZERO
		var cnt := 0
		for o in range(-3, 4):
			acc += meandered[clampi(k + o, 0, pts.size() - 1)]
			cnt += 1
		smooth[k] = acc / float(cnt)
	# Distancias acumuladas a lo largo de la polilinea ya suavizada
	var scum := PackedFloat32Array()
	scum.resize(smooth.size())
	scum[0] = 0.0
	for k in range(1, smooth.size()):
		scum[k] = scum[k - 1] + smooth[k].distance_to(smooth[k - 1])
	return {"points": smooth, "cum": scum}


func _polyline_mask(pts: PackedVector2Array) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(_width * _height)
	m.fill(0)
	for k in range(pts.size()):
		var pi := clampi(int(round(pts[k].x)), 0, _width - 1)
		var pj := clampi(int(round(pts[k].y)), 0, _height - 1)
		m[pj * _width + pi] = 1
	return m


func _along_fraction(p: Vector2, pts: PackedVector2Array, cum: PackedFloat32Array, total: float) -> float:
	if pts.size() < 2 or total <= 0.0:
		return 0.0
	var stride := maxi(1, pts.size() / 16)
	var best := 0
	var best_d := 1.0e18
	for k in range(0, pts.size(), stride):
		var d: float = pts[k].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = k
	for k in range(maxi(0, best - stride * 2), mini(pts.size() - 1, best + stride * 2) + 1):
		var d: float = pts[k].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = k
	return cum[best] / total


func _opposite_mouth(heights: PackedFloat32Array, src: int) -> Vector2i:
	# Boca en la costa opuesta al lado mas cercano a la fuente
	var si := src % _width
	var sj := src / _width
	var nx := float(si) / float(_width)
	var ny := float(sj) / float(_height)
	var nearest := 0
	var nearest_d := nx
	if 1.0 - nx < nearest_d:
		nearest_d = 1.0 - nx
		nearest = 1
	if ny < nearest_d:
		nearest_d = ny
		nearest = 2
	if 1.0 - ny < nearest_d:
		nearest_d = 1.0 - ny
		nearest = 3
	var side := (nearest + 2) % 4
	var band := int(float(mini(_width, _height)) * 0.35)
	var best := Vector2i(-1, -1)
	var best_d := 1.0e18
	for j in range(_height):
		for i in range(_width):
			var on_side := false
			match side:
				0:
					on_side = i <= band
				1:
					on_side = i >= _width - 1 - band
				2:
					on_side = j <= band
				_:
					on_side = j >= _height - 1 - band
			if not on_side:
				continue
			var idx := j * _width + i
			if heights[idx] <= 0.0 or heights[idx] > BEACH_TOP:
				continue
			var touches := false
			for dj in range(-1, 2):
				for di in range(-1, 2):
					if di == 0 and dj == 0:
						continue
					var ni := clampi(i + di, 0, _width - 1)
					var nj := clampi(j + dj, 0, _height - 1)
					if heights[nj * _width + ni] < SEA_LEVEL:
						touches = true
						break
				if touches:
					break
			if not touches:
				continue
			var d := (si - i) * (si - i) + (sj - j) * (sj - j)
			if d < best_d:
				best_d = d
				best = Vector2i(i, j)
	return best


# ---------------------------------------------------------------------------
# Herramientas de imagen / campo de distancias
# ---------------------------------------------------------------------------
func _highest_pixel(heights: PackedFloat32Array) -> int:
	var best := 0
	var best_h: float = heights[0]
	for i in range(1, heights.size()):
		if heights[i] > best_h:
			best_h = heights[i]
			best = i
	return best


# Direccion de la abertura del lago de montaña: hacia el bosque (el terreno mas
# bajo que se encuentra al salir de la sierra), para que el valle se abra al
# terreno llano y no a otra pared de montaña.
func _lake_gap_direction(heights: PackedFloat32Array, center: Vector2, radius_u: float) -> Vector2:
	var steps := 32
	var best := Vector2(1.0, 0.0)
	var best_r := 1.0e18
	for k in range(steps):
		var ang := TAU * k / steps
		var d := Vector2(cos(ang), sin(ang))
		var r := -1.0
		for rr in range(int(radius_u) + 2, int(radius_u) + int(MOUNTAIN_LAKE_GAP_MAX_LEN)):
			var p := center + d * (float(rr) * _px_per_unit)
			var idx := clampi(int(round(p.y)), 0, _height - 1) * _width + clampi(int(round(p.x)), 0, _width - 1)
			if heights[idx] < MOUNTAIN_LAKE_FOREST_H:
				r = float(rr)
				break
		if r >= 0.0 and r < best_r:
			best_r = r
			best = d
	return best


# Longitud del valle: hasta el borde del bosque mas un margen, para que el
# suelo del valle termine ya en terreno bajo (se abre del todo al bosque).
func _lake_gap_length(heights: PackedFloat32Array, center: Vector2, radius_u: float, dir: Vector2) -> float:
	for rr in range(int(radius_u) + 2, int(radius_u) + int(MOUNTAIN_LAKE_GAP_MAX_LEN)):
		var p := center + dir * (float(rr) * _px_per_unit)
		var idx := clampi(int(round(p.y)), 0, _height - 1) * _width + clampi(int(round(p.x)), 0, _width - 1)
		if heights[idx] < MOUNTAIN_LAKE_FOREST_H:
			return float(rr) - radius_u + 6.0
	return MOUNTAIN_LAKE_GAP_MAX_LEN


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
	return TerrainUtils.bicubic(_height_px, _width, _height, fx, fy)


func water_level_at(p: Vector2) -> float:
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
	# Interpolacion bilineal: el nivel de agua varia de forma continua entre
	# pixeles (no a saltos), eliminando el borde de agua escalonado.
	var v00: float = _wl_px[y0 * _width + x0]
	var v10: float = _wl_px[y0 * _width + x1]
	var v01: float = _wl_px[y1 * _width + x0]
	var v11: float = _wl_px[y1 * _width + x1]
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


func make_minimap_texture(tex_size: int) -> ImageTexture:
	# Textura de vision general a partir de los datos del terreno ya generado:
	# color de bioma + sombreado de relieve con luz desde el noroeste.
	if _width == 0:
		return ImageTexture.create_from_image(Image.create(tex_size, tex_size, false, Image.FORMAT_RGB8))
	var step := WORLD_SIZE / float(tex_size)
	var hs := PackedFloat32Array()
	hs.resize(tex_size * tex_size)
	for j in range(tex_size):
		for i in range(tex_size):
			var px := clampi(int(float(i) / tex_size * _width), 0, _width - 1)
			var py := clampi(int(float(j) / tex_size * _height), 0, _height - 1)
			hs[j * tex_size + i] = _height_px[py * _width + px]
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.55, 0.8, -0.35).normalized()
	for j in range(tex_size):
		for i in range(tex_size):
			var px := clampi(int(float(i) / tex_size * _width), 0, _width - 1)
			var py := clampi(int(float(j) / tex_size * _height), 0, _height - 1)
			var idx := py * _width + px
			var c: int = _class_px[idx]
			var h: float = _height_px[idx]
			var col := biome_color(c, h)
			if c != CLASS_WATER:
				var il := maxi(0, i - 1)
				var ir := mini(tex_size - 1, i + 1)
				var jt := maxi(0, j - 1)
				var jb := mini(tex_size - 1, j + 1)
				var dzx := (hs[j * tex_size + ir] - hs[j * tex_size + il]) / step
				var dzy := (hs[jb * tex_size + i] - hs[jt * tex_size + i]) / step
				var nrm := Vector3(-dzx, 1.0, -dzy).normalized()
				var shade := clampf(0.58 + 0.42 * light.dot(nrm), 0.0, 1.0)
				col *= shade
			img.set_pixel(i, j, col)
	return ImageTexture.create_from_image(img)


func distance_to_water(p: Vector2) -> float:
	if _width == 0:
		return 0.0
	if is_water(p):
		return -0.1
	var pi := _pixel(p)
	return _water_dist_px[pi.y * _width + pi.x] / _px_per_unit