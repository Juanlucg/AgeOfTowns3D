extends Node3D
# Ciclo dia/noche. Rota el sol alrededor del mundo, gestiona una luna para la
# noche y ajusta un cielo procedural con shader (WorldEnvironment) junto con
# la luz ambiental segun la posicion del sol.
#
# El sol y la luna se dibujan dentro del propio shader del cielo: sin sprites,
# se desvanecen gradualmente cerca del horizonte y no generan artefactos.

@export var cycle_duration := 600.0   # segundos por dia completo (10 min)
@export var start_time := 0.42        # hora inicial (0.0 = medianoche, 0.5 = mediodia)
@export var days_per_season := 2      # dias (ciclos dia/noche) por estacion

const SEASONS := ["Primavera", "Verano", "Otoño", "Invierno"]

const SUN_ENERGY_MAX := 1.0
const MOON_ENERGY := 0.5
const DAY_AMBIENT := 0.35
const NIGHT_AMBIENT := 0.25

# Cielo de noche
const SKY_TOP_NIGHT := Color(0.005, 0.008, 0.03)
const SKY_HORIZON_NIGHT := Color(0.08, 0.11, 0.17)
const GROUND_HORIZON_NIGHT := Color(0.04, 0.05, 0.07)
const GROUND_TOP_NIGHT := Color(0.01, 0.012, 0.02)

const MOON_DISC_COLOR := Color(0.90, 0.95, 1.0)

# --- Paletas por estacion (Primavera, Verano, Otono, Invierno) ---
const DAY_FRACTION_BY_SEASON := [0.92, 0.98, 0.88, 0.72]
const SUN_PEAK_BY_SEASON := [0.85, 1.0, 0.75, 0.55]
const SKY_TOP_BY_SEASON := [
	Color(0.28, 0.58, 1.0),  # primavera: azul fresco
	Color(0.22, 0.48, 1.0),  # verano: azul intenso
	Color(0.42, 0.46, 0.80), # otono: azul violaceo
	Color(0.48, 0.52, 0.66), # invierno: gris azulado
]
const SKY_HORIZON_BY_SEASON := [
	Color(0.83, 0.93, 1.0),
	Color(0.78, 0.91, 1.0),
	Color(0.90, 0.82, 0.72),
	Color(0.74, 0.78, 0.82),
]
const GROUND_HORIZON_BY_SEASON := [
	Color(0.62, 0.72, 0.80),
	Color(0.60, 0.70, 0.78),
	Color(0.70, 0.62, 0.55),
	Color(0.62, 0.64, 0.68),
]
const GROUND_TOP_BY_SEASON := [
	Color(0.37, 0.47, 0.57),
	Color(0.35, 0.45, 0.55),
	Color(0.48, 0.40, 0.34),
	Color(0.52, 0.54, 0.58),
]
const AMBIENT_DAY_BY_SEASON := [
	Color(0.40, 0.48, 0.65),
	Color.WHITE,
	Color(0.55, 0.50, 0.45),
	Color(0.50, 0.56, 0.65),
]
const CLOUD_AMOUNT_BY_SEASON := [0.6, 0.45, 0.7, 0.85]
const CLOUD_COLOR_BY_SEASON := [
	Color(0.95, 0.97, 1.0),
	Color(0.95, 0.97, 1.0),
	Color(0.88, 0.86, 0.84),
	Color(0.72, 0.76, 0.82),
]

# Terreno: colores de bioma y linea de nieve segun la estacion
const PLAINS_BY_SEASON := [
	Color(0.44, 0.62, 0.30),
	Color(0.42, 0.60, 0.30),
	Color(0.58, 0.50, 0.26),
	Color(0.55, 0.56, 0.50),
]
const FOREST_BY_SEASON := [
	Color(0.16, 0.36, 0.13),
	Color(0.20, 0.38, 0.16),
	Color(0.42, 0.25, 0.12),
	Color(0.32, 0.30, 0.26),
]
const SNOW_COLOR_BY_SEASON := [
	Color(0.94, 0.95, 0.97),
	Color(0.94, 0.95, 0.97),
	Color(0.90, 0.92, 0.95),
	Color(0.82, 0.88, 0.95),
]
const SNOW_LEVEL_BY_SEASON := [6.6, 7.2, 6.0, 3.6]

# Clima: niebla y precipitacion (0..1 de intensidad)
const FOG_DENSITY_BY_SEASON := [0.0007, 0.0002, 0.0014, 0.0022]
const FOG_COLOR_BY_SEASON := [
	Color(0.70, 0.75, 0.80),
	Color(0.80, 0.84, 0.88),
	Color(0.72, 0.66, 0.58),
	Color(0.62, 0.66, 0.72),
]
const RAIN_BY_SEASON := [0.30, 0.15, 0.55, 0.0]
const SNOW_BY_SEASON := [0.0, 0.0, 0.0, 0.85]

const RAIN_PARTICLES := 4500
const SNOW_PARTICLES := 2600

const SKY_SHADER_CODE := """
shader_type sky;

uniform vec3 sky_top : source_color = vec3(0.22, 0.48, 1.0);
uniform vec3 sky_horizon : source_color = vec3(0.78, 0.91, 1.0);
uniform vec3 ground_horizon : source_color = vec3(0.60, 0.70, 0.78);
uniform vec3 ground_bottom : source_color = vec3(0.35, 0.45, 0.55);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float sun_size = 0.018;
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 moon_color : source_color = vec3(0.9, 0.95, 1.0);
uniform float moon_size = 0.014;
uniform vec3 cloud_color : source_color = vec3(0.95, 0.97, 1.0);
uniform float cloud_amount = 0.6;
uniform float cloud_day = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.2;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float y = dir.y;

	vec3 col;
	if (y >= 0.0) {
		float t = pow(clamp(y, 0.0, 1.0), 0.45);
		col = mix(sky_horizon, sky_top, t);
	} else {
		float t = pow(clamp(-y, 0.0, 1.0), 0.6);
		col = mix(ground_horizon, ground_bottom, t);
	}

	// Nubes: copos dispersos con ruido de alta frecuencia (solo los picos del
	// fbm superan el umbral), desplazados con el tiempo y desvanecidos de
	// noche (cloud_day). El offset evita que el patron colapse en el cenit.
	vec2 cp = dir.xz * 12.0 + vec2(6.0, 3.0) + vec2(TIME * 0.02, 0.0);
	float n = fbm(cp) * 0.7 + vnoise(cp * 3.0 + 17.0) * 0.3;
	float cloud = smoothstep(0.60, 0.76, n) * cloud_amount;
	col = mix(col, cloud_color, cloud * smoothstep(0.0, 0.05, y) * cloud_day * 0.55);

	// Hundimiento real: el disco se recorta por la linea del horizonte
	// (bajo el horizonte no se ve nada; banda minima solo antialiasing)
	float show = smoothstep(-0.002, 0.0, y);

	// Sol: disco + resplandor suave
	float as_ = acos(clamp(dot(dir, sun_dir), -1.0, 1.0));
	float disc = 1.0 - smoothstep(sun_size * 0.5, sun_size, as_);
	float glow = 1.0 - smoothstep(sun_size, sun_size * 7.0, as_);
	col += sun_color * (disc * 2.5 + glow * 0.6) * show;

	// Luna
	float am = acos(clamp(dot(dir, moon_dir), -1.0, 1.0));
	float mdisc = 1.0 - smoothstep(moon_size * 0.5, moon_size, am);
	col += moon_color * mdisc * 1.2 * show;

	COLOR = col;
}
"""

var _time := 0.0
var _day := 0
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _sky: ShaderMaterial
var _env: Environment
var _terrain_mat: ShaderMaterial
var _veg: Node
var _rain: GPUParticles3D
var _snow: GPUParticles3D


func _ready() -> void:
	_time = start_time

	for child in get_parent().get_children():
		if child is DirectionalLight3D:
			_sun = child
			break
	if _sun == null:
		_sun = DirectionalLight3D.new()
		_sun.shadow_enabled = true
		get_parent().add_child(_sun)

	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.55, 0.62, 0.85)
	_moon.light_energy = MOON_ENERGY
	_moon.shadow_enabled = false
	get_parent().add_child.call_deferred(_moon)

	_sky = ShaderMaterial.new()
	_sky.shader = Shader.new()
	_sky.shader.code = SKY_SHADER_CODE
	var sky_resource := Sky.new()
	sky_resource.sky_material = _sky
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky_resource
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = DAY_AMBIENT
	_env.ambient_light_color = Color.WHITE
	_env.fog_enabled = true
	_env.fog_density = 0.0
	_env.fog_light_color = FOG_COLOR_BY_SEASON[0]
	var we := WorldEnvironment.new()
	we.environment = _env
	get_parent().add_child.call_deferred(we)

	var ground := get_parent().get_node_or_null("Ground") as MeshInstance3D
	if ground != null:
		_terrain_mat = ground.get_surface_override_material(0) as ShaderMaterial
	_veg = get_parent().get_node_or_null("Vegetation")
	_setup_weather()


func _setup_weather() -> void:
	_rain = _make_particles(QuadMesh.new(), ParticleProcessMaterial.new(), 0.05, 0.6, RAIN_PARTICLES)
	_snow = _make_particles(QuadMesh.new(), ParticleProcessMaterial.new(), 0.22, 0.22, SNOW_PARTICLES)
	get_parent().add_child.call_deferred(_rain)
	get_parent().add_child.call_deferred(_snow)


func _make_particles(mesh: QuadMesh, pm: ParticleProcessMaterial, sx: float, sy: float, amount: int) -> GPUParticles3D:
	var half := Terrain.WORLD_SIZE * 0.5
	var p := GPUParticles3D.new()
	mesh.size = Vector2(sx, sy)
	mesh.orientation = QuadMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	p.draw_pass_1 = mesh
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(half, 30.0, half)
	pm.lifetime_randomness = 0.3
	p.process_material = pm
	p.amount = 1
	p.emitting = false
	p.visible = false
	p.lifetime = 2.0
	p.position = Vector3(half, 30.0, half)
	p.visibility_aabb = AABB(Vector3(-half, -40.0, -half), Vector3(half * 3.0, 80.0, half * 3.0))
	return p


func _process(delta: float) -> void:
	var prev := _time
	_time = fmod(_time + delta / cycle_duration, 1.0)
	if _time < prev:
		_day += 1
	_apply_lighting()
	_apply_weather()


# --- Consulta de fecha (para la interfaz y futuras mecanicas) ---
func get_time_of_day() -> float:
	return _time


func get_hour() -> float:
	return _time * 24.0


func get_day() -> int:
	return _day


func get_season() -> int:
	return floori(_day / days_per_season) % SEASONS.size()


func get_season_name() -> String:
	return SEASONS[get_season()]


# Progreso dentro de la estacion actual: 0 al empezar, 1 justo antes de cambiar.
func get_season_progress() -> float:
	return fmod(float(_day) / float(days_per_season), 1.0)


func get_weather_name() -> String:
	var k: float = get_season_progress()
	if _sfloat(SNOW_BY_SEASON, k) > 0.1:
		return "Nieve"
	if _sfloat(RAIN_BY_SEASON, k) > 0.1:
		return "Lluvia"
	return "Despejado"


func _sfloat(values: Array, k: float) -> float:
	var s := get_season()
	return lerpf(values[s], values[(s + 1) % values.size()], k)


func _scolor(values: Array, k: float) -> Color:
	var s := get_season()
	return (values[s] as Color).lerp(values[(s + 1) % values.size()] as Color, k)


func _sun_elevation(t: float, peak: float) -> float:
	# Elevacion del sol: 0 en el horizonte, 1 en lo alto, -1 bajo el.
	# El dia ocupa una fraccion del ciclo segun la estacion; el pico (elevacion
	# maxima al mediodia) tambien depende de la estacion.
	var day_start := 0.5 - _day_frac * 0.5
	var day_end := 0.5 + _day_frac * 0.5
	if t >= day_start and t <= day_end:
		var u := (t - day_start) / (day_end - day_start)
		return sin(u * PI) * peak
	if t < day_start:
		return -cos((t / day_start) * PI * 0.5)
	return -cos(((1.0 - t) / (1.0 - day_end)) * PI * 0.5)


var _day_frac := 0.9
var _sun_peak := 0.85


func _apply_lighting() -> void:
	var k: float = get_season_progress()
	_day_frac = _sfloat(DAY_FRACTION_BY_SEASON, k)
	_sun_peak = _sfloat(SUN_PEAK_BY_SEASON, k)
	var elev: float = _sun_elevation(_time, _sun_peak)

	# Curvas suaves: 1 de dia, 0 de noche, con crepusculos amplios y graduales
	var day_curve := clampf((elev + 0.25) / 0.5, 0.0, 1.0)
	var sky_curve := clampf((elev + 0.2) / 0.6, 0.0, 1.0)

	# Sol: orienta la luz para que llegue desde su posicion en el cielo
	var sun_dir := Vector3(cos(_time * TAU), elev, sin(_time * TAU)).normalized()
	_sun.look_at(_sun.global_position - sun_dir * 10.0, Vector3.UP)
	var sun_e: float = smoothstep(0.0, 0.3, elev) * SUN_ENERGY_MAX
	var warmth := 1.0 - clampf(elev / 0.4, 0.0, 1.0)
	var sun_color := Color(1.0, 1.0, 0.95).lerp(Color(1.0, 0.45, 0.22), warmth)
	_sun.light_energy = sun_e
	_sun.light_color = sun_color

	# Luna: opuesta al sol, tenue y azulada
	if _moon.is_inside_tree():
		_moon.look_at(_moon.global_position + sun_dir * 10.0, Vector3.UP)
	_moon.light_energy = (1.0 - day_curve) * MOON_ENERGY

	# Cielo: colores de la estacion interpolados, dia/noche por hora
	var sky_top := _scolor(SKY_TOP_BY_SEASON, k)
	var sky_horizon := _scolor(SKY_HORIZON_BY_SEASON, k)
	var ground_horizon := _scolor(GROUND_HORIZON_BY_SEASON, k)
	var ground_top := _scolor(GROUND_TOP_BY_SEASON, k)
	_sky.set_shader_parameter("sky_top", _v(SKY_TOP_NIGHT.lerp(sky_top, sky_curve)))
	_sky.set_shader_parameter("sky_horizon", _v(SKY_HORIZON_NIGHT.lerp(sky_horizon, sky_curve)))
	_sky.set_shader_parameter("ground_horizon", _v(GROUND_HORIZON_NIGHT.lerp(ground_horizon, sky_curve)))
	_sky.set_shader_parameter("ground_bottom", _v(GROUND_TOP_NIGHT.lerp(ground_top, sky_curve)))
	_sky.set_shader_parameter("sun_dir", sun_dir)
	_sky.set_shader_parameter("sun_color", _v(sun_color))
	_sky.set_shader_parameter("moon_dir", -sun_dir)
	_sky.set_shader_parameter("moon_color", _v(MOON_DISC_COLOR))
	_sky.set_shader_parameter("cloud_day", sky_curve)
	_sky.set_shader_parameter("cloud_amount", _sfloat(CLOUD_AMOUNT_BY_SEASON, k))
	_sky.set_shader_parameter("cloud_color", _v(_scolor(CLOUD_COLOR_BY_SEASON, k)))

	# Luz ambiental: la noche nunca queda a oscuras; color por estacion
	_env.ambient_light_energy = lerpf(NIGHT_AMBIENT, DAY_AMBIENT, day_curve)
	_env.ambient_light_color = Color(0.35, 0.45, 0.65).lerp(_scolor(AMBIENT_DAY_BY_SEASON, k), day_curve)

	# Terreno: colores de bioma y linea de nieve de la estacion
	if _terrain_mat != null:
		_terrain_mat.set_shader_parameter("u_plains", _v(_scolor(PLAINS_BY_SEASON, k)))
		_terrain_mat.set_shader_parameter("u_forest", _v(_scolor(FOREST_BY_SEASON, k)))
		_terrain_mat.set_shader_parameter("u_snow", _v(_scolor(SNOW_COLOR_BY_SEASON, k)))
		_terrain_mat.set_shader_parameter("u_snow_level", _sfloat(SNOW_LEVEL_BY_SEASON, k))

	# Niebla de la estacion
	_env.fog_density = _sfloat(FOG_DENSITY_BY_SEASON, k)
	_env.fog_light_color = _scolor(FOG_COLOR_BY_SEASON, k)

	if _veg != null:
		_veg.apply_season(get_season(), k)


func _apply_weather() -> void:
	if _rain == null or _snow == null:
		return
	var k: float = get_season_progress()
	var rain := _sfloat(RAIN_BY_SEASON, k)
	var snow := _sfloat(SNOW_BY_SEASON, k)
	if rain > 0.001:
		var pm := _rain.process_material as ParticleProcessMaterial
		pm.gravity = Vector3(0.0, -60.0, 0.0)
		pm.initial_velocity_min = 4.0
		pm.initial_velocity_max = 7.0
		pm.scale_min = 0.04
		pm.scale_max = 0.08
		pm.color = Color(0.7, 0.82, 0.95, 0.75)
		_rain.lifetime = 1.6
		_rain.amount = int(RAIN_PARTICLES * rain)
		_rain.emitting = true
		_rain.visible = true
	else:
		_rain.emitting = false
		_rain.visible = false
	if snow > 0.001:
		var pm := _snow.process_material as ParticleProcessMaterial
		pm.gravity = Vector3(0.0, -3.5, 0.0)
		pm.initial_velocity_min = 0.4
		pm.initial_velocity_max = 1.2
		pm.scale_min = 0.18
		pm.scale_max = 0.34
		pm.color = Color(0.95, 0.98, 1.0, 0.9)
		_snow.lifetime = 10.0
		_snow.amount = int(SNOW_PARTICLES * snow)
		_snow.emitting = true
		_snow.visible = true
	else:
		_snow.emitting = false
		_snow.visible = false


func _v(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)