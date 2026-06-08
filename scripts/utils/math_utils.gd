class_name MathUtils

static func clampf(value: float, min_v: float, max_v: float) -> float:
	return clamp(value, min_v, max_v)


static func dist(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)


static func angle_between(from_pos: Vector2, to_pos: Vector2) -> float:
	return (to_pos - from_pos).angle()


static func point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func segment_circle_crossings(a: Vector2, b: Vector2, center: Vector2, radius: float) -> Array:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	if ab_len_sq < 0.0001:
		return []
	var ac := a - center
	var b_coeff := 2.0 * ac.dot(ab)
	var c_coeff := ac.length_squared() - radius * radius
	var disc := b_coeff * b_coeff - 4.0 * ab_len_sq * c_coeff
	if disc < 0.0:
		return []
	var sqrt_disc := sqrt(disc)
	var inv_denom := 1.0 / (2.0 * ab_len_sq)
	var ts: Array[float] = []
	var t_a: float = (-b_coeff - sqrt_disc) * inv_denom
	var t_b: float = (-b_coeff + sqrt_disc) * inv_denom
	if t_a >= 0.0 and t_a <= 1.0:
		ts.append(t_a)
	if t_b >= 0.0 and t_b <= 1.0:
		ts.append(t_b)
	ts.sort()
	var events: Array = []
	var inside: bool = ac.length_squared() <= radius * radius
	var last_t := -1.0
	for t in ts:
		if last_t >= 0.0 and abs(t - last_t) < 0.000001:
			continue
		last_t = t
		if inside:
			events.append({"t": t, "enter": false})
			inside = false
		else:
			events.append({"t": t, "enter": true})
			inside = true
	return events


static func count_path_circle_hits(path: Array, center: Vector2, radius: float) -> int:
	if path.is_empty():
		return 0
	var start: Vector2 = path[0]
	var inside: bool = start.distance_to(center) <= radius
	var count := 1 if inside else 0
	for i in range(path.size() - 1):
		var from: Vector2 = path[i]
		var to: Vector2 = path[i + 1]
		for ev in segment_circle_crossings(from, to, center, radius):
			if bool(ev.get("enter", false)):
				if not inside:
					count += 1
				inside = true
			else:
				inside = false
	return count


static func rand_range(min_v: float, max_v: float) -> float:
	return randf_range(min_v, max_v)


static func lerp_f(a: float, b: float, t: float) -> float:
	return lerpf(a, b, t)


static func pick_random(arr: Array):
	if arr.is_empty():
		return null
	return arr[randi() % arr.size()]


static func segment_intersection(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Variant:
	var ab := b - a
	var cd := d - c
	var denom := ab.x * cd.y - ab.y * cd.x
	if absf(denom) < 0.0001:
		return null
	var ac := c - a
	var t := (ac.x * cd.y - ac.y * cd.x) / denom
	var u := (ac.x * ab.y - ac.y * ab.x) / denom
	if t <= 0.001 or t >= 0.999 or u <= 0.001 or u >= 0.999:
		return null
	return a + ab * t


static func _polygon_area(points: Array) -> float:
	if points.size() < 3:
		return 0.0
	var area := 0.0
	var n := points.size()
	for i in range(n):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	return abs(area) * 0.5


static func path_extract_closed_loop(path: Array, close_dist: float = 36.0, min_points: int = 5, min_area: float = 800.0) -> Array:
	var loops := path_extract_all_closed_loops(path, close_dist, min_points, min_area)
	if loops.is_empty():
		return []
	return loops[0]


static func path_extract_all_closed_loops(path: Array, close_dist: float = 36.0, min_points: int = 5, min_area: float = 800.0) -> Array:
	var loops: Array = []
	if path.size() < min_points:
		return loops
	var start: Vector2 = path[0]
	var end: Vector2 = path[path.size() - 1]
	if start.distance_to(end) <= close_dist:
		var loop: Array = []
		for p in path:
			loop.append(Vector2(p))
		if _polygon_area(loop) >= min_area:
			loops.append(loop)
			return loops
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		for j in range(i + 2, path.size() - 1):
			var c: Vector2 = path[j]
			var d: Vector2 = path[j + 1]
			var hit = segment_intersection(a, b, c, d)
			if hit == null:
				continue
			var loop_pts: Array = [Vector2(hit)]
			for k in range(i + 1, j + 1):
				loop_pts.append(Vector2(path[k]))
			if _polygon_area(loop_pts) >= min_area:
				loops.append(loop_pts)
	return _dedupe_loops(loops)


static func _dedupe_loops(loops: Array) -> Array:
	var result: Array = []
	for loop in loops:
		var center := polygon_centroid(loop)
		var area := _polygon_area(loop)
		var duplicate := false
		for existing in result:
			var ex_center := polygon_centroid(existing)
			var ex_area := _polygon_area(existing)
			if ex_center.distance_to(center) < 32.0 and absf(ex_area - area) < maxf(ex_area, area) * 0.15:
				duplicate = true
				break
		if not duplicate:
			result.append(loop)
	return result


static func path_forms_closed_loop(path: Array, close_dist: float = 36.0, min_points: int = 5, min_area: float = 800.0) -> bool:
	return not path_extract_closed_loop(path, close_dist, min_points, min_area).is_empty()


static func points_centroid(points: Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in points:
		sum += Vector2(p)
	return sum / float(points.size())


static func polygon_centroid(points: Array) -> Vector2:
	if points.size() < 3:
		return points_centroid(points)
	var area := 0.0
	var cx := 0.0
	var cy := 0.0
	var n := points.size()
	for i in range(n):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		var cross := a.x * b.y - b.x * a.y
		area += cross
		cx += (a.x + b.x) * cross
		cy += (a.y + b.y) * cross
	area *= 0.5
	if absf(area) < 0.001:
		return points_centroid(points)
	var inv := 1.0 / (6.0 * area)
	return Vector2(cx * inv, cy * inv)


static func path_loop_centroid(path: Array) -> Vector2:
	var loop := path_extract_closed_loop(path)
	if loop.is_empty():
		return points_centroid(path)
	return polygon_centroid(loop)


static func path_loop_radius(path: Array, center: Vector2) -> float:
	var max_r := 0.0
	for p in path:
		max_r = maxf(max_r, center.distance_to(Vector2(p)))
	return maxf(24.0, max_r)
