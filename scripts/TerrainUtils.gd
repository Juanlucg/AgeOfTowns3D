extends RefCounted
class_name TerrainUtils
# Utilidades puras de imagen: blur separable, distance field 2D, upsampling
# bilineal e interpolacion bicubica Catmull-Rom.
#
# Antes vivian como metodos privados de Terrain.gd y reutilizaban su estado
# (_width/_height). Aqui son funciones estaticas que reciben w/h, para que:
#   - Se puedan probar sin instanciar el autoload Terrain.
#   - Sean reutilizables (minimapa, validacion de campos, etc.).
#   - Terrain.gd baje ~190 lineas.

# --- Interpolacion ---

static func catmull1(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)


static func bicubic(data: PackedFloat32Array, w: int, h: int, fx: float, fy: float) -> float:
	var x0 := int(fx) - 1
	var y0 := int(fy) - 1
	var tx := fx - int(fx)
	var ty := fy - int(fy)
	var ya := clampi(y0, 0, h - 1)
	var yb := clampi(y0 + 1, 0, h - 1)
	var yc := clampi(y0 + 2, 0, h - 1)
	var yd := clampi(y0 + 3, 0, h - 1)
	var xa := clampi(x0, 0, w - 1)
	var xb := clampi(x0 + 1, 0, w - 1)
	var xc := clampi(x0 + 2, 0, w - 1)
	var xd := clampi(x0 + 3, 0, w - 1)
	var r0 := catmull1(data[ya * w + xa], data[yb * w + xa], data[yc * w + xa], data[yd * w + xa], ty)
	var r1 := catmull1(data[ya * w + xb], data[yb * w + xb], data[yc * w + xb], data[yd * w + xb], ty)
	var r2 := catmull1(data[ya * w + xc], data[yb * w + xc], data[yc * w + xc], data[yd * w + xc], ty)
	var r3 := catmull1(data[ya * w + xd], data[yb * w + xd], data[yc * w + xd], data[yd * w + xd], ty)
	return catmull1(r0, r1, r2, r3, tx)


static func smoothstep(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# --- Blur separable con sumas prefix (O(w*h) en vez de O(w*h*r)) ---

static func blur_x(src: PackedFloat32Array, w: int, h: int, radius: int) -> PackedFloat32Array:
	return _blur_dim(src, w, h, radius, true)


static func blur_y(src: PackedFloat32Array, w: int, h: int, radius: int) -> PackedFloat32Array:
	return _blur_dim(src, w, h, radius, false)


static func _blur_dim(src: PackedFloat32Array, w: int, h: int, radius: int, horizontal: bool) -> PackedFloat32Array:
	var out := src.duplicate()
	var pref := PackedFloat32Array()
	if horizontal:
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
	else:
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


# --- Distance field 2D (Chamfer 1/1.41421, dos pasadas) ---

static func distance_field(inside: PackedByteArray, w: int, h: int) -> PackedFloat32Array:
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


# Igual pero limitada a una region (los pixeles fuera quedan a distancia enorme).
static func distance_field_region(inside: PackedByteArray, w: int, h: int, box: Rect2i) -> PackedFloat32Array:
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	dist.fill(1.0e9)
	var x0 := clampi(box.position.x, 0, w - 1)
	var y0 := clampi(box.position.y, 0, h - 1)
	var x1 := clampi(box.end.x - 1, 0, w - 1)
	var y1 := clampi(box.end.y - 1, 0, h - 1)
	for j in range(y0, y1 + 1):
		for i in range(x0, x1 + 1):
			if inside[j * w + i] == 1:
				dist[j * w + i] = 0.0
	for j in range(y0, y1 + 1):
		for i in range(x0, x1 + 1):
			var idx := j * w + i
			var d := dist[idx]
			if i > x0:
				d = minf(d, dist[idx - 1] + 1.0)
			if j > y0:
				d = minf(d, dist[idx - w] + 1.0)
			if i > x0 and j > y0:
				d = minf(d, dist[idx - w - 1] + 1.41421)
			if i < x1 and j > y0:
				d = minf(d, dist[idx - w + 1] + 1.41421)
			dist[idx] = d
	for j in range(y1, y0 - 1, -1):
		for i in range(x1, x0 - 1, -1):
			var idx := j * w + i
			var d := dist[idx]
			if i < x1:
				d = minf(d, dist[idx + 1] + 1.0)
			if j < y1:
				d = minf(d, dist[idx + w] + 1.0)
			if i < x1 and j < y1:
				d = minf(d, dist[idx + w + 1] + 1.41421)
			if i > x0 and j < y1:
				d = minf(d, dist[idx + w - 1] + 1.41421)
			dist[idx] = d
	return dist


# --- Upsampling bilineal ---

static func upsample_field(low: PackedFloat32Array, lw: int, lh: int, out_w: int, out_h: int, scale := 1.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(out_w * out_h)
	for j in range(out_h):
		var fy := (float(j) + 0.5) / float(out_h) * float(lh) - 0.5
		var y0 := clampi(int(floor(fy)), 0, lh - 1)
		var y1 := mini(y0 + 1, lh - 1)
		var ty: float = fy - floor(fy)
		for i in range(out_w):
			var fx := (float(i) + 0.5) / float(out_w) * float(lw) - 0.5
			var x0 := clampi(int(floor(fx)), 0, lw - 1)
			var x1 := mini(x0 + 1, lw - 1)
			var tx: float = fx - floor(fx)
			var v00 := low[y0 * lw + x0]
			var v10 := low[y0 * lw + x1]
			var v01 := low[y1 * lw + x0]
			var v11 := low[y1 * lw + x1]
			out[j * out_w + i] = lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), ty) * scale
	return out
