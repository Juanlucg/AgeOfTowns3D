extends MeshInstance3D
class_name OpenSea
## Mar abierto: una lamina plana al nivel del mar que rodea el mapa jugable y
## se extiende hasta perderse de vista.
##
## Sin esto, el terreno acaba en seco en el borde de las 300 unidades y detras
## solo se ve el hemisferio inferior del shader del cielo, que esta pintado de
## un gris azulado plano: una linea recta durisima cruzando la pantalla, y el
## sol poniendose tras ese gris en vez de tras el agua.
##
## Es un anillo (cuatro cuadrilateros alrededor del mapa), no una lamina
## completa: si tapara tambien el mapa, se solaparia con el agua que ya dibuja
## TerrainMesh a esa misma altura y las dos superficies pelearian por el
## z-buffer.
##
## Coste: 8 triangulos.

## Hasta donde llega el mar por fuera del mapa. Tiene que ser bastante mayor
## que la altura de camara para que su borde exterior quede por debajo del
## horizonte: con 3000 u y la camara a 200 u de alto, el borde cae 3,8 grados
## bajo el horizonte, y a esa distancia la niebla ya lo ha fundido con el cielo.
const REACH := 3000.0

## Mismo color que el agua profunda de TerrainMesh (C_WATER_DEEP): la costura
## entre el agua del mapa y el mar abierto tiene que ser invisible.
const DEEP := Color(0.07, 0.22, 0.42)

## Las olas de TerrainMesh usan UV (0..1 sobre las 300 u del mapa) a frecuencia
## 40, o sea una longitud de onda de 7,5 u. Aqui se usan coordenadas de mundo,
## asi que hay que reescalar para que el oleaje case a ambos lados de la costura.
const UV_TO_WORLD := 1.0 / 300.0

var sea_material: ShaderMaterial


func _ready() -> void:
	var size: float = Terrain.WORLD_SIZE
	mesh = _build_ring(size)
	sea_material = _make_material()
	material_override = sea_material
	# El mar tapa el borde cortado de la malla del terreno, que queda por
	# debajo del nivel del agua en todo el perimetro.
	position = Vector3.ZERO


# Cuatro cuadrilateros que cubren todo lo que hay fuera de [0,size] x [0,size]
# sin solaparse con el mapa.
func _build_ring(size: float) -> ArrayMesh:
	var lo := -REACH
	var hi := size + REACH
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# norte y sur ocupan todo el ancho; este y oeste solo la franja del mapa
	_quad(st, lo, lo, hi, 0.0)
	_quad(st, lo, size, hi, hi)
	_quad(st, lo, 0.0, 0.0, size)
	_quad(st, size, 0.0, hi, size)
	return st.commit()


func _quad(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float) -> void:
	var y := Terrain.SEA_LEVEL
	var a := Vector3(x0, y, z0)
	var b := Vector3(x1, y, z0)
	var c := Vector3(x0, y, z1)
	var d := Vector3(x1, y, z1)
	# Sentido horario visto desde arriba: es el que Godot toma como cara
	# frontal. Con el orden contrario el mar existe pero se lo come el
	# backface culling y no se ve nada.
	for v in [a, b, c, b, d, c]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)


func _make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
		shader_type spatial;
		render_mode cull_disabled;

		uniform vec3 u_deep : source_color = vec3(0.07, 0.22, 0.42);
		uniform float u_wave_scale = 0.00333333;
		uniform float u_rain_ripple = 0.0;

		varying vec3 vworld;

		void vertex() {
			vworld = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		}

		void fragment() {
			// Mismo oleaje que el agua de TerrainMesh, pero en coordenadas de
			// mundo para que no dependa del tamano del cuadrilatero.
			vec2 uv = vworld.xz * u_wave_scale;
			float n1 = sin(uv.x * 40.0 + TIME * 0.6) + sin(uv.y * 30.0 - TIME * 0.4);
			float n2 = cos(uv.x * 28.0 - TIME * 0.5) + cos(uv.y * 36.0 + TIME * 0.7);
			// El oleaje se aplana con la distancia. Sin esto, a 500+ u las olas
			// caen por debajo del tamano de un pixel y producen un moire de
			// anillos concentricos muy feo.
			float dist = length(vworld.xz - CAMERA_POSITION_WORLD.xz);
			float waves = 1.0 - smoothstep(80.0, 450.0, dist);
			ALBEDO = u_deep;
			NORMAL = normalize(vec3(n1 * 0.05 * waves, 1.0, n2 * 0.05 * waves));
			ROUGHNESS = mix(0.15, 0.28, clamp(u_rain_ripple * 0.6, 0.0, 1.0));
		}
	"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("u_deep", DEEP)
	mat.set_shader_parameter("u_wave_scale", UV_TO_WORLD)
	return mat
