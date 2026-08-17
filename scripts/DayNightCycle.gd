extends Node3D
# Ciclo dia/noche. Rota el sol alrededor del mundo, gestiona una luna para la
# noche y ajusta un cielo procedural con shader (WorldEnvironment) junto con
# la luz ambiental segun la posicion del sol.
#
# El sol y la luna se dibujan dentro del propio shader del cielo: sin sprites,
# se desvanecen gradualmente cerca del horizonte y no generan artefactos.

@export var cycle_duration := 180.0   # segundos por dia completo
@export var start_time := 0.42        # hora inicial (0.0 = medianoche, 0.5 = mediodia)

const SUN_ENERGY_MAX := 1.0
const MOON_ENERGY := 0.5
const DAY_AMBIENT := 0.35
const NIGHT_AMBIENT := 0.25
const DAY_FRACTION := 0.62   # fraccion del ciclo con el sol sobre el horizonte

# Cielo de dia
const SKY_TOP_DAY := Color(0.22, 0.48, 1.0)
const SKY_HORIZON_DAY := Color(0.78, 0.91, 1.0)
const GROUND_HORIZON_DAY := Color(0.60, 0.70, 0.78)
const GROUND_TOP_DAY := Color(0.35, 0.45, 0.55)
# Cielo de noche
const SKY_TOP_NIGHT := Color(0.005, 0.008, 0.03)
const SKY_HORIZON_NIGHT := Color(0.08, 0.11, 0.17)
const GROUND_HORIZON_NIGHT := Color(0.04, 0.05, 0.07)
const GROUND_TOP_NIGHT := Color(0.01, 0.012, 0.02)

const MOON_DISC_COLOR := Color(0.90, 0.95, 1.0)

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
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _sky: ShaderMaterial
var _env: Environment


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
	var we := WorldEnvironment.new()
	we.environment = _env
	get_parent().add_child.call_deferred(we)


func _process(delta: float) -> void:
	_time = fmod(_time + delta / cycle_duration, 1.0)
	_apply_lighting()


func _sun_elevation(t: float) -> float:
	# Elevacion del sol: 0 en el horizonte, 1 en lo alto, -1 bajo el.
	# El dia ocupa DAY_FRACTION del ciclo, la noche lo restante (mas corta).
	var day_start := 0.5 - DAY_FRACTION * 0.5
	var day_end := 0.5 + DAY_FRACTION * 0.5
	if t >= day_start and t <= day_end:
		var u := (t - day_start) / (day_end - day_start)
		return sin(u * PI)
	if t < day_start:
		return -cos((t / day_start) * PI * 0.5)
	return -cos(((1.0 - t) / (1.0 - day_end)) * PI * 0.5)


func _apply_lighting() -> void:
	var elev: float = _sun_elevation(_time)

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

	# Cielo (colores + disco del sol y la luna)
	_sky.set_shader_parameter("sky_top", _v(SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, sky_curve)))
	_sky.set_shader_parameter("sky_horizon", _v(SKY_HORIZON_NIGHT.lerp(SKY_HORIZON_DAY, sky_curve)))
	_sky.set_shader_parameter("ground_horizon", _v(GROUND_HORIZON_NIGHT.lerp(GROUND_HORIZON_DAY, sky_curve)))
	_sky.set_shader_parameter("ground_bottom", _v(GROUND_TOP_NIGHT.lerp(GROUND_TOP_DAY, sky_curve)))
	_sky.set_shader_parameter("sun_dir", sun_dir)
	_sky.set_shader_parameter("sun_color", _v(sun_color))
	_sky.set_shader_parameter("moon_dir", -sun_dir)
	_sky.set_shader_parameter("moon_color", _v(MOON_DISC_COLOR))

	# Luz ambiental: la noche nunca queda a oscuras
	_env.ambient_light_energy = lerpf(NIGHT_AMBIENT, DAY_AMBIENT, day_curve)
	_env.ambient_light_color = Color(0.35, 0.45, 0.65).lerp(Color.WHITE, day_curve)


func _v(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)