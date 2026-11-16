class_name AreaPreset
extends RefCounted

## Arena presets, MOBA/roguelike clearing silhouettes, and narrow causeway builders
## for Shape of Dreams-style procedural maps.

enum RoomRole {
	SPAWN,   ## Starting Sanctuary (with optional central pond)
	COMBAT,  ## Standard large combat clearing
	ELITE,   ## High-risk Hunter / Mini-Boss arena
	DEADEND, ## 1-hop side chamber (Memory Well, Shrine, Treasure)
	HUB,     ## Pre-Boss convergence crossroads
	BOSS     ## Colossal climax boss arena
}

# Backwards-compatibility alias
const LARGE: RoomRole = RoomRole.ELITE

enum ArenaShape {
	ROUNDED_RECT,      ## Wide meadow with smooth rounded corners
	CHAMFERED_OCTAGON, ## 8-sided Shape of Dreams arena with 45-degree corner sightlines
	CRUCIFORM          ## Plus-shaped battleground with 4 recessed cardinal alcoves
}


## Returns base dimensions (X width, Z depth) for a given room role
## Calibrated for Camera3D size = 11.0 (~19.5m x 19.0m view) to match Shape of Dreams ~2.0x-2.4x screen ratio
static func get_room_size(role: RoomRole, rng: RandomNumberGenerator, scale_mult: float = 1.0) -> Vector2:
	var base: Vector2
	match role:
		RoomRole.SPAWN:
			base = Vector2(rng.randf_range(31.0, 35.0), rng.randf_range(29.0, 33.0))
		RoomRole.COMBAT:
			base = Vector2(rng.randf_range(37.0, 45.0), rng.randf_range(32.0, 39.0))
		RoomRole.ELITE:
			base = Vector2(rng.randf_range(46.0, 53.0), rng.randf_range(38.0, 45.0))
		RoomRole.DEADEND:
			base = Vector2(rng.randf_range(24.0, 29.0), rng.randf_range(22.0, 26.0))
		RoomRole.HUB:
			base = Vector2(rng.randf_range(42.0, 48.0), rng.randf_range(36.0, 42.0))
		RoomRole.BOSS:
			base = Vector2(rng.randf_range(56.0, 64.0), rng.randf_range(46.0, 54.0))
		_:
			base = Vector2(38.0, 34.0)
	return base * scale_mult


## Chooses an appropriate arena silhouette for the given role
static func pick_arena_shape(role: RoomRole, rng: RandomNumberGenerator) -> ArenaShape:
	match role:
		RoomRole.SPAWN:
			return ArenaShape.ROUNDED_RECT
		RoomRole.DEADEND:
			return ArenaShape.CHAMFERED_OCTAGON if rng.randf() < 0.55 else ArenaShape.ROUNDED_RECT
		RoomRole.ELITE:
			var roll_e: float = rng.randf()
			if roll_e < 0.45:
				return ArenaShape.CHAMFERED_OCTAGON
			elif roll_e < 0.80:
				return ArenaShape.CRUCIFORM
			return ArenaShape.ROUNDED_RECT
		RoomRole.HUB:
			return ArenaShape.CHAMFERED_OCTAGON if rng.randf() < 0.65 else ArenaShape.CRUCIFORM
		RoomRole.BOSS:
			return ArenaShape.CHAMFERED_OCTAGON if rng.randf() < 0.60 else ArenaShape.ROUNDED_RECT
		_:
			var roll: float = rng.randf()
			if roll < 0.42:
				return ArenaShape.ROUNDED_RECT
			elif roll < 0.76:
				return ArenaShape.CHAMFERED_OCTAGON
			return ArenaShape.CRUCIFORM


## Builds the 2D XZ polygon for a given arena shape
static func build_arena_polygon(
	center: Vector2,
	size: Vector2,
	shape: ArenaShape
) -> PackedVector2Array:
	match shape:
		ArenaShape.CHAMFERED_OCTAGON:
			return build_chamfered_octagon(center, size)
		ArenaShape.CRUCIFORM:
			return build_cruciform(center, size)
		_:
			return build_rounded_rectangle(center, size, 4.0, 6)


## Returns an axis-aligned world Rect2 guaranteed strictly inside the arena polygon
## (used by GrassTileStamper to fast-accept interior 5m x 5m grass buckets in O(1)).
static func get_inner_safe_rect(center: Vector2, size: Vector2, shape: ArenaShape) -> Rect2:
	var half_w: float = size.x * 0.5
	var half_h: float = size.y * 0.5
	var margin: float = 0.25
	match shape:
		ArenaShape.CHAMFERED_OCTAGON:
			var cut_x: float = half_w * 0.28 + margin
			var cut_y: float = half_h * 0.28 + margin
			var iw: float = maxf(0.0, size.x - cut_x * 2.0)
			var ih: float = maxf(0.0, size.y - cut_y * 2.0)
			return Rect2(center.x - iw * 0.5, center.y - ih * 0.5, iw, ih)
		ArenaShape.CRUCIFORM:
			var iw_c: float = maxf(0.0, size.x * 0.58 - margin * 2.0)
			var ih_c: float = maxf(0.0, size.y * 0.58 - margin * 2.0)
			return Rect2(center.x - iw_c * 0.5, center.y - ih_c * 0.5, iw_c, ih_c)
		_:
			var r: float = minf(4.0, minf(half_w, half_h) * 0.4) + margin
			var iw_r: float = maxf(0.0, size.x - r * 2.0)
			var ih_r: float = maxf(0.0, size.y - r * 2.0)
			return Rect2(center.x - iw_r * 0.5, center.y - ih_r * 0.5, iw_r, ih_r)


## Builds a clean large rectangular polygon with rounded corners
static func build_rounded_rectangle(
	center: Vector2,
	size: Vector2,
	corner_radius: float = 4.0,
	corner_segments: int = 6
) -> PackedVector2Array:
	var half_w: float = size.x * 0.5
	var half_h: float = size.y * 0.5
	var r: float = minf(corner_radius, minf(half_w, half_h) * 0.4)

	var poly := PackedVector2Array()
	var centers: Array[Vector2] = [
		center + Vector2(half_w - r, -half_h + r), # Top-Right
		center + Vector2(half_w - r, half_h - r),  # Bottom-Right
		center + Vector2(-half_w + r, half_h - r), # Bottom-Left
		center + Vector2(-half_w + r, -half_h + r) # Top-Left
	]
	var start_angles: Array[float] = [
		-PI * 0.5,
		0.0,
		PI * 0.5,
		PI
	]

	for c_idx in range(4):
		var arc_c: Vector2 = centers[c_idx]
		var base_a: float = start_angles[c_idx]
		for i in range(corner_segments + 1):
			var a: float = base_a + (PI * 0.5) * (float(i) / float(corner_segments))
			poly.append(arc_c + Vector2(cos(a), sin(a)) * r)

	return poly


## Builds an 8-sided chamfered octagon clearing (Shape of Dreams arena style)
static func build_chamfered_octagon(
	center: Vector2,
	size: Vector2,
	chamfer_ratio: float = 0.27
) -> PackedVector2Array:
	var half_w: float = size.x * 0.5
	var half_h: float = size.y * 0.5
	var cx: float = half_w * clampf(chamfer_ratio, 0.12, 0.42)
	var cy: float = half_h * clampf(chamfer_ratio, 0.12, 0.42)

	var poly := PackedVector2Array([
		center + Vector2(-half_w + cx, -half_h),
		center + Vector2(half_w - cx, -half_h),
		center + Vector2(half_w, -half_h + cy),
		center + Vector2(half_w, half_h - cy),
		center + Vector2(half_w - cx, half_h),
		center + Vector2(-half_w + cx, half_h),
		center + Vector2(-half_w, half_h - cy),
		center + Vector2(-half_w, -half_h + cy)
	])
	return poly


## Builds a broad cruciform (plus-shaped) arena with 4 wide alcove bays
static func build_cruciform(
	center: Vector2,
	size: Vector2,
	arm_ratio: float = 0.58
) -> PackedVector2Array:
	var half_w: float = size.x * 0.5
	var half_h: float = size.y * 0.5
	var arm_hw: float = half_w * clampf(arm_ratio, 0.45, 0.78)
	var arm_hh: float = half_h * clampf(arm_ratio, 0.45, 0.78)

	var poly := PackedVector2Array([
		center + Vector2(-arm_hw, -half_h),
		center + Vector2(arm_hw, -half_h),
		center + Vector2(arm_hw, -arm_hh),
		center + Vector2(half_w, -arm_hh),
		center + Vector2(half_w, arm_hh),
		center + Vector2(arm_hw, arm_hh),
		center + Vector2(arm_hw, half_h),
		center + Vector2(-arm_hw, half_h),
		center + Vector2(-arm_hw, arm_hh),
		center + Vector2(-half_w, arm_hh),
		center + Vector2(-half_w, -arm_hh),
		center + Vector2(-arm_hw, -arm_hh)
	])
	return poly


## Builds a narrow bridge ribbon connecting any two arena polygons (cardinal or angled web link).
## Anchors 3.5m inside each arena boundary so boolean union and polygon clipping are always gap-free.
static func build_connecting_bridge(
	center_a: Vector2,
	poly_a: PackedVector2Array,
	center_b: Vector2,
	poly_b: PackedVector2Array,
	bridge_width: float
) -> PackedVector2Array:
	var delta: Vector2 = center_b - center_a
	var dist: float = delta.length()
	if dist < 0.01:
		return PackedVector2Array()

	var dir: Vector2 = delta / dist
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var half_w: float = bridge_width * 0.5

	var exit_a: Vector2 = _ray_polygon_exit(center_a, dir, poly_a, dist * 0.45)
	var exit_b: Vector2 = _ray_polygon_exit(center_b, -dir, poly_b, dist * 0.45)

	# Penetrate 5.5m inside each polygon so angled bridge corners & throat fillets fuse seamlessly
	var anchor_depth: float = 5.5
	var dist_exit_a: float = (exit_a - center_a).dot(dir)
	var dist_exit_b: float = (center_b - exit_b).dot(dir)

	var start_pt: Vector2 = center_a + dir * maxf(1.0, dist_exit_a - anchor_depth)
	var end_pt: Vector2 = center_b - dir * maxf(1.0, dist_exit_b - anchor_depth)

	var poly := PackedVector2Array([
		start_pt - perp * half_w,
		end_pt - perp * half_w,
		end_pt + perp * half_w,
		start_pt + perp * half_w
	])
	return poly


## Legacy helper retained for compatibility
static func build_cardinal_bridge(
	pos1: Vector2,
	size1: Vector2,
	pos2: Vector2,
	size2: Vector2,
	bridge_width: float
) -> PackedVector2Array:
	var poly1: PackedVector2Array = build_rounded_rectangle(pos1, size1)
	var poly2: PackedVector2Array = build_rounded_rectangle(pos2, size2)
	return build_connecting_bridge(pos1, poly1, pos2, poly2, bridge_width)


static func _ray_polygon_exit(
	origin: Vector2,
	dir: Vector2,
	poly: PackedVector2Array,
	fallback_dist: float
) -> Vector2:
	var best_t: float = -1.0
	var ray_end: Vector2 = origin + dir * 500.0
	var n: int = poly.size()
	for i in range(n):
		var p1: Vector2 = poly[i]
		var p2: Vector2 = poly[(i + 1) % n]
		var hit: Variant = Geometry2D.segment_intersects_segment(origin, ray_end, p1, p2)
		if hit != null:
			var hit_pt: Vector2 = hit as Vector2
			var t: float = (hit_pt - origin).dot(dir)
			if t > best_t:
				best_t = t
	if best_t > 0.0:
		return origin + dir * best_t
	return origin + dir * fallback_dist
