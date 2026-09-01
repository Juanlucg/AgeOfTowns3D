extends MeshInstance3D
# Malla del suelo. La altura y el ruido de bosque se pasan como atributos de
# vertice (se interpolan suavemente por triangulo) y el shader calcula el color
# de cada bioma con smoothstep: transiciones infinitamente suaves y sin
# resolucion de textura, nitidas a cualquier zoom.

const CELL := 0.45


func _ready() -> void:
	mesh = _build_mesh()
	_apply_material()


func _build_mesh() -> ArrayMesh:
	var size: float = Terrain.WORLD_SIZE
	var steps := int(size / CELL)
	var side := steps + 1
	var nv := side * side

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var custom := PackedFloat32Array()
	var hgrid := PackedFloat32Array()
	verts.resize(nv)
	uvs.resize(nv)
	custom.resize(nv * 4)
	hgrid.resize(nv)

	for j in range(side):
		var y: float = j * CELL
		for i in range(side):
			var x: float = i * CELL
			var p := Vector2(x, y)
			var h: float = Terrain.height_at(p)
			var forest: float = Terrain.forest_at(p)
			var wl: float = Terrain.water_level_at(p)
			# Bajo el nivel local de agua (mar=0, lagos elevados): superficie
			# plana a ese nivel (en CPU para que las normales queden correctas)
			var surf_h := wl if h < wl else h
			var idx := j * side + i
			var c4 := idx * 4
			hgrid[idx] = surf_h
			verts[idx] = Vector3(x, surf_h, y)
			uvs[idx] = Vector2(x / size, y / size)
			custom[c4] = h
			custom[c4 + 1] = forest
			custom[c4 + 2] = 0.0
			custom[c4 + 3] = wl

	var normals := PackedVector3Array()
	normals.resize(nv)
	for j in range(side):
		var row := j * side
		var row_u := maxi(0, j - 1) * side
		var row_d := mini(side - 1, j + 1) * side
		for i in range(side):
			var il := maxi(0, i - 1)
			var ir := mini(side - 1, i + 1)
			var dl: float = hgrid[row + il]
			var dr: float = hgrid[row + ir]
			var du: float = hgrid[row_u + i]
			var dd: float = hgrid[row_d + i]
			normals[row + i] = Vector3(dr - dl, -2.0 * CELL, dd - du).normalized()

	var inds := PackedInt32Array()
	inds.resize(steps * steps * 6)
	var o := 0
	for j in range(steps):
		for i in range(steps):
			var a := j * side + i
			var b := a + 1
			var c := a + side
			var d := c + 1
			inds[o] = a
			o += 1
			inds[o] = c
			o += 1
			inds[o] = b
			o += 1
			inds[o] = b
			o += 1
			inds[o] = c
			o += 1
			inds[o] = d
			o += 1

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_CUSTOM0] = custom
	arr[Mesh.ARRAY_INDEX] = inds
	var m := ArrayMesh.new()
	var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	return m


func _apply_material() -> void:
	var shader := Shader.new()
	shader.code = """
		shader_type spatial;
		render_mode cull_disabled;

		const vec3 C_WATER_DEEP = vec3(0.07, 0.22, 0.42);
		const vec3 C_BEACH = vec3(0.85, 0.78, 0.55);
		const vec3 C_ROCK = vec3(0.48, 0.46, 0.42);
		uniform vec3 u_plains = vec3(0.42, 0.60, 0.30);
		uniform vec3 u_forest = vec3(0.20, 0.38, 0.16);
		uniform vec3 u_snow = vec3(0.94, 0.95, 0.97);
		uniform float u_snow_level = 7.0;
		uniform float u_snow_cover = 0.0;
		uniform float u_wet = 0.0;
		uniform float u_rain_ripple = 0.0;

		varying vec4 custom0;

		float hash(vec2 p) {
			return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
		}

		void vertex() {
			custom0 = CUSTOM0;
		}

		void fragment() {
			float h = custom0.x;
			float forest = custom0.y;
			float wl = custom0.w;

			vec3 land = C_BEACH;
			float t_plains = smoothstep(0.28, 0.36, h);
			land = mix(land, u_plains, t_plains);
			float t_rock = smoothstep(2.6, 2.75, h);
			land = mix(land, C_ROCK, t_rock);
			float t_snow = smoothstep(u_snow_level, u_snow_level + 0.15, h);
			land = mix(land, u_snow, t_snow);
			float plains_lo = smoothstep(0.36, 0.5, h);
			float plains_hi = smoothstep(2.45, 2.3, h);
			float t_forest = plains_lo * plains_hi * smoothstep(0.06, 0.10, forest);
			land = mix(land, u_forest, t_forest);

			// Nieve acumulada fina por nevada (no altura, solo clima): capa translucida
			// sobre llanura/bosque, nunca sobre agua ni playa y menos en roca alta
			if (u_snow_cover > 0.001) {
				float snow_mask = (1.0 - step(h, 0.3)) * plains_lo * plains_hi;
				// Atenua en bosque denso y en roca para variedad
				snow_mask *= (1.0 - t_forest * 0.5) * (1.0 - t_rock * 0.7);
				float snow_a = u_snow_cover * snow_mask * 0.85;
				land = mix(land, u_snow, clamp(snow_a, 0.0, 0.55));
			}
			// Suelo mojado por lluvia: oscurece y baja rugosidad
			if (u_wet > 0.001) {
				float wet_mask = (1.0 - smoothstep(u_snow_level, u_snow_level + 0.15, h)) * (1.0 - t_rock * 0.6);
				land = mix(land, land * 0.78, clamp(u_wet * wet_mask * 0.65, 0.0, 0.35));
			}

			// Agua de un solo color plano: sin gradiente, sin espuma. El borde
			// es una transicion ANCHA (suave, como orilla mojada) para que la
			// linea de costa no se vea pixelada en lagos y rios pequenos.
			float water_t = smoothstep(wl + 0.2, wl - 0.2, h);
			vec3 col = mix(land, C_WATER_DEEP, water_t);

			ALBEDO = col;
			if (water_t > 0.5) {
				float n1 = sin(UV.x * 40.0 + TIME * 0.6) + sin(UV.y * 30.0 - TIME * 0.4);
				float n2 = cos(UV.x * 28.0 - TIME * 0.5) + cos(UV.y * 36.0 + TIME * 0.7);
				vec3 n = vec3(n1 * 0.15, 1.0, n2 * 0.15);
				// Lluvia sobre el agua: anillos concentricos como en la foto de referencia
				float rain_rings = 0.0;
				float rain_norm = 0.0;
				if (u_rain_ripple > 0.001) {
					vec2 uvp = UV * 75.0;
					vec2 ip = floor(uvp);
					vec2 fp = fract(uvp);
					float t = TIME * 0.55;
					for (int y = -1; y <= 1; y++) {
						for (int x = -1; x <= 1; x++) {
							vec2 cell = ip + vec2(float(x), float(y));
							float h1 = hash(cell);
							float h2 = hash(cell + vec2(19.3, 7.1));
							vec2 center = vec2(h1, h2);
							float dist = length(fp - center + vec2(float(x), float(y)));
							float phase = fract(t * (0.5 + h1 * 0.5) + h2 * 6.283);
							float radius = phase * 0.45;
							float w = 0.018 + h1 * 0.012;
							float ring = 1.0 - smoothstep(w, w + 0.022, abs(dist - radius));
							ring *= smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(0.35, 0.5, phase));
							rain_rings += ring * 0.55;
							// Normales sutiles de los anillos
							rain_norm += ring * sign(dist - radius) * 0.5;
						}
					}
					rain_rings = clamp(rain_rings, 0.0, 1.0);
					n.x += rain_norm * 0.06 * u_rain_ripple;
					n.z += rain_norm * 0.06 * u_rain_ripple;
					// Oscurece ligeramente el centro del anillo como en la foto
					col = mix(col, col * 0.88, clamp(rain_rings * u_rain_ripple * 0.45, 0.0, 0.3));
				}
				NORMAL = normalize(n);
				ROUGHNESS = mix(0.15, 0.28, clamp(u_rain_ripple * 0.6 + rain_rings * 0.25, 0.0, 1.0));
			} else {
				ROUGHNESS = mix(1.0, 0.45, clamp(u_wet * 0.7, 0.0, 1.0));
			}
		}
	"""

	var mat := ShaderMaterial.new()
	mat.shader = shader
	set_surface_override_material(0, mat)
