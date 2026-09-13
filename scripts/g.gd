extends Node
## Global config + shared helpers (autoload "G").

const ARENA_HALF := 55.0
const SHIP_RADIUS := 2.2

# 0 = big, 1 = medium, 2 = small
const ROCK_RADII := [6.5, 3.8, 2.0]
const ROCK_SPEEDS := [
	[18.0, 22.0],
	[30.0, 35.0],
	[40.0, 50.0],
]
const ROCK_COLORS := [
	Color(0.30, 1.0, 0.53),
	Color(1.0, 0.84, 0.29),
	Color(1.0, 0.36, 0.56),
]
const SCORES := [20, 20, 10]

const SHIP_COLOR := Color(0.21, 0.94, 1.0)
const SHIP_FILL := Color(0.04, 0.22, 0.30, 0.35)
const FLAME_COLOR := Color(1.0, 0.60, 0.24)
const BULLET_COLOR := Color(1.0, 0.85, 0.23)

const UI_COLOR := Color(0.85, 0.97, 1.0)
const GRID_COLOR := Color(0.05, 0.16, 0.22)
const FRAME_COLOR := Color(0.16, 0.50, 0.62)
const BG_COLOR := Color(0.010, 0.012, 0.035)


static func wrap_pos(p: Vector3) -> Vector3:
	# Toroidal wrap inside the arena (classic asteroids).
	var span := ARENA_HALF * 2.0
	var x := fmod(p.x + ARENA_HALF, span)
	if x < 0.0:
		x += span
	var z := fmod(p.z + ARENA_HALF, span)
	if z < 0.0:
		z += span
	return Vector3(x - ARENA_HALF, 0.0, z - ARENA_HALF)


static func unshaded(color: Color, energy: float = 2.0, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


# Godot 4.7 removed the wireframe shading mode, so neon edges are built as
# real PRIMITIVE_LINES meshes (thin lines + bloom read as neon wireframe).
static func lines_mesh(pts: PackedVector3Array, edges: PackedInt32Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for i in range(0, edges.size(), 2):
		st.add_vertex(pts[edges[i]])
		st.add_vertex(pts[edges[i + 1]])
	return st.commit()


# Incremental convex hull for small point sets (rocks use 12 jittered
# icosahedron vertices). Returns faces as flat triangle index triples,
# wound CCW as seen from outside. Godot 4.7's ConvexPolygonShape3D only
# exposes `points` (no face API), so the hull is computed here.
static func convex_hull_faces(points: PackedVector3Array) -> PackedInt32Array:
	var n := points.size()
	if n < 4:
		return PackedInt32Array()
	var EPS := 1e-7
	# --- initial tetrahedron: 4 non-coplanar points ---
	var ia := 0
	var ib := -1
	for i in range(1, n):
		if points[i].distance_squared_to(points[ia]) > EPS:
			ib = i
			break
	if ib == -1:
		return PackedInt32Array()
	var ic := -1
	for i in range(n):
		if i == ia or i == ib:
			continue
		if (points[ib] - points[ia]).cross(points[i] - points[ia]).length() > EPS:
			ic = i
			break
	if ic == -1:
		return PackedInt32Array()
	var plane_n := (points[ib] - points[ia]).cross(points[ic] - points[ia])
	if plane_n.length() < EPS:
		return PackedInt32Array()
	var id := -1
	var best := 0.0
	for i in range(n):
		if i == ia or i == ib or i == ic:
			continue
		var dist := absf(plane_n.dot(points[i] - points[ia]))
		if dist > best:
			best = dist
			id = i
	if id == -1:
		return PackedInt32Array()
	var faces: Array = [
		_outward_tri(ia, ib, ic, id, points),
		_outward_tri(ia, ic, id, ib, points),
		_outward_tri(ia, id, ib, ic, points),
		_outward_tri(ib, ic, id, ia, points),
	]
	# --- incremental insertion of the remaining points ---
	for i in range(n):
		if i == ia or i == ib or i == ic or i == id:
			continue
		if not _point_outside(points[i], faces, points, EPS):
			continue
		_add_hull_point(i, faces, points, EPS)
	var out := PackedInt32Array()
	for f in faces:
		out.append(int(f[0]))
		out.append(int(f[1]))
		out.append(int(f[2]))
	return out


static func _outward_tri(a: int, b: int, c: int, opp: int, pts: PackedVector3Array) -> Array:
	var nrm := (pts[b] - pts[a]).cross(pts[c] - pts[a])
	if nrm.dot(pts[opp] - pts[a]) > 0.0:
		return [a, c, b]
	return [a, b, c]


static func _face_normal(f: Array, pts: PackedVector3Array) -> Vector3:
	var nrm := (pts[int(f[1])] - pts[int(f[0])]).cross(pts[int(f[2])] - pts[int(f[0])])
	var l := nrm.length()
	if l < 1e-12:
		return Vector3.UP
	return nrm / l


static func _point_outside(p: Vector3, faces: Array, pts: PackedVector3Array, eps: float) -> bool:
	for f in faces:
		if _face_normal(f, pts).dot(p - pts[int(f[0])]) > eps:
			return true
	return false


static func _add_hull_point(idx: int, faces: Array, pts: PackedVector3Array, eps: float) -> void:
	var p := pts[idx]
	var visible := {}
	for i in range(faces.size()):
		var f: Array = faces[i]
		if _face_normal(f, pts).dot(p - pts[int(f[0])]) > eps:
			visible[i] = true
	# ridge = edge bordering exactly one visible face
	var ridge_vis_count := {}
	var ridge_first_vis := {}
	for vi in visible:
		var f: Array = faces[vi]
		for k in 3:
			var u: int = int(f[k])
			var v: int = int(f[(k + 1) % 3])
			var key := mini(u, v) * 10000 + maxi(u, v)
			ridge_vis_count[key] = ridge_vis_count.get(key, 0) + 1
			ridge_first_vis[key] = f
	var kept: Array = []
	for i in range(faces.size()):
		if not visible.has(i):
			kept.append(faces[i])
	var new_faces: Array = []
	for key in ridge_vis_count.keys():
		if ridge_vis_count[key] != 1:
			continue
		var f: Array = ridge_first_vis[key]
		var u: int = -1
		var v: int = -1
		for k in 3:
			if mini(int(f[k]), int(f[(k + 1) % 3])) * 10000 + maxi(int(f[k]), int(f[(k + 1) % 3])) == key:
				u = int(f[k])
				v = int(f[(k + 1) % 3])
				break
		if u == -1:
			continue
		# find the adjacent non-visible face to get the opposite vertex w
		var w := -1
		for g in kept:
			for kk in 3:
				if (int(g[kk]) == u and int(g[(kk + 1) % 3]) == v) or (int(g[kk]) == v and int(g[(kk + 1) % 3]) == u):
					w = int(g[(kk + 2) % 3])
					break
			if w != -1:
				break
		if w == -1:
			continue
		var nf := [u, v, idx]
		var nrm := (pts[v] - pts[u]).cross(pts[idx] - pts[u])
		if nrm.dot(pts[w] - pts[u]) > 0.0:
			nf = [v, u, idx]
		new_faces.append(nf)
	faces.clear()
	faces.assign(kept + new_faces)


static func hull_edges(faces: PackedInt32Array) -> PackedInt32Array:
	var seen := {}
	var edges := PackedInt32Array()
	for i in range(0, faces.size(), 3):
		var tri := [faces[i], faces[i + 1], faces[i + 2]]
		for k in 3:
			var a: int = int(tri[k])
			var b: int = int(tri[(k + 1) % 3])
			var lo := mini(a, b)
			var hi := maxi(a, b)
			var key := lo * 10000 + hi
			if not seen.has(key):
				seen[key] = true
				edges.append(lo)
				edges.append(hi)
	return edges
