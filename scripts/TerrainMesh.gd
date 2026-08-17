extends MeshInstance3D
# Malla del suelo. La altura y el ruido de bosque se pasan como atributos de
# vertice (se interpolan suavemente por triangulo) y el shader calcula el color
# de cada bioma con smoothstep: transiciones infinitamente suaves y sin
# resolucion de textura, nitidas a cualquier zoom.

const CELL := 0.4


func _ready() -> void:
	mesh = _build_mesh()
	_apply_material()


func _build_mesh() -> ArrayMesh:
	var size: float = Terrain.WORLD_SIZE
	var steps := int(size / CELL)
	var side := steps + 1

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)

	for j in range(side):
		for i in range(side):
			var x: float = i * CELL
			var y: float = j * CELL
			var p := Vector2(x, y)
			var h: float = Terrain.height_at(p)
			var forest: float = Terrain.forest_at(p)
			st.set_custom(0, Color(h, forest, 0.0, 0.0))
			st.set_uv(Vector2(x / size, y / size))
			st.add_vertex(Vector3(x, h, y))

	for j in range(steps):
		for i in range(steps):
			var a := j * side + i
			var b := a + 1
			var c := a + side
			var d := c + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)

	st.generate_normals()
	return st.commit()


func _apply_material() -> void:
	var shader := Shader.new()
	shader.code = """
		shader_type spatial;
		render_mode cull_disabled;

		uniform float noise_amp = 0.10;

		const vec3 C_WATER_SHALLOW = vec3(0.20, 0.50, 0.72);
		const vec3 C_WATER_DEEP = vec3(0.07, 0.22, 0.42);
		const vec3 C_BEACH = vec3(0.85, 0.78, 0.55);
		const vec3 C_PLAINS = vec3(0.42, 0.60, 0.30);
		const vec3 C_FOREST = vec3(0.20, 0.38, 0.16);
		const vec3 C_ROCK = vec3(0.48, 0.46, 0.42);
		const vec3 C_SNOW = vec3(0.94, 0.95, 0.97);

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
			return 0.65 * vnoise(p) + 0.35 * vnoise(p * 2.7 + 17.3);
		}

		varying vec4 custom0;

		void vertex() {
			custom0 = CUSTOM0;
		}

		void fragment() {
			float h = custom0.x;
			float forest = custom0.y;

			vec3 water_col = mix(C_WATER_SHALLOW, C_WATER_DEEP, clamp(-h / 1.5, 0.0, 1.0));

			vec3 land = C_BEACH;
			float t_plains = smoothstep(0.28, 0.36, h);
			land = mix(land, C_PLAINS, t_plains);
			float t_rock = smoothstep(3.0, 3.15, h);
			land = mix(land, C_ROCK, t_rock);
			float t_snow = smoothstep(4.2, 4.35, h);
			land = mix(land, C_SNOW, t_snow);
			float plains_lo = smoothstep(0.36, 0.5, h);
			float plains_hi = smoothstep(3.0, 2.8, h);
			float t_forest = plains_lo * plains_hi * smoothstep(0.06, 0.10, forest);
			land = mix(land, C_FOREST, t_forest);

			float water_t = smoothstep(0.15, -0.05, h);
			vec3 base = mix(land, water_col, water_t);

			vec2 wp = UV * vec2(100.0);
			float n = fbm(wp * 1.4);
			float m = fbm(wp * 6.2 + 53.7);
			float detail = n * 0.7 + m * 0.3 - 0.5;
			ALBEDO = base * (1.0 + detail * noise_amp);
			ROUGHNESS = 1.0;
		}
	"""

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("noise_amp", 0.10)
	set_surface_override_material(0, mat)
