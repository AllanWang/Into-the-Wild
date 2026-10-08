class_name AreaPreset
extends RefCounted

## Presets for area sizes and geometric formats.
## Generates smooth, rounded polygons (circles, capsules, dual-lobes)
## attached by clean bridges.

enum SizeCategory {
	SMALL,   ## Shrine, checkpoint, spawn node (radius ~7-8.5m)
	MEDIUM,  ## Standard combat arena (radius ~11-13.5m)
	LARGE,   ## Elite arena / multi-wave clearing (radius ~16-19m)
	BOSS     ## Final encounter / boss chamber (radius ~22-26m)
}

enum ShapeFormat {
	CIRCLE,       ## Single smooth rounded circle
	CAPSULE,      ## Smooth elongated pill / capsule
	DUAL_CIRCLE,  ## Two merged smooth circular lobes
	TRIPLE_CLOVER ## Three merged smooth circular lobes
}

## Returns a random size category based on layer context
static func pick_size_category(layer: int, total_layers: int, rng: RandomNumberGenerator) -> SizeCategory:
	if layer == 0:
		return SizeCategory.SMALL # Clean spawn clearing
	if layer == total_layers - 1:
		return SizeCategory.BOSS if total_layers >= 4 else SizeCategory.LARGE
	# Middle layers can be medium or large
	var roll: float = rng.randf()
	if roll < 0.25:
		return SizeCategory.SMALL
	elif roll < 0.75:
		return SizeCategory.MEDIUM
	else:
		return SizeCategory.LARGE

## Returns a radius range for a given size category
static func get_radius_for_category(category: SizeCategory, rng: RandomNumberGenerator) -> float:
	match category:
		SizeCategory.SMALL:
			return rng.randf_range(7.0, 8.5)
		SizeCategory.MEDIUM:
			return rng.randf_range(11.0, 13.5)
		SizeCategory.LARGE:
			return rng.randf_range(16.0, 19.0)
		SizeCategory.BOSS:
			return rng.randf_range(22.0, 26.0)
	return 12.0

## Returns a random shape format
static func pick_format(rng: RandomNumberGenerator) -> ShapeFormat:
	var roll := rng.randf()
	if roll < 0.50:
		return ShapeFormat.CIRCLE
	elif roll < 0.75:
		return ShapeFormat.CAPSULE
	elif roll < 0.90:
		return ShapeFormat.DUAL_CIRCLE
	else:
		return ShapeFormat.TRIPLE_CLOVER

## Generates a smooth rounded polygon according to format & radius
static func build_smooth_area_polygon(
	center: Vector2,
	radius: float,
	format: ShapeFormat,
	rng: RandomNumberGenerator,
	circle_segments: int = 48
) -> PackedVector2Array:
	match format:
		ShapeFormat.CIRCLE:
			return _build_smooth_circle(center, radius, circle_segments)

		ShapeFormat.CAPSULE:
			var angle: float = rng.randf_range(0.0, TAU)
			var offset_dir := Vector2(cos(angle), sin(angle))
			var half_len: float = radius * 0.45
			var c1 := center - offset_dir * half_len
			var c2 := center + offset_dir * half_len
			var p1 := _build_smooth_circle(c1, radius * 0.85, circle_segments)
			var p2 := _build_smooth_circle(c2, radius * 0.85, circle_segments)
			var merged := Geometry2D.merge_polygons(p1, p2)
			if not merged.is_empty():
				return merged[0]
			return p1

		ShapeFormat.DUAL_CIRCLE:
			var angle: float = rng.randf_range(0.0, TAU)
			var dir := Vector2(cos(angle), sin(angle))
			var c1 := center - dir * (radius * 0.4)
			var c2 := center + dir * (radius * 0.4)
			var r1 := radius * rng.randf_range(0.75, 0.95)
			var r2 := radius * rng.randf_range(0.75, 0.95)
			var p1 := _build_smooth_circle(c1, r1, circle_segments)
			var p2 := _build_smooth_circle(c2, r2, circle_segments)
			var merged := Geometry2D.merge_polygons(p1, p2)
			if not merged.is_empty():
				return merged[0]
			return p1

		ShapeFormat.TRIPLE_CLOVER:
			var base_angle: float = rng.randf_range(0.0, TAU)
			var p_base := _build_smooth_circle(center, radius * 0.65, circle_segments)
			for i in range(3):
				var a := base_angle + float(i) * (TAU / 3.0)
				var lobe_c := center + Vector2(cos(a), sin(a)) * (radius * 0.5)
				var lobe_p := _build_smooth_circle(lobe_c, radius * 0.6, circle_segments)
				var m := Geometry2D.merge_polygons(p_base, lobe_p)
				if not m.is_empty():
					p_base = m[0]
			return p_base

	return _build_smooth_circle(center, radius, circle_segments)

## Helper to build a clean, perfectly smooth rounded circle polygon
static func _build_smooth_circle(center: Vector2, radius: float, segments: int = 48) -> PackedVector2Array:
	var poly := PackedVector2Array()
	poly.resize(segments)
	var step: float = TAU / float(segments)
	for i in range(segments):
		var theta: float = float(i) * step
		poly[i] = center + Vector2(cos(theta), sin(theta)) * radius
	return poly

## Helper to build a clean bridge corridor connecting two rounded areas
static func build_bridge_polygon(
	start: Vector2,
	end: Vector2,
	bridge_width: float,
	segments: int = 16
) -> PackedVector2Array:
	var diff := end - start
	var length := diff.length()
	if length < 0.001:
		return PackedVector2Array()

	var dir := diff / length
	var normal := Vector2(-dir.y, dir.x)

	var half_w := bridge_width * 0.5
	var left_side := PackedVector2Array()
	var right_side := PackedVector2Array()

	# Clean bridge ribbon with slight flare at the ends where it anchors into the circles
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var pt := start.lerp(end, t)

		# Subtle flare at the anchor points so bridge merges smoothly into the circular rims
		var anchor_flare: float = 1.0 + 0.3 * (4.0 * (t - 0.5) * (t - 0.5))
		var w := half_w * anchor_flare

		left_side.append(pt + normal * w)
		right_side.append(pt - normal * w)

	right_side.reverse()
	var full := PackedVector2Array()
	full.append_array(left_side)
	full.append_array(right_side)
	return full
