extends MeshInstance3D
# Malla del suelo. La altura y el ruido de bosque se pasan como atributos de
# vertice (se interpolan suavemente por triangulo) y el shader calcula el color
# de cada bioma con smoothstep: transiciones infinitamente suaves y sin
# resolucion de textura, nitidas a cualquier zoom.

const CELL := 0.3


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
			var wl: float = Terrain.water_level_at(p)
			# Bajo el nivel local de agua (mar=0, lagos elevados): superficie
			# plana a ese nivel (en CPU para que las normales queden correctas)
			var surf_h := wl if h < wl else h
			st.set_custom(0, Color(h, forest, 0.0, wl))
			st.set_uv(Vector2(x / size, y / size))
			st.add_vertex(Vector3(x, surf_h, y))

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

		const vec3 C_WATER_DEEP = vec3(0.07, 0.22, 0.42);
		const vec3 C_BEACH = vec3(0.85, 0.78, 0.55);
		const vec3 C_PLAINS = vec3(0.42, 0.60, 0.30);
		const vec3 C_FOREST = vec3(0.20, 0.38, 0.16);
		const vec3 C_ROCK = vec3(0.48, 0.46, 0.42);
		const vec3 C_SNOW = vec3(0.94, 0.95, 0.97);

		varying vec4 custom0;

		void vertex() {
			custom0 = CUSTOM0;
		}

		void fragment() {
			float h = custom0.x;
			float forest = custom0.y;
			float wl = custom0.w;

			vec3 land = C_BEACH;
			float t_plains = smoothstep(0.28, 0.36, h);
			land = mix(land, C_PLAINS, t_plains);
			float t_rock = smoothstep(2.6, 2.75, h);
			land = mix(land, C_ROCK, t_rock);
			float t_snow = smoothstep(7.0, 7.15, h);
			land = mix(land, C_SNOW, t_snow);
			float plains_lo = smoothstep(0.36, 0.5, h);
			float plains_hi = smoothstep(2.45, 2.3, h);
			float t_forest = plains_lo * plains_hi * smoothstep(0.06, 0.10, forest);
			land = mix(land, C_FOREST, t_forest);

			// Agua de un solo color plano: sin gradiente, sin espuma. El borde
			// es una transicion ANCHA (suave, como orilla mojada) para que la
			// linea de costa no se vea pixelada en lagos y rios pequenos.
			float water_t = smoothstep(wl + 0.2, wl - 0.2, h);
			vec3 col = mix(land, C_WATER_DEEP, water_t);

			ALBEDO = col;
			if (water_t > 0.5) {
				// Brillo del sol sobre olas amplias y lentas (solo iluminacion)
				float n1 = sin(UV.x * 40.0 + TIME * 0.6) + sin(UV.y * 30.0 - TIME * 0.4);
				float n2 = cos(UV.x * 28.0 - TIME * 0.5) + cos(UV.y * 36.0 + TIME * 0.7);
				NORMAL = normalize(vec3(n1 * 0.15, 1.0, n2 * 0.15));
				ROUGHNESS = 0.15;
			} else {
				ROUGHNESS = 1.0;
			}
		}
	"""

	var mat := ShaderMaterial.new()
	mat.shader = shader
	set_surface_override_material(0, mat)
